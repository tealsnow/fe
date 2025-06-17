const std = @import("std");
const Allocator = std.mem.Allocator;

pub const c = @cImport({
    @cInclude("fontconfig/fontconfig.h");
});

pub fn init() !void {
    if (c.FcInit() == c.FcFalse) return error.fc_init;
}

pub fn deinit() void {
    c.FcFini();
}

pub fn getVersion() c_int {
    return c.FcGetVersion();
}

pub const Result = enum(c.FcResult) {
    match = c.FcResultMatch,
    no_match = c.FcResultNoMatch,
    type_mismatch = c.FcResultTypeMismatch,
    no_id = c.FcResultNoId,
    out_of_memory = c.FcResultOutOfMemory,

    pub fn toError(self: Result) ?ResultError {
        return switch (self) {
            .match => null,
            .no_match => ResultError.no_match,
            .type_mismatch => ResultError.type_mismatch,
            .no_id => ResultError.no_id,
            .out_of_memory => ResultError.out_out_memory,
        };
    }
};

pub const ResultError = error{
    no_match,
    type_mismatch,
    no_id,
    out_out_memory,
};

fn errorFromResult(result: c.FcResult) ?ResultError {
    const r: Result = @enumFromInt(result);
    return r.toError();
}

pub const Bool = enum(c.FcBool) {
    false = c.FcFalse,
    true = c.FcTrue,
    dont_care = c.FcDontCare,
};

pub const MatchKind = enum(c.FcMatchKind) {
    pattern = c.FcMatchPattern,
    font = c.FcMatchFont,
    scan = c.FcMatchScan,
};

pub const Property = enum {
    family,
    style,
    slant,
    weight,
    size,
    aspect,
    pixel_size,
    spacing,
    foundry,
    antialias,
    hinting,
    hint_style,
    vertical_layout,
    autohint,
    global_advance,
    width,
    file,
    index,
    ft_face,
    rasterizer,
    outline,
    scalable,
    color,
    variable,
    scale,
    symbol,
    dpi,
    rgba,
    minspace,
    source,
    charset,
    lang,
    fontversion,
    fullname,
    familylang,
    stylelang,
    fullnamelang,
    capability,
    fontformat,
    embolden,
    embedded_bitmap,
    decorative,
    lcd_filter,
    font_features,
    font_variations,
    namelang,
    prgname,
    hash,
    postscript_name,
    font_has_hint,
    order,
    desktop_name,
    named_instance,
    font_wrapper,

    pub fn string(self: Property) [:0]const u8 {
        return switch (self) {
            .family => c.FC_FAMILY,
            .style => c.FC_STYLE,
            .slant => c.FC_SLANT,
            .weight => c.FC_WEIGHT,
            .size => c.FC_SIZE,
            .aspect => c.FC_ASPECT,
            .pixel_size => c.FC_PIXEL_SIZE,
            .spacing => c.FC_SPACING,
            .foundry => c.FC_FOUNDRY,
            .antialias => c.FC_ANTIALIAS,
            .hinting => c.FC_HINTING,
            .hint_style => c.FC_HINT_STYLE,
            .vertical_layout => c.FC_VERTICAL_LAYOUT,
            .autohint => c.FC_AUTOHINT,
            .global_advance => c.FC_GLOBAL_ADVANCE,
            .width => c.FC_WIDTH,
            .file => c.FC_FILE,
            .index => c.FC_INDEX,
            .ft_face => c.FC_FT_FACE,
            .rasterizer => c.FC_RASTERIZER,
            .outline => c.FC_OUTLINE,
            .scalable => c.FC_SCALABLE,
            .color => c.FC_COLOR,
            .variable => c.FC_VARIABLE,
            .scale => c.FC_SCALE,
            .symbol => c.FC_SYMBOL,
            .dpi => c.FC_DPI,
            .rgba => c.FC_RGBA,
            .minspace => c.FC_MINSPACE,
            .source => c.FC_SOURCE,
            .charset => c.FC_CHARSET,
            .lang => c.FC_LANG,
            .fontversion => c.FC_FONTVERSION,
            .fullname => c.FC_FULLNAME,
            .familylang => c.FC_FAMILYLANG,
            .stylelang => c.FC_STYLELANG,
            .fullnamelang => c.FC_FULLNAMELANG,
            .capability => c.FC_CAPABILITY,
            .fontformat => c.FC_FONTFORMAT,
            .embolden => c.FC_EMBOLDEN,
            .embedded_bitmap => c.FC_EMBEDDED_BITMAP,
            .decorative => c.FC_DECORATIVE,
            .lcd_filter => c.FC_LCD_FILTER,
            .font_features => c.FC_FONT_FEATURES,
            .font_variations => c.FC_FONT_VARIATIONS,
            .namelang => c.FC_NAMELANG,
            .prgname => c.FC_PRGNAME,
            .hash => c.FC_HASH,
            .postscript_name => c.FC_POSTSCRIPT_NAME,
            .font_has_hint => c.FC_FONT_HAS_HINT,
            .order => c.FC_ORDER,
            .desktop_name => c.FC_DESKTOP_NAME,
            .named_instance => c.FC_NAMED_INSTANCE,
            .font_wrapper => c.FC_FONT_WRAPPER,
        };
    }
};

pub const Pattern = opaque {
    pub fn create() !*Pattern {
        return @ptrCast(c.FcPatternCreate() orelse return error.fc_pattern_create);
    }

    pub fn destroy(self: *Pattern) void {
        c.FcPatternDestroy(@ptrCast(self));
    }

    pub fn addString(self: *Pattern, property: Property, value: [:0]const u8) !void {
        if (c.FcPatternAddString(@ptrCast(self), property.string(), value) == c.FcFalse)
            return error.fc_pattern_addString;
    }

    pub fn addBool(self: *Pattern, property: Property, value: Bool) !void {
        if (c.FcPatternAddBool(@ptrCast(self), property.string(), @intFromEnum(value)) == c.FcFalse)
            return error.fc_pattern_addBool;
    }

    pub fn getString(self: *Pattern, property: Property, n: c_int) ResultError![:0]const u8 {
        var string: [*c]u8 = undefined;
        const result = c.FcPatternGetString(@ptrCast(self), property.string(), n, &string);
        return errorFromResult(result) orelse std.mem.sliceTo(string, 0);
    }
};

pub const Config = opaque {
    pub fn create() !*Config {
        return @ptrCast(c.FcConfigCreate() orelse return error.fc_config_create);
    }

    pub fn destroy(self: *Config) void {
        c.FcConfigDestroy(@ptrCast(self));
    }

    pub fn getCurrent() !*Config {
        return @ptrCast(c.FcConfigGetCurrent() orelse return error.fc_config_getCurrent);
    }

    pub fn substitute(self: *Config, pattern: *Pattern, kind: MatchKind) !void {
        if (c.FcConfigSubstitute(@ptrCast(self), @ptrCast(pattern), @intFromEnum(kind)) == c.FcFalse)
            return error.fc_config_substitute;
    }
};

pub fn defaultSubstitute(pattern: *Pattern) void {
    c.FcDefaultSubstitute(@ptrCast(pattern));
}

pub fn fontMatch(config: *Config, pattern: *Pattern) (ResultError || error{fc_fontMatch})!*Pattern {
    var result: c.FcResult = undefined;
    const font =
        c.FcFontMatch(@ptrCast(config), @ptrCast(pattern), &result) orelse return error.fc_fontMatch;
    return errorFromResult(result) orelse @ptrCast(font);
}
