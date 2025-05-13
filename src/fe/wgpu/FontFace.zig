const FontFace = @This();

const hb = @import("hb.zig").c;
const ft = @import("freetype");

ft_face: *ft.Face,
hb_font: *hb.hb_font_t,

pub fn fromPath(ft_lib: ft.Library, path: [:0]const u8) !FontFace {
    const ft_face = try ft_lib.initFace(path, 0);
    const hb_font =
        hb.hb_ft_font_create_referenced(@ptrCast(ft_face)) orelse
        return error.hb;

    return .{
        .ft_face = ft_face,
        .hb_font = hb_font,
    };
}

// pub fn fromFtFace(ft_face: *ft.Face) !FontFace {
//     const hb_font =
//         hb.hb_ft_font_create_referenced(@ptrCast(ft_face)) orelse
//         return error.hb;
//     return .{
//         .ft_face = ft_face,
//         .hb_font = hb_font,
//     };
// }

pub fn deinit(face: FontFace) void {
    face.ft_face.deinit();
    hb.hb_font_destroy(face.hb_font);
}

pub fn setSize(face: FontFace, pt: i32, dpi: u16) !void {
    // const vert_dpi: u16 = @intFromFloat(@floor(conn.vdpi));
    // const horz_dpi: u16 = @intFromFloat(@floor(conn.hdpi));
    // log.debug("dpi: {d}x{d}", .{ horz_dpi, vert_dpi });
    // try ft_face.setCharSize(0, pt * 64, horz_dpi, vert_dpi);

    try face.ft_face.setCharSize(0, pt * 2 * 64, dpi, dpi);
}

pub fn lineHeight(face: *const FontFace) f32 {
    return @as(f32, @floatFromInt(face.ft_face.size.metrics.height)) / 64;
}

pub fn topLeftToBaselineAdjustment(face: *const FontFace) f32 {
    const line_height = face.lineHeight();
    const descender =
        @as(f32, @floatFromInt(face.ft_face.size.metrics.descender)) / 64;
    return line_height + descender;
}
