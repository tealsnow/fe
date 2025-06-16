const std = @import("std");
const Allocator = std.mem.Allocator;

const cu = @import("cu");
const mt = cu.math;

const platform = @import("platform.zig");
const WindowInitParams = platform.WindowInitParams;
const BackendEvent = platform.BackendEvent;
const MenuBar = @import("MenuBar.zig");

pub const NoopBackend = struct {
    pub const Window = NoopWindow;
    pub const WindowId = u32;

    gpa: Allocator,
    windows: std.AutoArrayHashMapUnmanaged(WindowId, *Window) = .empty,
    next_window_id: u32 = 1,

    pub fn init(gpa: Allocator) !*NoopBackend {
        const plat = try gpa.create(NoopBackend);
        plat.* = .{ .gpa = gpa };
        return plat;
    }

    pub fn deinit(self: *NoopBackend) void {
        const gpa = self.gpa;
        gpa.destroy(self);
    }

    pub fn createWindow(self: *NoopBackend, params: WindowInitParams) !*Window {
        _ = params;

        const window_id = blk: {
            const id = self.next_window_id;
            self.next_window_id += 1;
            break :blk id;
        };

        const window = try self.gpa.create(Window);
        try self.windows.put(self.gpa, window_id, window);
        window.* = .{ .id = window_id };
        return window;
    }

    pub fn closeWindow(self: *NoopBackend, window_id: WindowId) void {
        const window =
            (self.windows.fetchSwapRemove(window_id) orelse return).value;
        self.gpa.destroy(window);
    }

    pub fn getEvents(
        self: *NoopBackend,
        arena: Allocator,
    ) ![]const BackendEvent {
        _ = self;
        _ = arena;
        return .{};
    }
};

pub const NoopWindow = struct {
    id: NoopBackend.WindowId,
    font_kind_map: cu.FontKindMap = .initFill(undefined),

    pub fn getId(self: *NoopWindow) NoopBackend.WindowId {
        return self.id;
    }

    pub fn getTitle(self: *NoopWindow) [:0]const u8 {
        _ = self;
        return "";
    }

    pub fn callbacks(self: *NoopWindow) cu.State.Callbacks {
        _ = self;
        return CuCallbacks.callbacks();
    }

    pub fn startBuild(self: *NoopWindow, menu_bar: MenuBar) void {
        _ = self;
        _ = menu_bar;
    }

    pub fn endBuild(self: *NoopWindow) void {
        _ = self;
    }

    pub fn present(self: *NoopWindow, arena: Allocator, cu_state: cu.State) !void {
        _ = self;
        _ = arena;
        _ = cu_state;
    }

    pub const CuCallbacks = struct {
        pub fn callbacks() cu.State.Callbacks {
            return .{
                .context = undefined,
                .vtable = .{
                    .measureText = &measureText,
                    .lineHeight = &lineHeight,
                    .getGraphicsInfo = &getGraphicsInfo,
                },
            };
        }

        fn measureText(
            context: *anyopaque,
            text: []const u8,
            font_handle: cu.State.FontHandle,
        ) mt.Size(f32) {
            _ = context;
            _ = text;
            _ = font_handle;
            return .zero;
        }

        fn lineHeight(context: *anyopaque, font_handle: cu.State.FontHandle) f32 {
            _ = context;
            _ = font_handle;
            return 0;
        }

        fn getGraphicsInfo(context: *anyopaque) cu.State.GraphicsInfo {
            _ = context;
            return .{
                .double_click_time_us = 500 * std.time.us_per_ms,
                .cursor_size_px = 24,
            };
        }
    };
};
