const builtin = @import("builtin");

const build_options = @import("build_options");

const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;

const log = std.log.scoped(.@"fe[sdl]");

const tracy = @import("tracy");
const sdl = @import("sdl3");

const cu = @import("cu");
const AtomFlags = cu.AtomFlags;

const fc = @import("fontconfig.zig");
const CuSdlRenderer = @import("CuSdlRenderer.zig");
const plugins = @import("plugins.zig");

pub fn entry(gpa: Allocator) !void {
    run(gpa) catch |err| {
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

pub fn run(gpa: Allocator) !void {
    const trace_app_init = tracy.beginZone(@src(), .{ .name = "init" });

    // =-= plugin setup =-=
    log.info("setting up plugins", .{});

    const host = try plugins.PluginHost.init(gpa);
    defer host.deinit(gpa);

    const plugin = host.plugins[0];
    try plugins.doTest(plugin);

    // =-= sdl setup =-=
    log.debug("initilizing sdl", .{});

    _ = sdl.c.SDL_SetHint(sdl.c.SDL_HINT_APP_ID, "me.ketanr.fe");
    _ = sdl.c.SDL_SetHint(sdl.c.SDL_HINT_VIDEO_WAYLAND_ALLOW_LIBDECOR, "1");
    _ = sdl.c.SDL_SetHint(sdl.c.SDL_HINT_VIDEO_WAYLAND_PREFER_LIBDECOR, "0");

    try sdl.init(sdl.InitFlag.events | sdl.InitFlag.video);
    defer sdl.quit();

    try sdl.ttf.init();
    defer sdl.ttf.quit();

    // =-= state =-=
    state = try AppState.init(gpa);
    defer state.deinit();

    // =-= main loop =-=
    log.debug("starting main loop", .{});

    trace_app_init.end();

    while (if (builtin.mode == .Debug) state.dbg_running else true) {
        tracy.frameMark();

        cu.state = state.main_window.ui_state;
        cu.startFrame();
        defer {
            cu.state = state.main_window.ui_state;
            cu.endFrame();
        }

        cu.state = state.dbg_window.ui_state;
        cu.startFrame();
        defer {
            cu.state = state.dbg_window.ui_state;
            cu.endFrame();
        }

        try state.frameStart();

        try processEvents();

        try update();
    }

    if (builtin.mode != .Debug) unreachable;
}

pub const Window = struct {
    window_handle: *sdl.Window,
    render_handle: CuSdlRenderer,
    ui_state: *cu.State,

    default_font_handle: *sdl.ttf.Font,
    monospace_font_handle: *sdl.ttf.Font,
    default_font: cu.State.FontId,
    monospace_font: cu.State.FontId,

    pub fn init(
        gpa: std.mem.Allocator,
        title: [:0]const u8,
        borderless: bool,
        size: cu.Axis2(c_int),
    ) !*Window {
        const trace = tracy.beginZone(@src(), .{ .name = "init window" });
        defer trace.end();

        log.debug("creating window", .{});

        const window = try sdl.Window.init(
            title,
            size.w,
            size.h,
            sdl.WindowFlag.high_pixel_density |
                sdl.WindowFlag.resizable |
                if (borderless) sdl.WindowFlag.borderless else 0,
        );
        try window.setHitTest(&windowHitTestCallback, null);

        // @BUG: for some reason the window shows up as black until resized, unless we do this
        try sdl.Event.push(.makeWindowResized(window.getID(), size.w, size.h));

        const sdl_renderer = try sdl.Renderer.init(window, null);
        const renderer = CuSdlRenderer{ .sdl_rend = sdl_renderer };

        const ui_state = try cu.State.init(gpa, CuSdlRenderer.Callbacks.callbacks);

        log.debug("setting up fonts", .{});
        const default_font_handle, const monospace_font_handle = blk: {
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

        const default_font =
            ui_state.registerFont(@alignCast(@ptrCast(default_font_handle)));
        const monospace_font =
            ui_state.registerFont(@alignCast(@ptrCast(monospace_font_handle)));

        ui_state.default_palette = cu.Atom.Palette{
            .background = .hexRgb(0x1d2021), // gruvbox bg0
            .text = .hexRgb(0xebdbb2), // gruvbox fg1
            .text_weak = .hexRgb(0xbdae93), // gruvbox fg3
            .border = .hexRgb(0x3c3836), // gruvbox bg1
            .hot = .hexRgb(0x665c54), // grovbox bg3
            .active = .hexRgb(0xfbf1c7), // grovbox fg0
        };
        ui_state.default_font = default_font;

        const result = try gpa.create(Window);
        result.* = .{
            .window_handle = window,
            .render_handle = renderer,
            .ui_state = ui_state,

            .default_font_handle = default_font_handle,
            .monospace_font_handle = monospace_font_handle,

            .default_font = default_font,
            .monospace_font = monospace_font,
        };
        return result;
    }

    pub fn deinit(window: *Window, gpa: std.mem.Allocator) void {
        window.ui_state.deinit();

        window.default_font_handle.close();
        window.monospace_font_handle.close();

        window.render_handle.sdl_rend.deinit();
        window.window_handle.deinit();

        gpa.destroy(window);
    }
};

pub const AppState = struct {
    gpa: std.mem.Allocator,
    dbg_running: if (builtin.mode == .Debug) bool else void = if (builtin.mode == .Debug) true else void{},

    main_window: *Window,
    dbg_window: *Window,

    // move to AppState
    fps_buffer: FpsCircleBuffer(100) = .{},
    app_start_time: std.time.Instant,
    previous_time: std.time.Instant,
    delta_time_ms: f32 = 0,
    delta_time_s: f32 = 0,
    uptime_s: u64 = 0,
    fps: f32 = 0,

    test_toggle: bool = false,

    pub fn init(gpa: std.mem.Allocator) !AppState {
        const main_window = try Window.init(gpa, "fe", true, .axis(800, 600));
        const dbg_window = try Window.init(gpa, "fe dbg", false, .axis(600, 400));

        const now = try std.time.Instant.now();

        return AppState{
            .gpa = gpa,
            .main_window = main_window,
            .dbg_window = dbg_window,
            .app_start_time = now,
            .previous_time = now,
        };
    }

    pub fn deinit(app: *AppState) void {
        app.main_window.deinit(app.gpa);
        app.dbg_window.deinit(app.gpa);
    }

    pub fn windowFromId(app: *const AppState, id: sdl.WindowID) ?*Window {
        return if (app.main_window.window_handle.getID() == id)
            app.main_window
        else if (app.dbg_window.window_handle.getID() == id)
            app.dbg_window
        else
            null;
    }

    pub fn frameStart(app: *AppState) !void {
        const current_time = try std.time.Instant.now();

        const delta_time_ns = current_time.since(app.previous_time);
        app.previous_time = current_time;

        app.delta_time_ms = @as(f32, @floatFromInt(delta_time_ns)) / @as(f32, std.time.ns_per_ms);
        app.delta_time_s = @as(f32, @floatFromInt(delta_time_ns)) / @as(f32, std.time.ns_per_s);

        app.fps = @as(f32, std.time.ns_per_s) / @as(f32, @floatFromInt(delta_time_ns));
        app.fps_buffer.push(app.fps);
        tracy.plot(f32, "fps", app.fps);

        app.uptime_s = current_time.since(app.app_start_time) / std.time.ns_per_s;
    }
};

var state: AppState = undefined;

fn processEvents() !void {
    const trace_events = tracy.beginZone(@src(), .{ .name = "events" });
    defer trace_events.end();

    // @TODO: base this value on display refresh rate
    const event_timeout_ms = 10;

    if (if (comptime build_options.poll_event_loop)
        sdl.Event.poll()
    else
        sdl.Event.waitTimeout(event_timeout_ms)) |event|
    ev: {
        const trace_handle_event = tracy.beginZone(@src(), .{ .name = "handle event" });
        defer trace_handle_event.end();

        switch (event.type) {
            .quit => {
                log.info("recived quit request", .{});

                if (builtin.mode == .Debug) {
                    log.debug("debug mode quit, cleaning up...", .{});
                    state.dbg_running = false;
                } else {
                    log.debug("release mode quit, exiting immediatly", .{});
                    std.debug.lockStdErr();
                    std.process.exit(0);
                }
            },

            .key_down, .key_up => {
                const key = event.key;
                const window = state.windowFromId(key.window_id) orelse break :ev;

                cu.state.pushEvent(.{
                    .key = .{
                        .scancode = @intFromEnum(key.scancode),
                        .keycode = .unknown, // @TODO
                        .mod = .{
                            .shift = key.mod.shift(),
                            .ctrl = key.mod.ctrl(),
                            .alt = key.mod.alt(),
                        },
                        .state = if (key.down) .pressed else .released,
                    },
                });

                if (!key.down) break :ev;

                switch (key.scancode) {
                    .minus => {
                        try window.default_font_handle.setSize((window.default_font_handle.getSize() catch @panic("")) - 1);
                        try window.monospace_font_handle.setSize((window.monospace_font_handle.getSize() catch @panic("")) - 1);
                    },
                    .equals => {
                        try window.default_font_handle.setSize((window.default_font_handle.getSize() catch @panic("")) + 1);
                        try window.monospace_font_handle.setSize((window.monospace_font_handle.getSize() catch @panic("")) + 1);
                    },
                    .f11 => {
                        if (window.window_handle.getFlags() & sdl.WindowFlag.fullscreen != 0) {
                            try window.window_handle.setFullscreen(false);
                        } else {
                            try window.window_handle.setFullscreen(true);
                        }
                    },
                    else => {},
                }
            },

            .mouse_motion => {
                const motion = event.motion;
                const window = state.windowFromId(motion.window_id) orelse break :ev;

                window.ui_state.pushEvent(.{
                    .mouse_move = .{ .pos = .vec(motion.x, motion.y) },
                });
            },

            .mouse_button_down, .mouse_button_up => {
                const button = event.button;
                const window = state.windowFromId(button.window_id) orelse break :ev;

                const button_kind: cu.MouseButton = switch (button.button) {
                    .left => .left,
                    .middle => .middle,
                    .right => .right,
                    .x1 => .forward,
                    .x2 => .back,
                    else => @enumFromInt(@intFromEnum(button.button)),
                };
                window.ui_state.pushEvent(.{
                    .mouse_button = .{
                        .button = button_kind,
                        .pos = .vec(button.x, button.y),
                        .state = if (button.down) .pressed else .released,
                    },
                });
            },

            .mouse_wheel => {
                const wheel = event.wheel;
                const window = state.windowFromId(wheel.window_id) orelse break :ev;

                window.ui_state.pushEvent(.{
                    .scroll = .{
                        .scroll = .vec(wheel.x, wheel.y),
                        .pos = .vec(wheel.mouse_x, wheel.mouse_y),
                    },
                });
            },

            .text_input => {
                const text = event.text;
                const window = state.windowFromId(text.window_id) orelse break :ev;

                const slice = std.mem.sliceTo(text.text[0..], 0);
                window.ui_state.pushEvent(.{
                    .text = .{ .text = slice },
                });
            },

            .window_resized => {
                const resized = event.window;
                const window = state.windowFromId(resized.window_id) orelse break :ev;

                window.ui_state.window_size =
                    .axis(@floatFromInt(resized.data1), @floatFromInt(resized.data2));
            },

            .window_exposed => {
                tracy.message("window expose");

                const exposed = event.window;
                const window = state.windowFromId(exposed.window_id) orelse break :ev;
                cu.state = window.ui_state;
                try window.render_handle.render();
            },

            .window_close_requested => {
                // const close = event.window;
                // const window = state.windowFromId(close.window_id) orelse break :ev;

                try sdl.Event.push(.makeQuit());
            },

            else => {},
        }
    }
}

fn update() !void {
    const window = state.main_window;
    cu.state = window.ui_state;

    // build ui
    cu.startBuild(@intFromEnum(window.window_handle.getID()));
    cu.state.ui_root.layout_axis = .y;
    cu.state.ui_root.flags.draw_background = true;
    // Don't ask me why, but no matter how I slice it without the if, it doesn't work
    // I know it should, I don't know why it doesn't
    cu.state.ui_root.flags.draw_border =
        if (window.window_handle.getFlags() & (sdl.WindowFlag.fullscreen | sdl.WindowFlag.maximized) != 0)
            false
        else
            true;

    { // topbar
        cu.pushFlags(.once(AtomFlags.none.drawSideBottom()));
        cu.pushLayoutAxis(.once(.x));
        cu.pushPrefSize(.once(.axis(.fill, .px(24))));
        const topbar = cu.open("topbar");
        defer cu.close(topbar);

        const menu_items = [_][]const u8{
            "Fe",
            "File",
            "Edit",
            "Help",
        };

        for (menu_items) |item_str| {
            cu.pushFlags(.once(AtomFlags.none.clickable().drawText()));
            cu.pushPrefSize(.once(.square(.text_pad(8))));
            const item = cu.build(item_str);

            const inter = item.interaction();
            if (inter.f.hovering) {
                item.flags.draw_border = true;
            }

            if (inter.f.isClicked()) {
                std.debug.print("clicked {s}\n", .{item_str});
                // dropdown_open = true;
            }
        }

        {
            cu.pushFlags(.once(AtomFlags.none.clickable()));
            cu.pushPrefSize(.once(.square(.grow)));
            const topbar_space = cu.build("topbar spacer");

            const inter = topbar_space.interaction();
            if (inter.f.left_double_clicked) {
                if (window.window_handle.getFlags() & sdl.WindowFlag.maximized == 0) {
                    try window.window_handle.maximize();
                } else {
                    try window.window_handle.restore();
                }
            }
        }

        for (0..3) |i| {
            cu.pushFlags(.once(AtomFlags.none.clickable().drawBorder()));
            cu.pushPrefSize(.once(.square(.px(24))));
            const button = cu.openf("top bar button {d}", .{i});
            defer cu.close(button);

            const int = button.interaction();
            if (int.f.hovering) {
                button.palette.border = cu.Color.hexRgb(0xFF0000);
            }

            if (int.f.isClicked()) {
                switch (i) {
                    0 => try window.window_handle.minimize(),
                    1 => if (window.window_handle.getFlags() & sdl.WindowFlag.maximized != 0) {
                        try window.window_handle.restore();
                    } else {
                        try window.window_handle.maximize();
                    },
                    2 => try sdl.Event.push(.makeWindowCloseRequested(window.window_handle.getID())),
                    else => unreachable,
                }
            }
        }
    }

    { // main pane
        cu.pushLayoutAxis(.once(.x));
        cu.pushPrefSize(.once(.square(.grow)));
        const main_pane = cu.open("main pain");
        defer cu.close(main_pane);

        { // left pane
            cu.pushFlags(.once(AtomFlags.none.drawSideRight()));
            cu.pushLayoutAxis(.once(.y));
            cu.pushPrefSize(.once(.axis(.percent(0.4), .fill)));
            const pane = cu.open("left pane");
            defer cu.close(pane);

            { // header
                cu.pushFlags(.once(AtomFlags.none.drawSideBottom().drawText()));
                cu.pushTextAlignment(.once(.axis(.end, .center)));
                cu.pushPrefSize(.once(.axis(.grow, .text)));
                const header = cu.build("left header");
                header.display_string = "Left Header gylp";
            }

            { // content
                cu.pushFlags(.once(AtomFlags.none.clipRect().allowOverflow()));
                cu.pushLayoutAxis(.once(.y));
                cu.pushPrefSize(.once(.square(.grow)));
                const content = cu.open("left content");
                defer cu.close(content);

                cu.pushFont(.keep(window.monospace_font));
                defer cu.popFont();

                _ = cu.labelf("draw window border: {}", .{cu.state.ui_root.flags.draw_border});

                _ = cu.lineSpacer();
            }
        }

        { // right pane
            cu.pushLayoutAxis(.once(.y));
            cu.pushPrefSize(.once(.axis(.grow, .fill)));
            const pane = cu.open("right pane");
            defer cu.close(pane);

            { // header
                cu.pushFlags(.once(AtomFlags.none.drawSideBottom().drawText()));
                cu.pushLayoutAxis(.once(.x));
                cu.pushTextAlignment(.once(.square(.center)));
                cu.pushPrefSize(.once(.axis(.grow, .text)));
                const header = cu.open("right header");
                defer cu.close(header);
                header.display_string = "Right Header";

                if (header.interaction().f.mouse_over) {
                    cu.pushBackgroundColor(.keep(.hexRgb(0x001800)));
                    defer cu.popPalette();

                    cu.pushFlags(.once(AtomFlags.none.floating().drawBackground()));
                    cu.pushLayoutAxis(.once(.y));
                    cu.pushPrefSize(.once(.square(.fit)));
                    const float = cu.open("floating");
                    defer cu.close(float);
                    float.rel_position = cu.state.mouse.sub(header.rect.p0).add(.square(10)).intoAxis();

                    _ = cu.label("tool tip!");
                    _ = cu.label("extra tips!");
                }
            }

            { // content
                cu.pushLayoutAxis(.once(.y));
                cu.pushPrefSize(.once(.square(.grow)));
                const content = cu.open("right content");
                defer cu.close(content);

                cu.pushPrefSize(.once(.square(.text_pad(8))));
                if (cu.button("foo bar").f.isClicked()) {
                    log.debug("foo bar clicked", .{});
                }

                _ = cu.lineSpacer();

                cu.pushPrefSize(.once(.axis(.px(40), .px(20))));
                _ = cu.toggleSwitch(&state.test_toggle);
            }
        }

        { // right bar
            cu.pushFlags(.once(AtomFlags.none.drawSideLeft()));
            cu.pushLayoutAxis(.once(.y));
            const bar = cu.open("right bar");
            defer cu.close(bar);

            const icon_size = cu.Atom.PrefSize.px(24);
            bar.pref_size = .{ .w = icon_size, .h = .grow };

            { // inner
                cu.pushLayoutAxis(.once(.y));
                cu.pushPrefSize(.once(.axis(icon_size, .fit)));
                const inner = cu.open("right bar inner");
                defer cu.close(inner);

                for (0..5) |i| {
                    {
                        cu.pushFlags(.once(AtomFlags.none.drawBorder()));
                        cu.pushPrefSize(.once(.square(icon_size)));
                        _ = cu.buildf("right bar icon {d}", .{i});
                    }

                    cu.pushPrefSize(.once(.axis(icon_size, .px(4))));
                    _ = cu.spacer();
                }
            }
        }
    }

    // the debug window accesses information that is reset with endBuild
    try updateDbgWindow();
    cu.state = window.ui_state;

    cu.endBuild();
    try window.render_handle.render();
}

pub fn updateDbgWindow() !void {
    const window = state.dbg_window;
    cu.state = window.ui_state;

    cu.startBuild(@intFromEnum(window.window_handle.getID()));
    cu.state.ui_root.layout_axis = .y;
    cu.state.ui_root.flags = cu.state.ui_root.flags.drawBackground().allowOverflow();

    {
        cu.pushTextColor(.keep(.hexRgb(0xff0000)));
        defer cu.popPalette();

        _ = cu.labelf("fps: {d:.2}", .{state.fps});
        _ = cu.labelf("ave fps: {d:.2}", .{state.fps_buffer.average()});
        _ = cu.labelf("frame time: {d:.2}ms", .{state.delta_time_ms});
        _ = cu.labelf("uptime: {d:.2}s", .{state.uptime_s});
    }

    _ = cu.lineSpacer();

    const main_state = state.main_window.ui_state;

    _ = cu.labelf("build count: {d}", .{main_state.current_build_index});
    _ = cu.labelf("atom build count: {d}", .{main_state.build_atom_count});

    _ = cu.lineSpacer();

    _ = cu.labelf("current atom count: {d}", .{main_state.atom_map.count()});
    _ = cu.labelf("event count: {d}", .{main_state.event_list.len});

    _ = cu.lineSpacer();

    var an_active_atom = false;
    for (main_state.active_atom_key, 0..) |key, i| {
        if (key != .nil) {
            const button: cu.MouseButton = @enumFromInt(i);
            const active = main_state.atom_map.get(key).?;
            _ = cu.labelf("active atom: [{s}] {?}", .{ @tagName(button), active });

            an_active_atom = true;
        }
    }
    if (!an_active_atom)
        _ = cu.label("active atom: none");

    const hot = main_state.atom_map.get(main_state.hot_atom_key);
    cu.pushFlags(.once(AtomFlags.none.drawTextWeak()));
    _ = cu.labelf("hot atom: {?}", .{hot});

    cu.endBuild();
    try window.render_handle.render();
}

pub fn FpsCircleBuffer(comptime Size: usize) type {
    return struct {
        const Self = @This();

        buffer: [Size]f32 = undefined,
        pos: usize = 0,
        count: usize = 0,

        pub fn push(self: *Self, value: f32) void {
            self.buffer[self.pos] = value;
            self.pos = (self.pos + 1) % Size;
            self.count = @min(self.count + 1, Size);
        }

        pub fn average(self: Self) f32 {
            var sum: f32 = 0;
            for (self.buffer[0..self.count]) |value|
                sum += value;
            return sum / @as(f32, @floatFromInt(self.count));
        }
    };
}

fn windowHitTestCallback(
    window: *sdl.Window,
    point: *const sdl.Point,
    data: ?*anyopaque,
) callconv(.c) sdl.HitTestResult {
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
    // We can also look into how raddbg does it,
    // but I'm unsure if linux support has been done for this kind if thing
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
