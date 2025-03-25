const c = @cImport({
    @cInclude("SDL3/SDL_render.h");
});
const sdl = @import("sdl3.zig");
const Error = sdl.Error;
const Window = sdl.Window;
const Color = sdl.Color;
const Rect = sdl.Rect;
const FRect = sdl.FRect;
const Surface = sdl.Surface;
const PixelFormat = sdl.PixelFormat;

pub const Renderer = opaque {
    pub fn init(window: *Window, name: ?[:0]const u8) Error!*Renderer {
        const renderer = c.SDL_CreateRenderer(@ptrCast(window), @ptrCast(name));
        if (renderer == null) return error.sdl;
        return @ptrCast(renderer);
    }

    pub fn deinit(self: *Renderer) void {
        c.SDL_DestroyRenderer(@ptrCast(self));
    }

    pub fn setDrawColor(self: *Renderer, r: u8, g: u8, b: u8, a: u8) Error!void {
        if (!c.SDL_SetRenderDrawColor(@ptrCast(self), r, g, b, a)) return error.sdl;
    }

    pub fn setDrawColorT(self: *Renderer, color: Color) Error!void {
        if (!c.SDL_SetRenderDrawColor(@ptrCast(self), color.r, color.g, color.b, color.a)) return error.sdl;
    }

    pub fn renderRect(self: *Renderer, rect: *const FRect) Error!void {
        if (!c.SDL_RenderRect(@ptrCast(self), @ptrCast(rect))) return error.sdl;
    }

    pub fn fillRect(self: *Renderer, rect: *const FRect) Error!void {
        if (!c.SDL_RenderFillRect(@ptrCast(self), @ptrCast(rect))) return error.sdl;
    }

    pub fn renderLine(self: *Renderer, x1: f32, y1: f32, x2: f32, y2: f32) Error!void {
        if (!c.SDL_RenderLine(@ptrCast(self), x1, y1, x2, y2)) return error.sdl;
    }

    pub fn setClipRect(self: *Renderer, rect: ?*const Rect) Error!void {
        if (!c.SDL_SetRenderClipRect(@ptrCast(self), @ptrCast(rect))) return error.sdl;
    }

    pub fn clear(self: *Renderer) Error!void {
        if (!c.SDL_RenderClear(@ptrCast(self))) return error.sdl;
    }

    pub fn present(self: *Renderer) Error!void {
        if (!c.SDL_RenderPresent(@ptrCast(self))) return error.sdl;
    }

    pub fn createTextureFromSurface(self: *Renderer, surface: *Surface) Error!*Texture {
        const texture = c.SDL_CreateTextureFromSurface(
            @ptrCast(self),
            @alignCast(@ptrCast(surface)),
        ) orelse return error.sdl;
        return @ptrCast(@alignCast(texture));
    }

    pub fn renderTexture(
        self: *Renderer,
        texture: *Texture,
        src_rect: ?*const FRect,
        dest_rect: ?*const FRect,
    ) Error!void {
        if (!c.SDL_RenderTexture(@ptrCast(self), @ptrCast(texture), @ptrCast(src_rect), @ptrCast(dest_rect))) return error.sdl;
    }
};

pub const Texture = extern struct {
    format: PixelFormat,
    w: c_int,
    h: c_int,
    refcount: c_int,

    pub fn deinit(self: *Texture) void {
        c.SDL_DestroyTexture(@ptrCast(self));
    }
};
