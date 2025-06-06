const std = @import("std");
const c = @import("c.zig").c;
const Face = @import("face.zig").Face;
const errors = @import("errors.zig");
const Error = errors.Error;
const intToError = errors.intToError;

pub const Library = opaque {
    /// Initialize a new FreeType library object. The set of modules that are
    /// registered by this function is determined at build time.
    pub fn init() Error!*Library {
        var res: c.FT_Library = null;
        try intToError(c.FT_Init_FreeType(&res));
        return @ptrCast(res);
    }

    /// Destroy a given FreeType library object and all of its children,
    /// including resources, drivers, faces, sizes, etc.
    pub fn deinit(self: *Library) void {
        _ = c.FT_Done_FreeType(@ptrCast(self));
    }

    /// Return the version of the FreeType library being used. This is useful when
    /// dynamically linking to the library, since one cannot use the macros
    /// FREETYPE_MAJOR, FREETYPE_MINOR, and FREETYPE_PATCH.
    pub fn version(self: *Library) Version {
        var v: Version = undefined;
        c.FT_Library_Version(@ptrCast(self), &v.major, &v.minor, &v.patch);
        return v;
    }

    /// Call FT_New_Face to open a font from a file.
    pub fn initFace(self: *Library, path: [:0]const u8, index: i32) Error!*Face {
        var face: *Face = undefined;
        try intToError(c.FT_New_Face(
            @ptrCast(self),
            path.ptr,
            index,
            @ptrCast(&face),
        ));
        return face;
    }

    /// Call FT_Open_Face to open a font that has been loaded into memory.
    pub fn initMemoryFace(self: *Library, data: []const u8, index: i32) Error!Face {
        var face: Face = undefined;
        try intToError(c.FT_New_Memory_Face(
            @ptrCast(self),
            data.ptr,
            @intCast(data.len),
            index,
            &face.handle,
        ));
        return face;
    }

    /// Call when you're done with a loaded MM var.
    pub fn doneMMVar(self: *Library, mm: *c.FT_MM_Var) void {
        _ = c.FT_Done_MM_Var(@ptrCast(self), mm);
    }

    pub fn setLcdFilter(self: *Library, lcd_filter: LcdFilter) !void {
        try intToError(c.FT_Library_SetLcdFilter(
            @ptrCast(self),
            @intFromEnum(lcd_filter),
        ));
    }

    pub fn setLcdGeometry(self: *Library, sub: [3]Vector) !void {
        try intToError(c.FT_Library_SetLcdGeometry(
            @ptrCast(self),
            @constCast(@ptrCast(&sub)),
        ));
    }
};

pub const Geometry = struct {
    pub const rgb = [3]Vector{
        .{ .x = -21, .y = 0 },
        .{ .x = 0, .y = 0 },
        .{ .x = 21, .y = 0 },
    };

    pub const bgr = [3]Vector{
        .{ .x = 21, .y = 0 },
        .{ .x = 0, .y = 0 },
        .{ .x = -21, .y = 0 },
    };
};

const Pos = c.FT_Pos;

pub const Vector = extern struct {
    x: Pos,
    y: Pos,
};

pub const LcdFilter = enum(c.enum_FT_LcdFilter_) {
    none = c.FT_LCD_FILTER_NONE,
    default = c.FT_LCD_FILTER_DEFAULT,
    light = c.FT_LCD_FILTER_LIGHT,
    legacy1 = c.FT_LCD_FILTER_LEGACY1,
    legacy = c.FT_LCD_FILTER_LEGACY,
    _,
};

pub const Version = struct {
    major: i32,
    minor: i32,
    patch: i32,

    /// Convert the version to a string. The buffer should be able to
    /// accommodate the size, recommended to be at least 8 chars wide.
    /// The returned slice will be a slice of buf that contains the full
    /// version string.
    pub fn toString(self: Version, buf: []u8) ![]const u8 {
        return try std.fmt.bufPrint(buf, "{d}.{d}.{d}", .{
            self.major, self.minor, self.patch,
        });
    }
};

test "basics" {
    const testing = std.testing;

    var lib = try Library.init();
    defer lib.deinit();

    const vsn = lib.version();
    try testing.expect(vsn.major > 1);

    var buf: [32]u8 = undefined;
    _ = try vsn.toString(&buf);
}
