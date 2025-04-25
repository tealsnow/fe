const std = @import("std");
const Allocator = std.mem.Allocator;
const c = @import("c.zig").c;
const errors = @import("errors.zig");
const Library = @import("Library.zig");
const Tag = @import("tag.zig").Tag;
const Error = errors.Error;
const intToError = errors.intToError;

pub const Fixed = c_long;
pub const Pos = c_long;

pub const GlyphSlot = extern struct {
    library: c.FT_Library,
    face: *Face,
    next: ?*GlyphSlot,
    glyph_index: c_uint,
    generic: c.FT_Generic,
    metrics: c.FT_Glyph_Metrics,
    linearHoriAdvance: Fixed,
    linearVertAdvance: Fixed,
    advance: c.FT_Vector,
    format: GlyphFormat,
    bitmap: Bitmap,
    bitmap_left: c_int,
    bitmap_top: c_int,
    outline: c.FT_Outline,
    num_subglyphs: c_uint,
    subglyphs: c.FT_SubGlyph,
    control_data: ?*anyopaque,
    control_len: c_long,
    lsb_delta: Pos,
    rsb_delta: Pos,
    other: ?*anyopaque,
    internal: c.FT_Slot_Internal,

    /// Convert a given glyph image to a bitmap.
    pub fn render(
        glyph: *GlyphSlot,
        render_mode: RenderMode,
    ) Error!void {
        return intToError(c.FT_Render_Glyph(
            @ptrCast(glyph),
            @intFromEnum(render_mode),
        ));
    }
};

pub const GlyphFormat = enum(c.FT_Glyph_Format) {
    none = c.FT_GLYPH_FORMAT_NONE,
    composite = c.FT_GLYPH_FORMAT_COMPOSITE,
    bitmap = c.FT_GLYPH_FORMAT_BITMAP,
    outline = c.FT_GLYPH_FORMAT_OUTLINE,
    plotter = c.FT_GLYPH_FORMAT_PLOTTER,
    svg = c.FT_GLYPH_FORMAT_SVG,
    _,
};

pub const Bitmap = extern struct {
    rows: c_uint,
    width: c_uint,
    pitch: c_int,
    buffer: [*]u8,
    num_grays: c_ushort,
    pixel_mode: PixelMode,
    palette_mode: u8,
    palette: ?*anyopaque,
};

pub const PixelMode = enum(u8) {
    none = c.FT_PIXEL_MODE_NONE,
    mono = c.FT_PIXEL_MODE_MONO,
    gray = c.FT_PIXEL_MODE_GRAY,
    gray2 = c.FT_PIXEL_MODE_GRAY2,
    gray4 = c.FT_PIXEL_MODE_GRAY4,
    lcd = c.FT_PIXEL_MODE_LCD,
    lcd_v = c.FT_PIXEL_MODE_LCD_V,
    bgra = c.FT_PIXEL_MODE_BGRA,
    max = c.FT_PIXEL_MODE_MAX,
    _,
};

pub const Face = extern struct {
    num_faces: c_long,
    face_index: c_long,
    face_flags: c_long,
    style_flags: c_long,
    num_glyphs: c_long,
    family_name: [*:0]u8,
    style_name: [*:0]u8,
    num_fixed_sizes: c_int,
    available_sizes: [*]c.FT_Bitmap_Size,
    num_charmaps: c_int,
    charmaps: [*]c.FT_CharMap,
    generic: c.FT_Generic,
    bbox: c.FT_BBox,
    units_per_EM: c_ushort,
    ascender: c_short,
    descender: c_short,
    height: c_short,
    max_advance_width: c_short,
    max_advance_height: c_short,
    underline_position: c_short,
    underline_thickness: c_short,
    glyph: *GlyphSlot,
    size: c.FT_Size,
    charmap: c.FT_CharMap,
    driver: c.FT_Driver,
    memory: c.FT_Memory,
    stream: c.FT_Stream,
    sizes_list: c.FT_ListRec,
    autohint: c.FT_Generic,
    extensions: ?*anyopaque,
    internal: c.FT_Face_Internal,

    pub fn deinit(face: *Face) void {
        _ = c.FT_Done_Face(@ptrCast(face));
    }

    /// Increment the counter of the face.
    pub fn ref(face: Face) void {
        _ = c.FT_Reference_Face(@ptrCast(face));
    }

    /// A macro that returns true whenever a face object contains some
    /// embedded bitmaps. See the available_sizes field of the FT_FaceRec structure.
    pub fn hasFixedSizes(face: *Face) bool {
        return c.FT_HAS_FIXED_SIZES(@as(c.FT_Face, @ptrCast(face)));
    }

    /// A macro that returns true whenever a face object contains tables for
    /// color glyphs.
    pub fn hasColor(face: *Face) bool {
        return c.FT_HAS_COLOR(@as(c.FT_Face, @ptrCast(face)));
    }

    /// A macro that returns true whenever a face object contains an ‘sbix’
    /// OpenType table and outline glyphs.
    pub fn hasSBIX(face: *Face) bool {
        return c.FT_HAS_SBIX(@as(c.FT_Face, @ptrCast(face)));
    }

    /// A macro that returns true whenever a face object contains some
    /// multiple masters.
    pub fn hasMultipleMasters(face: *Face) bool {
        return c.FT_HAS_MULTIPLE_MASTERS(@as(c.FT_Face, @ptrCast(face)));
    }

    /// A macro that returns true whenever a face object contains a scalable
    /// font face (true for TrueType, Type 1, Type 42, CID, OpenType/CFF,
    /// and PFR font formats).
    pub fn isScalable(face: *Face) bool {
        return c.FT_IS_SCALABLE(@as(c.FT_Face, @ptrCast(face)));
    }

    /// Select a given charmap by its encoding tag (as listed in freetype.h).
    pub fn selectCharmap(face: *Face, encoding: Encoding) Error!void {
        return intToError(c.FT_Select_Charmap(@ptrCast(face), @intFromEnum(encoding)));
    }

    /// Call FT_Request_Size to request the nominal size (in points).
    pub fn setCharSize(
        face: *Face,
        char_width: i32,
        char_height: i32,
        horz_resolution: u16,
        vert_resolution: u16,
    ) Error!void {
        return intToError(c.FT_Set_Char_Size(
            @ptrCast(face),
            char_width,
            char_height,
            horz_resolution,
            vert_resolution,
        ));
    }

    pub fn setPixelSizes(
        face: *Face,
        pixel_width: u32,
        pixel_height: u32,
    ) Error!void {
        return intToError(c.FT_Set_Pixel_Sizes(
            @ptrCast(face),
            pixel_width,
            pixel_height,
        ));
    }

    /// Select a bitmap strike. To be more precise, this function sets the
    /// scaling factors of the active FT_Size object in a face so that bitmaps
    /// from this particular strike are taken by FT_Load_Glyph and friends.
    pub fn selectSize(face: *Face, idx: i32) Error!void {
        return intToError(c.FT_Select_Size(@ptrCast(face), idx));
    }

    /// Return the glyph index of a given character code. This function uses
    /// the currently selected charmap to do the mapping.
    pub fn getCharIndex(face: *Face, char: u32) ?u32 {
        const i = c.FT_Get_Char_Index(@ptrCast(face), char);
        return if (i == 0) null else i;
    }

    /// Load a glyph into the glyph slot of a face object.
    pub fn loadGlyph(face: *Face, glyph_index: u32, load_flags: LoadFlags) Error!void {
        return intToError(c.FT_Load_Glyph(
            @ptrCast(face),
            glyph_index,
            @bitCast(load_flags),
        ));
    }

    /// Return a pointer to a given SFNT table stored within a face.
    pub fn getSfntTable(face: *Face, comptime tag: SfntTag) ?*tag.DataType() {
        return @ptrCast(@alignCast(c.FT_Get_Sfnt_Table(
            @ptrCast(face),
            @intFromEnum(tag),
        )));
    }

    /// Retrieve the number of name strings in the SFNT ‘name’ table.
    pub fn getSfntNameCount(face: *Face) usize {
        return @intCast(c.FT_Get_Sfnt_Name_Count(@ptrCast(face)));
    }

    /// Retrieve a string of the SFNT ‘name’ table for a given index.
    pub fn getSfntName(face: *Face, i: usize) Error!c.FT_SfntName {
        var name: c.FT_SfntName = undefined;
        const res = c.FT_Get_Sfnt_Name(@ptrCast(face), @intCast(i), &name);
        return if (intToError(res)) |_| name else |err| err;
    }

    /// Load any SFNT font table into client memory.
    pub fn loadSfntTable(
        face: *Face,
        alloc: Allocator,
        tag: Tag,
    ) (Allocator.Error || Error)!?[]u8 {
        const tag_c: c_ulong = @intCast(@as(u32, @bitCast(tag)));

        // Get the length of the table in bytes
        var len: c_ulong = 0;
        var res = c.FT_Load_Sfnt_Table(@ptrCast(face), tag_c, 0, null, &len);
        _ = intToError(res) catch |err| return err;

        // If our length is zero we don't have a table.
        if (len == 0) return null;

        // Allocate a buffer to hold the table and load it
        const buf = try alloc.alloc(u8, len);
        errdefer alloc.free(buf);
        res = c.FT_Load_Sfnt_Table(@ptrCast(face), tag_c, 0, buf.ptr, &len);
        _ = intToError(res) catch |err| return err;

        return buf;
    }

    /// Check whether a given SFNT table is available in a face.
    pub fn hasSfntTable(face: *Face, tag: Tag) bool {
        const tag_c: c_ulong = @intCast(@as(u32, @bitCast(tag)));
        var len: c_ulong = 0;
        const res = c.FT_Load_Sfnt_Table(@ptrCast(face), tag_c, 0, null, &len);
        _ = intToError(res) catch return false;
        return len != 0;
    }

    /// Retrieve the font variation descriptor for a font.
    pub fn getMMVar(face: *Face) Error!*c.FT_MM_Var {
        var result: *c.FT_MM_Var = undefined;
        const res = c.FT_Get_MM_Var(@ptrCast(face), @ptrCast(&result));
        return if (intToError(res)) |_| result else |err| err;
    }

    /// Get the design coordinates of the currently selected interpolated font.
    pub fn getVarDesignCoordinates(face: *Face, coords: []c.FT_Fixed) Error!void {
        const res = c.FT_Get_Var_Design_Coordinates(
            @ptrCast(face),
            @intCast(coords.len),
            coords.ptr,
        );
        return intToError(res);
    }

    /// Choose an interpolated font design through design coordinates.
    pub fn setVarDesignCoordinates(face: *Face, coords: []c.FT_Fixed) Error!void {
        const res = c.FT_Set_Var_Design_Coordinates(
            @ptrCast(face),
            @intCast(coords.len),
            coords.ptr,
        );
        return intToError(res);
    }

    /// Set the transformation that is applied to glyph images when they are
    /// loaded into a glyph slot through FT_Load_Glyph.
    pub fn setTransform(
        face: *Face,
        matrix: ?*const c.FT_Matrix,
        delta: ?*const c.FT_Vector,
    ) void {
        c.FT_Set_Transform(
            @ptrCast(face),
            @constCast(@ptrCast(matrix)),
            @constCast(@ptrCast(delta)),
        );
    }
};

/// An enumeration to specify indices of SFNT tables loaded and parsed by
/// FreeType during initialization of an SFNT font. Used in the
/// FT_Get_Sfnt_Table API function.
pub const SfntTag = enum(c_int) {
    head = c.FT_SFNT_HEAD,
    maxp = c.FT_SFNT_MAXP,
    os2 = c.FT_SFNT_OS2,
    hhea = c.FT_SFNT_HHEA,
    vhea = c.FT_SFNT_VHEA,
    post = c.FT_SFNT_POST,
    pclt = c.FT_SFNT_PCLT,

    /// The data type for a given sfnt tag.
    pub fn DataType(comptime self: SfntTag) type {
        return switch (self) {
            .os2 => c.TT_OS2,
            .head => c.TT_Header,
            .post => c.TT_Postscript,
            .hhea => c.TT_HoriHeader,
            else => unreachable, // As-needed...
        };
    }
};

/// An enumeration to specify character sets supported by charmaps. Used in the
/// FT_Select_Charmap API function.
pub const Encoding = enum(u31) {
    none = c.FT_ENCODING_NONE,
    ms_symbol = c.FT_ENCODING_MS_SYMBOL,
    unicode = c.FT_ENCODING_UNICODE,
    sjis = c.FT_ENCODING_SJIS,
    prc = c.FT_ENCODING_PRC,
    big5 = c.FT_ENCODING_BIG5,
    wansung = c.FT_ENCODING_WANSUNG,
    johab = c.FT_ENCODING_JOHAB,
    adobe_standard = c.FT_ENCODING_ADOBE_STANDARD,
    adobe_expert = c.FT_ENCODING_ADOBE_EXPERT,
    adobe_custom = c.FT_ENCODING_ADOBE_CUSTOM,
    adobe_latin_1 = c.FT_ENCODING_ADOBE_LATIN_1,
    old_latin_2 = c.FT_ENCODING_OLD_LATIN_2,
    apple_roman = c.FT_ENCODING_APPLE_ROMAN,
};

/// https://freetype.org/freetype2/docs/reference/ft2-glyph_retrieval.html#ft_render_mode
pub const RenderMode = enum(c_uint) {
    normal = c.FT_RENDER_MODE_NORMAL,
    light = c.FT_RENDER_MODE_LIGHT,
    mono = c.FT_RENDER_MODE_MONO,
    lcd = c.FT_RENDER_MODE_LCD,
    lcd_v = c.FT_RENDER_MODE_LCD_V,
    sdf = c.FT_RENDER_MODE_SDF,
};

/// A list of bit field constants for FT_Load_Glyph to indicate what kind of
/// operations to perform during glyph loading.
pub const LoadFlags = packed struct(i32) {
    no_scale: bool = false,
    no_hinting: bool = false,
    render: bool = false,
    no_bitmap: bool = false,
    vertical_layout: bool = false,
    force_autohint: bool = false,
    crop_bitmap: bool = false,
    pedantic: bool = false,
    ignore_global_advance_with: bool = false,
    no_recurse: bool = false,
    ignore_transform: bool = false,
    monochrome: bool = false,
    linear_design: bool = false,
    no_autohint: bool = false,
    _padding1: u1 = 0,
    target_normal: bool = false,
    target_light: bool = false,
    target_mono: bool = false,
    target_lcd: bool = false,
    target_lcd_v: bool = false,
    color: bool = false,
    compute_metrics: bool = false,
    bitmap_metrics_only: bool = false,
    _padding2: u1 = 0,
    no_svg: bool = false,
    _padding3: u7 = 0,

    test "bitcast" {
        const testing = std.testing;
        const cval: i32 = c.FT_LOAD_RENDER | c.FT_LOAD_PEDANTIC | c.FT_LOAD_COLOR;
        const flags = @as(LoadFlags, @bitCast(cval));
        try testing.expect(!flags.no_hinting);
        try testing.expect(flags.render);
        try testing.expect(flags.pedantic);
        try testing.expect(flags.color);
    }
};

test "loading memory font" {
    const testing = std.testing;
    const font_data = @import("test.zig").font_regular;

    var lib = try Library.init();
    defer lib.deinit();
    var face = try lib.initMemoryFace(font_data, 0);
    defer face.deinit();

    // Try APIs
    try face.selectCharmap(.unicode);
    try testing.expect(!face.hasFixedSizes());
    try face.setCharSize(12, 0, 0, 0);

    // Try loading
    const idx = face.getCharIndex('A').?;
    try face.loadGlyph(idx, .{});

    // Try getting a truetype table
    const os2 = face.getSfntTable(.os2);
    try testing.expect(os2 != null);
}
