const c = @cImport({
    @cInclude("SDL3/SDL_surface.h");
});

const sdl = @import("sdl3.zig");
const PixelFormat = sdl.pixels.PixelFormat;

pub const SurfaceFlag = struct {
    pub const preallocated = c.SDL_SURFACE_PREALLOCATED;
    pub const lock_needed = c.SDL_SURFACE_LOCK_NEEDED;
    pub const locked = c.SDL_SURFACE_LOCKED;
    pub const simd_aligned = c.SDL_SURFACE_SIMD_ALIGNED;
};

// see `SurfaceFlag`
pub const SurfaceFlags = u32;

pub const Surface = extern struct {
    flags: SurfaceFlags,
    format: PixelFormat,
    w: c_int,
    h: c_int,
    pitch: c_int,
    pixels: ?*anyopaque,
    refcount: c_int,
    reserved: ?*anyopaque,

    pub fn deinit(self: *Surface) void {
        c.SDL_DestroySurface(@ptrCast(self));
    }
};
