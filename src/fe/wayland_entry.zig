// @TODO:
//   @[ ]: setup cu
//   @[ ]: cu: window border
//   @[ ]: window rounding - cu?
//   @[ ]: window shadows - cu?

const std = @import("std");
const assert = std.debug.assert;
const mem = std.mem;
const Allocator = mem.Allocator;

const log = std.log.scoped(.@"fe[wl]");

const xkb = @import("xkbcommon");

const mt = @import("math.zig");
const Point = @import("math.zig").Point;
const Size = @import("math.zig").Size;

const wl = @import("platform/linux/wayland/wayland.zig");

const WgpuRenderer = @import("wgpu/WgpuRenderer.zig");

// @TODO: Migrate to use ghostty/pkg/fontconfig
const fc = @import("fontconfig.zig");

const ft = @import("freetype");

const hb = @cImport({
    @cInclude("hb.h");
    @cInclude("hb-ft.h");
});

const pretty = @import("pretty");

pub fn entry(gpa: Allocator) !void {
    try run(gpa);

    std.process.cleanExit();
}

// @TODO: auto grow
pub const FontAtlas = struct {
    bytes: []u32, // 4 bit rgba format
    size: Size(u32),

    cursor: Point(u32) = .all(0),
    max_y: u32 = 0,

    face: *ft.Face,

    glyph_map: std.AutoHashMapUnmanaged(GlyphIndex, GlyphInfo) = .empty,

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

    pub fn init(
        gpa: Allocator,
        size: mt.Size(u32),
        face: *ft.Face,
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

        try atlas.face.loadGlyph(@intFromEnum(glyph_index), .{});
        try atlas.face.glyph.render(.lcd);
        const glyph = atlas.face.glyph;
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
        const idx = atlas.face.getCharIndex(codepoint) orelse 0;
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
};

pub const FontFace = struct {
    ft_face: *ft.Face,
    hb_font: *hb.hb_font_t,

    pub fn fromFtFace(ft_face: *ft.Face) !FontFace {
        const hb_font =
            hb.hb_ft_font_create_referenced(@ptrCast(ft_face)) orelse
            return error.hb;
        return .{
            .ft_face = ft_face,
            .hb_font = hb_font,
        };
    }

    pub fn deinit(face: FontFace) void {
        face.ft_face.deinit();
        hb.hb_font_destroy(face.hb_font);
    }

    pub fn lineHeight(font_face: *const FontFace) i32 {
        return @intCast(font_face.ft_face.size.metrics.height >> 6);
    }

    pub fn topLeftToBaselineAdjustment(font_face: *const FontFace) i32 {
        const line_height = font_face.lineHeight();
        const descender: i32 =
            @intCast(font_face.ft_face.size.metrics.descender >> 6);
        return line_height + descender;
    }
};

pub const ShapedText = struct {
    font_face: *const FontFace,

    buffer: *hb.hb_buffer_t,
    string: []const u8,

    glyph_infos: []hb.hb_glyph_info_t,
    glyph_positions: []hb.hb_glyph_position_t,

    pub fn init(font_face: *const FontFace, string: []const u8) !ShapedText {
        //- setup buffer
        const hb_buffer = hb.hb_buffer_create() orelse return error.hb;
        hb.hb_buffer_add_utf8(
            hb_buffer,
            string.ptr,
            @intCast(string.len),
            0,
            -1,
        );
        hb.hb_buffer_guess_segment_properties(hb_buffer);

        //- shape
        hb.hb_shape(font_face.hb_font, hb_buffer, null, 0);

        var glyph_info_count: u32 = undefined;
        const glyph_info =
            hb.hb_buffer_get_glyph_infos(hb_buffer, &glyph_info_count) orelse
            return error.hb;

        var glyph_pos_count: u32 = undefined;
        const glyph_pos =
            hb.hb_buffer_get_glyph_positions(hb_buffer, &glyph_pos_count) orelse
            return error.hb;

        assert(glyph_info_count == glyph_pos_count);
        const glyph_count = glyph_info_count;

        return .{
            .font_face = font_face,

            .buffer = hb_buffer,
            .string = string,

            .glyph_infos = glyph_info[0..glyph_count],
            .glyph_positions = glyph_pos[0..glyph_count],
        };
    }

    pub fn deinit(text: ShapedText) void {
        hb.hb_buffer_destroy(text.buffer);
    }

    pub fn calculateSize(text: *const ShapedText) mt.Size(i32) {
        var size = mt.Size(i32).zero;

        size.height = text.font_face.lineHeight();

        for (text.glyph_positions) |pos| {
            const x_advance = pos.x_advance >> 6;
            const y_advance = pos.y_advance >> 6;

            size.width += x_advance;
            size.height += y_advance; // not sure if this is correct
        }

        return size;
    }

    pub fn generateRectsArrayList(
        text: *const ShapedText,
        gpa: Allocator,
        font_atlas: *FontAtlas,
        list: *std.ArrayListUnmanaged(WgpuRenderer.RectInstance),
        origin: mt.Point(i32), // topleft
        color: mt.RgbaF32,
    ) !void {
        var cursor = origin;

        // adjust from topleft to baseline
        cursor.y += text.font_face.topLeftToBaselineAdjustment();

        try list.ensureUnusedCapacity(gpa, text.glyph_infos.len);

        for (text.glyph_infos, 0..) |info, i| {
            // codepoint here is a misnomer - it is the glyph index in the
            // font and has no correlation to the unicode character
            const glyph_index: FontAtlas.GlyphIndex =
                @enumFromInt(info.codepoint);

            const atlas_info =
                try font_atlas.getInfoOrCacheForGlyphIndex(gpa, glyph_index);
            const tex_coords = atlas_info.tex_coords.floatFromInt(f32);
            const bearing = atlas_info.bearing;

            const pos = text.glyph_positions[i];
            const x_offset = pos.x_offset;
            const y_offset = pos.y_offset;
            const x_advance = pos.x_advance >> 6;
            const y_advance = pos.y_advance >> 6;

            const point = mt.Point(i32)
                .pt(
                    cursor.x + x_offset + bearing.x,
                    cursor.y + y_offset + -bearing.y,
                )
                .floatFromInt(f32)
                .floor();
            const size = atlas_info.size.floatFromInt(f32);

            try list.append(
                gpa,
                .recti(
                    .fromBounds(.bounds(point, size)),
                    tex_coords,
                    color,
                ),
            );

            cursor.x += x_advance;
            cursor.y += y_advance;
        }
    }

    /// origin is top left point to start from
    pub fn generateRects(
        text: *const ShapedText,
        gpa: Allocator,
        font_atlas: *FontAtlas,
        origin: mt.Point(i32),
        color: mt.RgbaF32,
    ) ![]WgpuRenderer.RectInstance {
        var list =
            try std.ArrayListUnmanaged(WgpuRenderer.RectInstance)
                .initCapacity(gpa, text.glyph_infos.len);

        try text.generateRectsArrayList(gpa, font_atlas, &list, origin, color);

        const slice = try list.toOwnedSlice(gpa);
        return slice;
    }
};

fn run(gpa: Allocator) !void {
    //- window
    const conn = try wl.Connection.init(gpa);
    defer conn.deinit(gpa);

    const window = try wl.Window.init(
        gpa,
        conn,
        .{ .width = 1024, .height = 576 },
    );
    defer window.deinit(gpa);
    window.inset = 15;
    window.minimium_size = .{ .width = 200, .height = 100 };

    //- font loading
    const def_font_path = def_font_path: {
        const font_family = "sans";

        try fc.init();
        defer fc.deinit();

        const pattern = try fc.Pattern.create();
        defer pattern.destroy();
        try pattern.addString(.family, font_family);
        try pattern.addBool(.outline, .true);

        const config = try fc.Config.getCurrent();
        try config.substitute(pattern, .pattern);
        fc.defaultSubsitute(pattern);

        const match = try fc.fontMatch(config, pattern);
        defer match.destroy();

        const path = try match.getString(.file, 0);
        break :def_font_path try gpa.dupeZ(u8, path);
    };
    defer gpa.free(def_font_path);

    log.debug("default font path (sans): {s}", .{def_font_path});

    // freetype

    const ft_lib = try ft.Library.init();
    defer ft_lib.deinit();
    try ft_lib.setLcdFilter(.default);

    const ft_face = try ft_lib.initFace(def_font_path, 0);

    const font_face = try FontFace.fromFtFace(ft_face);
    defer font_face.deinit();

    {
        const pt = 28;
        // const vert_dpi: u16 = @intFromFloat(@floor(conn.vdpi));
        // const horz_dpi: u16 = @intFromFloat(@floor(conn.hdpi));
        // log.debug("dpi: {d}x{d}", .{ horz_dpi, vert_dpi });
        // try ft_face.setCharSize(0, pt * 64, horz_dpi, vert_dpi);
        const dpi = 96;
        try ft_face.setCharSize(0, pt * 2 * 64, dpi, dpi);
    }

    var font_atlas = try FontAtlas.init(gpa, .square(32 * 64 * 2), ft_face);
    defer font_atlas.deinit(gpa);

    // create a small white square at 0,0 for texture-less rects
    _ = font_atlas.blit(.square(2), 0, &(.{255} ** (3 * 2 * 2)));

    // pre-cache all basic ascii chars
    // 0, 32..128
    _ = try font_atlas.getInfoOrCacheForGlyphIndex(
        gpa,
        font_atlas.getGlyphIndexForCodepoint(0),
    );
    for (32..128) |ascii| {
        const codepoint = @as(u21, @intCast(ascii));
        const glyph_index = font_atlas.getGlyphIndexForCodepoint(codepoint);
        _ = try font_atlas.getInfoOrCacheForGlyphIndex(gpa, glyph_index);
    }

    // const random_test_strings = [_][]const u8{
    //     // https://stackoverflow.com/a/51539774/13156251
    //     // Vertically-stacked characters
    //     "Z̤͔ͧ̑̓ä͖̭̈̇lͮ̒ͫǧ̗͚̚o̙̔ͮ̇͐̇",
    //     // Right-to-left words
    //     "اختبار النص",
    //     // Mixed-direction words
    //     // @TODO: mixed bidi
    //     // "من left اليمين to الى right اليسار",
    //     // Mixed-direction characters
    //     // @TODO: mixed bidi
    //     // "a‭b‮c‭d‮e‭f‮g",
    //     // Very long characters
    //     "﷽﷽﷽﷽﷽﷽﷽﷽﷽﷽﷽﷽﷽﷽﷽﷽",
    //     // Emoji with skintone variations
    //     // @TODO: Emoji
    //     // "👱👱🏻👱🏼👱🏽👱🏾👱🏿",
    //     // Emoji with gender variations
    //     // @TODO: Emoji
    //     // "🧟‍♀️🧟‍♂️",
    //     // Emoji created by combining codepoints
    //     // @TODO: Emoji
    //     // "👨‍❤️‍💋‍👨👩‍👩‍👧‍👦🏳️‍⚧️🇵🇷",
    // };
    //
    // const unicode_test_strings = @import("unicode_3_2_test.zig").strings;
    // const strings = unicode_test_strings ++ random_test_strings;

    const strings = [_][]const u8{
        "Hello, World!",
        "this is in red",
        "this is in green",
        "this is in blue",
        "this is half transparent",
    };
    const colors = [_]mt.RgbaF32{
        .hexRgb(0xffffff),
        .hexRgb(0xff0000),
        .hexRgb(0x00ff00),
        .hexRgb(0x0000ff),
        .hexRgba(0xffffff7f),
    };
    // // const strings = unicode_test_strings;

    var list = std.ArrayListUnmanaged(WgpuRenderer.RectInstance).empty;
    defer list.deinit(gpa);

    const line_height = font_face.lineHeight();
    const origin = mt.Point(i32).all(200);
    for (strings, 0..) |string, i| {
        var pos = origin;
        pos.y += line_height * @as(i32, @intCast(i));

        const color = colors[i];

        const shaped = try ShapedText.init(&font_face, string);
        defer shaped.deinit();

        try shaped.generateRectsArrayList(
            gpa,
            &font_atlas,
            &list,
            pos,
            color,
        );
    }

    try font_atlas.writeToBmp("atlas.bmp");

    // try list.append(
    //     gpa,
    //     .recti(
    //         .fromBounds(.bounds(.all(40), font_atlas.size.floatFromInt(f32))),
    //         .fromBounds(.bounds(.all(0), font_atlas.size.floatFromInt(f32))),
    //         .hexRgb(0xffffff),
    //     ),
    // );

    try list.append(
        gpa,
        .recti(
            .fromBounds(.bounds(origin.floatFromInt(f32), .square(20))),
            .zero,
            .hexRgb(0xff0000),
        ),
    );

    //- wpgu

    var renderer = try WgpuRenderer.init(
        WgpuRenderer.wgpu.surfaceDescriptorFromWaylandSurface(.{
            .label = "wayland surface",
            .display = conn.wl_display,
            .surface = window.wl_surface,
        }),
        window.size,
        .{
            // .instance = gpa,
            // .adapter = gpa,
            // .device = gpa,
            // .surface = true,
        },
        &font_atlas,
        list.items,
    );
    defer renderer.deinit();

    //- main loop

    var pointer_pos = Point(f64).all(-1);
    var pointer_enter_serial: u32 = 0;

    log.info("starting main loop", .{});

    window.commit();

    main_loop: while (true) {
        try conn.dispatch();

        var do_render = false;

        while (conn.event_queue.dequeue()) |event| {
            switch (event.kind) {
                .surface_configure => |configure| {
                    window.handleSurfaceConfigureEvent(configure);
                    do_render = true;
                },

                .toplevel_configure => |conf| {
                    if (window.handleToplevelConfigureEvent(conf)) |size| {
                        // window was resized
                        renderer.reconfigure(size);
                    }

                    do_render = true;
                },

                .toplevel_close => {
                    log.debug("close request", .{});
                    break :main_loop;
                },

                .frame => {
                    // the compositor has told us this is a good time to render
                    // useful for animations or just rendering every time

                    do_render = true;
                },

                .keyboard_focus => |focus| {
                    _ = focus;
                    // log.debug(
                    //     "keyboard_focus: state: {s}, serial: {d}",
                    //     .{ @tagName(focus.state), focus.serial },
                    // );
                },

                .key => |key| key: {
                    // log.debug(
                    //     "key: state: {s}, scancode: {d}, keysym: {}," ++
                    //         " codepoint: 0x{x}",
                    //     .{
                    //         @tagName(key.state),
                    //         key.scancode,
                    //         key.keysym,
                    //         key.codepoint,
                    //     },
                    // );

                    if (key.state != .pressed) break :key;

                    switch (@intFromEnum(key.keysym)) {
                        xkb.Keysym.q, xkb.Keysym.Escape => break :main_loop,

                        else => {},
                    }
                },

                .modifier => |mods| {
                    _ = mods;
                    // log.debug(
                    //     "mods: shift: {}, caps_lock: {}, ctrl: {}, alt: {}," ++
                    //         " gui: {}, serial: {d}",
                    //     .{
                    //         mods.state.shift,
                    //         mods.state.caps_lock,
                    //         mods.state.ctrl,
                    //         mods.state.alt,
                    //         mods.state.logo,
                    //         mods.serial,
                    //     },
                    // );
                },

                .text => |text| {
                    _ = text;
                    // const utf8 = text.sliceZ();
                    // log.debug(
                    //     "text: codepoint: 0x{x}, text: '{s}'",
                    //     .{
                    //         text.codepoint,
                    //         std.fmt.fmtSliceEscapeLower(utf8),
                    //     },
                    // );
                },

                .pointer_focus => |focus| {
                    // log.debug(
                    //     "pointer_focus: state: {s}, serial: {d}",
                    //     .{ @tagName(focus.state), focus.serial },
                    // );

                    switch (focus.state) {
                        .enter => {
                            pointer_enter_serial = focus.serial;
                        },
                        .leave => {},
                    }
                },
                .pointer_motion => |motion| {
                    // log.debug(
                    //     "pointer_motion: {d}x{d}",
                    //     .{ motion.x, motion.y },
                    // );

                    pointer_pos = motion.point;

                    const kind: wl.CursorKind =
                        if (window.getEdge(pointer_pos)) |edge|
                            switch (edge) {
                                .top_left, .bottom_right => .resize_nwse,
                                .top_right, .bottom_left => .resize_nesw,
                                .left, .right => .resize_ew,
                                .top, .bottom => .resize_ns,
                            }
                        else
                            .default;

                    try conn.cursor_manager.setCursor(
                        pointer_enter_serial,
                        kind,
                    );
                },
                .pointer_button => |button| button: {
                    // log.debug(
                    //     "pointer_button: state: {s}, button: {s}, serial: {d}",
                    //     .{
                    //         @tagName(button.state),
                    //         @tagName(button.button),
                    //         button.serial,
                    //     },
                    // );

                    if (button.state != .pressed) break :button;

                    if (button.button == .left) {
                        if (window.getEdge(pointer_pos)) |edge| {
                            window.startResize(button.serial, edge);
                        } else {
                            window.startMove(button.serial);
                        }
                    }
                },
                .pointer_scroll => |scroll| {
                    _ = scroll;
                    // log.debug(
                    //     "pointer_scroll: axis: {s}, source: {s}, value: {?d}",
                    //     .{
                    //         @tagName(scroll.axis),
                    //         @tagName(scroll.source),
                    //         scroll.value,
                    //     },
                    // );
                },
            }
        }

        if (do_render) {
            renderer.render();
            renderer.surface.present();
        }
    }
}
