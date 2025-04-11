const c = @cImport({
    @cInclude("SDL3_ttf/SDL_ttf.h");
});

const sdl = @import("sdl3.zig");
const Color = sdl.Color;
const Surface = sdl.Surface;

pub const Error = error{sdl_ttf};

pub fn init() Error!void {
    if (!c.TTF_Init()) return error.sdl_ttf;
}

pub fn quit() void {
    c.TTF_Quit();
}

pub const Font = opaque {
    pub fn open(file: [:0]u8, ptsize: f32) Error!*Font {
        const font = c.TTF_OpenFont(file, ptsize) orelse return error.sdl_ttf;
        return @ptrCast(font);
    }

    pub fn close(self: *Font) void {
        c.TTF_CloseFont(@ptrCast(self));
    }

    pub fn renderTextLCD(self: *Font, text: []const u8, fg: Color, bg: Color) Error!*Surface {
        const surface = c.TTF_RenderText_LCD(
            @ptrCast(self),
            text.ptr,
            text.len,
            @bitCast(fg),
            @bitCast(bg),
        ) orelse return error.sdl_ttf;
        return @ptrCast(@alignCast(surface));
    }

    pub fn getStringSize(self: *Font, text: []const u8) Error!struct { c_int, c_int } {
        var w: c_int = undefined;
        var h: c_int = undefined;
        if (!c.TTF_GetStringSize(@ptrCast(self), text.ptr, text.len, &w, &h)) return error.sdl_ttf;
        return .{ w, h };
    }

    pub fn setSize(self: *Font, ptsize: f32) Error!void {
        if (!c.TTF_SetFontSize(@ptrCast(self), ptsize)) return error.sdl_ttf;
    }

    pub fn getSize(self: *Font) Error!f32 {
        const size = c.TTF_GetFontSize(@ptrCast(self));
        if (size == 0) return error.sdl_ttf;
        return size;
    }

    pub fn setSizeDpi(self: *Font, ptsize: f32, hdpi: c_int, vdpi: c_int) Error!void {
        if (!c.TTF_SetFontSizeDPI(@ptrCast(self), ptsize, hdpi, vdpi)) return error.sdl_ttf;
    }

    pub fn getDpi(self: *Font) Error!struct { hdpi: c_int, vdpi: c_int } {
        var hdpi: c_int = undefined;
        var vdpi: c_int = undefined;
        if (!c.TTF_GetFontDPI(@ptrCast(self), &hdpi, &vdpi)) return error.sdl_ttf;
        return .{ .hdpi = hdpi, .vdpi = vdpi };
    }
};
