const FontManager = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;

const ft = @import("freetype");

const mt = @import("cu").math;

const FontFace = @import("FontFace.zig");
const FontAtlas = @import("FontAtlas.zig");

ft_lib: *ft.Library,
atlas_map: std.AutoHashMapUnmanaged(*const FontFace, *FontAtlas) = .empty,

pub fn init() !FontManager {
    const ft_lib = try ft.Library.init();
    return .{ .ft_lib = ft_lib };
}

pub fn deinit(self: *FontManager, gpa: Allocator) void {
    var iter = self.atlas_map.iterator();
    while (iter.next()) |entry| {
        const font_face = entry.key_ptr.*;
        font_face.deinit();
        gpa.destroy(font_face);

        const atlas = entry.value_ptr.*;
        atlas.deinit(gpa);
        gpa.destroy(atlas);
    }

    self.atlas_map.deinit(gpa);

    self.ft_lib.deinit();
}

pub fn initFontFace(
    self: *FontManager,
    gpa: Allocator,
    path: [:0]const u8,
    index: i32,
    pt_size: i32,
    dpi: mt.Point(u16),
) !*FontFace {
    const face = try gpa.create(FontFace);
    face.* = try FontFace.fromPath(self.ft_lib, path, index, pt_size, dpi);

    const atlas = try gpa.create(FontAtlas);
    atlas.* = try FontAtlas.init(face);

    try atlas.cacheAscii(gpa);

    try self.atlas_map.put(gpa, face, atlas);

    return face;
}

pub fn getAtlas(
    self: *const FontManager,
    font_face: *const FontFace,
) *FontAtlas {
    return self.atlas_map.get(font_face) orelse
        @panic("given font face not owned by this atlas manager");
}
