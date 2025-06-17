const PanelWindow = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const log = std.log.scoped(.@"fe.app.PanelWindow");
const assert = std.debug.assert;

const App = @import("App.zig");

const cu = @import("cu");
const mt = cu.math;
const b = cu.builder;
const TreeMixin = cu.TreeMixin;

app: *App,
window: *App.BackendWindow,
cu_state: *cu.State,

panel_pool: PanelPool,
root_panel: *Panel,

const PanelPool = std.heap.MemoryPoolExtra(Panel, .{ .growable = true });

pub fn init(app: *App) !*PanelWindow {
    const window = try app.newWindow("Panel");
    const cu_state = try cu.State.init(app.gpa, .{
        .callbacks = window.callbacks(),
        .font_kind_map = window.font_kind_map,
        .interaction_styles = app.interaction_styles,
        .root_palette = app.root_palette,
    });

    const self = try app.gpa.create(PanelWindow);
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

    self.* = .{
        .app = app,
        .window = window,
        .cu_state = cu_state,

        .panel_pool = pool,
        .root_panel = root_panel,
    };
    return self;
}

pub fn deinit(self: *PanelWindow) void {
    self.cu_state.deinit();

    self.panel_pool.deinit();

    const gpa = self.app.gpa;
    gpa.destroy(self);
}

pub fn appWindow(self: *PanelWindow) App.AppWindow {
    return .{
        .id = self.window.getId(),
        .context = @ptrCast(self),
        .vtable = &.{
            .deinit = &vtable.deinit,
            .getWindow = &vtable.getWindow,
            .getCuState = &vtable.getCuState,
            .buildUI = &vtable.buildUI,
        },
    };
}

pub const vtable = struct {
    fn deinit(ctx: *anyopaque) void {
        const self: *PanelWindow = @ptrCast(@alignCast(ctx));
        self.deinit();
    }
    fn getWindow(ctx: *anyopaque) *App.BackendWindow {
        const self: *PanelWindow = @ptrCast(@alignCast(ctx));
        return self.window;
    }
    fn getCuState(ctx: *anyopaque) *cu.State {
        const self: *PanelWindow = @ptrCast(@alignCast(ctx));
        return self.cu_state;
    }
    fn buildUI(ctx: *anyopaque) void {
        const self: *PanelWindow = @ptrCast(@alignCast(ctx));
        self.buildUI();
    }
};

const menu_bar = struct {
    const MenuBar = App.MenuBar;

    pub fn menuBar(state: *PanelWindow) MenuBar {
        return .{
            .context = state,
            .root = &.{
                panel.button,
            },
        };
    }

    pub const panel = struct {
        pub const button = MenuBar.MenuList{
            .name = "Panel",
            .items = &.{
                .{ .button = .{ .name = "new window", .action = newWindow } },
                .{ .button = .{ .name = "close", .action = close } },
                .{ .button = .{ .name = "quit", .action = quit } },
            },
        };

        pub fn newWindow(ctx: *anyopaque) void {
            const self: *PanelWindow = @ptrCast(@alignCast(ctx));

            const new_win = PanelWindow.init(self.app) catch
                @panic("failed to create new panel window");
            self.app.addAppWindow(new_win.appWindow()) catch
                @panic("failed to add new panel window");
        }

        pub fn close(ctx: *anyopaque) void {
            const self: *PanelWindow = @ptrCast(@alignCast(ctx));
            self.app.action_queue.queue(.{
                .close_window = self.window.getId(),
            });
        }

        pub fn quit(ctx: *anyopaque) void {
            const self: *PanelWindow = @ptrCast(@alignCast(ctx));
            self.app.action_queue.queue(.quit);
        }
    };
};

fn buildUI(self: *PanelWindow) void {
    self.cu_state.select();

    b.startBuild(@intFromPtr(self.window));
    defer b.endBuild();

    self.window.startBuild(menu_bar.menuBar(self));
    defer self.window.endBuild();

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
        var iter = self.root_panel.tree.depthFirstPreOrderIterator();
        while (iter.next()) |panel| {
            if (panel.tree.children.len == 0) continue;

            const split_axis = panel.split_axis;
            const axis_i = @intFromEnum(split_axis);

            //- calculate rect
            const panel_rect =
                panel.rectFromPanel(self.app.arena, root_rect);
            const panel_rect_size = panel_rect.size();

            //- build drag boundaries
            var child_iter = panel.tree.childIterator();
            while (child_iter.next()) |child| {
                if (child.tree.siblings.next == null) break;

                const child_rect = child.rectFromPanelChildRect(panel_rect);
                var boundary_rect = child_rect;
                boundary_rect.p0.arr()[axis_i] = boundary_rect.p1.arr()[axis_i];
                boundary_rect.p0.arr()[axis_i] -= split_handle_size;
                boundary_rect.p1.arr()[axis_i] += split_handle_size;

                b.stacks.pref_size.push(.square(.none));
                b.stacks.flags.push(.init(&.{ .clickable, .floating }));
                b.stacks.hover_cursor_shape.push(
                    if (panel.split_axis == .x) .resize_ew else .resize_ns,
                );
                const boundary = b.buildf("###panel_boundary [{*}]", .{child});

                boundary.rel_position = boundary_rect.origin().sub(root_rect.origin());
                boundary.fixed_size = boundary_rect.size();

                const inter = boundary.interaction();
                if (inter.dragging()) {
                    const min_child = child;
                    const max_child = child.tree.siblings.next.?;
                    if (inter.pressed()) {
                        const drag_data = [2]f32{
                            min_child.parent_percent,
                            max_child.parent_percent,
                        };

                        cu.state.storeDragData(&drag_data);
                    }

                    const drag_data = cu.state.getDragData([2]f32).*;
                    const drag_delta = cu.state.dragDelta();

                    const min_child_pct__pre_drag = drag_data[0];
                    const max_child_pct__pre_drag = drag_data[1];

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
                .rectFromPanel(self.app.arena, root_rect)
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
