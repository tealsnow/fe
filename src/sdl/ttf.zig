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
    fn asPtr(self: *Font) *c.TTF_Font {
        return @alignCast(@ptrCast(self));
    }

    fn asPtrConst(self: *const Font) *const c.TTF_Font {
        return @alignCast(@ptrCast(self));
    }

    pub fn open(file: [*c]u8, ptsize: c_int) !*Font {
        const font = c.TTF_OpenFont(file, ptsize) orelse return error.ttf_font_openFont;
        return @ptrCast(font);
    }

    pub fn close(self: *Font) void {
        c.TTF_CloseFont(@ptrCast(self));
    }

    pub fn faceFamilyName(self: *const Font) ![:0]const u8 {
        const name = c.TTF_FontFaceFamilyName(self.asPtrConst());
        return if (name != null)
            std.mem.sliceTo(name, 0)
        else
            return error.ttf_font_faceFamilyName;
    }

    pub fn renderTextSolid(self: *Font, text: [:0]const u8, color: sdl.Color) !*sdl.Surface {
        const surface = c.TTF_RenderText_Solid(
            self.asPtr(),
            text,
            color,
        ) orelse return error.tff_font_renderTextSold;
        return @ptrCast(@alignCast(surface));
    }

    pub fn renderTextBlended(self: *Font, text: [:0]const u8, fg: sdl.Color) !*sdl.Surface {
        const surface = c.TTF_RenderText_Blended(
            self.asPtr(),
            text,
            fg,
        ) orelse return error.tff_font_renderTextBlend;
        return @ptrCast(@alignCast(surface));
    }

    pub fn renderTextShaded(self: *Font, text: [:0]const u8, fg: sdl.Color, bg: sdl.Color) !*sdl.Surface {
        const surface = c.TTF_RenderText_Shaded(
            self.asPtr(),
            text,
            fg,
            bg,
        ) orelse return error.tff_font_renderTextShaded;
        return @ptrCast(@alignCast(surface));
    }

    pub fn renderTextLCD(self: *Font, text: [:0]const u8, fg: sdl.Color, bg: sdl.Color) !*sdl.Surface {
        const surface = c.TTF_RenderText_LCD(
            self.asPtr(),
            text,
            fg,
            bg,
        ) orelse return error.tff_font_renderTextLcd;
        return @ptrCast(@alignCast(surface));
    }

    pub fn sizeText(self: *Font, text: [:0]const u8, w: *c_int, h: *c_int) !void {
        if (c.TTF_SizeText(self.asPtr(), text, w, h) != 0)
            return error.ttf_font_sizeText;
    }

    pub fn sizeTextTuple(self: *Font, text: [:0]const u8) !struct { c_int, c_int } {
        var w: c_int = undefined;
        var h: c_int = undefined;
        try self.sizeText(text, &w, &h);
        return .{ w, h };
    }

    pub fn setSize(self: *Font, ptsize: c_int) !void {
        if (c.TTF_SetFontSize(@ptrCast(self), ptsize) != 0)
            return error.ttf_font_setSize;
    }

    pub fn setSizeDpi(self: *Font, ptsize: c_int, hdpi: c_int, vdpi: c_int) !void {
        if (c.TTF_SetFontSizeDPI(@ptrCast(self), ptsize, hdpi, vdpi) != 0)
            return error.ttf_font_setSizeDpi;
    }
};
