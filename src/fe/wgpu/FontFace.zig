const FontFace = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const log = std.log.scoped(.@"WgpuRenderer.FontFace");

const mt = @import("cu").math;

const hb = @import("hb.zig").c;
const ft = @import("freetype");

ft_face: *ft.Face,
hb_font: *hb.hb_font_t,

pt_size: i32,
ascender: f32,
descender: f32,
line_gap: f32,
line_height: f32,

pub fn fromPath(
    ft_lib: *ft.Library,
    path: [:0]const u8,
    index: i32,
    pt_size: i32,
    dpi: mt.Point(u16),
) !FontFace {
    const ft_face = try ft_lib.initFace(path, index);
    const hb_font =
        hb.hb_ft_font_create_referenced(@ptrCast(ft_face)) orelse
        return error.hb;

    try ft_face.setCharSize(0, pt_size * 64, dpi.x, dpi.y);

    const os2: *ft.c.TT_OS2 = ft_face.getSfntTable(.os2) orelse @panic("");

    const y_ppem = @as(f32, @floatFromInt(ft_face.size.metrics.y_ppem));
    const units_per_em = @as(f32, @floatFromInt(ft_face.units_per_EM));

    const ascender =
        @as(f32, @floatFromInt(os2.sTypoAscender)) *
        y_ppem / units_per_em;
    const descender =
        @as(f32, @floatFromInt(os2.sTypoDescender)) *
        y_ppem / units_per_em;
    const line_gap =
        @as(f32, @floatFromInt(os2.sTypoLineGap)) *
        y_ppem / units_per_em;

    const fudge = 4;
    const line_height = ascender - descender + fudge;

    return .{
        .ft_face = ft_face,
        .hb_font = hb_font,

        .pt_size = pt_size,
        .ascender = ascender,
        .descender = descender,
        .line_gap = line_gap,
        .line_height = line_height,
    };
}

pub fn deinit(face: FontFace) void {
    face.ft_face.deinit();
    hb.hb_font_destroy(face.hb_font);
}
