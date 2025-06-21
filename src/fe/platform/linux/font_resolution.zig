const std = @import("std");
const Allocator = std.mem.Allocator;
const log_scope = .@"font resolution";
const log = std.log.scoped(log_scope);

const pretty = @import("pretty");
const cu = @import("cu");
const fc = @import("fontconfig");

pub const ResolveFontsParams = struct {
    size: cu.text.TextUnit = .undef,
    weight: cu.text.FontWeight = .normal,
    slant: cu.text.FontSlant = .normal,
    family: cu.text.FontFamily = .default,

    pub fn fromTextStyle(style: cu.text.TextStyle) ResolveFontsParams {
        return .{
            .size = style.size,
            .weight = style.weight,
            .slant = style.slant,
            .family = style.family,
        };
    }
};

pub const ResolvedFont = struct {
    path: [:0]const u8,
    index: i32,
};

pub fn resolveFontList(
    arena: Allocator,
    params: ResolveFontsParams,
) ![]ResolvedFont {
    const weight_map = std.EnumMap(cu.text.FontWeight, fc.Weight).init(.{
        .zero = .thin,
        .thin = .thin,
        .extra_light = .extralight,
        .light = .light,
        .normal = .regular,
        .medium = .medium,
        .semi_bold = .demibold,
        .bold = .bold,
        .extra_bold = .extrabold,
        .black = .black,
    });

    if (std.log.logEnabled(.debug, log_scope)) dbg: {
        const str = pretty.dump(arena, params, .{}) catch break :dbg;
        log.debug("resolving font list with params:\n{s}", .{str});
    }

    //- fast path for a predefined set
    if (params.family == .file_backed) {
        var list = std.ArrayListUnmanaged(ResolvedFont).empty;

        const file_backed = params.family.file_backed;
        for (file_backed.map) |entry| {
            const key, const font_file = entry;
            if (std.meta.eql(
                key,
                .{ .weight = params.weight, .slant = params.slant },
            )) {
                try list.append(arena, .{
                    .path = font_file.path,
                    .index = font_file.index,
                });
            }
        }

        return try list.toOwnedSlice(arena);
    }

    if (!fc.init()) return error.fc_init; // init if not already

    const pattern = fc.Pattern.create();
    defer pattern.destroy();

    //- size
    switch (params.size.kind) {
        .undef => {},
        .px => {
            const px = params.size.value.toF32();
            if (!pattern.add(
                .pixel_size,
                .{ .double = px },
                false,
            )) return error.fc_pattern_add;
        },
        .pt => {
            const pt = params.size.value.toF32();
            if (!pattern.add(
                .size,
                .{ .double = pt },
                false,
            )) return error.fc_pattern_add;
        },
    }

    //- family
    family: switch (params.family) {
        .generic => |generic| {
            const str: [:0]const u8 = switch (generic) {
                .default => break :family,
                .cursive, .monospace, .serif => @tagName(generic),
                .sans_serif => "sans",
            };
            if (!pattern.add(
                .family,
                .{ .string = str },
                true,
            )) return error.fc_pattern_add;
        },
        .file_backed => unreachable,
    }

    //- weight
    // round to nearest 100 (named weight)
    const weight: cu.text.FontWeight = @enumFromInt(@min(
        (@intFromEnum(params.weight) + 50) / 100 * 100,
        @intFromEnum(cu.text.FontWeight.black),
    ));
    const fc_weight = weight_map.get(weight).?;
    if (!pattern.add(
        .weight,
        .{ .integer = @intCast(@intFromEnum(fc_weight)) },
        true,
    )) return error.fc_pattern_add;

    //- slant
    const slant: fc.Slant = switch (params.slant) {
        .normal => .roman,
        .italic => .italic,
        .oblique => .oblique,
    };
    if (!pattern.add(
        .slant,
        .{ .integer = @intCast(@intFromEnum(slant)) },
        true,
    )) return error.fc_pattern_add;

    //- print pattern
    if (std.log.logEnabled(.debug, log_scope)) {
        log.debug("fontconfig pattern:", .{});
        // @FIXME: this goes directly to stdout/err not to our log file
        pattern.print();
    }

    //- get matches
    const config = fc.Config.getCurrent() orelse
        return error.fc_config_get_current;

    if (!config.substituteWithPat(pattern, .pattern))
        return error.fc_subs;
    pattern.defaultSubstitute();

    const res = config.fontSort(pattern, true, null);
    try res.result.toError();
    const fs = res.fs;
    defer fs.destroy();

    const fonts = fs.fonts();
    var list = try arena.alloc(ResolvedFont, fonts.len);
    for (fonts, 0..) |pat, i| {
        const path = (try pat.get(.file, 0)).string;
        const index = (try pat.get(.index, 0)).integer;

        list[i] = .{ .path = path, .index = index };
    }

    if (std.log.logEnabled(.debug, log_scope)) {
        log.debug("found {d} matching fonts", .{list.len});

        const max_count = 5;
        const dbg_print_count = @min(max_count, list.len);
        log.debug("first {d} fonts:", .{dbg_print_count});
        for (list[0..dbg_print_count]) |file|
            log.debug("{s} @ {d}", .{ file.path, file.index });
    }

    return list;
}
