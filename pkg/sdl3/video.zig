const c = @cImport({
    @cInclude("SDL3/SDL_video.h");
});
const sdl = @import("sdl3.zig");
const Error = sdl.Error;
const Point = sdl.Point;

pub const WindowID = enum(u32) { _ };

pub const DisplayID = enum(u32) { _ };

pub const HitTest = *const fn (*Window, *const Point, ?*anyopaque) callconv(.c) HitTestResult;

pub const HitTestResult = enum(c_uint) {
    normal = c.SDL_HITTEST_NORMAL,
    draggable = c.SDL_HITTEST_DRAGGABLE,
    resize_topleft = c.SDL_HITTEST_RESIZE_TOPLEFT,
    resize_top = c.SDL_HITTEST_RESIZE_TOP,
    resize_topright = c.SDL_HITTEST_RESIZE_TOPRIGHT,
    resize_right = c.SDL_HITTEST_RESIZE_RIGHT,
    resize_bottomright = c.SDL_HITTEST_RESIZE_BOTTOMRIGHT,
    resize_bottom = c.SDL_HITTEST_RESIZE_BOTTOM,
    resize_bottomleft = c.SDL_HITTEST_RESIZE_BOTTOMLEFT,
    resize_left = c.SDL_HITTEST_RESIZE_LEFT,
};

pub const WindowFlag = struct {
    pub const fullscreen = c.SDL_WINDOW_FULLSCREEN;
    pub const opengl = c.SDL_WINDOW_OPENGL;
    pub const occluded = c.SDL_WINDOW_OCCLUDED;
    pub const hidden = c.SDL_WINDOW_HIDDEN;
    pub const borderless = c.SDL_WINDOW_BORDERLESS;
    pub const resizable = c.SDL_WINDOW_RESIZABLE;
    pub const minimized = c.SDL_WINDOW_MINIMIZED;
    pub const maximized = c.SDL_WINDOW_MAXIMIZED;
    pub const mouse_grabbed = c.SDL_WINDOW_MOUSE_GRABBED;
    pub const input_focus = c.SDL_WINDOW_INPUT_FOCUS;
    pub const mouse_focus = c.SDL_WINDOW_MOUSE_FOCUS;
    pub const external = c.SDL_WINDOW_EXTERNAL;
    pub const modal = c.SDL_WINDOW_MODAL;
    pub const high_pixel_density = c.SDL_WINDOW_HIGH_PIXEL_DENSITY;
    pub const mouse_capture = c.SDL_WINDOW_MOUSE_CAPTURE;
    pub const mouse_relative_mode = c.SDL_WINDOW_MOUSE_RELATIVE_MODE;
    pub const always_on_top = c.SDL_WINDOW_ALWAYS_ON_TOP;
    pub const utility = c.SDL_WINDOW_UTILITY;
    pub const tooltip = c.SDL_WINDOW_TOOLTIP;
    pub const popup_menu = c.SDL_WINDOW_POPUP_MENU;
    pub const keyboard_grabbed = c.SDL_WINDOW_KEYBOARD_GRABBED;
    pub const vulkan = c.SDL_WINDOW_VULKAN;
    pub const metal = c.SDL_WINDOW_METAL;
    pub const transparent = c.SDL_WINDOW_TRANSPARENT;
    pub const not_focusable = c.SDL_WINDOW_NOT_FOCUSABLE;
};

// see `WindowFlag`
pub const WindowFlags = u64;

pub const Window = opaque {
    pub fn init(title: [*:0]const u8, w: c_int, h: c_int, flags: WindowFlags) Error!*Window {
        return @ptrCast(c.SDL_CreateWindow(title, w, h, flags) orelse return error.sdl);
    }

    pub fn initPopup(parent: *Window, offset_x: c_int, offset_y: c_int, w: c_int, h: c_int, flags: WindowFlags) !*Window {
        return @ptrCast(c.SDL_CreatePopupWindow(@ptrCast(parent), offset_x, offset_y, w, h, flags) orelse return error.sdl);
    }

    pub fn deinit(self: *Window) void {
        c.SDL_DestroyWindow(@ptrCast(self));
    }

    pub fn show(self: *Window) Error!void {
        if (!c.SDL_ShowWindow(@ptrCast(self))) return error.sdl;
    }

    pub fn getSize(self: *Window) Error!struct { c_int, c_int } {
        var w: c_int = undefined;
        var h: c_int = undefined;
        if (!c.SDL_GetWindowSize(@ptrCast(self), &w, &h)) return error.sdl;
        return .{ w, h };
    }

    pub fn getID(self: *Window) WindowID {
        return @enumFromInt(c.SDL_GetWindowID(@ptrCast(self)));
    }

    pub fn setHitTest(window: *Window, callback: HitTest, callback_data: ?*anyopaque) Error!void {
        if (!c.SDL_SetWindowHitTest(@ptrCast(window), @ptrCast(callback), callback_data)) return error.sdl;
    }

    pub fn getFlags(window: *Window) WindowFlags {
        return c.SDL_GetWindowFlags(@ptrCast(window));
    }

    pub fn maximize(window: *Window) Error!void {
        if (!c.SDL_MaximizeWindow(@ptrCast(window))) return error.sdl;
    }

    pub fn restore(window: *Window) Error!void {
        if (!c.SDL_RestoreWindow(@ptrCast(window))) return error.sdl;
    }

    pub fn minimize(window: *Window) Error!void {
        if (!c.SDL_MinimizeWindow(@ptrCast(window))) return error.sdl;
    }

    pub fn setFullscreen(window: *Window, fullscreen: bool) Error!void {
        if (!c.SDL_SetWindowFullscreen(@ptrCast(window), fullscreen)) return error.sdl;
    }

    pub fn sync(window: *Window) !void {
        if (!c.SDL_SyncWindow(@ptrCast(window))) return error.sdl;
    }

    pub fn setPosition(window: *Window, x: c_int, y: c_int) !void {
        if (!c.SDL_SetWindowPosition(@ptrCast(window), x, y)) return error.sdl;
    }

    pub fn getPosition(window: *Window) !struct { c_int, c_int } {
        var x: c_int = undefined;
        var y: c_int = undefined;
        if (!c.SDL_GetWindowPosition(@ptrCast(window), &x, &y)) return error.sdl;
        return .{ x, y };
    }

    pub fn getSurface(window: *Window) Error!*sdl.Surface {
        const surface = c.SDL_GetWindowSurface(@ptrCast(window));
        if (surface == null) return error.sdl;
        return @ptrCast(surface);
    }
};
