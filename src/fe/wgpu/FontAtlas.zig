const FontAtlas = @This();

// @TODO: auto grow

const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

const mt = @import("../math.zig");
const FontFace = @import("FontFace.zig");

//= fields

bytes: []u32, // 4 bit rgba format
size: mt.Size(u32),

cursor: mt.Point(u32) = .all(0),
max_y: u32 = 0,

face: *const FontFace,

glyph_map: std.AutoHashMapUnmanaged(GlyphIndex, GlyphInfo) = .empty,

//= types

/// Index into font for a specific glyph
/// has no relation to unicode codepoint or consistency between fonts
pub const GlyphIndex = enum(u32) {
    missing = 0, // by convention 0 maps to the missing character
    _, // every other index is dependent on the font used
};

pub const GlyphInfo = struct {
    /// top-left to bottom-right
    tex_coords: mt.Rect(u32),
    /// Per character pos data to be used in conjuction with shaping
    bearing: mt.Point(i32),
    size: mt.Size(i32),
};

pub const TextureDataRef = struct {
    bytes: [*]u32,
    size: mt.Size(u32),
};

//= methods

pub fn init(
    gpa: Allocator,
    size: mt.Size(u32),
    face: *const FontFace,
) !FontAtlas {
    const bytes = try gpa.alloc(u32, size.width * size.height);
    return .{
        .bytes = bytes,
        .size = size,
        .face = face,
    };
}

pub fn deinit(atlas: *FontAtlas, gpa: Allocator) void {
    gpa.free(atlas.bytes);
    atlas.glyph_map.deinit(gpa);
}

pub fn getInfoOrCacheForGlyphIndex(
    atlas: *FontAtlas,
    gpa: Allocator,
    glyph_index: GlyphIndex,
) !GlyphInfo {
    if (atlas.glyph_map.get(glyph_index)) |info| return info;

    const ft_face = atlas.face.ft_face;

    try ft_face.loadGlyph(@intFromEnum(glyph_index), .{});
    try ft_face.glyph.render(.lcd);
    const glyph = ft_face.glyph;
    const bitmap = glyph.bitmap;

    assert(bitmap.pixel_mode == .lcd);

    const rect = atlas.blit(
        .size(bitmap.width, bitmap.rows),
        bitmap.pitch,
        bitmap.buffer,
    );

    const info = GlyphInfo{
        .tex_coords = rect,
        .bearing = .pt(
            @intCast(glyph.metrics.horiBearingX >> 6),
            @intCast(glyph.metrics.horiBearingY >> 6),
        ),
        .size = .size(
            @intCast(glyph.metrics.width >> 6),
            @intCast(glyph.metrics.height >> 6),
        ),
    };

    try atlas.glyph_map.put(gpa, glyph_index, info);

    return info;
}

pub fn getGlyphIndexForCodepoint(
    atlas: *const FontAtlas,
    codepoint: u21,
) GlyphIndex {
    const idx = atlas.face.ft_face.getCharIndex(codepoint) orelse 0;
    return @enumFromInt(idx);
}

pub fn blit(
    atlas: *FontAtlas,
    size: mt.Size(u32),
    pitch: i32, // row
    bitmap: [*]const u8,
) mt.Rect(u32) {
    if (atlas.cursor.x + size.width > atlas.size.width) {
        atlas.cursor = .{
            .x = 0,
            .y = atlas.max_y,
        };
    }

    if (atlas.cursor.y + size.height > atlas.size.height) {
        @panic("TODO: atlas overflow");
    }

    const rect = mt.Rect(u32).fromBounds(.bounds(atlas.cursor, size));

    if (pitch < 0) {
        // @TODO: if row padding is negative the flow is up,
        //  we only support down flow atm
        @panic("TODO: up flow bitmap");
    }
    const pitch_u: usize = @intCast(pitch);

    for (0..size.height) |bitmap_y| {
        for (0..size.width) |bitmap_x| {
            const atlas_x = atlas.cursor.x + bitmap_x;
            const atlas_y = atlas.cursor.y + bitmap_y;

            const bitmap_i = bitmap_y * pitch_u + bitmap_x;
            const atlas_i = atlas_y * atlas.size.width + atlas_x;

            const bitmap_pixel_rgb_u8: [3]u8 =
                bitmap[bitmap_i..(bitmap_i + 3)][0..3].*;
            const bitmap_pixel_rgb_u24: u24 =
                @bitCast(bitmap_pixel_rgb_u8);

            const bitmap_pixel_rgba_u32: u32 =
                @as(u32, bitmap_pixel_rgb_u24) << 8 | 0x000000ff;

            atlas.bytes[atlas_i] = bitmap_pixel_rgba_u32;

            // const r = bitmap[bitmap_i + 0];
            // const g = bitmap[bitmap_i + 1];
            // const b = bitmap[bitmap_i + 2];

            // var atlas_pixel: u32 = 0;
            // atlas_pixel |= @as(u32, r) << 24;
            // atlas_pixel |= @as(u32, g) << 16;
            // atlas_pixel |= @as(u32, b) << 8;
            // atlas_pixel |= @as(u32, 0xff) << 0;

            // atlas.bytes[atlas_i] = atlas_pixel;
        }
    }
    atlas.cursor.x += size.width;
    atlas.max_y = @max(atlas.max_y, atlas.cursor.y + size.height);

    return rect;
}

/// assumes size is 32 bit aligned
pub fn writeToBmp(
    atlas: *const FontAtlas,
    file_name: []const u8,
) !void {
    const cwd = std.fs.cwd();

    const out_file = try cwd.createFile(file_name, .{});
    defer out_file.close();

    var buffered_writer = std.io.bufferedWriter(out_file.writer());
    var w = buffered_writer.writer();

    const width = atlas.size.width;
    const height = atlas.size.height;

    //- BMP header
    try w.writeInt(u16, 0x4D42, .little); // magic 'BM'
    try w.writeInt(u32, width * height + 14, .little); // size
    try w.writeInt(u32, 0x0, .little); // reserved
    try w.writeInt(u32, 54, .little); // start of pixel array

    //- DIB header - Windows BITMAPINFOHEADER
    try w.writeInt(u32, 40, .little); // header size
    try w.writeInt(i32, @intCast(width), .little); // width
    try w.writeInt(i32, -@as(i32, @intCast(height)), .little); // height
    try w.writeInt(u16, 1, .little); // num color planes
    try w.writeInt(u16, 32, .little); // bits per pixel
    try w.writeInt(u32, 0, .little); // compression method - none
    try w.writeInt(u32, width * height, .little); // size of pixel array
    try w.writeInt(i32, @intCast(width), .little); // horiz res px/m
    try w.writeInt(i32, @intCast(height), .little); // vert res px/m
    try w.writeInt(u32, 0, .little); // num colors in pallete - 0 for default
    try w.writeInt(u32, 0, .little); // num 'important' colors - 0 for all

    //- pixel array

    // @NOTE: each row is meant to be aligned to 32 bits
    //  this assumes the atlas size is aligned
    try w.writeAll(@ptrCast(atlas.bytes));

    try buffered_writer.flush();
}

pub fn textureDataRef(
    atlas: *const FontAtlas,
) TextureDataRef {
    return .{
        .bytes = atlas.bytes.ptr,
        .size = atlas.size,
    };
}
