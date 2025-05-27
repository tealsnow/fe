const FontAtlas = @This();

// @PERF: simd might be usefull here

const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

const log = std.log.scoped(.FontAtlas);

const mt = @import("cu").math;
const FontFace = @import("FontFace.zig");

const ft = @import("freetype");

//= fields

bytes: []u8 = &[_]u8{}, // 1 bit format
size: mt.Size(u32) = .zero,

cursor: mt.Point(u32) = .splat(0),
max_y: u32 = 0,

face: *const FontFace,

glyph_map: std.AutoHashMapUnmanaged(GlyphIndex, GlyphInfo) = .empty,

modified: bool = false,

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
    /// in 26.6 fixed point
    bearing: mt.Point(i64),
    /// physical size of glyph
    /// in 26.6 fixed point
    size: mt.Size(i64),
    /// px
    bitmap_offset: mt.Point(i32),
};

pub const TextureDataRef = struct {
    bytes: [*]u8,
    size: mt.Size(u32),
};

//= methods

pub fn init(face: *const FontFace) !FontAtlas {
    return .{ .face = face };
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

    atlas.modified = true;

    const ft_face = atlas.face.ft_face;

    try ft_face.loadGlyph(@intFromEnum(glyph_index), 0);
    try ft_face.glyph.render(.sdf);
    const glyph = ft_face.glyph;
    const bitmap = glyph.bitmap;

    assert(bitmap.pixel_mode == .gray);

    const rect = try atlas.blit(
        gpa,
        .size(bitmap.width, bitmap.rows),
        bitmap.pitch,
        bitmap.buffer,
        2,
    );

    // int casts here since I highly doubt that there will be > a i32 worth
    // of bearing or size for a single glyph
    const info = GlyphInfo{
        .tex_coords = rect,
        .bearing = .point(
            glyph.metrics.horiBearingX,
            glyph.metrics.horiBearingY,
        ),
        .size = .size(
            glyph.metrics.width,
            glyph.metrics.height,
        ),
        .bitmap_offset = .point(
            glyph.bitmap_left,
            glyph.bitmap_top,
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
    gpa: Allocator,
    size: mt.Size(u32),
    pitch: i32, // row
    bitmap: [*]const u8,
    padding: u32,
) !mt.Rect(u32) {
    const padded_size = mt.Size(u32)
        .size(size.width + padding * 2, size.height + padding * 2);

    if (atlas.cursor.x + padded_size.width > atlas.size.width) {
        atlas.cursor = .{
            .x = 0,
            .y = atlas.max_y,
        };
    }

    if (atlas.cursor.y + padded_size.height > atlas.size.height) {
        if (std.meta.eql(atlas.size, .zero)) {
            const new_size = mt.Size(u32).square(32 * 32 * 2);
            const bytes = try gpa.alloc(u8, new_size.width * new_size.height);

            atlas.bytes = bytes;
            atlas.size = new_size;
        } else {
            const new_height = atlas.size.height + atlas.size.height / 2;
            const new_size = mt.Size(u32).size(atlas.size.width, new_height);

            const new_len = new_size.width * new_size.height;

            if (gpa.resize(atlas.bytes, new_len)) {
                atlas.size = new_size;
            } else if (gpa.remap(atlas.bytes, new_len)) |bytes| {
                atlas.bytes = bytes;
                atlas.size = new_size;
            } else {
                const bytes = try gpa.realloc(atlas.bytes, new_len);

                atlas.bytes = bytes;
                atlas.size = new_size;
            }
        }

        assert(atlas.cursor.y + size.height <= atlas.size.height);
    }

    const rect = mt.Rect(u32).fromBounds(.bounds(atlas.cursor, padded_size));

    if (pitch < 0) {
        // @TODO: if row padding is negative the flow is up,
        //  we only support down flow atm
        @panic("TODO: up flow bitmap");
    }
    const pitch_u: usize = @intCast(pitch);

    // const subpixel_width = size.width * 3;

    for (0..padded_size.height) |y| {
        for (0..padded_size.width) |x| {
            const atlas_x = atlas.cursor.x + x;
            const atlas_y = atlas.cursor.y + y;
            const atlas_i = atlas_y * atlas.size.width + atlas_x;

            // Set to transparent
            atlas.bytes[atlas_i] = 0;
        }
    }

    for (0..size.height) |bitmap_y| {
        for (0..size.width) |bitmap_x| {
            const atlas_x = atlas.cursor.x + bitmap_x + padding;
            const atlas_y = atlas.cursor.y + bitmap_y + padding;

            const bitmap_i = bitmap_y * pitch_u + bitmap_x;
            const atlas_i = atlas_y * atlas.size.width + atlas_x;

            atlas.bytes[atlas_i] = bitmap[bitmap_i];
        }
    }
    atlas.cursor.x += padded_size.width;
    atlas.max_y = @max(atlas.max_y, atlas.cursor.y + padded_size.height);

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
    try w.writeInt(u16, 8, .little); // bits per pixel
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

pub fn cacheAscii(atlas: *FontAtlas, gpa: Allocator) !void {
    // pre-cache all basic ascii chars
    // 0, 32..128
    _ = try atlas.getInfoOrCacheForGlyphIndex(
        gpa,
        atlas.getGlyphIndexForCodepoint(0),
    );
    for (32..128) |ascii| {
        const codepoint = @as(u21, @intCast(ascii));
        const glyph_index = atlas.getGlyphIndexForCodepoint(codepoint);
        _ = try atlas.getInfoOrCacheForGlyphIndex(gpa, glyph_index);
    }
}
