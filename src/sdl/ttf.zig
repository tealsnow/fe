pub const sdl = @import("sdl.zig");
const c = sdl.c;

pub fn init() !void {
    if (c.TTF_Init() != 0)
        return error.ttf_init;
}

pub fn deinit() void {
    c.TTF_Quit();
}

pub const Font = opaque {
    pub fn open(file: [*c]u8, ptsize: c_int) !*Font {
        const font = c.TTF_OpenFont(file, ptsize);
        if (font == null)
            return error.ttf_open_font;
        return @ptrCast(font.?);
    }

    pub fn deinit(self: *Font) void {
        c.TTF_CloseFont(@ptrCast(self));
    }

    pub fn renderTextSolid(self: *Font, text: [*c]const u8, color: sdl.Color) !*sdl.Surface {
        const surface = c.TTF_RenderText_Solid(@ptrCast(self), text, color);
        if (surface == null)
            return error.ttf_render_text_solid;
        return @ptrCast(surface.?);
    }
};
