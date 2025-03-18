// @TODO:
//   @[ ]: use a panicing allocators instead of 'catch @panic()' everywhere ?
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

const builtin = @import("builtin");
const std = @import("std");
const assert = std.debug.assert;

const sdl = @import("sdl/sdl.zig");
const fc = @import("fontconfig.zig");

const CuSdlRenderer = @import("CuSdlRenderer.zig");
const TermColor = @import("TermColor.zig");

const cu = @import("cu/cu.zig");

pub const std_options = std.Options{
    .logFn = logFn,
};

pub fn main() !void {
    run() catch |err| {
        const ttf_err = sdl.ttf.getError() orelse "[none]";
        const sdl_err = sdl.getError() orelse "[none]";
        std.log.err("[SDL_TTF]: {s}", .{ttf_err});
        std.log.err("[SDL]: {s}", .{sdl_err});

        return err;
    };
}

pub fn run() !void {
    // =-= allocator setup =-=

    const debug_mode = builtin.mode == .Debug;
    var debug_alloc = if (debug_mode) blk: {
        var debug_alloc = std.heap.DebugAllocator(.{
            // .never_unmap = true,
            // .retain_metadata = true,
            // .verbose_log = true,
            // .backing_allocator_zeroes = false,
        }).init;
        debug_alloc.backing_allocator = std.heap.c_allocator;
        break :blk debug_alloc;
    } else {};
    defer if (debug_mode) {
        const result = debug_alloc.deinit();
        if (result == .leak) {
            std.debug.print("Memory leak detected\n", .{});
        }
    };

    const alloc = if (builtin.mode == .Debug)
        debug_alloc.allocator()
    else if (builtin.mode == .ReleaseFast)
        std.heap.smp_allocator // allocator optimized for release-fast
    else
        std.heap.c_allocator;

    // =-= sdl window and renderer setup =-=

    try sdl.init(sdl.InitFlags.All);
    defer sdl.quit();

    try sdl.ttf.init();
    defer sdl.ttf.quit();

    const window = try sdl.Window.init(.{
        .title = "fe",
        .flags = sdl.Window.Flag.allow_highdpi | sdl.Window.Flag.resizable,
    });
    defer window.deinit();

    const renderer = try sdl.Renderer.init(.{
        .window = window,
        .flags = .{
            .software = false,
            .accelerated = true,
            .present_vsync = false,
        },
    });
    defer renderer.deinit();

    // =-= font setup =-=

    var default_font_handle, var monospace_font_handle = blk: {
        // ensure fonconfig is initialized
        try fc.init();
        defer fc.deinit();

        const font_size = 13;

        const default =
            try CuSdlRenderer.FontHandle.createFromFamilyName(alloc, "sans", font_size);
        const monospace =
            try CuSdlRenderer.FontHandle.createFromFamilyName(alloc, "monospace", font_size);

        break :blk .{ default, monospace };
    };
    defer {
        default_font_handle.destroy(alloc);
        monospace_font_handle.destroy(alloc);
    }

    // =-= cu setup =-=

    try cu.state.init(alloc, CuSdlRenderer.Callbacks.callbacks);
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
    const event_timeout_ms = 15;
    var previous_time = try std.time.Instant.now(); // used to measure elapsed time between frames
    var fps_buffer = FpsCircleBuffer{};

    var cu_sdl_renderer = CuSdlRenderer{ .sdl_rend = renderer };

    // =-= main loop =-=

    var running = true;
    while (running) {
        // frame stuff
        const current_time = try std.time.Instant.now();
        const delta_time_ns = current_time.since(previous_time);
        previous_time = current_time;

        const delta_time_ms = delta_time_ns / 1_000_000;
        const fps = 1e9 / @as(f32, @floatFromInt(delta_time_ns));
        fps_buffer.push(fps);

        const uptime_s = current_time.since(app_start_time) / std.time.ns_per_s;

        // process input
        if (sdl.Event.waitTimeout(event_timeout_ms)) |event| {
            // if (sdl.Event.poll()) |event| {
            switch (event.type) {
                .quit => running = false,
                .key => |key| key_blk: {
                    cu.state.pushEvent(.{
                        .kind = .key_press,
                        .key = key.keysym,
                        .state = @enumFromInt(@intFromEnum(key.state)),
                    });

                    if (key.state != .pressed) break :key_blk;

                    switch (key.keysym.scancode) {
                        .escape => {
                            running = false;
                        },
                        .minus => {
                            try default_font_handle.setSize(default_font_handle.ptsize - 1);
                            try monospace_font_handle.setSize(monospace_font_handle.ptsize - 1);
                        },
                        .equals => {
                            try default_font_handle.setSize(default_font_handle.ptsize + 1);
                            try monospace_font_handle.setSize(monospace_font_handle.ptsize + 1);
                        },
                        else => {},
                    }
                },
                .motion => |motion| {
                    cu.state.pushEvent(.{
                        .kind = .mouse_move,
                        .pos = .vec(@floatFromInt(motion.x), @floatFromInt(motion.y)),
                    });
                },
                .button => |button| {
                    cu.state.pushEvent(.{
                        .kind = .mouse_press,
                        .button = button.button,
                        .button_clicks = button.clicks,
                        .state = @enumFromInt(@intFromEnum(button.state)),
                        .pos = .vec(@floatFromInt(button.x), @floatFromInt(button.y)),
                    });
                },

                .wheel => |wheel| {
                    cu.state.pushEvent(.{
                        .kind = .scroll,
                        .scroll = .vec(wheel.preciseX, wheel.preciseY),
                    });
                },

                .text => |text| {
                    const slice = std.mem.sliceTo(text.text[0..], 0);
                    cu.state.pushEvent(.{
                        .kind = .text_input,
                        .text = slice,
                    });
                },

                .window => |wind| switch (wind.event) {
                    .resized => {
                        cu.state.window_size =
                            .axis(@floatFromInt(wind.data1), @floatFromInt(wind.data2));
                    },

                    else => {},
                },

                else => {},
            }
        }

        // build ui
        cu.startBuild(window.getID());
        cu.state.ui_root.layout_axis = .y;
        cu.state.ui_root.flags.draw_background = true;

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

            _ = cu.spacer(.square(.grow));

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
                    std.debug.print("top bar button {d} clicked\n", .{i});
                    switch (i) {
                        0 => {},
                        1 => {},
                        2 => running = false,
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
                        _ = cu.labelf("uptime: {d:.2}s", .{uptime_s});
                        _ = cu.labelf("build count: {d}", .{cu.state.current_build_index});
                        _ = cu.labelf("atom build count: {d}", .{cu.state.build_atom_count});
                    }

                    _ = cu.labelf("current atom count: {d}", .{cu.state.atom_map.count()});
                    _ = cu.labelf("event count: {d}", .{cu.state.event_list.len});

                    const active = cu.state.atom_map.get(cu.state.active_atom_key);
                    _ = cu.labelf("active atom: {?}", .{active});
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

                        float.rel_position = cu.state.mouse.sub(header.rect.p0).add(.square(10)).asAxis();

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

    std.process.cleanExit();
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

fn logFn(
    comptime message_level: std.log.Level,
    comptime scope: @TypeOf(.enum_literal),
    comptime format: []const u8,
    args: anytype,
) void {
    const faint = TermColor{ .style = .{ .faint = true } };
    const reset = TermColor.reset;

    const now = std.time.milliTimestamp();
    const level_txt, const level_color = switch (message_level) {
        .err => .{ "ERROR", TermColor{ .color = .red, .layer = .background } },
        .warn => .{ "WARNING", TermColor{ .color = .yellow, .layer = .background } },
        .info => .{ "INFO", TermColor{ .color = .blue, .layer = .background } },
        .debug => .{ "DEBUG", TermColor{ .color = .magenta, .layer = .background } },
    };

    const scope_str = if (scope == .default) "" else " " ++ @tagName(scope);

    const stderr = std.io.getStdErr().writer();
    var bw = std.io.bufferedWriter(stderr);
    const writer = bw.writer();

    std.debug.lockStdErr();
    defer std.debug.unlockStdErr();
    nosuspend {
        writer.print(
            "{[faint]}[{[now]d}{[reset]}{[scope]s}{[faint]}]{[reset]} {[level_color]} {[level]s} {[reset]} ",
            .{
                .faint = faint,
                .reset = reset,
                .now = now,
                .scope = scope_str,
                .level = level_txt,
                .level_color = level_color,
            },
        ) catch return;

        writer.print(format ++ "\n", args) catch return;

        bw.flush() catch return;
    }
}
