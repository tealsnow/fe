const ShapedText = @This();

const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;

const FontAtlas = @import("FontAtlas.zig");
const FontFace = @import("FontFace.zig");
const RectInstance = @import("WgpuRenderer.zig").RectInstance;

const mt = @import("../math.zig");

const hb = @import("hb.zig").c;

font_face: *const FontFace,

buffer: *hb.hb_buffer_t,
string: []const u8,

glyph_infos: []hb.hb_glyph_info_t,
glyph_positions: []hb.hb_glyph_position_t,

pub fn init(font_face: *const FontFace, string: []const u8) !ShapedText {
    //- setup buffer
    const hb_buffer = hb.hb_buffer_create() orelse return error.hb;
    hb.hb_buffer_add_utf8(
        hb_buffer,
        string.ptr,
        @intCast(string.len),
        0,
        -1,
    );
    hb.hb_buffer_guess_segment_properties(hb_buffer);

    //- shape
    hb.hb_shape(font_face.hb_font, hb_buffer, null, 0);

    var glyph_info_count: u32 = undefined;
    const glyph_info =
        hb.hb_buffer_get_glyph_infos(hb_buffer, &glyph_info_count) orelse
        return error.hb;

    var glyph_pos_count: u32 = undefined;
    const glyph_pos =
        hb.hb_buffer_get_glyph_positions(hb_buffer, &glyph_pos_count) orelse
        return error.hb;

    assert(glyph_info_count == glyph_pos_count);
    const glyph_count = glyph_info_count;

    return .{
        .font_face = font_face,

        .buffer = hb_buffer,
        .string = string,

        .glyph_infos = glyph_info[0..glyph_count],
        .glyph_positions = glyph_pos[0..glyph_count],
    };
}

pub fn deinit(text: ShapedText) void {
    hb.hb_buffer_destroy(text.buffer);
}

pub fn calculateSize(text: *const ShapedText) mt.Size(i32) {
    var size = mt.Size(i32).zero;

    size.height = text.font_face.lineHeight();

    for (text.glyph_positions) |pos| {
        const x_advance = pos.x_advance >> 6;
        const y_advance = pos.y_advance >> 6;

        size.width += x_advance;
        size.height += y_advance; // not sure if this is correct
    }

    return size;
}

pub fn generateRectsArrayList(
    text: *const ShapedText,
    gpa: Allocator,
    font_atlas: *FontAtlas,
    list: *std.ArrayListUnmanaged(RectInstance),
    origin: mt.Point(i32), // topleft
    color: mt.RgbaF32,
) !void {
    var cursor = origin;

    // adjust from topleft to baseline
    cursor.y += text.font_face.topLeftToBaselineAdjustment();

    try list.ensureUnusedCapacity(gpa, text.glyph_infos.len);

    for (text.glyph_infos, 0..) |info, i| {
        // codepoint here is a misnomer - it is the glyph index in the
        // font and has no correlation to the unicode character
        const glyph_index: FontAtlas.GlyphIndex =
            @enumFromInt(info.codepoint);

        const atlas_info =
            try font_atlas.getInfoOrCacheForGlyphIndex(gpa, glyph_index);
        const tex_coords = atlas_info.tex_coords.floatFromInt(f32);
        const bearing = atlas_info.bearing;

        const pos = text.glyph_positions[i];
        const x_offset = pos.x_offset;
        const y_offset = pos.y_offset;
        const x_advance = pos.x_advance >> 6;
        const y_advance = pos.y_advance >> 6;

        const point = mt.Point(i32)
            .pt(
                cursor.x + x_offset + bearing.x,
                cursor.y + y_offset + -bearing.y,
            )
            .floatFromInt(f32)
            .floor();
        const size = atlas_info.size.floatFromInt(f32);

        try list.append(
            gpa,
            .recti(
                .fromBounds(.bounds(point, size)),
                tex_coords,
                color,
                0,
                0,
                0,
            ),
        );

        cursor.x += x_advance;
        cursor.y += y_advance;
    }
}

/// origin is top left point to start from
pub fn generateRects(
    text: *const ShapedText,
    gpa: Allocator,
    font_atlas: *FontAtlas,
    origin: mt.Point(i32),
    color: mt.RgbaF32,
) ![]RectInstance {
    var list =
        try std.ArrayListUnmanaged(RectInstance)
            .initCapacity(gpa, text.glyph_infos.len);

    try text.generateRectsArrayList(gpa, font_atlas, &list, origin, color);

    const slice = try list.toOwnedSlice(gpa);
    return slice;
}
