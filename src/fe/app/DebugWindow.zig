const Self = @This();

const std = @import("std");
const log = std.log.scoped(.@"app.DebugWindow");

const App = @import("App.zig");

const cu = @import("cu");
const mt = cu.math;
const b = cu.builder;
const Atom = cu.Atom;

app: *App,
window: *App.BackendWindow,
cu_state: *cu.State,

target: ?*cu.State = null,
debug_ui_state: cu.debug.DebugUIState = .init,

pub fn init(app: *App) !*Self {
    const window = try app.newWindow("Debug");
    const cu_state = try cu.State.init(app.gpa, .{
        .callbacks = window.callbacks(),
        .font_kind_map = window.font_kind_map,
        .interaction_styles = app.interaction_styles,
        .root_palette = app.root_palette,
    });

    const self = try app.gpa.create(Self);
    self.* = .{
        .app = app,
        .window = window,
        .cu_state = cu_state,
    };
    return self;
}

pub fn deinit(self: *Self) void {
    self.cu_state.deinit();

    const gpa = self.app.gpa;
    gpa.destroy(self);
}

pub fn appWindow(self: *Self) App.AppWindow {
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
        const self: *Self = @ptrCast(@alignCast(ctx));
        self.deinit();
    }
    fn getWindow(ctx: *anyopaque) *App.BackendWindow {
        const self: *Self = @ptrCast(@alignCast(ctx));
        return self.window;
    }
    fn getCuState(ctx: *anyopaque) *cu.State {
        const self: *Self = @ptrCast(@alignCast(ctx));
        return self.cu_state;
    }
    fn buildUI(ctx: *anyopaque) void {
        const self: *Self = @ptrCast(@alignCast(ctx));
        self.buildUI();
    }
};

const menu_bar = struct {
    const MenuBar = App.MenuBar;

    pub fn menuBar(self: *Self) MenuBar {
        return .{
            .context = self,
            .root = &.{
                debug.button,
            },
        };
    }

    pub const debug = struct {
        pub const button = MenuBar.MenuList{
            .name = "Debug",
            .items = &.{
                .{ .button = .{ .name = "reset", .action = reset } },
                .{ .button = .{ .name = "close", .action = close } },
                .{ .button = .{ .name = "quit", .action = quit } },
            },
        };

        fn reset(ctx: *anyopaque) void {
            const self: *Self = @ptrCast(@alignCast(ctx));
            self.target = null;
            self.debug_ui_state = .init;
        }

        pub fn close(ctx: *anyopaque) void {
            const self: *Self = @ptrCast(@alignCast(ctx));
            self.app.action_queue.queue(.{
                .close_window = self.window.getId(),
            });
        }

        pub fn quit(ctx: *anyopaque) void {
            const self: *Self = @ptrCast(@alignCast(ctx));
            self.app.action_queue.queue(.quit);
        }
    };
};

fn buildUI(self: *Self) void {
    self.cu_state.select();

    b.startBuild(@intFromPtr(self.window));
    defer b.endBuild();

    self.window.startBuild(menu_bar.menuBar(self));
    defer self.window.endBuild();

    self.buildMainUI();
}

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

        for (self.app.windows.values(), 0..) |window, i| {
            const title = window.getWindow().getTitle();
            const btn = b.buttonf("{s}##{d}", .{ title, i });

            if (btn.clicked()) {
                self.target = window.getCuState();
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
