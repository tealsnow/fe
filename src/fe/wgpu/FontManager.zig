const FontManager = @This();

const std = @import("std");
const log = std.log.scoped(.@"wgpu.FontManager");
const Allocator = std.mem.Allocator;

const ft = @import("freetype");

const cu = @import("cu");
const mt = cu.math;

const FontFace = @import("FontFace.zig");
const FontAtlas = @import("FontAtlas.zig");

ft_lib: *ft.Library,
atlas_map: AtlasMap = .empty,

pub const AtlasMap = std.AutoHashMapUnmanaged(*const FontFace, *FontAtlas);

pub fn init(gpa: Allocator) !*FontManager {
    const ft_lib = try ft.Library.init();
    const self = try gpa.create(FontManager);
    self.* = .{ .ft_lib = ft_lib };
    return self;
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

    gpa.destroy(self);
}

pub fn initFontFace(
    self: *FontManager,
    gpa: Allocator,
    path: [:0]const u8,
    index: i32,
    pt_size: i32,
    dpi: mt.Size(u16),
) !*FontFace {
    const face = try gpa.create(FontFace);
    face.* = try FontFace.fromPath(self.ft_lib, path, index, pt_size, dpi);

    const atlas = try gpa.create(FontAtlas);
    atlas.* = try FontAtlas.init(face);

    try atlas.cacheAscii(gpa);

    try self.atlas_map.put(gpa, face, atlas);

    return face;
}

pub fn fontFaceIterator(self: *const FontManager) AtlasMap.KeyIterator {
    return self.atlas_map.keyIterator();
}

pub fn getAtlas(
    self: *const FontManager,
    font_face: *const FontFace,
) *FontAtlas {
    return self.atlas_map.get(font_face) orelse
        @panic("given font face not owned by this font manager");
}

pub const FontDesc = struct {
    path: [:0]const u8,
    pt: i32,
};

pub const FontPathMap = std.EnumArray(cu.FontKind, FontDesc);
pub const FontFaceMap = std.EnumArray(cu.FontKind, *const FontFace);

pub fn makeFontFaceMap(
    self: *FontManager,
    gpa: Allocator,
    path_map: FontPathMap,
    dpi: mt.Size(u16),
) !FontFaceMap {
    var face_map = FontFaceMap.initUndefined();

    var map = path_map;
    var iter = map.iterator();
    while (iter.next()) |entry| {
        const path = entry.value.path;
        const pt = entry.value.pt;
        const font_face = try self.initFontFace(gpa, path, 0, pt, dpi);
        face_map.set(entry.key, font_face);
    }

    return face_map;
}
