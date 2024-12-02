const std = @import("std");
const Allocator = std.mem.Allocator;

const log = @import("log.zig").Scoped("fontconfig");

pub const fc = @cImport({
    @cInclude("fontconfig/fontconfig.h");
});

pub fn init() !void {
    if (fc.FcInit() == fc.FcFalse) return error.FcInit;
}

pub fn deinit() void {
    fc.FcFini();
}

pub fn getVersion() c_int {
    return fc.FcGetVersion();
}

// pub fn testListAllFonts() !void {
//     const pattern = fc.FcPatternCreate();
//     defer fc.FcPatternDestroy(pattern);
//     if (pattern == null) return error.FcFailCreatePattern;

//     const object_set = fc.FcObjectSetCreate();
//     defer fc.FcObjectSetDestroy(object_set);
//     if (object_set == null) return error.FcFailCreateObjectSet;

//     if (fc.FcObjectSetAdd(object_set, "file") == 0) return error.FcFailToAddFileProperty;

//     const font_list = fc.FcFontList(null, pattern, object_set);
//     defer fc.FcFontSetDestroy(font_list);
//     if (font_list == null) return error.FcFailToGetFontList;

//     var i: u32 = 0;
//     while (i < font_list.*.nfont) : (i += 1) {
//         const font = font_list.*.fonts[i];
//         var path: [*c]u8 = undefined;
//         if (fc.FcPatternGetString(font, "file", 0, &path) != 0)
//             continue;
//         log.tracekv(@src(), "got font", .{ .path = path });
//     }
// }

/// Free returned slice
/// Returns the font for a generic name such as monospace or arial
pub fn getFontForFamilyName(allocator: Allocator, family: [*c]const u8) ![:0]u8 {
    try init();
    defer deinit();

    const pattern = fc.FcPatternCreate();
    defer fc.FcPatternDestroy(pattern);
    if (pattern == null) return error.FcPatternCreate;

    if (fc.FcPatternAddString(pattern, fc.FC_FAMILY, family) == fc.FcFalse)
        return error.FcPatternAddString;
    if (fc.FcPatternAddBool(pattern, fc.FC_OUTLINE, fc.FcTrue) == fc.FcFalse)
        return error.FcPatternAddBool;

    const config = fc.FcConfigGetCurrent();
    if (config == null) return error.FcConfigGetCurrent;

    if (fc.FcConfigSubstitute(config, pattern, fc.FcMatchPattern) == fc.FcFalse)
        return error.FcConfigSubstitute;
    fc.FcDefaultSubstitute(pattern);

    var result: fc.FcResult = undefined;
    const font = fc.FcFontMatch(config, pattern, &result);
    defer fc.FcPatternDestroy(font);
    if (font == null) return error.FcFontMatch;

    if (result != fc.FcResultMatch) {
        log.fatalkv(@src(), "Could not find matching font", .{ .family = family });
        return error.CouldNotFindFont;
    }

    var path: [*c]u8 = undefined;
    if (fc.FcPatternGetString(font, fc.FC_FILE, 0, &path) != fc.FcResultMatch)
        return error.DoesNotMatch;

    const path_slice = std.mem.sliceTo(path, 0);
    const len = path_slice.len;
    const path_alloc = try allocator.allocSentinel(u8, len, 0);
    @memcpy(path_alloc[0..len], path_slice[0..len]);

    return path_alloc;
}
