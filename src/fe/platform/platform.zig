const builtin = @import("builtin");
const std = @import("std");

const cu = @import("cu");
const mt = cu.math;

pub const MenuBar = @import("MenuBar.zig");

const noop = false; // just for testing the api

pub const BackendType = enum {
    noop,
    wayland,
    sdl,

    pub fn getForOs(os_tag: std.Target.Os.Tag) ?BackendType {
        return switch (os_tag) {
            .linux => .wayland,
            .windows, .macos => .sdl,
            else => null,
        };
    }
};

pub const backend_type: BackendType =
    if (noop) .noop else BackendType.getForOs(builtin.os.tag) orelse
    @compileError("Unsupported platform");

pub const Backend = switch (backend_type) {
    .wayland => @import("linux/wayland.zig").WaylandBackend,
    .sdl => @compileError("TODO: Basic sdl backend"),
    .noop => @import("noop.zig").NoopBackend,
};

pub const WindowInitParams = struct {
    title: [:0]const u8 = "",
    app_id: ?[:0]const u8 = null,
    initial_size: mt.Size(u32) = .size(800, 600),
    min_size: ?mt.Size(u32) = .size(200, 200),
};

pub const BackendEvent = union(enum) {
    window_close: Backend.WindowId,
    window_resize: struct {
        window: Backend.WindowId,
        size: mt.Size(u32),
    },

    keyboard_focus: struct {
        window: Backend.WindowId,
        focused: bool,
    },
    key: cu.input.EventKind.KeyEvent,
    text: [:0]const u8,

    pointer_focus: struct {
        window: Backend.WindowId,
        focused: bool,
    },
    pointer_move: mt.Point(f32),
    pointer_button: cu.input.EventKind.MouseButtonEvent,
    pointer_scroll: mt.Point(f32),
};
