const std = @import("std");
const assert = std.debug.assert;
const mem = std.mem;
const Allocator = mem.Allocator;

const log = std.log.scoped(.@"fe[wl]");

const xdg = @import("wayland").client.xdg;
const xkb = @import("xkbcommon");

const Connection = @import("platform/linux/wayland/Connection.zig");
const Window = @import("platform/linux/wayland/Window.zig");

const CursorKind = @import("platform/linux/wayland/cursor_manager.zig").CursorKind;

const Size = @import("math.zig").Size;
const Point = @import("math.zig").Point;

// @TODO:
//   @[ ]: wgpu intergration
//
//   @[ ]: setup cu
//
//   @[ ]: pointer gestures
//     https://wayland.app/protocols/pointer-gestures-unstable-v1
//     gonna wait until support has been around for a little longer
//
//   @[ ]: xdg-desktop-portal
//     @[x]: cursor theme and size
//     @[ ]: desktop theme / appearance
//     @[ ]: listen to changes
//
//   @[ ]: window rounding - cu?
//
//   @[ ]: window shadows - cu?
//
//   @[ ]: cu: window border
//
//   @[x]: cursor shape
//     https://wayland.app/protocols/cursor-shape-v1
//
//   @[x]: out of window resizing

pub fn entry(gpa: Allocator) !void {
    try run(gpa);

    std.process.cleanExit();
}

fn run(gpa: Allocator) !void {
    const conn = try Connection.init(gpa);
    defer conn.deinit(gpa);

    const initial_size = Size(u32){ .width = 200, .height = 200 };
    var window = Window.init(
        initial_size,
        try Window.PixelData.configure(
            initial_size,
            conn.wl_shm,
        ),
    );
    defer window.deinit();

    window.inset = 10;

    var alpha: u8 = 0;
    var pointer_pos = Point(f64){ .x = -1, .y = -1 };
    var pointer_enter_serial: u32 = 0;

    log.info("starting main loop", .{});

    conn.wl_surface.commit();

    main_loop: while (true) {
        // gather events
        try conn.dispatch();

        var do_render = false;

        while (conn.event_queue.dequeue()) |event| {
            switch (event.kind) {
                .surface_configure => |configure| {
                    // surface requested a rerender
                    // acknowledge configure and mark for render

                    configure.xdg_surface.ackConfigure(configure.serial);

                    // window gemetry excludes CSD
                    const window_gemoetry = window.innerBounds();

                    conn.xdg_surface.setWindowGeometry(
                        window_gemoetry.origin.x,
                        window_gemoetry.origin.y,
                        window_gemoetry.size.width,
                        window_gemoetry.size.height,
                    );

                    do_render = true;
                },

                .toplevel_configure => |conf| {
                    // mostly just a resize event

                    window.tiling = conf.state;

                    // this size is in terms of window geometry
                    // so we need to add back our inset to get the actual size
                    const new_size = conf.size orelse initial_size;
                    const size =
                        Window.computeOuterSize(window.inset, new_size, conf.state);

                    window.size = size;

                    try window.pixel_data.reconfigure(
                        size,
                        conn.wl_shm,
                    );

                    do_render = true;
                },

                .toplevel_close => {
                    // window was requested to close

                    log.debug("close request", .{});
                    break :main_loop;
                },

                .frame => {
                    // the compositor has told us this is a good time to render
                    // useful for animations or just rendering every time

                    do_render = true;
                },

                .keyboard_focus => |focus| {
                    log.debug(
                        "keyboard_focus: state: {s}, serial: {d}",
                        .{ @tagName(focus.state), focus.serial },
                    );
                },

                .key => |key| key: {
                    log.debug(
                        "key: state: {s}, scancode: {d}, keysym: {}," ++
                            " codepoint: 0x{x}",
                        .{
                            @tagName(key.state),
                            key.scancode,
                            key.keysym,
                            key.codepoint,
                        },
                    );

                    if (key.state != .pressed) break :key;

                    switch (@intFromEnum(key.keysym)) {
                        xkb.Keysym.q => break :main_loop,

                        xkb.Keysym.w => {
                            std.Thread.sleep(std.time.ns_per_s * 2);
                        },

                        else => {},
                    }
                },

                .modifier => |mods| {
                    log.debug(
                        "mods: shift: {}, caps_lock: {}, ctrl: {}, alt: {}," ++
                            " gui: {}, serial: {d}",
                        .{
                            mods.state.shift,
                            mods.state.caps_lock,
                            mods.state.ctrl,
                            mods.state.alt,
                            mods.state.logo,
                            mods.serial,
                        },
                    );
                },

                .text => |text| {
                    const utf8 = text.sliceZ();
                    log.debug(
                        "text: codepoint: 0x{x}, text: '{s}'",
                        .{
                            text.codepoint,
                            std.fmt.fmtSliceEscapeLower(utf8),
                        },
                    );
                },

                .pointer_focus => |focus| {
                    log.debug(
                        "pointer_focus: state: {s}, serial: {d}",
                        .{ @tagName(focus.state), focus.serial },
                    );

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

                    const cursor: CursorKind = if (window.inset) |inset|
                        if (Window.Edge.fromPoint(
                            pointer_pos,
                            window.size,
                            inset,
                            window.tiling,
                        )) |edge|
                            switch (edge) {
                                .top_left, .bottom_right => .resize_nwse,
                                .top_right, .bottom_left => .resize_nesw,
                                .left, .right => .resize_ew,
                                .top, .bottom => .resize_ns,
                            }
                        else
                            .default
                    else
                        .default;

                    try conn.cursor_manager.setCursor(
                        pointer_enter_serial,
                        cursor,
                    );
                },
                .pointer_button => |button| button: {
                    log.debug(
                        "pointer_button: state: {s}, button: {s}, serial: {d}",
                        .{
                            @tagName(button.state),
                            @tagName(button.button),
                            button.serial,
                        },
                    );

                    if (button.state != .pressed) break :button;

                    if (window.inset) |inset| resize: {
                        if (button.button != .left) break :resize;

                        if (Window.Edge.fromPoint(
                            pointer_pos,
                            window.size,
                            inset,
                            window.tiling,
                        )) |edge| {
                            const resize: xdg.Toplevel.ResizeEdge = switch (edge) {
                                .left => .left,
                                .right => .right,
                                .top => .top,
                                .bottom => .bottom,
                                .top_left => .top_left,
                                .top_right => .top_right,
                                .bottom_left => .bottom_left,
                                .bottom_right => .bottom_right,
                            };

                            conn.xdg_toplevel.resize(
                                conn.wl_seat,
                                button.serial,
                                resize,
                            );
                        }
                    }

                    if (button.button == .left) {
                        conn.xdg_toplevel.move(conn.wl_seat, button.serial);
                    }
                },
                .pointer_scroll => |scroll| {
                    log.debug(
                        "pointer_scroll: axis: {s}, source: {s}, value: {?d}",
                        .{
                            @tagName(scroll.axis),
                            @tagName(scroll.source),
                            scroll.value,
                        },
                    );
                },
            }
        }

        if (do_render) {
            const pixel_data = window.pixel_data;

            const pixels_u32 =
                @as([*]u32, @ptrCast(@alignCast(pixel_data.pixels.ptr))) //
                [0..(pixel_data.size.width * pixel_data.size.height)];

            const pink = 0x00f4597b | (@as(u32, @intCast(alpha)) << 24);

            if (window.inset) |inset| {
                for (0..pixel_data.size.height) |y| {
                    for (0..pixel_data.size.width) |x| {
                        const i = y * pixel_data.size.width + x;

                        const color: u32 = if (Window.Edge.fromPoint(
                            .{ .x = @floatFromInt(x), .y = @floatFromInt(y) },
                            window.size,
                            inset,
                            window.tiling,
                        )) |edge|
                            switch (edge) {
                                .left => 0xffff0000,
                                .right => 0xff00ff00,
                                .top => 0xff0000ff,
                                .bottom => 0xffffff00,

                                .top_left => 0xffff00ff,
                                .top_right => 0xffffff00,
                                .bottom_left => 0xffffffff,
                                .bottom_right => 0xff000000,
                            }
                        else
                            pink;

                        pixels_u32[i] = color;
                    }
                }
            } else {
                @memset(pixels_u32, pink);
            }

            alpha +%= 1;

            conn.wl_surface.attach(pixel_data.wl_buffer, 0, 0);
            conn.wl_surface.damageBuffer(
                0,
                0,
                @intCast(pixel_data.size.width),
                @intCast(pixel_data.size.height),
            );
            conn.wl_surface.commit();
        }
    }
}
