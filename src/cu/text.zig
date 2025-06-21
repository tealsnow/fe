const std = @import("std");
const Allocator = std.mem.Allocator;

pub const TextStyle = struct {
    size: TextUnit,
    weight: FontWeight = .normal,
    slant: FontSlant = .normal,
    family: FontFamily = .default,
    // features: []const u8,

    // synthesis: FontSynthesis = .all,
    letter_spacing: TextUnit = .undef,
    // ? baseline shift
    decoration: TextDecoration = .none,
    // ? shadow
    // ? draw style
    // ? text align
    // text_direction: TextDirection,
};

pub const TextUnit = packed struct(u32) {
    kind: Kind, // u8
    value: Fp12p12, // u24

    // size optimization for a none/null value
    pub const undef = TextUnit{ .kind = .undef, .value = undefined };

    pub fn pt(value: f32) TextUnit {
        return .{ .kind = .pt, .value = .fromF32(value) };
    }

    pub fn px(value: f32) TextUnit {
        return .{ .kind = .px, .value = .fromF32(value) };
    }

    // pub fn em(value: f32) TextUnit {
    //     return .{ .kind = .em, .value = value };
    // }

    // pub fn sp(value: f32) TextUnit {
    //     return .{ .kind = .sp, .value = value };
    // }

    /// 12.12 Fixed-point number
    pub const Fp12p12 = enum(u24) {
        _,

        pub fn fromF32(d: f32) Fp12p12 {
            return @enumFromInt(@as(u24, @intFromFloat(d * 4096.0)));
        }

        pub fn toF32(f: Fp12p12) f32 {
            return @as(f32, @floatFromInt(@intFromEnum(f))) / 4096.0;
        }
    };

    pub const Kind = enum(u8) {
        undef,
        pt, // font points, most standard
        px, // plain pixels

        // em, // scale with font size
        // sp, // scale with dpi
    };
};

pub const FontWeight = enum(u16) {
    zero = 0, // not practical but here anyway
    thin = 100,
    extra_light = 200,
    light = 300,
    normal = 400,
    medium = 500,
    semi_bold = 600,
    bold = 700,
    extra_bold = 800,
    black = 900,
    _,

    pub const w100 = .thin;
    pub const w200 = .extra_light;
    pub const w300 = .light;
    pub const w400 = .normal;
    pub const w500 = .medium;
    pub const w600 = .semi_bold;
    pub const w700 = .bold;
    pub const w800 = .extra_bold;
    pub const w900 = .black;

    pub const regular = .normal;
    pub const plain = .normal;

    pub fn custom(value: u16) FontWeight {
        return @enumFromInt(value);
    }

    pub fn getValue(self: FontWeight) u16 {
        return @intFromEnum(self);
    }
};

pub const FontSlant = enum {
    normal,
    italic,
    oblique,
};

pub const FontSynthesis = packed struct {
    style: bool,
    weight: bool,

    pub const none = FontSynthesis{ .style = false, .weight = false };
    pub const all = FontSynthesis{ .style = true, .weight = true };
};

pub const FontFamily = union(enum) {
    generic: Generic,
    file_backed: FileBackedFontFamily,

    pub const default = FontFamily{ .generic = .default };
    pub const cursive = FontFamily{ .generic = .cursive };
    pub const monospace = FontFamily{ .generic = .monospace };
    pub const mono = monospace;
    pub const sans_serif = FontFamily{ .generic = .sans_serif };
    pub const sans = sans_serif;
    pub const serif = FontFamily{ .generic = .serif };

    pub fn fileBacked(map: FileBackedFontFamily.Map) FontFamily {
        return .{ .file_backed = .{ .map = map } };
    }

    pub const Generic = enum(u8) {
        default,
        cursive,
        monospace,
        sans_serif,
        serif,
    };
};

pub const FileBackedFontFamily = struct {
    map: []const Entry,

    pub const Key = struct {
        weight: FontWeight = .normal,
        slant: FontSlant = .normal,
    };

    pub const FontFile = struct {
        path: [:0]const u8,
        index: i32,
    };

    pub const Entry = struct { Key, FontFile };
};

pub const TextDecoration = enum {
    none,
    strikethrough,
    underline,
};

// pub const TextDirection = enum {
//     default,
//     ltr,
//     rtl,
// };
