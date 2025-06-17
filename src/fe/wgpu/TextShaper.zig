const TextShaper = @This();

const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const log = std.log.scoped(.TextShaper);

const FontFace = @import("FontFace.zig");
const FontAtlas = @import("FontAtlas.zig");
const RectInstance = @import("WgpuRenderer.zig").RectInstance;

const mt = @import("cu").math;

const hb = @import("hb.zig").c;
const ft = @import("freetype");

buffer: *hb.hb_buffer_t,

pub fn init() !TextShaper {
    const hb_buffer = hb.hb_buffer_create() orelse return error.hb;
    return .{ .buffer = hb_buffer };
}

pub fn deinit(shaper: TextShaper) void {
    hb.hb_buffer_destroy(shaper.buffer);
}

pub fn shape(
    shaper: *const TextShaper,
    font_face: *const FontFace,
    font_atlas: *FontAtlas,
    string: []const u8,
) !ShapedText {
    hb.hb_buffer_reset(shaper.buffer);

    hb.hb_buffer_add_utf8(
        shaper.buffer,
        string.ptr,
        @intCast(string.len),
        0,
        -1,
    );

    hb.hb_buffer_guess_segment_properties(shaper.buffer);

    hb.hb_shape(font_face.hb_font, shaper.buffer, null, 0);

    var glyph_info_count: u32 = undefined;
    const glyph_info =
        hb.hb_buffer_get_glyph_infos(shaper.buffer, &glyph_info_count) orelse
        return error.hb;

    var glyph_pos_count: u32 = undefined;
    const glyph_pos =
        hb.hb_buffer_get_glyph_positions(shaper.buffer, &glyph_pos_count) orelse
        return error.hb;

    assert(glyph_info_count == glyph_pos_count);
    const glyph_count = glyph_info_count;

    return .{
        .font_face = font_face,
        .font_atlas = font_atlas,
        .glyph_infos = glyph_info[0..glyph_count],
        .glyph_positions = glyph_pos[0..glyph_count],
    };
}

pub const ShapedText = struct {
    font_face: *const FontFace,
    font_atlas: *FontAtlas,
    glyph_infos: []hb.hb_glyph_info_t,
    glyph_positions: []hb.hb_glyph_position_t,

    debug_rects: bool = false,

    pub fn calculateSize(
        data: *const ShapedText,
        alloc: Allocator,
    ) !mt.Size(f32) {
        var size = mt.Size(f32).zero;
        size.height = data.font_face.line_height;

        if (data.glyph_positions.len == 0) return size;

        // sum all advances except last
        var total_width: f32 = 0;
        for (data.glyph_positions[0 .. data.glyph_positions.len - 1]) |pos| {
            total_width += @as(f32, @floatFromInt(pos.x_advance)) / 64;
        }

        // handle first glyph's possible negative offset
        const first_x_offset =
            @as(f32, @floatFromInt(data.glyph_positions[0].x_offset)) / 64;
        if (first_x_offset < 0) total_width -= first_x_offset;

        // last glyph
        const last_idx = data.glyph_positions.len - 1;
        const last_pos = data.glyph_positions[last_idx];
        const last_glyph: FontAtlas.GlyphIndex =
            @enumFromInt(data.glyph_infos[last_idx].codepoint);
        const last_info =
            try data.font_atlas.getInfoOrCacheForGlyphIndex(alloc, last_glyph);

        const last_advance = @as(f32, @floatFromInt(last_pos.x_advance)) / 64;
        const last_bitmap_offset =
            @as(f32, @floatFromInt(last_info.bitmap_offset.x));

        // @HACK:
        //  without this the right side does not have quite enough padding
        //  making it look off center in a rect
        //  I don't particularly like this solution but it works good enough
        //  for now
        total_width += last_advance - (last_bitmap_offset / 2.0);

        size.width = total_width;
        return size;
    }

    pub fn generateRects(
        data: *const ShapedText,
        alloc: Allocator,
        list: *std.ArrayListUnmanaged(RectInstance),
        origin: mt.Point(f32), // topleft
        color: mt.RgbaF32,
    ) !void {
        var cursor = origin;

        // adjust topleft coord to baseline
        cursor.y += data.font_face.ascender;

        const dbg_colors = [_]mt.RgbaF32{
            .hexRgb(0x0000ff), // blue
            .hexRgb(0x00ffff), // cyan
            .hexRgb(0x00ff00), // green
            .hexRgb(0xffff00), // yellow
            .hexRgb(0xff0000), // red
        };

        const prealloc_rects_len =
            if (data.debug_rects)
                data.glyph_infos.len * 3
            else
                data.glyph_infos.len;

        try list.ensureUnusedCapacity(alloc, prealloc_rects_len);

        for (data.glyph_infos, 0..) |info, i| {
            // codepoint here is a misnomer - it is the glyph index in the
            // font and has no correlation to the unicode character
            const glyph_index: FontAtlas.GlyphIndex =
                @enumFromInt(info.codepoint);

            const atlas_info =
                try data.font_atlas
                    .getInfoOrCacheForGlyphIndex(alloc, glyph_index);
            const tex_coords = atlas_info.tex_coords.floatFromInt(f32);

            const pos = data.glyph_positions[i];

            const x_offset = @as(f32, @floatFromInt(pos.x_offset)) / 64;
            const y_offset = @as(f32, @floatFromInt(pos.y_offset)) / 64;

            const x_advance = @as(f32, @floatFromInt(pos.x_advance)) / 64;
            const y_advance = @as(f32, @floatFromInt(pos.y_advance)) / 64;

            // const bearing = atlas_info.bearing;
            // const x_bearing = @as(f32, @floatFromInt(bearing.x)) / 64;
            // const y_bearing = @as(f32, @floatFromInt(bearing.y)) / 64;

            const bitmap_offset = atlas_info.bitmap_offset;
            const x_bitmap_offset: f32 = @floatFromInt(bitmap_offset.x);
            const y_bitmap_offset: f32 = @floatFromInt(bitmap_offset.y);

            const point = mt.Point(f32)
                .point(
                    // cursor.x + x_offset + x_bearing,
                    // cursor.y + y_offset + -y_bearing,
                    cursor.x + x_offset + x_bitmap_offset,
                    cursor.y + y_offset + -y_bitmap_offset,
                )
                .round();

            // const size_fixed = atlas_info.size;
            // const width = @as(f32, @floatFromInt(size_fixed.width)) / 64;
            // const height = @as(f32, @floatFromInt(size_fixed.height)) / 64;
            // const size = mt.Size(f32).size(width, height);

            const size = tex_coords.size();

            list.appendAssumeCapacity(.{
                .dst = .fromBounds(.bounds(point, size)),
                .tex = tex_coords,
                .color = color,
            });

            if (data.debug_rects) {
                const dbg_color = dbg_colors[i % dbg_colors.len];

                list.appendAssumeCapacity(.{
                    .dst = .fromBounds(.bounds(point, size)),
                    .color = dbg_color,
                    .border_thickness = 1,
                });
                list.appendAssumeCapacity(.{
                    .dst = .fromBounds(.bounds(cursor, .square(2))),
                    .color = dbg_color,
                });
            }

            cursor.x += x_advance;
            cursor.y += y_advance;
        }
    }
};
