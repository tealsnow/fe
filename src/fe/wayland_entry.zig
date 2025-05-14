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
const FontAtlas = WgpuRenderer.FontAtlas;
const FontFace = WgpuRenderer.FontFace;
const ShapedText = WgpuRenderer.ShapedText;

const cu = @import("cu");

// @TODO: Migrate to use ghostty/pkg/fontconfig
const fc = @import("fontconfig.zig");

const ft = @import("freetype");

const pretty = @import("pretty");

pub fn entry(gpa: Allocator) !void {
    try run(gpa);

    std.process.cleanExit();
}

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

    var font_face = try FontFace.fromPath(ft_lib, def_font_path);
    defer font_face.deinit();
    try font_face.setSize(12, 96);

    var font_atlas = try FontAtlas.init(&font_face);
    defer font_atlas.deinit(gpa);

    // create a small white square at 0,0 for texture-less rects
    _ = try font_atlas.blit(gpa, .square(2), 0, &(.{255} ** (3 * 2 * 2)), 0);

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

    // const strings = @import("unicode_3_2_test.zig").strings;
    const strings = [_][]const u8{
        "Hello, World! - hgl dq - fi fl ff fj ffi ffl - WAV T. W. Lewis",
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

    var list = std.ArrayListUnmanaged(WgpuRenderer.RectInstance).empty;
    defer list.deinit(gpa);

    const line_height = font_face.lineHeight();
    const origin = mt.Point(f32).all(200);
    for (strings, 0..) |string, i| {
        var pos = origin;
        pos.y += line_height * @as(f32, @floatFromInt(i));

        const color = colors[i];

        const shaped = try ShapedText.init(&font_face, string);
        defer shaped.deinit();

        try shaped.generateRectsArrayList(
            gpa,
            &font_atlas,
            &list,
            pos,
            color,
            // .hexRgb(0xffffff),
        );
    }

    // try font_atlas.writeToBmp("atlas.bmp");

    try list.append(
        gpa,
        .recti(
            .fromBounds(.bounds(origin, .square(200))),
            .zero,
            .hexRgb(0xff0000),
            15,
            0,
            4,
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
    );
    defer renderer.deinit();

    const render_pass_data = try WgpuRenderer.RenderPassData.init(
        renderer.device,
        renderer.queue,
        renderer.texture_bind_group_layout,
        font_atlas.textureDataRef(),
        list.items,
    );
    defer render_pass_data.deinit();

    //- cu

    const ui_state = try cu.State.init(
        gpa,
        WgpuRenderer.CuCallbacks.callbacks,
    );
    defer ui_state.deinit();

    cu.state = ui_state;

    const default_font =
        ui_state.registerFont(@alignCast(@ptrCast(&font_face)));

    ui_state.default_palette = cu.Atom.Palette{
        .background = .hexRgb(0x1d2021), // gruvbox bg0
        .text = .hexRgb(0xebdbb2), // gruvbox fg1
        .text_weak = .hexRgb(0xbdae93), // gruvbox fg3
        .border = .hexRgb(0x3c3836), // gruvbox bg1
        .hot = .hexRgb(0x665c54), // grovbox bg3
        .active = .hexRgb(0xfbf1c7), // grovbox fg0
    };
    ui_state.default_font = default_font;

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

                        cu.state.window_size = .axis(
                            @floatFromInt(size.width),
                            @floatFromInt(size.height),
                        );
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

                    cu.state.pushEvent(.{ .key = .{
                        .scancode = @intCast(key.scancode),
                        .keycode = .unknown,
                        .mod = .{},
                        .state = if (key.state == .pressed)
                            .pressed
                        else
                            .released,
                    } });

                    if (key.state != .pressed) break :key;

                    switch (@intFromEnum(key.keysym)) {
                        xkb.Keysym.q, xkb.Keysym.Escape => break :main_loop,

                        else => {},
                    }
                },

                .modifier => |mods| {
                    cu.state.pushEvent(.{ .key = .{
                        .scancode = 0,
                        .keycode = .unknown,
                        .mod = .{
                            .shift = mods.state.shift,
                            .ctrl = mods.state.ctrl,
                            .alt = mods.state.alt,
                        },
                        .state = .none,
                    } });

                    // _ = mods;
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
                    // const utf8 = text.sliceZ();
                    // log.debug(
                    //     "text: codepoint: 0x{x}, text: '{s}'",
                    //     .{
                    //         text.codepoint,
                    //         std.fmt.fmtSliceEscapeLower(utf8),
                    //     },
                    // );

                    cu.state.pushEvent(.{ .text = .{
                        .text = text.slice(),
                    } });
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

                    cu.state.pushEvent(.{ .mouse_move = .{
                        .pos = .vec(
                            @floatCast(motion.point.x),
                            @floatCast(motion.point.y),
                        ),
                    } });

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

                    cu.state.pushEvent(.{ .mouse_button = .{
                        .button = switch (button.button) {
                            .left => .left,
                            .middle => .middle,
                            .right => .right,
                            .forward => .forward,
                            .back => .back,
                        },
                        .pos = cu.state.mouse,
                        .state = if (button.state == .pressed)
                            .pressed
                        else
                            .released,
                    } });

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
                    // _ = scroll;
                    // log.debug(
                    //     "pointer_scroll: axis: {s}, source: {s}, value: {?d}",
                    //     .{
                    //         @tagName(scroll.axis),
                    //         @tagName(scroll.source),
                    //         scroll.value,
                    //     },
                    // );

                    if (scroll.value) |value|
                        cu.state.pushEvent(.{ .scroll = .{
                            .scroll = if (scroll.axis == .vertical)
                                .vec(@floatCast(value), 0)
                            else
                                .vec(0, @floatCast(value)),
                            .pos = cu.state.mouse,
                        } });
                },
            }
        }

        if (do_render) {
            cu.startBuild(0);
            cu.state.ui_root.layout_axis = .y;
            cu.state.ui_root.flags.draw_background = true;
            cu.state.ui_root.flags.draw_border = true;

            cu.endBuild();

            renderer.render(&render_pass_data);
            renderer.surface.present();
        }
    }
}
