const PanelWindow = @This();

const std = @import("std");
const log = std.log.scoped(.@"fe.app.PanelWindow");

const AppState = @import("State.zig");
const Window = AppState.Window;
const titlebar = @import("titlebar.zig");
const WindowInsetWrapper = @import("WindowInsetWrapper.zig");

const cu = @import("cu");
const b = cu.builder;

app: *AppState,
window: *Window = undefined,

pub fn init(app: *AppState) !*PanelWindow {
    const win = try app.gpa.create(PanelWindow);
    win.* = .{ .app = app };
    return win;
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

fn onClose(state: *PanelWindow) void {
    state.app.gpa.destroy(state);
}

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
                .initial_size = .size(1024, 576),
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

    {
        const centered = b.centered.begin(.y);
        defer b.centered.end(centered);

        b.stacks.pref_size.push(.size(.grow, .text));
        _ = b.label("Hello, World");
    }
}
