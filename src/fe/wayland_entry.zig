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

pub const FontAtlas = struct {
    bytes: []u8, // 1 bit format
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
        const bytes = try gpa.alloc(u8, size.width * size.height);
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

        // log.debug("caching glyph idx: {d}", .{@intFromEnum(glyph_index)});

        try atlas.face.loadGlyph(@intFromEnum(glyph_index), .{});
        try atlas.face.glyph.render(.normal);
        const glyph = atlas.face.glyph;
        const bitmap = glyph.bitmap;

        if (bitmap.pixel_mode != .gray) {
            log.err("not gray pixel mode: {}", .{bitmap.pixel_mode});
            @panic("not gray");
        }

        // assert(bitmap.pixel_mode == .gray);

        const rect =
            atlas.blit(.size(bitmap.width, bitmap.rows), bitmap.buffer);

        const info = GlyphInfo{
            .tex_coords = rect,
            .bearing = .pt(
                @intCast(@divTrunc(glyph.metrics.horiBearingX, 64)),
                @intCast(@divTrunc(glyph.metrics.horiBearingY, 64)),
            ),
            .size = .size(
                @intCast(@divTrunc(glyph.metrics.width, 64)),
                @intCast(@divTrunc(glyph.metrics.height, 64)),
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

    // pub fn getRectForCodepoint(
    //     atlas: *const FontAtlas,
    //     codepoint: u21,
    // ) ?mt.Rect(u32) {
    //     const glyph_index = atlas.getGlyphIndexForCodepoint(codepoint);
    //     return atlas.glyph_map.get(glyph_index);
    // }

    pub fn blit(
        atlas: *FontAtlas,
        size: mt.Size(u32),
        bytes: [*]const u8,
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

        for (0..size.height) |y| {
            for (0..size.width) |x| {
                const adj_x = atlas.cursor.x + x;
                const adj_y = atlas.cursor.y + y;

                const atlas_i = adj_y * atlas.size.width + adj_x;
                const bitmap_i = y * size.width + x;

                const byte = &atlas.bytes[atlas_i];
                byte.* = bytes[bitmap_i];
            }
        }
        atlas.cursor.x += size.width;
        atlas.max_y = @max(atlas.max_y, atlas.cursor.y + size.height);

        return rect;
    }

    /// assumes size is 32 bit aligned
    pub fn writeToBmp(atlas: *const FontAtlas, file_name: []const u8) !void {
        const cwd = std.fs.cwd();

        const out_file = try cwd.createFile(file_name, .{});
        defer out_file.close();

        var buffered_writer = std.io.bufferedWriter(out_file.writer());
        var w = buffered_writer.writer();

        const width = atlas.size.width;
        const height = atlas.size.height;

        //- BMP header
        try w.writeInt(u16, 0x4D42, .little); // magic 'BM'
        const bmp_size = width * height + 14;
        try w.writeInt(u32, bmp_size, .little); // size
        try w.writeInt(u32, 0x0, .little); // reserved
        // try w.writeInt(u32, 26, .little); // start of pixel array
        try w.writeInt(u32, 54, .little); // start of pixel array

        // // DIB header - OS/2 1.x BITMAPCOREHEADER
        // try w.writeInt(u32, 12, .little); // header size
        // try w.writeInt(u16, @intCast(font_atlas.size.width), .little); // width
        // try w.writeInt(u16, @intCast(font_atlas.size.height), .little); // height
        // try w.writeInt(u16, 1, .little); // num color planes
        // try w.writeInt(u16, 8, .little); // bits per pixel

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
        try w.writeAll(atlas.bytes);

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
};

pub const ShapedText = struct {
    font_face: *const FontFace,

    buffer: *hb.hb_buffer_t,
    string: []const u8,

    glyph_infos: []hb.hb_glyph_info_t,
    glyph_positions: []hb.hb_glyph_position_t,

    size: ?mt.Size(i32),

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

            .size = null,
        };
    }

    pub fn deinit(text: ShapedText) void {
        hb.hb_buffer_destroy(text.buffer);
    }

    pub fn getSize(text: *ShapedText) mt.Size(i32) {
        if (text.size) |size| return size;

        var size = mt.Size(i32).zero;

        const line_height =
            @divTrunc(text.font_face.ft_face.size.metrics.height, 64);
        size.height = @intCast(line_height);

        for (text.glyph_positions) |pos| {
            const x_advance = @divTrunc(pos.x_advance, 64);
            const y_advance = @divTrunc(pos.y_advance, 64);

            size.width += x_advance;
            size.height += y_advance; // not sure if this is correct
        }

        text.size = size;
        return size;
    }

    /// origin is top left point to start from
    pub fn generateRects(
        text: *ShapedText,
        gpa: Allocator,
        font_atlas: *FontAtlas,
        origin: mt.Point(i32),
    ) ![]WgpuRenderer.RectInstance {
        const size = text.getSize();
        var cursor = origin;

        const descender: i32 = @intCast(
            @divTrunc(text.font_face.ft_face.size.metrics.descender, 64),
        );
        cursor.y += size.height + descender; // adjust to bottom right

        var rect_buffer_data =
            try std.ArrayListUnmanaged(WgpuRenderer.RectInstance)
                .initCapacity(gpa, text.glyph_infos.len);

        for (text.glyph_infos, 0..) |info, i| {
            const pos = text.glyph_positions[i];

            // codepoint here is a misnomer - it is actually the glyph index in the
            // font and has no correlation to the unicode character
            const glyph_index: FontAtlas.GlyphIndex = @enumFromInt(info.codepoint);

            const atlas_info =
                try font_atlas.getInfoOrCacheForGlyphIndex(gpa, glyph_index);
            const tex_coords = atlas_info.tex_coords.floatFromInt(f32);
            const bearing = atlas_info.bearing;

            const x_offset = @divFloor(pos.x_offset, 64);
            const y_offset = @divFloor(pos.y_offset, 64);
            const x_advance = @divFloor(pos.x_advance, 64);
            const y_advance = @divFloor(pos.y_advance, 64);

            const point = mt.Point(i32)
                .pt(
                    cursor.x + x_offset + bearing.x,
                    cursor.y + y_offset + -bearing.y,
                )
                .floatFromInt(f32)
                .floor();

            try rect_buffer_data.append(
                gpa,
                .recti(
                    .fromBounds(.bounds(point, tex_coords.size())),
                    tex_coords,
                    mt.RgbaF32.hexRgb(0xffffff),
                ),
            );

            cursor.x += x_advance;
            cursor.y += y_advance;
        }

        const slice = try rect_buffer_data.toOwnedSlice(gpa);
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

    const ft_face = try ft_lib.initFace(def_font_path, 0);

    const font_face = try FontFace.fromFtFace(ft_face);
    defer font_face.deinit();

    {
        // const pt = 24;
        const pt = 32;
        const vert_dpi: u16 = @intFromFloat(@floor(conn.vdpi));
        const horz_dpi: u16 = @intFromFloat(@floor(conn.hdpi));
        try ft_face.setCharSize(0, pt * 64, horz_dpi, vert_dpi);
    }

    var font_atlas = try FontAtlas.init(gpa, .square(512), ft_face);
    defer font_atlas.deinit(gpa);

    // create a small white square at 0,0 for texture-less rects
    _ = font_atlas.blit(.square(2), &.{ 255, 255, 255, 255 });

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

    const text_string =
        "Hello, World! - hgl dq - fi fl ff fj ffi ffl - WAV T. W. Lewis";

    var shaped_text = try ShapedText.init(&font_face, text_string);
    defer shaped_text.deinit();

    const rect_buffer_data =
        try shaped_text.generateRects(gpa, &font_atlas, .all(100));
    defer gpa.free(rect_buffer_data);

    //- hb font

    // const hb_font = hb.hb_ft_font_create_referenced(@ptrCast(ft_face)) orelse
    //     return error.hb;
    // defer hb.hb_font_destroy(hb_font);

    //- hb buffer

    // const hb_buffer = hb.hb_buffer_create() orelse return error.hb;
    // defer hb.hb_buffer_destroy(hb_buffer);
    //
    // hb.hb_buffer_add_utf8(hb_buffer, text_string, text_string.len, 0, -1);
    //
    // hb.hb_buffer_guess_segment_properties(hb_buffer);
    //
    // //- hb shape
    //
    // hb.hb_shape(hb_font, hb_buffer, null, 0);
    //
    // //- hb glyph and position information
    //
    // var glyph_info_count: u32 = undefined;
    // const glyph_info =
    //     hb.hb_buffer_get_glyph_infos(hb_buffer, &glyph_info_count) orelse
    //     return error.hb;
    //
    // var glyph_pos_count: u32 = undefined;
    // const glyph_pos =
    //     hb.hb_buffer_get_glyph_positions(hb_buffer, &glyph_pos_count);
    //
    // assert(glyph_info_count == glyph_pos_count);
    // const glyph_count = glyph_info_count;
    //
    // //- hb iterate
    //
    // var rect_buffer_data =
    //     try std.ArrayListUnmanaged(WgpuRenderer.RectInstance)
    //         .initCapacity(gpa, text_string.len);
    // defer rect_buffer_data.deinit(gpa);
    //
    // var cursor = mt.Point(i32).all(100); // top left
    //
    // // pre size
    // {
    //     var size = mt.Size(i32).zero;
    //
    //     const line_height = @divTrunc(ft_face.size.metrics.height, 64);
    //
    //     size.height = @intCast(line_height);
    //     const descender: i32 =
    //         @intCast(@divTrunc(ft_face.size.metrics.descender, 64));
    //
    //     var i: u32 = 0;
    //     while (i < glyph_count) : (i += 1) {
    //         const pos = glyph_pos[i];
    //         const x_advance = @divTrunc(pos.x_advance, 64);
    //         const y_advance = @divTrunc(pos.y_advance, 64);
    //
    //         size.width += x_advance;
    //         size.height += y_advance; // not sure if this is correct
    //     }
    //
    //     log.debug("size: {d}x{d}", .{ size.width, size.height });
    //
    //     var whole_rect = mt.Rect(i32).fromBounds(.bounds(cursor, size));
    //     try rect_buffer_data.append(
    //         gpa,
    //         .recti(
    //             whole_rect.floatFromInt(f32),
    //             .zero,
    //             .hexRgb(0xff0000),
    //         ),
    //     );
    //
    //     cursor.y += size.height + descender; // adjust to bottom right
    // }
    //
    // var i: u32 = 0;
    // while (i < glyph_count) : (i += 1) {
    //     const info = glyph_info[i];
    //     // codepoint here is a misnomer - it is actually the glyph index in the
    //     // font and has no correlation to the unicode character
    //     const glyph_index: FontAtlas.GlyphIndex = @enumFromInt(info.codepoint);
    //
    //     const atlas_info =
    //         try font_atlas.getInfoOrCacheForGlyphIndex(gpa, glyph_index);
    //     const tex_coords = atlas_info.tex_coords.floatFromInt(f32);
    //     const bearing = atlas_info.bearing;
    //
    //     const pos = glyph_pos[i];
    //     const x_offset = @divFloor(pos.x_offset, 64);
    //     const y_offset = @divFloor(pos.y_offset, 64);
    //     const x_advance = @divFloor(pos.x_advance, 64);
    //     const y_advance = @divFloor(pos.y_advance, 64);
    //
    //     const origin = mt.Point(i32)
    //         .pt(
    //             cursor.x + x_offset + bearing.x,
    //             cursor.y + y_offset + -bearing.y,
    //         )
    //         .floatFromInt(f32)
    //         .floor();
    //
    //     try rect_buffer_data.append(
    //         gpa,
    //         .recti(
    //             .fromBounds(.bounds(origin, tex_coords.size())),
    //             tex_coords,
    //             mt.RgbaF32.hexRgb(0xffffff),
    //         ),
    //     );
    //
    //     cursor.x += x_advance;
    //     cursor.y += y_advance;
    // }

    try font_atlas.writeToBmp("text.bmp");

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
        rect_buffer_data,
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
