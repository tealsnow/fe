const Self = @This();

const std = @import("std");
const log = std.log.scoped(.@"app.DebugWindow");

const AppState = @import("State.zig");
const Window = AppState.Window;
const WindowInsetWrapper = @import("WindowInsetWrapper.zig");
const titlebar = @import("titlebar.zig");

const cu = @import("cu");
const mt = cu.math;
const b = cu.builder;
const Atom = cu.Atom;

app: *AppState,

window: *Window = undefined,

target: ?*cu.State = null,

debug_ui_state: cu.debug.DebugUIState = .init,

pub fn windowInterface(self: *Self) Window.Interface {
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
        const self: *Self = @ptrCast(@alignCast(ctx));
        self.window = window;
        self.build();
    }

    fn close(ctx: *anyopaque, window: *Window) void {
        _ = ctx;
        _ = window;
    }
};

fn build(self: *Self) void {
    const window_rounding = self.app.window_rounding;

    const tiling = self.window.wl_window.tiling;
    b.stacks.flags.push(flags: {
        var flags = cu.AtomFlags.draw_background;

        if (!tiling.isTiled()) {
            flags.insert(.draw_border);
            b.stacks.corner_radius.push(window_rounding);
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
        WindowInsetWrapper.begin(self.window.wl_window);
    defer window_inset_wrapper.end();

    const menu_bar = titlebar_buttons.menuBar(self);

    titlebar.buildTitlebar(
        self.window.wl_window,
        self.app.window_rounding,
        *Self,
        menu_bar,
    );

    self.buildMainUI();
}

const titlebar_buttons = struct {
    const MenuBar = titlebar.TitlebarButtons(*Self);

    pub fn menuBar(self: *Self) MenuBar {
        return .{
            .context = self,
            .buttons = &buttons,
        };
    }

    pub const buttons = [_]MenuBar.Button{
        debug.button,
    };

    pub const debug = struct {
        pub const button = MenuBar.Button{
            .name = "Debug",
            .items = &.{
                .{ .name = "pick new", .action = reset },
                .{ .name = "close", .action = close },
                .{ .name = "quit", .action = quit },
            },
        };

        fn reset(self: *Self) void {
            self.target = null;
            self.debug_ui_state = .init;
        }

        pub fn close(self: *Self) void {
            self.app.action_queue.queue(.{
                .close_window = self.window.wl_window.id,
            });
        }

        pub fn quit(self: *Self) void {
            self.app.action_queue.queue(.quit);
        }
    };
};

fn buildMainUI(self: *Self) void {
    b.stacks.layout_axis.push(.y);
    b.stacks.pref_size.push(.square(.grow));
    const main_pane = b.open("###main content");
    defer b.close(main_pane);

    if (self.target) |cu_state| {
        cu.debug.buildDebugUI(&self.debug_ui_state, self.app.arena, cu_state);
    } else {
        b.stacks.pref_size.push(.square(.text));
        _ = b.label("no cu state selected");

        b.stacks.pref_size.pushForMany(.square(.text_pad(8)));
        defer _ = b.stacks.pref_size.pop();

        for (self.app.window_list.slice(), 0..) |window, i| {
            const btn = b.buttonf("{s}##{d}", .{ window.title, i });

            if (btn.clicked()) {
                self.target = window.cu_state;
            }
        }

        //-

        // b.stacks.flags.push(.init(&.{ .floating, .draw_border, .clickable }));
        // b.stacks.pref_size.push(.square(.px(100)));
        // const box = b.build("###drag box");
        //
        // const inter = box.interaction();
        // b.baseClickableInteractionStyles(inter);
        //
        // if (inter.dragging()) {
        //     if (inter.pressed()) {
        //         cu.state.storeDragData(&box.rel_position);
        //     }
        //
        //     const pos = cu.state.getDragData(mt.Point(f32)).*;
        //     const delta = cu.state.dragDelta();
        //
        //     box.rel_position = pos.add(delta);
        // }
    }
}
