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

const freetype = @import("freetype");

// @TODO:
//   @[ ]: setup cu
//   @[ ]: cu: window border
//   @[ ]: window rounding - cu?
//   @[ ]: window shadows - cu?

pub fn entry(gpa: Allocator) !void {
    try run(gpa);

    std.process.cleanExit();
}

pub const FontAtlas = struct {
    bytes: []u8, // 1 bit format
    size: Size(u32),

    cursor: Point(u32) = .all(0),
    max_y: u32 = 0,

    face: *freetype.Face,

    // glyph index -> tex coords
    glyph_map: std.AutoHashMapUnmanaged(GlyphIndex, mt.Rect(u32)) = .empty,

    pub const GlyphIndex = enum(u32) {
        missing = 0,
        _,
    };

    pub fn init(
        gpa: Allocator,
        size: mt.Size(u32),
        face: *freetype.Face,
    ) !FontAtlas {
        const bytes = try gpa.alloc(u8, size.width * size.height);
        for (bytes) |*byte| {
            byte.* = 0;
        }
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

    pub fn cacheGlyph(
        atlas: *FontAtlas,
        gpa: Allocator,
        glyph_index: GlyphIndex,
    ) !void {
        if (atlas.glyph_map.contains(glyph_index)) return;

        // log.debug("caching glyph idx: {d}", .{@intFromEnum(glyph_index)});

        try atlas.face.loadGlyph(@intFromEnum(glyph_index), .{});
        try atlas.face.glyph.render(.normal);
        const bitmap = atlas.face.glyph.bitmap;

        assert(bitmap.pixel_mode == .gray);

        try atlas.glyph_map.put(gpa, glyph_index, .rect(
            atlas.cursor,
            .pt(atlas.cursor.x + bitmap.width, atlas.cursor.y + bitmap.rows),
        ));

        atlas.blit(bitmap.width, bitmap.rows, bitmap.buffer);
    }

    pub fn getGlyphIndexForCodepoint(
        atlas: *const FontAtlas,
        codepoint: u21,
    ) GlyphIndex {
        const idx = atlas.face.getCharIndex(codepoint) orelse 0;
        return @enumFromInt(idx);
    }

    pub fn getRectForCodepoint(
        atlas: *const FontAtlas,
        codepoint: u21,
    ) ?mt.Rect(u32) {
        const glyph_index = atlas.getGlyphIndexForCodepoint(codepoint);
        return atlas.glyph_map.get(glyph_index);
    }

    pub fn blit(
        atlas: *FontAtlas,
        width: u32,
        height: u32,
        bytes: [*]u8,
    ) void {
        if (atlas.cursor.x + width > atlas.size.width) {
            atlas.cursor = .{
                .x = 0,
                .y = atlas.max_y,
            };
        }

        if (atlas.cursor.y + height > atlas.size.height) {
            @panic("TODO: atlas overflow");
        }

        for (0..height) |y| {
            for (0..width) |x| {
                const adj_x = atlas.cursor.x + x;
                const adj_y = atlas.cursor.y + y;

                const atlas_i = adj_y * atlas.size.width + adj_x;
                const bitmap_i = y * width + x;

                const byte = &atlas.bytes[atlas_i];
                byte.* = bytes[bitmap_i];
            }
        }
        atlas.cursor.x += width;
        atlas.max_y = @max(atlas.max_y, atlas.cursor.y + height);
    }

    /// assumes size is 32 bit aligned
    pub fn writeToBmp(atlas: *const FontAtlas, file_name: []const u8) !void {
        const cwd = std.fs.cwd();

        const out_file = try cwd.createFile(file_name, .{});
        defer out_file.close();

        const w = out_file.writer();

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

    const ft = try freetype.Library.init();
    defer ft.deinit();

    const ft_face = try ft.initFace(def_font_path, 0);
    defer ft_face.deinit();

    // @FIXME: Just a temporary solution until I figure out proper sizing
    // try ft_face.setPixelSizes(0, 64);
    {
        const pt = 22;
        const vert_dpi: u16 = @intFromFloat(@floor(conn.vdpi));
        const horz_dpi: u16 = @intFromFloat(@floor(conn.hdpi));
        try ft_face.setCharSize(0, pt * 64, horz_dpi, vert_dpi);
    }

    var font_atlas = try FontAtlas.init(gpa, .square(512), ft_face);
    defer font_atlas.deinit(gpa);

    // 0, 32..128
    try font_atlas.cacheGlyph(gpa, font_atlas.getGlyphIndexForCodepoint(0));
    for (32..128) |ascii| {
        const codepoint = @as(u21, @intCast(ascii));
        const glyph_index = font_atlas.getGlyphIndexForCodepoint(codepoint);
        try font_atlas.cacheGlyph(gpa, glyph_index);
    }

    // try font_atlas.writeToBmp("text.bmp");

    // const text_string = "Hello, World!";
    // const utf8_view = try std.unicode.Utf8View.init(text_string);
    // var utf8_iter = utf8_view.iterator();
    // while (utf8_iter.nextCodepoint()) |codepoint| {
    //     const rect = font_atlas.getRectForCodepoint(codepoint) orelse
    //         @panic("TODO: no rect");
    //
    //     log.debug("char: {u} - rect: {d}x{d}-{d}x{d} ", .{
    //         codepoint,
    //         rect.p0.x,
    //         rect.p0.y,
    //         rect.p1.x,
    //         rect.p1.y,
    //     });
    // }

    // if (true) return;

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

                    const cursor: wl.CursorKind =
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
                        cursor,
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
