const PanelWindow = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const log = std.log.scoped(.@"fe.app.PanelWindow");
const assert = std.debug.assert;

const AppState = @import("State.zig");
const Window = AppState.Window;
const titlebar = @import("titlebar.zig");
const WindowInsetWrapper = @import("WindowInsetWrapper.zig");

const cu = @import("cu");
const mt = cu.math;
const b = cu.builder;
const TreeMixin = cu.TreeMixin;

app: *AppState,
window: *Window = undefined,

panel_pool: PanelPool,
root_panel: *Panel,

const PanelPool = std.heap.MemoryPoolExtra(Panel, .{ .growable = true });

pub fn init(app: *AppState) !*PanelWindow {
    const win = try app.gpa.create(PanelWindow);
    var pool = PanelPool.init(app.gpa);

    const root_panel = tree: {
        const p0 = try pool.create();
        p0.* = .{ .name = "p0", .parent_percent = 1, .split_axis = .x };

        const p1 = try pool.create();
        p1.* = .{ .name = "p1", .parent_percent = 1.0 / 2.0, .split_axis = .y };
        const p2 = try pool.create();
        p2.* = .{ .name = "p2", .parent_percent = 1.0 / 2.0, .split_axis = .y };

        const p3 = try pool.create();
        p3.* = .{ .name = "p3", .parent_percent = 1.0 / 3.0, .split_axis = .x };
        const p4 = try pool.create();
        p4.* = .{ .name = "p4", .parent_percent = 1.0 / 3.0, .split_axis = .x };
        const p5 = try pool.create();
        p5.* = .{ .name = "p5", .parent_percent = 1.0 / 3.0, .split_axis = .x };

        const p6 = try pool.create();
        p6.* = .{ .name = "p6", .parent_percent = 1.0 / 2.0, .split_axis = .x };
        const p7 = try pool.create();
        p7.* = .{ .name = "p7", .parent_percent = 1.0 / 2.0, .split_axis = .x };

        p0.addChild(p1);
        p0.addChild(p2);

        p1.addChild(p3);
        p1.addChild(p4);
        p1.addChild(p5);

        p5.addChild(p6);
        p5.addChild(p7);

        break :tree p0;
    };

    win.* = .{
        .app = app,
        .panel_pool = pool,
        .root_panel = root_panel,
    };
    return win;
}

fn onClose(state: *PanelWindow) void {
    state.panel_pool.deinit();
    state.app.gpa.destroy(state);
}

pub fn windowInterface(self: *PanelWindow) Window.Interface {
    return .{
        .context = @ptrCast(self),
        .vtable = &.{
            .build = vtable.build,
            .close = vtable.close,
        },
    };
}

pub const vtable = struct {
    fn build(ctx: *anyopaque, window: *Window) void {
        const state: *PanelWindow = @ptrCast(@alignCast(ctx));
        state.window = window;
        state.build();
    }

    fn close(ctx: *anyopaque, window: *Window) void {
        _ = window;
        const state: *PanelWindow = @ptrCast(@alignCast(ctx));
        state.onClose();
    }
};

const titlebar_buttons = struct {
    const MenuBar = titlebar.TitlebarButtons(*PanelWindow);

    pub fn menuBar(state: *PanelWindow) MenuBar {
        return .{
            .context = state,
            .buttons = &buttons,
        };
    }

    pub const buttons = [_]MenuBar.Button{
        panel.button,
    };

    pub const panel = struct {
        pub const button = MenuBar.Button{
            .name = "Panel",
            .items = &.{
                .{ .name = "new window", .action = newWindow },
                .{ .name = "close", .action = close },
                .{ .name = "quit", .action = quit },
            },
        };

        pub fn newWindow(state: *PanelWindow) void {
            const panel_window_state = PanelWindow.init(state.app) catch
                @panic("oom");

            _ = state.app.newWindow(.{
                .title = "Panel",
                .initial_size = .size(800, 600),
                .interface = panel_window_state.windowInterface(),
            }) catch |err| {
                log.err("failed to create new panel window: {}", .{err});
                return;
            };
        }

        pub fn close(state: *PanelWindow) void {
            state.app.action_queue.queue(.{
                .close_window = state.window.wl_window.id,
            });
        }

        pub fn quit(state: *PanelWindow) void {
            state.app.action_queue.queue(.quit);
        }
    };
};

fn build(state: *PanelWindow) void {
    const tiling = state.window.wl_window.tiling;
    b.stacks.flags.push(flags: {
        var flags = cu.AtomFlags.draw_background;

        if (!tiling.isTiled()) {
            flags.insert(.draw_border);
            b.stacks.corner_radius.push(state.app.window_rounding);
        } else {
            flags.setPresent(.draw_side_top, !tiling.tiled_top);
            flags.setPresent(.draw_side_bottom, !tiling.tiled_bottom);
            flags.setPresent(.draw_side_left, !tiling.tiled_left);
            flags.setPresent(.draw_side_right, !tiling.tiled_right);
        }

        break :flags flags;
    });
    b.stacks.layout_axis.push(.y);
    const window_inset_wrapper =
        WindowInsetWrapper.begin(state.window.wl_window);
    defer window_inset_wrapper.end();

    const menu_bar_buttons = titlebar_buttons.menuBar(state);
    titlebar.buildTitlebar(
        state.window.wl_window,
        state.app.window_rounding,
        *PanelWindow,
        menu_bar_buttons,
    );

    //- panel ui
    {
        const split_handle_size = 2;
        const inset_size = 4;

        //- root container
        b.stacks.pref_size.push(.square(.grow));
        b.stacks.layout_axis.push(.x);
        const root_container = b.open("###root_panel_container");
        defer b.close(root_container);

        b.dbg.debugBorder(root_container);

        const root_rect = root_container.rect;

        //- build non-leaf panel ui
        var iter = state.root_panel.tree.depthFirstPreOrderIterator();
        while (iter.next()) |panel| {
            if (panel.tree.children.len == 0) continue;

            const split_axis = panel.split_axis;
            const axis_i = @intFromEnum(split_axis);

            //- calculate rect
            const panel_rect =
                panel.rectFromPanel(state.app.arena, root_rect);
            const panel_rect_size = panel_rect.size();

            //- build drag boundraies
            var child_iter = panel.tree.childIterator();
            while (child_iter.next()) |child| {
                if (child.tree.siblings.next == null) break;

                const child_rect = child.rectFromPanelChildRect(panel_rect);
                var boundry_rect = child_rect;
                boundry_rect.p0.arr()[axis_i] = boundry_rect.p1.arr()[axis_i];
                boundry_rect.p0.arr()[axis_i] -= split_handle_size;
                boundry_rect.p1.arr()[axis_i] += split_handle_size;

                b.stacks.pref_size.push(.square(.none));
                b.stacks.flags.push(.init(&.{ .clickable, .floating }));
                b.stacks.hover_pointer.push(
                    if (panel.split_axis == .x) .resize_ew else .resize_ns,
                );
                const boundry = b.buildf("###panel_boundry [{*}]", .{child});

                boundry.rel_position = boundry_rect.origin().sub(root_rect.origin());
                boundry.fixed_size = boundry_rect.size();

                const inter = boundry.interaction();
                if (inter.dragging()) {
                    const min_child = child;
                    const max_child = child.tree.siblings.next.?;
                    if (inter.pressed()) {
                        const drag_data = mt.point(
                            min_child.parent_percent,
                            max_child.parent_percent,
                        );

                        cu.state.storeDragData(&drag_data);
                    }

                    const drag_data = cu.state.getDragData(mt.Point(f32)).*;
                    // defer cu.state.storeDragData(mt.Point(f32), drag_data);
                    const drag_delta = cu.state.dragDelta();

                    const min_child_pct__pre_drag = drag_data.x;
                    const max_child_pct__pre_drag = drag_data.y;

                    const min_child_px__pre_drag =
                        min_child_pct__pre_drag *
                        panel_rect_size.fromAxis(split_axis);
                    const max_child_px__pre_drag =
                        max_child_pct__pre_drag *
                        panel_rect_size.fromAxis(split_axis);

                    const min_child_px__post_drag =
                        min_child_px__pre_drag +
                        drag_delta.fromAxis(split_axis);
                    const max_child_px__post_drag =
                        max_child_px__pre_drag -
                        drag_delta.fromAxis(split_axis);

                    const min_child_pct__post_drag =
                        min_child_px__post_drag /
                        panel_rect_size.fromAxis(split_axis);
                    const max_child_pct__post_drag =
                        max_child_px__post_drag /
                        panel_rect_size.fromAxis(split_axis);

                    min_child.parent_percent = min_child_pct__post_drag;
                    max_child.parent_percent = max_child_pct__post_drag;
                }
            }
        }

        //- build leaf panel ui
        iter.reset();
        while (iter.next()) |panel| {
            if (panel.tree.children.len != 0) continue;

            //- setup atom
            b.stacks.pref_size.push(.square(.none));
            b.stacks.flags.push(.init(&.{
                .draw_background,
                .draw_border,
                .clickable,
                .floating,
            }));
            b.stacks.layout_axis.push(.y);
            b.stacks.alignment.push(.square(.center));
            const atom = b.openf("###panel_{s} [{*}]", .{ panel.name, panel });
            defer b.close(atom);

            b.dbg.debugBorder(atom);

            //- calculate rect
            const rect = panel
                .rectFromPanel(state.app.arena, root_rect)
                .innerRect(.splat(inset_size));
            atom.rel_position = rect.origin().sub(root_rect.origin());
            atom.fixed_size = rect.size();

            //- panel ui
            b.stacks.pref_size.push(.square(.text_pad(8)));
            _ = b.buttonf("hello world! {s}", .{panel.name});
        }
    }
}

const Panel = struct {
    tree: TreeMixin(Panel) = .{},

    name: []const u8,
    parent_percent: f32 = 1,
    split_axis: cu.Atom.LayoutAxis = .x,

    pub fn addChild(self: *Panel, child: *Panel) void {
        self.tree.addChild(child);
    }

    pub fn rectFromPanel(
        panel: *Panel,
        arena: Allocator,
        root_rect: mt.Rect(f32),
    ) mt.Rect(f32) {
        var stack = std.ArrayListUnmanaged(*Panel).empty;
        var depth: usize = 0;

        // Walk up to root, collecting ancestors
        var parent_iter = panel.tree.parentIterator();
        while (parent_iter.next()) |parent| {
            stack.append(arena, parent) catch @panic("oom");
            depth += 1;
        }

        // Walk down from root, subdividing at each ancestor
        var i: usize = depth;
        var result = root_rect;
        while (i > 0) {
            i -= 1;
            const curr = stack.items[i];
            result = curr.rectFromPanelChildRect(result);
        }
        return result;
    }

    pub fn rectFromPanelChildRect(
        panel: *Panel,
        parent_rect: mt.Rect(f32),
    ) mt.Rect(f32) {
        var result = parent_rect;
        const parent = panel.tree.parent orelse return parent_rect;

        var parent_size = result.size();
        const axis_i = @intFromEnum(parent.split_axis);

        // Find offset for this child among siblings
        var offset: f32 = 0;
        var child_iter = parent.tree.childIterator();
        while (child_iter.next()) |sibling| {
            if (sibling == panel) break;
            offset += sibling.parent_percent * parent_size.arr()[axis_i];
        }

        // Set start and end along the split axis
        result.p0.arr()[axis_i] += offset;
        result.p1.arr()[axis_i] =
            result.p0.arr()[axis_i] +
            panel.parent_percent *
                parent_size.arr()[axis_i];

        return result;
    }
};
