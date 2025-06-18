const App = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const log = std.log.scoped(.@"fe.app.State");

const tracy = @import("tracy");

const platform = @import("../platform/platform.zig");
pub const Backend = platform.Backend;
pub const BackendWindow = Backend.Window;
pub const WindowId = Backend.WindowId;
pub const MenuBar = platform.MenuBar;

pub const APP_ID = "me.ketanr.fe";

const EventQueueCircleBuffer =
    @import("../misc/event_queue_circle_buffer.zig")
        .EventQueueCircleBuffer;

const cu = @import("cu");
const b = cu.builder;

running: bool = true,

gpa: Allocator,
arena: Allocator,

arena_allocator: std.heap.ArenaAllocator,
tracing_arena_alloc: tracy.TracingAllocator,
warn_arena_reset_failed: bool = false,

backend: *Backend,

action_queue: ActionQueue = .empty,

windows: std.AutoArrayHashMapUnmanaged(WindowId, AppWindow) = .empty,

keyboard_focus: ?WindowId = null,
pointer_focus: ?WindowId = null,

interaction_styles: cu.builder.InteractionStyles,
root_palette: cu.Atom.Palette,

pub fn init(gpa: Allocator) !*App {
    const backend = try Backend.init(gpa);
    errdefer backend.deinit();

    const base_interaction_style = cu.builder.InteractionStyle{
        .target = .border,
        .hot = .hexRgb(0x665c54), // gruvbox bg3
        .active = .hexRgb(0xfbf1c7), // gruvbox fg0
    };

    const interaction_styles = cu.builder.InteractionStyles{
        .button = base_interaction_style,
        .toggle_switch = base_interaction_style,
    };

    const root_palette = cu.Atom.Palette.init(.{
        .background = .hexRgb(0x1d2021), // gruvbox bg0
        .border = .hexRgb(0x3c3836), // gruvbox bg1
        .text = .hexRgb(0xebdbb2), // gruvbox fg1
        // .text_weak = .hexRgb(0xbdae93), // gruvbox fg3
    });

    const self = try gpa.create(App);
    errdefer gpa.destroy(self);
    self.* = .{
        .gpa = gpa,
        .arena = undefined,
        .arena_allocator = .init(gpa),
        .tracing_arena_alloc = undefined,
        .backend = backend,

        .interaction_styles = interaction_styles,
        .root_palette = root_palette,
    };

    self.arena = self.arena_allocator.allocator();
    self.tracing_arena_alloc = .initNamed("arena", self.arena);

    return self;
}

pub fn deinit(self: *App) void {
    for (self.windows.values()) |win| self.deinitWindow(win);
    self.windows.deinit(self.gpa);

    self.arena_allocator.deinit();
    self.tracing_arena_alloc.discard();

    self.backend.deinit();

    const gpa = self.gpa;
    gpa.destroy(self);
}

pub fn newWindow(self: *App, title: [:0]const u8) !*BackendWindow {
    return self.backend.createWindow(.{
        .title = title,
        .app_id = APP_ID,
    });
}

pub fn addAppWindow(self: *App, window: AppWindow) !void {
    try self.windows.put(self.gpa, window.id, window);
}

pub fn closeWindow(self: *App, window_id: WindowId) void {
    const app_win =
        (self.windows.fetchSwapRemove(window_id) orelse return).value;
    self.deinitWindow(app_win);
}

fn deinitWindow(self: *App, app_win: AppWindow) void {
    const backend_window = app_win.getWindow();
    app_win.deinit();
    self.backend.closeWindow(backend_window.getId());
}

pub inline fn run(self: *App) !void {
    while (self.running) {
        try self.updateAndRender();
    }
}

pub inline fn updateAndRender(self: *App) !void {
    const events = try self.backend.getEvents(self.arena);

    for (events) |event| switch (event) {
        .window_present => |id| present: {
            const win = self.windows.getPtr(id) orelse break :present;
            win.should_draw = true;
        },

        .window_close => |id| {
            // @TODO: pass event to window to intercept
            self.action_queue.queue(.{ .close_window = id });
        },

        .window_resize => |resize| resize: {
            const win = self.windows.get(resize.window) orelse break :resize;
            win.getCuState().window_size = resize.size.floatFromInt(f32);
        },

        .keyboard_focus => |focus| {
            self.keyboard_focus =
                if (focus.focused) focus.window else null;
        },
        .key => |key| key: {
            const win = self.windows.get(
                self.keyboard_focus orelse break :key,
            ) orelse break :key;
            win.getCuState().pushEvent(.{ .key = key });
        },
        .text => |text| text: {
            const win = self.windows.get(
                self.keyboard_focus orelse break :text,
            ) orelse break :text;
            win.getCuState().pushEvent(.{ .text = text });
        },

        .pointer_focus => |focus| focus: {
            self.pointer_focus =
                if (focus.focused) focus.window else pointer_focus: {
                    const win = self.windows.get(
                        self.pointer_focus orelse break :focus,
                    ) orelse break :focus;
                    win.getCuState().pushEvent(.{ .mouse_move = .inf });
                    break :pointer_focus null;
                };
        },
        .pointer_move => |pos| move: {
            const win = self.windows.get(
                self.pointer_focus orelse break :move,
            ) orelse break :move;
            win.getCuState().pushEvent(.{ .mouse_move = pos });
        },
        .pointer_button => |button| button: {
            const win = self.windows.get(
                self.pointer_focus orelse break :button,
            ) orelse break :button;
            win.getCuState().pushEvent(.{ .mouse_button = button });
        },
        .pointer_scroll => |scroll| scroll: {
            const win = self.windows.get(
                self.pointer_focus orelse break :scroll,
            ) orelse break :scroll;
            win.getCuState().pushEvent(.{ .scroll = scroll });
        },
    };

    //- build ui and present
    for (self.windows.values()) |*app_win| {
        if (!app_win.should_draw) continue;
        app_win.should_draw = false;

        app_win.buildUI();

        const win = app_win.getWindow();
        const cu_state = app_win.getCuState();

        try win.present(self.arena, cu_state);
    }

    //- handle actions
    while (self.action_queue.dequeue()) |action| switch (action) {
        .quit => {
            // exits here and skip cleanup on release builds
            std.process.cleanExit();

            self.running = false;
        },

        .close_window => |id| {
            self.closeWindow(id);

            if (self.windows.count() == 0)
                self.action_queue.queue(.quit);
        },
    };

    //- reset arena
    {
        self.tracing_arena_alloc.discard();

        if (self.arena_allocator.reset(.retain_capacity)) return;
        if (self.warn_arena_reset_failed) return;
        log.warn(
            "Failed to reset arena allocator while keeping capacity; " ++
                "further failures will not be logged",
            .{},
        );
        self.warn_arena_reset_failed = true;
    }
}

pub const Action = union(enum) {
    quit,
    close_window: WindowId,
};

pub const ActionQueue = EventQueueCircleBuffer(16, Action);

pub const AppWindow = struct {
    id: WindowId,
    should_draw: bool = true,

    context: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        deinit: *const fn (*anyopaque) void,
        getWindow: *const fn (*anyopaque) *BackendWindow,
        getCuState: *const fn (*anyopaque) *cu.State,
        buildUI: *const fn (*anyopaque) void,
    };

    pub fn deinit(self: AppWindow) void {
        self.vtable.deinit(self.context);
    }

    pub fn getWindow(self: AppWindow) *BackendWindow {
        return self.vtable.getWindow(self.context);
    }

    pub fn getCuState(self: AppWindow) *cu.State {
        return self.vtable.getCuState(self.context);
    }

    pub fn buildUI(self: AppWindow) void {
        self.vtable.buildUI(self.context);
    }
};
