// @TODO:
//   @[ ]: Migrate to github issue tracker for all of these
//   @[x]: plugins: pass guest function to host to call
//   @[ ]: investigate using gtk for windowing and events
//   @[ ]: tooltips/dropdowns - general popups
//   @[ ]: animations
//   @[ ]: focus behaviour
//   @[ ]: migrate to wgpu rendering
//     harfbuzz for shaping
//     freetype(SDF?) for rastering, have to implement atlas packing
//     icu for layout
//   @[ ]: scrolling
//     @[x]: overflow
//     @[x]: clip
//   @[ ]: better rendering
//     @[x]: text alignment
//     @[x]: backgrounds
//     @[x]: borders
//     @[x]: clipping
//     @[ ]: drop shadow
//     @[ ]: truncate text with ellipses
//     @[ ]: rounding
//   @[x]: floating
//   @[x]: text padding
//   @[x]: rename general purpose allocator instances to gpa,
//     this is aligned with zig's std and is more convienient

const builtin = @import("builtin");
const std = @import("std");
const assert = std.debug.assert;
const log = std.log;

const cu = @import("cu");

const sdl = @import("sdl3");
const fc = @import("fontconfig.zig");

const CuSdlRenderer = @import("CuSdlRenderer.zig");
const plugins = @import("plugins.zig");
const logFn = @import("logFn.zig");

const build_options = @import("build_options");

pub const std_options = std.Options{
    .logFn = logFn.logFn,
    .log_level = @enumFromInt(@intFromEnum(build_options.log_level)),
};

pub fn main() !void {
    log.info("starting fe", .{});

    run() catch |err| {
        if (sdl.getError()) |e| {
            std.log.err("[SDL]: {s}", .{e});
            sdl.clearError() catch {};
        }

        plugins.printLastWasmError();

        return err;
    };

    // run() should not return in release mode
    assert(builtin.mode == .Debug);
    log.debug("finished quitting, bye-bye", .{});
}

var debug_allocator = std.heap.DebugAllocator(.{
    // .never_unmap = true,
    // .retain_metadata = true,
    // .verbose_log = true,
    // .backing_allocator_zeroes = false,
}).init;

pub fn run() !void {
    // =-= allocator setup =-=
    log.debug("initializing allocator", .{});

    const gpa, const is_debug = gpa: {
        if (builtin.os.tag == .wasi) break :gpa .{ std.heap.wasm_allocator, false };
        break :gpa switch (builtin.mode) {
            .Debug, .ReleaseSafe => .{ debug_allocator.allocator(), true },
            .ReleaseFast, .ReleaseSmall => .{ std.heap.smp_allocator, false },
        };
    };
    if (is_debug and builtin.link_libc)
        debug_allocator.backing_allocator = std.heap.c_allocator;
    defer if (is_debug) {
        _ = debug_allocator.deinit();
    };

    // =-= plugin setup =-=
    log.info("setting up plugins", .{});

    const host = try plugins.PluginHost.init(gpa);
    defer host.deinit(gpa);

    const plugin = host.plugins[0];
    try plugins.doTest(plugin);

    // =-= sdl window and renderer setup =-=
    log.debug("initilizing sdl", .{});

    _ = sdl.c.SDL_SetHint(sdl.c.SDL_HINT_APP_ID, "me.ketanr.fe");
    _ = sdl.c.SDL_SetHint(sdl.c.SDL_HINT_VIDEO_WAYLAND_ALLOW_LIBDECOR, "1");
    _ = sdl.c.SDL_SetHint(sdl.c.SDL_HINT_VIDEO_WAYLAND_PREFER_LIBDECOR, "0");

    try sdl.init(sdl.InitFlag.all);
    defer sdl.quit();

    try sdl.ttf.init();
    defer sdl.ttf.quit();

    log.debug("creating window", .{});
    const window_size = cu.axis2(@as(c_int, 800), 600);
    const window = try sdl.Window.init(
        "fe",
        window_size.w,
        window_size.h,
        sdl.WindowFlag.high_pixel_density | sdl.WindowFlag.resizable | sdl.WindowFlag.borderless,
        // sdl.WindowFlag.high_pixel_density | sdl.WindowFlag.resizable,
    );
    defer window.deinit();
    try window.setHitTest(&windowHitTestCallback, null);

    const renderer = try sdl.Renderer.init(window, null);
    defer renderer.deinit();

    // =-= font setup =-=

    log.debug("setting up fonts", .{});
    var default_font_handle, var monospace_font_handle = blk: {
        // ensure fonconfig is initialized
        try fc.init();
        defer fc.deinit();

        const font_size = 13;

        const default =
            try CuSdlRenderer.createFontFromFamilyName(gpa, "sans", font_size);
        const monospace =
            try CuSdlRenderer.createFontFromFamilyName(gpa, "monospace", font_size);

        break :blk .{ default, monospace };
    };
    defer {
        default_font_handle.close();
        monospace_font_handle.close();
    }

    // =-= cu setup =-=
    log.debug("initializing cu", .{});

    try cu.state.init(gpa, CuSdlRenderer.Callbacks.callbacks);
    defer cu.state.deinit();

    const default_font =
        cu.state.font_manager.registerFont(@alignCast(@ptrCast(default_font_handle)));
    const monospace_font =
        cu.state.font_manager.registerFont(@alignCast(@ptrCast(monospace_font_handle)));

    cu.state.default_palette = cu.Atom.Palette{
        .background = .hexRgb(0x1d2021), // gruvbox bg0
        .text = .hexRgb(0xebdbb2), // gruvbox fg1
        .text_weak = .hexRgb(0xbdae93), // gruvbox fg3
        .border = .hexRgb(0x3c3836), // gruvbox bg1
    };
    cu.state.default_font = default_font;

    // =-= state =-=

    // var dropdown_open = false;

    // =-= main loop setup =-=

    // @TODO: base this value on display refresh rate
    const app_start_time = try std.time.Instant.now();
    const event_timeout_ms = 10;
    var previous_time = try std.time.Instant.now(); // used to measure elapsed time between frames
    var fps_buffer = FpsCircleBuffer{};

    var cu_sdl_renderer = CuSdlRenderer{ .sdl_rend = renderer };

    // @BUG: for some reason the window shows up as black until resized, unless we do this
    try sdl.Event.push(.mkWindow(.window_resized, window.getID(), window_size.w, window_size.h));

    // =-= main loop =-=
    log.debug("starting main loop", .{});

    var dbg_running = if (is_debug) true else void{};
    while (if (is_debug) dbg_running else true) {
        // frame stuff
        const current_time = try std.time.Instant.now();
        const delta_time_ns = current_time.since(previous_time);
        previous_time = current_time;

        const delta_time_ms = delta_time_ns / std.time.ns_per_ms;
        const fps = @as(f32, std.time.ns_per_s) / @as(f32, @floatFromInt(delta_time_ns));
        fps_buffer.push(fps);

        const uptime_s = current_time.since(app_start_time) / std.time.ns_per_s;

        // process events
        if (sdl.Event.waitTimeout(event_timeout_ms)) |event| {
            switch (event.type) {
                .quit => {
                    log.info("recived quit request", .{});

                    if (is_debug) {
                        log.debug("debug mode quit, cleaning up...", .{});
                        dbg_running = false;
                    } else {
                        log.debug("release mode quit, exiting immediatly", .{});
                        std.debug.lockStdErr();
                        std.process.exit(0);
                    }
                },

                .key_down, .key_up => key: {
                    const key = event.key;
                    cu.state.pushEvent(.{
                        .kind = .key_press,
                        .key = .{
                            .scancode = key.scancode,
                            .keycode = key.key,
                            .mod = key.mod,
                        },
                        .state = if (key.down) .pressed else .released,
                    });

                    if (!key.down) break :key;

                    switch (key.scancode) {
                        .escape => {
                            try sdl.Event.push(.mkQuit());
                        },
                        .minus => {
                            try default_font_handle.setSize((default_font_handle.getSize() catch @panic("")) - 1);
                            try monospace_font_handle.setSize((monospace_font_handle.getSize() catch @panic("")) - 1);
                        },
                        .equals => {
                            try default_font_handle.setSize((default_font_handle.getSize() catch @panic("")) + 1);
                            try monospace_font_handle.setSize((monospace_font_handle.getSize() catch @panic("")) + 1);
                        },
                        .f11 => {
                            if (window.getFlags() & sdl.WindowFlag.fullscreen != 0) {
                                try window.setFullscreen(false);
                            } else {
                                try window.setFullscreen(true);
                            }
                        },
                        else => {},
                    }
                },

                .mouse_motion => {
                    const motion = event.motion;
                    cu.state.pushEvent(.{
                        .kind = .mouse_move,
                        .pos = .vec(motion.x, motion.y),
                    });
                },

                .mouse_button_down, .mouse_button_up => {
                    const button = event.button;
                    const button_kind: cu.MouseButton = switch (button.button) {
                        .left => .left,
                        .middle => .middle,
                        .right => .right,
                        .x1 => .forward,
                        .x2 => .back,
                        else => @enumFromInt(@intFromEnum(button.button)),
                    };
                    cu.state.pushEvent(.{
                        .kind = .mouse_press,
                        .button = button_kind,
                        .state = if (button.down) .pressed else .released,
                        .pos = .vec(button.x, button.y),
                    });
                },

                .mouse_wheel => {
                    const wheel = event.wheel;
                    cu.state.pushEvent(.{
                        .kind = .scroll,
                        .scroll = .vec(wheel.x, wheel.y),
                        .pos = .vec(wheel.mouse_x, wheel.mouse_y),
                    });
                },

                .text_input => {
                    const text = event.text;
                    const slice = std.mem.sliceTo(text.text[0..], 0);
                    cu.state.pushEvent(.{
                        .kind = .text_input,
                        .text = slice,
                    });
                },

                .window_resized => {
                    const wind = event.window;
                    cu.state.window_size =
                        .axis(@floatFromInt(wind.data1), @floatFromInt(wind.data2));
                },

                .window_exposed => {
                    try cu_sdl_renderer.render();
                },

                else => {},
            }
        }

        // build ui
        cu.startBuild(@intFromEnum(window.getID()));
        cu.state.ui_root.layout_axis = .y;
        cu.state.ui_root.flags.draw_background = true;
        // Don't ask me why, but no matter how I slice it without the if, it doesn't work
        // I know it should, I don't know why it doesn't
        cu.state.ui_root.flags.draw_border =
            if (window.getFlags() & (sdl.WindowFlag.fullscreen | sdl.WindowFlag.maximized) != 0)
                false
            else
                true;

        { // topbar
            const topbar = cu.open("topbar");
            defer cu.close(topbar);
            topbar.flags = topbar.flags.drawSideBottom();
            topbar.layout_axis = .x;
            topbar.pref_size = .{ .w = .fill, .h = .px(24) };

            const menu_items = [_][]const u8{
                "Fe",
                "File",
                "Edit",
                "Help",
            };

            for (menu_items) |item_str| {
                const item = cu.build(item_str);
                item.flags = item.flags.clickable().drawText();
                item.pref_size = .square(.text_pad(8));

                const inter = item.interation();
                if (inter.f.hovering) {
                    item.flags.draw_border = true;
                }

                if (inter.f.isClicked()) {
                    std.debug.print("clicked {s}\n", .{item_str});
                    // dropdown_open = true;
                }
            }

            {
                const topbar_space = cu.build("topbar spacer");
                topbar_space.pref_size = .square(.grow);
                topbar_space.flags = topbar_space.flags.clickable();

                const inter = topbar_space.interation();
                if (inter.f.left_double_clicked) {
                    if (window.getFlags() & sdl.WindowFlag.maximized == 0) {
                        try window.maximize();
                    } else {
                        try window.restore();
                    }
                }
            }

            for (0..3) |i| {
                const button = cu.openf("top bar button {d}", .{i});
                defer cu.close(button);
                button.flags = button.flags.clickable().drawBorder();
                button.pref_size = .square(.px(24));

                const int = button.interation();
                if (int.f.hovering) {
                    button.palette.border = cu.Color.hexRgb(0xFF0000);
                }

                if (int.f.isClicked()) {
                    switch (i) {
                        0 => try window.minimize(),
                        1 => if (window.getFlags() & sdl.WindowFlag.maximized != 0) {
                            try window.restore();
                        } else {
                            try window.maximize();
                        },
                        2 => try sdl.Event.push(.mkQuit()),
                        else => unreachable,
                    }
                }
            }
        }

        { // main pane
            const main_pane = cu.open("main pain");
            defer cu.close(main_pane);
            main_pane.layout_axis = .x;
            main_pane.pref_size = .square(.grow);

            { // left pane
                const pane = cu.open("left pane");
                defer cu.close(pane);
                pane.flags = pane.flags.drawSideRight();
                pane.layout_axis = .y;
                pane.pref_size = .{ .w = .percent(0.4), .h = .fill };

                { // header
                    const header = cu.build("left header");
                    header.flags = header.flags.drawSideBottom().drawText();
                    header.display_string = "Left Header gylp";
                    header.pref_size = .{ .w = .grow, .h = .text };
                    header.text_align = .{ .w = .end, .h = .center };
                }

                { // content
                    const content = cu.open("left content");
                    defer cu.close(content);
                    content.flags = content.flags.clipRect().allowOverflow();
                    content.layout_axis = .y;
                    content.pref_size = .square(.grow);

                    cu.pushFont(monospace_font);
                    defer cu.popFont();

                    {
                        cu.pushTextColor(.hexRgb(0xff0000));
                        defer cu.popPalette();

                        _ = cu.labelf("fps: {d:.2}", .{fps});
                        _ = cu.labelf("ave fps: {d:.2}", .{fps_buffer.average()});
                        _ = cu.labelf("frame time: {d:.2}ms", .{delta_time_ms});
                        _ = cu.labelf("frame time: {d:.2}ns", .{delta_time_ns});
                        _ = cu.labelf("uptime: {d:.2}s", .{uptime_s});
                        _ = cu.labelf("build count: {d}", .{cu.state.current_build_index});
                        _ = cu.labelf("atom build count: {d}", .{cu.state.build_atom_count});
                    }

                    {
                        const spacer = cu.spacer(.axis(.grow, .text));
                        spacer.display_string = " ";
                    }

                    _ = cu.labelf("draw window border: {}", .{cu.state.ui_root.flags.draw_border});

                    _ = cu.labelf("current atom count: {d}", .{cu.state.atom_map.count()});
                    _ = cu.labelf("event count: {d}", .{cu.state.event_list.len});

                    {
                        const spacer = cu.spacer(.axis(.grow, .text));
                        spacer.display_string = " ";
                    }

                    var an_active_atom = false;
                    for (cu.state.active_atom_key, 0..) |key, i| {
                        if (key != .nil) {
                            const button: cu.MouseButton = @enumFromInt(i);
                            const active = cu.state.atom_map.get(key).?;
                            _ = cu.labelf("active atom: [{s}] {?}", .{ @tagName(button), active });

                            an_active_atom = true;
                        }
                    }
                    if (!an_active_atom)
                        _ = cu.label("active atom: none");

                    const hot = cu.state.atom_map.get(cu.state.hot_atom_key);
                    const hot_lbl = cu.labelf("hot atom: {?}", .{hot});
                    hot_lbl.flags.draw_text_weak = true;
                }
            }

            { // right pane
                const pane = cu.open("right pane");
                defer cu.close(pane);
                pane.layout_axis = .y;
                pane.pref_size = .{ .w = .grow, .h = .fill };

                { // header
                    const header = cu.open("right header");
                    defer cu.close(header);
                    header.flags = header.flags.drawSideBottom().drawText();
                    header.display_string = "Right Header";
                    header.pref_size = .{ .w = .grow, .h = .text };
                    header.text_align = .square(.center);
                    header.layout_axis = .x;

                    if (header.interation().f.mouse_over) {
                        cu.pushBackgroundColor(.hexRgb(0x001800));
                        defer cu.popPalette();

                        const float = cu.open("floating");
                        defer cu.close(float);
                        float.flags = float.flags.floating().drawBackground();
                        float.layout_axis = .y;
                        float.pref_size = .square(.fit);

                        float.rel_position = cu.state.mouse.sub(header.rect.p0).add(.square(10)).intoAxis();

                        _ = cu.label("tool tip!");
                        _ = cu.label("extra tips!");
                    }
                }

                { // content
                    const content = cu.open("right content");
                    defer cu.close(content);
                    content.layout_axis = .y;
                    content.pref_size = .square(.grow);
                }
            }

            { // right bar
                const bar = cu.open("right bar");
                defer cu.close(bar);
                bar.flags = bar.flags.drawSideLeft();
                bar.layout_axis = .y;

                const icon_size = cu.Atom.PrefSize.px(24);
                bar.pref_size = .{ .w = icon_size, .h = .grow };

                { // inner
                    const inner = cu.open("right bar inner");
                    defer cu.close(inner);
                    inner.layout_axis = .y;
                    inner.pref_size = .{ .w = icon_size, .h = .fit };

                    for (0..5) |i| {
                        {
                            const icon = cu.buildf("right bar icon {d}", .{i});
                            icon.flags.draw_border = true;
                            icon.pref_size = .square(icon_size);
                        }

                        _ = cu.spacer(.{ .w = icon_size, .h = .px(4) });
                    }
                }
            }
        }

        cu.endBuild();
        try cu_sdl_renderer.render();
    }

    if (!is_debug) unreachable;
}

pub const FpsCircleBuffer = struct {
    const Self = @This();
    const size = 100;

    buffer: [size]f32 = undefined,
    pos: usize = 0,
    count: usize = 0,

    pub fn push(self: *Self, value: f32) void {
        self.buffer[self.pos] = value;
        self.pos = (self.pos + 1) % size;
        self.count = @min(self.count + 1, size);
    }

    pub fn average(self: Self) f32 {
        var sum: f32 = 0;
        for (self.buffer[0..self.count]) |value|
            sum += value;
        return sum / @as(f32, @floatFromInt(self.count));
    }
};

fn windowHitTestCallback(window: *sdl.Window, point: *const sdl.Point, data: ?*anyopaque) callconv(.c) sdl.HitTestResult {
    _ = data;

    // I cannot for the life of me figure out a way to get window dragging/
    // moving working.
    //
    // If I set the titlebar to be a draggable area in here then we don't get
    // click events, okay so we set it to the empty space only.
    // Oh well now we cannot maximize/restore on a double click since we never
    // get such events.
    //
    // Okay so what if we set the area to be draggable dynamically?
    // We deal with double clicks just fine and when we detect a drag from our
    // end we can set a flag to set the area as draggable in the hit test.
    // Oh but now thats not working. Sometimes it works, but most the time
    // nothing happens.
    //
    // What about calling `SDL_SetWindowPosition`? Nope, wayland doesn't
    // support it and on x11 its laggy as heck.
    //
    // **So we're just shit outa luck huh? Yes - at least with sdl.**
    //
    // We can path on a platform specific solution to sdl. Not easy.
    // or we can give up on sdl and use something else
    // This is one of many reminders that sdl is built for gamse not
    // applications. Look at the note below about the resize handles
    //
    // What else then?
    // Or we could implement it all our self like zed.
    // We could go the ghostty route - custom-ish.
    //
    // It seams ghostty starts off with glfw and incrementally uses native apis:
    // https://github.com/ghostty-org/ghostty/discussions/2563
    // It is a good example of how we would do it in zig.
    //
    // Code of note from Zed custom implmentation:
    // https://github.com/zed-industries/zed/blob/68d453da52df43390be0d69ab33d42f78a694e43/crates/gpui/src/platform/linux/wayland/window.rs#L979
    // https://github.com/zed-industries/zed/blob/68d453da52df43390be0d69ab33d42f78a694e43/crates/gpui/src/platform/linux/x11/window.rs#L1428
    //
    // Looking at Zed's implementation, only x11 and wayland support this
    // `window.start_window_move` method. MacOs and Windows must have another
    // mechainisim for this. We could investigate further by looking into
    // how the titlebar is implemented for these platforms.
    //
    // For now we'll continue to use sdl3, maybe we can investigate using glfw
    // once we have gpu rendering.
    // Then we can investigate using gtk/adwaita for a native linux experience.
    // And also investiagte a custom implementation like Zed

    // @NOTE: Looking at how this works in gnome as compared to other
    //  applications the handles are on the outside of the window for others.
    //
    //  This includes: Ghostty (uses gtk/adwaita), Zed (wayland direct) and
    //  Zen browser (firefox: probably wayland direct)
    //
    //  Ghostty uses a gtk/adwaita titlebar, client-side nether the less,
    //  Zed uses a wholly custom titlebar and
    //  Zen uses a custom (even from firefox) titlebar
    //
    //  And these windows are rounded unlike ours.
    //
    //  If we don't set the window to borderless sdl will use libdecor on both
    //  x11 and wayland providing the out-of-window resizing.
    //  It does not seem there is any way to hook into this useage of libdecor
    //  to customize it any way.
    if (window.getFlags() & sdl.WindowFlag.borderless == 0)
        return .normal;

    const w, const h = window.getSize() catch @panic("could not get window size in hit test");

    const padding = 4;
    const in_left = point.x < padding;
    const in_right = point.x > w - padding;
    const in_top = point.y < padding;
    const in_bottom = point.y > h - padding;

    return if (in_top and in_left) .resize_topleft //
    else if (in_top and in_right) .resize_topright //
    else if (in_bottom and in_left) .resize_bottomleft //
    else if (in_bottom and in_right) .resize_bottomright //
    else if (in_top) .resize_top //
    else if (in_bottom) .resize_bottom //
    else if (in_left) .resize_left //
    else if (in_right) .resize_right //
    else .normal;
}
