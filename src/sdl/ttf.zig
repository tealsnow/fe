const std = @import("std");

const sdl = @import("sdl.zig");
const c = sdl.c;

pub fn init() !void {
    if (c.TTF_Init() != 0)
        return error.ttf_init;
}

pub fn quit() void {
    c.TTF_Quit();
}

pub fn getError() ?[:0]const u8 {
    const err = c.TTF_GetError();
    return if (err != null)
        std.mem.sliceTo(err, 0)
    else
        null;
}

pub const Font = opaque {
    pub fn open(file: [*c]u8, ptsize: c_int) !*Font {
        const font = c.TTF_OpenFont(file, ptsize) orelse return error.ttf_open_font;
        return @ptrCast(font);
    }

    pub fn deinit(self: *Font) void {
        c.TTF_CloseFont(@ptrCast(self));
    }

    pub fn renderTextSolid(self: *Font, text: [:0]const u8, color: sdl.Color) !*sdl.Surface {
        const surface = c.TTF_RenderText_Solid(
            @ptrCast(self),
            text,
            color,
        ) orelse return error.tff_render_text_sold;
        return @ptrCast(@alignCast(surface));
    }

    pub fn renderTextBlended(self: *Font, text: [:0]const u8, fg: sdl.Color) !*sdl.Surface {
        const surface = c.TTF_RenderText_Blended(
            @ptrCast(self),
            text,
            fg,
        ) orelse return error.tff_render_text_blend;
        return @ptrCast(@alignCast(surface));
    }

    pub fn renderTextShaded(self: *Font, text: [:0]const u8, fg: sdl.Color, bg: sdl.Color) !*sdl.Surface {
        const surface = c.TTF_RenderText_Shaded(
            @ptrCast(self),
            text,
            fg,
            bg,
        ) orelse return error.tff_render_text_shaded;
        return @ptrCast(@alignCast(surface));
    }

    pub fn renderTextLCD(self: *Font, text: [:0]const u8, fg: sdl.Color, bg: sdl.Color) !*sdl.Surface {
        const surface = c.TTF_RenderText_LCD(
            @ptrCast(self),
            text,
            fg,
            bg,
        ) orelse return error.tff_render_text_lcd;
        return @ptrCast(@alignCast(surface));
    }

    pub fn sizeText(self: *Font, text: [:0]const u8, w: *c_int, h: *c_int) !void {
        if (c.TTF_SizeText(@ptrCast(self), text, w, h) != 0)
            return error.ttf_size_text;
    }
};
