const c = @cImport({
    @cInclude("SDL3/SDL_error.h");
});
const Error = @import("sdl3.zig").Error;

pub fn getError() ?[*:0]const u8 {
    return @ptrCast(c.SDL_GetError());
}

pub fn setError(fmt: [*:0]const u8, args: anytype) !void {
    // I think letting the compiler figure out and complain
    // if anytype does not work is the best option
    if (!c.SDL_SetError(fmt, args)) return error.sdl;
}

pub fn clearError() !void {
    if (!c.SDL_ClearError()) return error.sdl;
}

pub fn outOfMemory() !void {
    if (!c.SDL_OutOfMemory()) return error.sdl;
}
