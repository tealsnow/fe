pub const Color = extern struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8,

    pub fn rgba(r: u8, g: u8, b: u8, a: u8) Color {
        return .{ .r = r, .g = g, .b = b, .a = a };
    }

    pub fn rgb(r: u8, g: u8, b: u8) Color {
        return rgba(r, g, b, 255);
    }

    /// 0xRRGGBB
    pub fn hexRgb(hex: u24) Color {
        return rgb(
            @truncate(hex >> 16),
            @truncate(hex >> 8),
            @truncate(hex),
        );
    }

    /// 0xRRGGBBAA
    pub fn hexRgba(hex: u32) Color {
        return rgba(
            @truncate(hex >> 24),
            @truncate(hex >> 16),
            @truncate(hex >> 8),
            @truncate(hex),
        );
    }
};
