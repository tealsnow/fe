const std = @import("std");
const assert = std.debug.assert;
const mem = std.mem;
const Allocator = mem.Allocator;

const log = std.log.scoped(.@"fe[wl]");

const wayland = @import("wayland");
const wl = wayland.client.wl;
const xdg = wayland.client.xdg;
const Fixed = wl.Fixed;

const xkb = @import("xkbcommon");

// @TODO:
//   @[ ]: pointer gestures
//     https://wayland.app/protocols/pointer-gestures-unstable-v1
//
//   @[ ]: cursor shape
//     https://wayland.app/protocols/cursor-shape-v1
//
//   @[x]: out of window resizing
//
//   @[ ]: window rounding
//
//   @[ ]: xdg-desktop-portal

pub fn entry(gpa: Allocator) !void {
    try run(gpa);

    std.process.cleanExit();
}

fn run(gpa: Allocator) !void {
    _ = gpa;

    const wl_display = try wl.Display.connect(null);
    defer wl_display.disconnect();

    const wl_registry = try wl_display.getRegistry();
    defer wl_registry.destroy();

    var wl_registry_listener_data = WlRegistryListenerData.empty;
    wl_registry.setListener(
        *WlRegistryListenerData,
        &wlRegistryListener,
        &wl_registry_listener_data,
    );

    if (wl_display.roundtrip() != .SUCCESS) return error.wl;

    const wl_compositor = wl_registry_listener_data.wl_compositor.?;
    defer wl_compositor.destroy();

    const wl_shared_memory = wl_registry_listener_data.wl_shared_memory.?;
    defer wl_shared_memory.destroy();

    const wl_seat = wl_registry_listener_data.wl_seat.?;
    defer wl_seat.destroy();

    const xkb_context = xkb.Context.new(.no_flags) orelse return error.xkb;
    defer xkb_context.unref();

    var event_queue = EventQueue.empty;

    var wl_keyboard_listener_data = WlKeyboardListenerData{
        .event_queue = &event_queue,

        .xkb_context = xkb_context,
    };
    defer {
        if (wl_keyboard_listener_data.xkb_state) |xkb_state|
            xkb_state.unref();
        if (wl_keyboard_listener_data.xkb_keymap) |xkb_keymap|
            xkb_keymap.unref();
    }

    var wl_pointer_listener_data = WlPointerListenerData{
        .event_queue = &event_queue,
    };

    var wl_seat_listener_data = WlSeatListenerData{
        .wl_keyboard_listener_data = &wl_keyboard_listener_data,
        .wl_pointer_listener_data = &wl_pointer_listener_data,
    };
    wl_seat.setListener(
        *WlSeatListenerData,
        wlSeatListener,
        &wl_seat_listener_data,
    );
    defer {
        if (wl_seat_listener_data.wl_keyboard) |wl_keyboard|
            wl_keyboard.destroy();
        if (wl_seat_listener_data.wl_pointer) |wl_pointer|
            wl_pointer.destroy();
    }

    const xdg_wm_base = wl_registry_listener_data.xdg_wm_base.?;
    defer xdg_wm_base.destroy();

    var xdg_wm_base_listener_data = XdgWmBaseListenerData{};
    xdg_wm_base.setListener(
        *XdgWmBaseListenerData,
        &xdgWmBaseListener,
        &xdg_wm_base_listener_data,
    );

    const wl_surface = try wl_compositor.createSurface();
    defer wl_surface.destroy();

    const xdg_surface = try xdg_wm_base.getXdgSurface(wl_surface);
    defer xdg_surface.destroy();

    var xdg_surface_listener_data = XdgSurfaceListenerData{
        .event_queue = &event_queue,

        .wl_surface = wl_surface,
    };
    xdg_surface.setListener(
        *XdgSurfaceListenerData,
        xdgSurfaceListener,
        &xdg_surface_listener_data,
    );

    const xdg_toplevel = try xdg_surface.getToplevel();
    defer xdg_toplevel.destroy();

    xdg_toplevel.setTitle("fe wayland 2");

    var xdg_toplevel_listener_data = XdgToplevelListenerData{
        .event_queue = &event_queue,
    };
    xdg_toplevel.setListener(
        *XdgToplevelListenerData,
        &xdgToplevelListener,
        &xdg_toplevel_listener_data,
    );

    const wl_frame_callback = try wl_surface.frame();

    var wl_frame_callback_listener_data = WlFrameCallbackListenerData{
        .event_queue = &event_queue,

        .wl_surface = wl_surface,
    };
    wl_frame_callback.setListener(
        *WlFrameCallbackListenerData,
        &wlFrameCallbackListener,
        &wl_frame_callback_listener_data,
    );

    const initial_size = Size(u32){ .width = 200, .height = 200 };
    var window = Window.init(
        initial_size,
        try PixelData.configure(
            initial_size,
            wl_shared_memory,
        ),
    );
    defer window.deinit();

    window.inset = 10;

    var alpha: u8 = 0;
    var pointer_pos = Point(f64){ .x = -1, .y = -1 };

    log.info("starting main loop", .{});

    wl_surface.commit();

    main_loop: while (true) {
        // run listeners
        if (wl_display.dispatch() != .SUCCESS) {
            log.err("wl_display.dispatch() failed", .{});
            break :main_loop;
        }

        var do_render = false;

        while (event_queue.dequeue()) |event| {
            switch (event.kind) {
                .surface_configure => |configure| {
                    // surface requested a rerender
                    // acknowledge configure and mark for render

                    configure.xdg_surface.ackConfigure(configure.serial);

                    // window gemetry excludes CSD
                    const window_gemoetry = window.innerBounds();

                    xdg_surface.setWindowGeometry(
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
                        computeOuterSize(window.inset, new_size, conf.state);

                    window.bounds.size = size;

                    try window.pixel_data.reconfigure(
                        size,
                        wl_shared_memory,
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

                .key => |key| {
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

                    if (key.state == .pressed and key.codepoint == 'w') {
                        std.Thread.sleep(std.time.ns_per_s * 2);
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
                },
                .pointer_motion => |motion| {
                    // log.debug(
                    //     "pointer_motion: {d}x{d}",
                    //     .{ motion.x, motion.y },
                    // );

                    pointer_pos = motion.point;
                },
                .pointer_button => |button| {
                    log.debug(
                        "pointer_button: state: {s}, button: {s}, serial: {d}",
                        .{
                            @tagName(button.state),
                            @tagName(button.button),
                            button.serial,
                        },
                    );

                    if (window.inset) |inset_int| resize: {
                        if (button.state != .pressed) break :resize;
                        if (button.button != .left) break :resize;

                        const inset: f64 = @floatFromInt(inset_int);

                        const x = pointer_pos.x;
                        const y = pointer_pos.y;

                        const width: f64 =
                            @floatFromInt(window.bounds.size.width);
                        const height: f64 =
                            @floatFromInt(window.bounds.size.height);
                        const tiling = window.tiling;

                        const left = x < inset and !tiling.tiled_left;
                        const right = x >= width - inset and !tiling.tiled_right;
                        const top = y < inset and !tiling.tiled_top;
                        const bottom = y >= height - inset and !tiling.tiled_bottom;

                        // top left
                        if (top and left) {
                            xdg_toplevel.resize(
                                wl_seat,
                                button.serial,
                                .top_left,
                            );
                        }
                        // top right
                        if (top and right) {
                            xdg_toplevel.resize(
                                wl_seat,
                                button.serial,
                                .top_right,
                            );
                        }
                        // bottom left
                        if (bottom and left) {
                            xdg_toplevel.resize(
                                wl_seat,
                                button.serial,
                                .bottom_left,
                            );
                        }
                        // bottom right
                        if (bottom and right) {
                            xdg_toplevel.resize(
                                wl_seat,
                                button.serial,
                                .bottom_right,
                            );
                        }
                        // left
                        else if (left) {
                            xdg_toplevel.resize(
                                wl_seat,
                                button.serial,
                                .left,
                            );
                        }
                        // right
                        else if (right) {
                            xdg_toplevel.resize(
                                wl_seat,
                                button.serial,
                                .right,
                            );
                        }
                        // top
                        else if (top) {
                            xdg_toplevel.resize(
                                wl_seat,
                                button.serial,
                                .top,
                            );
                        }
                        // bottom
                        else if (bottom) {
                            xdg_toplevel.resize(
                                wl_seat,
                                button.serial,
                                .bottom,
                            );
                        }
                    }

                    if (button.button == .left) {
                        xdg_toplevel.move(wl_seat, button.serial);
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

                // else => {},
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

                        // left
                        if (x < inset and !window.tiling.tiled_left) {
                            pixels_u32[i] = 0xff_ff_00_00;
                            // pixels_u32[i] = 0x00000000;
                        }
                        // right
                        else if (x >= pixel_data.size.width - inset and
                            !window.tiling.tiled_right)
                        {
                            pixels_u32[i] = 0xff_00_ff_00;
                            // pixels_u32[i] = 0x00000000;
                        }
                        // top
                        else if (y < inset and !window.tiling.tiled_top) {
                            pixels_u32[i] = 0xff_00_00_ff;
                            // pixels_u32[i] = 0x00000000;
                        }
                        // bottom
                        else if (y >= pixel_data.size.height - inset and
                            !window.tiling.tiled_bottom)
                        {
                            pixels_u32[i] = 0xff_ff_ff_00;
                            // pixels_u32[i] = 0x00000000;
                        }
                        // content
                        else {
                            pixels_u32[i] = pink;
                        }
                    }
                }
            } else {
                @memset(pixels_u32, pink);
            }

            alpha +%= 1;

            wl_surface.attach(pixel_data.wl_buffer, 0, 0);
            wl_surface.damageBuffer(
                0,
                0,
                @intCast(pixel_data.size.width),
                @intCast(pixel_data.size.height),
            );
            wl_surface.commit();
        }
    }
}

// =============================================================================
// = wl registry

const WlRegistryListenerData = struct {
    wl_compositor: ?*wl.Compositor,
    wl_shared_memory: ?*wl.Shm,
    wl_seat: ?*wl.Seat,
    xdg_wm_base: ?*xdg.WmBase,

    pub const empty = WlRegistryListenerData{
        .wl_compositor = null,
        .wl_shared_memory = null,
        .wl_seat = null,
        .xdg_wm_base = null,
    };
};

fn wlRegistryListener(
    registry: *wl.Registry,
    event: wl.Registry.Event,
    data: *WlRegistryListenerData,
) void {
    const global = switch (event) {
        .global => |global| global,
        .global_remove => return,
    };

    log.debug(
        "wl: got global interface: '{s}', version: {d}",
        .{ global.interface, global.version },
    );

    if (mem.orderZ(
        u8,
        global.interface,
        wl.Compositor.interface.name,
    ) == .eq) {
        data.wl_compositor = registry.bind(
            global.name,
            wl.Compositor,
            6,
        ) catch @panic("could not bind wayland compositor");
    } else if (mem.orderZ(
        u8,
        global.interface,
        wl.Shm.interface.name,
    ) == .eq) {
        data.wl_shared_memory = registry.bind(
            global.name,
            wl.Shm,
            2,
        ) catch @panic("could not bind wayland shared memory");
    } else if (mem.orderZ(
        u8,
        global.interface,
        wl.Seat.interface.name,
    ) == .eq) {
        data.wl_seat = registry.bind(
            global.name,
            wl.Seat,
            8,
        ) catch @panic("could not bind wayland seat");
    } else if (mem.orderZ(
        u8,
        global.interface,
        xdg.WmBase.interface.name,
    ) == .eq) {
        data.xdg_wm_base = registry.bind(
            global.name,
            xdg.WmBase,
            6,
        ) catch @panic("could not bind xdg wm_base");
    }
}

// =============================================================================
// = xdg wm base

const XdgWmBaseListenerData = struct {};

fn xdgWmBaseListener(
    xdg_wm_base: *xdg.WmBase,
    event: xdg.WmBase.Event,
    data: *XdgWmBaseListenerData,
) void {
    _ = data;
    switch (event) {
        .ping => |ping| {
            xdg_wm_base.pong(ping.serial);
        },
    }
}

// =============================================================================
// = xdg surface

const XdgSurfaceListenerData = struct {
    event_queue: *EventQueue,

    wl_surface: *wl.Surface,
};

fn xdgSurfaceListener(
    xdg_surface: *xdg.Surface,
    event: xdg.Surface.Event,
    data: *XdgSurfaceListenerData,
) void {
    const configure = switch (event) {
        .configure => |configure| configure,
    };

    data.event_queue.queue(.{ .kind = .{
        .surface_configure = .{
            .wl_surface = data.wl_surface,
            .xdg_surface = xdg_surface,
            .serial = configure.serial,
        },
    } });
}

// =============================================================================
// = xdg toplevel

const XdgToplevelListenerData = struct {
    event_queue: *EventQueue,
};

fn xdgToplevelListener(
    toplevel: *xdg.Toplevel,
    event: xdg.Toplevel.Event,
    data: *XdgToplevelListenerData,
) void {
    _ = toplevel;

    switch (event) {
        .configure => |configure| {
            const size: ?Size(u32) =
                if (configure.width == 0 or configure.height == 0)
                    null
                else
                    .{
                        .width = @intCast(configure.width),
                        .height = @intCast(configure.height),
                    };

            var state = Event.ToplevelConfigureState{};
            const states = configure.states.slice(xdg.Toplevel.State);
            for (states) |s| {
                if (s == .maximized)
                    state.maximized = true;
                if (s == .fullscreen)
                    state.fullscreen = true;
                if (s == .resizing)
                    state.resizing = true;
                if (s == .activated)
                    state.activated = true;
                if (s == .tiled_left)
                    state.tiled_left = true;
                if (s == .tiled_right)
                    state.tiled_right = true;
                if (s == .tiled_top)
                    state.tiled_top = true;
                if (s == .tiled_bottom)
                    state.tiled_bottom = true;
                if (s == .suspended)
                    state.suspended = true;
            }

            data.event_queue.queue(.{ .kind = .{
                .toplevel_configure = .{
                    .size = size,
                    .state = state,
                },
            } });
        },
        .close => {
            data.event_queue.queue(.{ .kind = .{
                .toplevel_close = void{},
            } });
        },
        .configure_bounds => |configure_bounds| {
            // informs the client of the bounds we exist in
            // such as the monitor size

            _ = configure_bounds;
        },
        .wm_capabilities => {},
    }
}

// =============================================================================
// = wl frame callback

const WlFrameCallbackListenerData = struct {
    event_queue: *EventQueue,

    wl_surface: *wl.Surface,
};

fn wlFrameCallbackListener(
    callback: *wl.Callback,
    event: wl.Callback.Event,
    data: *WlFrameCallbackListenerData,
) void {
    assert(event == .done);

    data.event_queue.queue(.{ .kind = .{ .frame = void{} } });

    // setup a new callback
    // each callback is only valid once
    callback.destroy();
    const new_callback = data.wl_surface.frame() catch
        @panic("failed to contine frame callbacks");
    new_callback.setListener(
        *WlFrameCallbackListenerData,
        wlFrameCallbackListener,
        data,
    );
}

// =============================================================================
// = wl seat

const WlSeatListenerData = struct {
    wl_keyboard: ?*wl.Keyboard = null,
    wl_pointer: ?*wl.Pointer = null,

    wl_keyboard_listener_data: *WlKeyboardListenerData,
    wl_pointer_listener_data: *WlPointerListenerData,
};

fn wlSeatListener(
    wl_seat: *wl.Seat,
    event: wl.Seat.Event,
    data: *WlSeatListenerData,
) void {
    switch (event) {
        .capabilities => |capabilities| {
            const capability = capabilities.capabilities;

            if (capability.keyboard) {
                log.debug("getting wl keyboard", .{});

                const wl_keyboard = wl_seat.getKeyboard() catch unreachable;
                data.wl_keyboard = wl_keyboard;

                wl_keyboard.setListener(
                    *WlKeyboardListenerData,
                    &wlKeyboardListener,
                    data.wl_keyboard_listener_data,
                );
            }

            if (capability.pointer) {
                log.debug("getting wl pointer", .{});

                const wl_pointer = wl_seat.getPointer() catch unreachable;
                data.wl_pointer = wl_pointer;

                wl_pointer.setListener(
                    *WlPointerListenerData,
                    &wlPointerListener,
                    data.wl_pointer_listener_data,
                );
            }
        },
        .name => {},
    }
}

// =============================================================================
// = wl keyboard

const WlKeyboardListenerData = struct {
    event_queue: *EventQueue,

    xkb_context: *xkb.Context,
    xkb_keymap: ?*xkb.Keymap = null,
    xkb_state: ?*xkb.State = null,

    modifier_indices: XkbModifierIndices = undefined,
};

const XkbModifierIndices = struct {
    shift: u32,
    caps_lock: u32,
    ctrl: u32,
    alt: u32,
    logo: u32,
};

fn wlKeyboardListener(
    wl_keyboard: *wl.Keyboard,
    event: wl.Keyboard.Event,
    data: *WlKeyboardListenerData,
) void {
    _ = wl_keyboard;

    switch (event) {
        .keymap => |keymap| {
            assert(keymap.format == .xkb_v1);

            const xkb_keymap = keymap: {
                defer std.posix.close(keymap.fd);

                const map_shm = std.posix.mmap(
                    null,
                    keymap.size,
                    std.posix.PROT.READ,
                    .{ .TYPE = .PRIVATE },
                    keymap.fd,
                    0,
                ) catch @panic("failed to mmap keymap");
                defer std.posix.munmap(map_shm);

                const xkb_keymap = xkb.Keymap.newFromString(
                    data.xkb_context,
                    @ptrCast(map_shm.ptr),
                    .text_v1,
                    .no_flags,
                ) orelse @panic("failed to create keymap");
                break :keymap xkb_keymap;
            };

            data.xkb_keymap = xkb_keymap;

            data.xkb_state = xkb.State.new(xkb_keymap) orelse
                @panic("failed to create xkb state");

            data.modifier_indices = .{
                .shift = xkb_keymap.modGetIndex(xkb.names.mod.shift),
                .caps_lock = xkb_keymap.modGetIndex(xkb.names.mod.caps),
                .ctrl = xkb_keymap.modGetIndex(xkb.names.mod.ctrl),
                .alt = xkb_keymap.modGetIndex(xkb.names.mod.alt),
                .logo = xkb_keymap.modGetIndex(xkb.names.mod.logo),
            };
        },
        .enter => |enter| {
            data.event_queue.queue(.{ .kind = .{
                .keyboard_focus = .{
                    .state = .enter,
                    .serial = enter.serial,
                    .wl_surface = enter.surface,
                },
            } });

            const keys = enter.keys.slice(u32);
            for (keys) |key| {
                const xkb_state = data.xkb_state.?;
                const scancode = key + 8;
                const keysym = xkb_state.keyGetOneSym(scancode);
                const codepoint: u21 = @intCast(xkb_state.keyGetUtf32(scancode));

                data.event_queue.queue(.{ .kind = .{
                    .key = .{
                        .state = .pressed,
                        .scancode = scancode,
                        .keysym = keysym,
                        .codepoint = codepoint,
                        .serial = enter.serial,
                    },
                } });
            }
        },
        .leave => |leave| {
            data.event_queue.queue(.{ .kind = .{
                .keyboard_focus = .{
                    .state = .leave,
                    .serial = leave.serial,
                    .wl_surface = leave.surface,
                },
            } });
        },
        .key => |key| {
            const xkb_state = data.xkb_state.?;
            const scancode = key.key + 8;
            const keysym = xkb_state.keyGetOneSym(scancode);
            const codepoint: u21 = @intCast(xkb_state.keyGetUtf32(scancode));

            const state: Event.PressState = switch (key.state) {
                .pressed => .pressed,
                .released => .released,
                else => unreachable,
            };

            data.event_queue.queue(.{
                .kind = .{
                    .key = .{
                        .state = state,
                        .scancode = scancode,
                        .keysym = keysym,
                        .codepoint = codepoint,
                        .serial = key.serial,
                    },
                },
                .time = key.time,
            });

            if (state == .pressed) {
                var utf8_buffer: [4:0]u8 = @splat(0);
                const utf8_len =
                    std.unicode.utf8Encode(codepoint, &utf8_buffer) catch
                        @panic("got invalid utf8 from xkb");

                const utf8: ?[4:0]u8 = if (utf8_len == 1)
                    // filter out ascii control chars
                    // there may be more that we need to filter out
                    if (std.ascii.isPrint(utf8_buffer[0]))
                        utf8_buffer
                    else
                        null
                else
                    utf8_buffer;

                if (utf8) |text| {
                    data.event_queue.queue(.{
                        .kind = .{
                            .text = .{
                                .codepoint = codepoint,
                                .utf8 = text,
                            },
                        },
                        .time = key.time,
                    });
                }
            }
        },
        .modifiers => |modifiers| {
            const xkb_state = data.xkb_state.?;

            const component = xkb_state.updateMask(
                modifiers.mods_depressed,
                modifiers.mods_latched,
                modifiers.mods_locked,
                0,
                0,
                modifiers.group,
            );

            const shift = xkb_state.modIndexIsActive(
                data.modifier_indices.shift,
                component,
            ) == 1;
            const caps_lock = xkb_state.modIndexIsActive(
                data.modifier_indices.caps_lock,
                component,
            ) == 1;
            const ctrl = xkb_state.modIndexIsActive(
                data.modifier_indices.ctrl,
                component,
            ) == 1;
            const alt = xkb_state.modIndexIsActive(
                data.modifier_indices.alt,
                component,
            ) == 1;
            const gui = xkb_state.modIndexIsActive(
                data.modifier_indices.logo,
                component,
            ) == 1;

            const mod_state = Event.ModifierState{
                .shift = shift,
                .caps_lock = caps_lock,
                .ctrl = ctrl,
                .alt = alt,
                .logo = gui,
            };

            data.event_queue.queue(.{ .kind = .{
                .modifier = .{
                    .state = mod_state,
                    .serial = modifiers.serial,
                },
            } });
        },
        .repeat_info => |repeat_info| {
            // specifies how repeat should be done
            //  rate: keys per second
            //  delay: ms before repeat start
            // rate of 0 disables repeating

            // @TODO: Implement repeat

            log.debug(
                "got repeat info: rate: {d}, delay: {d}",
                .{ repeat_info.rate, repeat_info.delay },
            );
        },
    }
}

// =============================================================================
// = wl pointer

const WlPointerListenerData = struct {
    event_queue: *EventQueue,

    time: ?u32 = null,
    focus: ?Event.PointerFocus = null,
    motion: ?Event.PointerMotion = null,
    button: ?Event.PointerButton = null,

    scroll_axis: ?Event.PointerScrollAxis = null,
    scroll_source: ?Event.PointerScrollSource = null,
    scroll_value: ?f64 = null,
    scroll_value120: ?f64 = null,
    scroll_stop: bool = false,
};

// https://github.com/torvalds/linux/blob/e618ee89561b6b0fdc69f79e6fd0c33375d3e6b4/include/uapi/linux/input-event-codes.h#L355
const RawLinuxButtons = struct {
    pub const left = 0x110;
    pub const right = 0x111;
    pub const middle = 0x112;
    pub const forward = 0x115;
    pub const back = 0x116;
};

fn wlPointerListener(
    wl_pointer: *wl.Pointer,
    event: wl.Pointer.Event,
    data: *WlPointerListenerData,
) void {
    _ = wl_pointer;

    switch (event) {
        .enter => |enter| {
            data.focus = .{
                .state = .enter,
                .serial = enter.serial,
                .wl_surface = enter.surface,
            };

            // It makes more sense to put all motion interpreting in one place
            data.motion = .{
                .point = .{
                    .x = enter.surface_x.toDouble(),
                    .y = enter.surface_y.toDouble(),
                },
            };
        },
        .leave => |leave| {
            data.focus = .{
                .state = .leave,
                .serial = leave.serial,
                .wl_surface = leave.surface,
            };
        },
        .motion => |motion| {
            data.time = motion.time;

            data.motion = .{
                .point = .{
                    .x = motion.surface_x.toDouble(),
                    .y = motion.surface_y.toDouble(),
                },
            };
        },
        .button => |button| button: {
            data.time = button.time;

            const mbutton: Event.PointerButtonKind = switch (button.button) {
                RawLinuxButtons.left => .left,
                RawLinuxButtons.right => .right,
                RawLinuxButtons.middle => .middle,
                RawLinuxButtons.forward => .forward,
                RawLinuxButtons.back => .back,
                else => break :button,
            };

            const state: Event.PressState = switch (button.state) {
                .pressed => .pressed,
                .released => .released,
                else => unreachable,
            };

            data.button = .{
                .button = mbutton,
                .state = state,
                .serial = button.serial,
            };
        },
        .axis_source => |axis_source| {
            data.scroll_source = switch (axis_source.axis_source) {
                .wheel => .wheel,
                .finger => .finger,
                .continuous => .continuous,
                .wheel_tilt => .wheel_tilt,
                else => .unknown,
            };
        },
        .axis => |axis| {
            data.time = axis.time;

            data.scroll_axis = switch (axis.axis) {
                .vertical_scroll => .vertical,
                .horizontal_scroll => .horizontal,
                else => unreachable,
            };

            if (data.scroll_value) |*value| {
                value.* += axis.value.toDouble();
            } else {
                data.scroll_value = axis.value.toDouble();
            }
        },
        .axis_discrete => |axis_discrete| {
            // Not used in favour of axis_value120 from version 8 of wl_pointer

            _ = axis_discrete.axis;
            _ = axis_discrete.discrete;
        },
        .axis_value120 => |axis_value120| {
            // High resolution scroll event
            // measured as a fraction of 120
            //
            // e.g. value120 = 30
            //      30 / 120 = 0.25
            // thus scroll by a quater of a logical step
            //
            // repleaces axis_descrete from version 8 of wl_pointer

            data.scroll_axis = switch (axis_value120.axis) {
                .vertical_scroll => .vertical,
                .horizontal_scroll => .horizontal,
                else => unreachable,
            };

            // @NOTE:
            //  on my machine running gnome 47 I get (-)10 for axis events and
            //  (-)120 ((-)1 adjusted) for this with my mouse - my touchpad does
            //  not emit this event - thus I have opted to mulitply this value
            //  by ten. So that when it is prefferd during a frame event the
            //  value matches what axis would have emited.
            //
            //  Since the normal axis event emits 10, it seems to me that a
            //  step is `10` and that my mouse emits a descrete scroll of 1 step
            //
            //  This may be a wrong interpretation
            const value_scaled =
                @as(f64, @floatFromInt(axis_value120.value120)) / 120 * 10;

            if (data.scroll_value120) |*value| {
                value.* += value_scaled;
            } else {
                data.scroll_value120 = value_scaled;
            }
        },
        .axis_stop => |axis_stop| {
            data.time = axis_stop.time;

            data.scroll_axis = switch (axis_stop.axis) {
                .vertical_scroll => .vertical,
                .horizontal_scroll => .horizontal,
                else => unreachable,
            };
            data.scroll_stop = true;
        },
        .frame => {
            // we batch input until we get this event, then send it

            const time = data.time; // time may be null
            data.time = null;

            if (data.focus) |focus| {
                data.focus = null;
                data.event_queue.queue(.{
                    .kind = .{ .pointer_focus = focus },
                    .time = time,
                });
            }

            if (data.motion) |motion| {
                data.motion = null;
                data.event_queue.queue(.{
                    .kind = .{ .pointer_motion = motion },
                    .time = time,
                });
            }

            if (data.button) |button| {
                data.button = null;
                data.event_queue.queue(.{
                    .kind = .{ .pointer_button = button },
                    .time = time,
                });
            }

            // both the scroll axis and source are sent every scroll
            if (data.scroll_axis) |axis| {
                const source = data.scroll_source.?;

                // prefer value120 over the standard
                // at least one will be set
                // ...if stop is not set
                const value = if (data.scroll_stop)
                    null
                else if (data.scroll_value120) |value120|
                    value120
                else
                    data.scroll_value.?;

                data.event_queue.queue(.{
                    .kind = .{
                        .pointer_scroll = .{
                            .axis = axis,
                            .source = source,
                            .value = value,
                        },
                    },
                    .time = time,
                });

                data.scroll_axis = null;
                data.scroll_source = null;
                data.scroll_value = null;
                data.scroll_value120 = null;
                data.scroll_stop = false;
            }
        },
    }
}

// =============================================================================
// = Event plumbing

/// Will be faster (if only marginal) with a power of 2 Size
///
/// This has no checking for overwriting
pub fn CircleBufferQueue(comptime size: usize, comptime T: type) type {
    return struct {
        buffer: [size]T,
        head: usize,
        tail: usize,

        const Queue = @This();

        pub const empty = Queue{
            .buffer = undefined,
            .head = 0,
            .tail = 0,
        };

        pub fn queue(self: *Queue, item: T) void {
            self.buffer[self.head] = item;
            self.head = (self.head + 1) % size;
        }

        pub fn dequeue(self: *Queue) ?T {
            if (self.tail == self.head) return null;

            const item = self.buffer[self.tail];
            self.tail = (self.tail + 1) % size;
            return item;
        }

        pub fn count(self: *Queue) usize {
            return (self.head -% self.tail +% size) % size;
        }
    };
}

// set to 8 max as a conservative measure, I have not seen more than 3 in my
// testing, but different compositors could act different
pub const EventQueue = CircleBufferQueue(8, Event);

pub const Event = struct {
    kind: Kind,
    time: ?u32 = null, // ms

    pub const Kind = union(enum) {
        surface_configure: SurfaceConfigure,

        toplevel_configure: ToplevelConfigure,
        toplevel_close: void,

        frame: void,

        keyboard_focus: KeyboardFocus,
        key: Key,
        modifier: Modifier,
        text: Text,

        pointer_focus: PointerFocus,
        pointer_motion: PointerMotion,
        pointer_button: PointerButton,
        pointer_scroll: PointerScroll,
    };

    pub const PressState = enum {
        pressed,
        released,
    };

    pub const FocusState = enum {
        enter,
        leave,
    };

    pub const Ping = struct {
        xdg_wm_base: *xdg.WmBase,
        serial: u32,
    };

    pub const SurfaceConfigure = struct {
        wl_surface: *wl.Surface,
        xdg_surface: *xdg.Surface,
        serial: u32,
    };

    pub const ToplevelConfigure = struct {
        size: ?Size(u32),
        state: ToplevelConfigureState,
    };

    pub const ToplevelConfigureState = packed struct {
        maximized: bool = false,
        fullscreen: bool = false,
        resizing: bool = false,
        activated: bool = false,
        tiled_left: bool = false,
        tiled_right: bool = false,
        tiled_top: bool = false,
        tiled_bottom: bool = false,
        suspended: bool = false,

        pub fn isTiled(state: ToplevelConfigureState) bool {
            return state.maximized or
                state.fullscreen or
                (state.tiled_left and
                    state.tiled_right and
                    state.tiled_top and
                    state.tiled_bottom);
        }
    };

    pub const KeyboardFocus = struct {
        state: FocusState,
        serial: u32,
        wl_surface: ?*wl.Surface,
    };

    pub const Key = struct {
        state: PressState,
        scancode: u32,
        keysym: xkb.Keysym,
        codepoint: u21, // may be 0
        serial: u32,
    };

    pub const Modifier = struct {
        state: ModifierState,
        serial: u32,
    };

    pub const Text = struct {
        codepoint: u21,
        utf8: [4:0]u8,

        pub fn sliceZ(text: Text) [:0]const u8 {
            return std.mem.sliceTo(&text.utf8, 0);
        }

        pub fn slice(text: Text) []const u8 {
            const z = text.sliceZ();
            z[0..z.len];
        }
    };

    pub const ModifierState = packed struct(u8) {
        shift: bool = false,
        caps_lock: bool = false,
        ctrl: bool = false,
        alt: bool = false,
        logo: bool = false, // super
        _padding: u3 = 0,
    };

    pub const PointerFocus = struct {
        state: FocusState,
        serial: u32,
        wl_surface: ?*wl.Surface,
    };

    pub const PointerMotion = struct {
        point: Point(f64),
    };

    pub const PointerButton = struct {
        state: PressState,
        button: PointerButtonKind,
        serial: u32,
    };

    pub const PointerButtonKind = enum {
        left,
        right,
        middle,
        forward,
        back,
    };

    pub const PointerScroll = struct {
        axis: PointerScrollAxis,
        source: PointerScrollSource,
        /// null means stop event see `PointerScrollSource`
        value: ?f64,
    };

    pub const PointerScrollAxis = enum {
        vertical,
        horizontal,
    };

    /// A stop event is garenteed for finger,
    /// it is not garenteed for any other type
    pub const PointerScrollSource = enum {
        unknown,
        wheel,
        finger,
        continuous,
        wheel_tilt,
    };
};

// =============================================================================
// = Math

pub fn Point(comptime T: type) type {
    return struct {
        x: T,
        y: T,

        const Self = @This();

        pub fn intCast(point: Self, comptime NT: type) Point(NT) {
            return .{
                .x = @intCast(point.x),
                .y = @intCast(point.y),
            };
        }
    };
}

pub fn Size(comptime T: type) type {
    return struct {
        width: T,
        height: T,

        const Self = @This();

        pub fn intCast(size: Self, comptime NT: type) Size(NT) {
            return .{
                .width = @intCast(size.width),
                .height = @intCast(size.height),
            };
        }
    };
}

pub fn Bounds(comptime T: type) type {
    return struct {
        origin: Point(T),
        size: Size(T),

        const Self = @This();

        pub fn intCast(bounds: Self, comptime NT: type) Bounds(NT) {
            return .{
                .origin = bounds.origin.intCast(NT),
                .size = bounds.size.intCast(NT),
            };
        }
    };
}

fn computeOuterSize(
    window_inset: ?u32,
    new_size: Size(u32),
    tiling: Event.ToplevelConfigureState,
) Size(u32) {
    const inset = window_inset orelse return new_size;

    var size = new_size;

    if (!tiling.tiled_top)
        size.height += inset;
    if (!tiling.tiled_bottom)
        size.height += inset;
    if (!tiling.tiled_left)
        size.width += inset;
    if (!tiling.tiled_right)
        size.width += inset;

    return size;
}

fn insetBounds(
    bounds: Bounds(u32),
    window_inset: ?u32,
    tiling: Event.ToplevelConfigureState,
) Bounds(i32) {
    var out = bounds.intCast(i32);
    const inset: i32 = @intCast(window_inset orelse return out);

    if (!tiling.tiled_top) {
        out.origin.y += inset;
        out.size.height -= inset;
    }
    if (!tiling.tiled_bottom) {
        out.size.height -= inset;
    }
    if (!tiling.tiled_left) {
        out.origin.x += inset;
        out.size.width -= inset;
    }
    if (!tiling.tiled_right) {
        out.size.width -= inset;
    }

    return out;
}

// =============================================================================
// = Window

pub const Window = struct {
    bounds: Bounds(u32),
    inset: ?u32,
    tiling: Event.ToplevelConfigureState,

    pixel_data: PixelData,

    pub fn init(size: Size(u32), pixel_data: PixelData) Window {
        return .{
            .bounds = .{
                .origin = .{ .x = 0, .y = 0 },
                .size = size,
            },
            .inset = null,
            .tiling = .{},
            .pixel_data = pixel_data,
        };
    }

    pub fn deinit(window: Window) void {
        window.pixel_data.deinit();
    }

    pub fn innerBounds(window: Window) Bounds(i32) {
        return insetBounds(window.bounds, window.inset, window.tiling);
    }
};

const PixelData = struct {
    wl_buffer: *wl.Buffer,
    pixels: []u8,
    size: Size(u32),

    pub fn configure(
        size: Size(u32),
        wl_shared_memory: *wl.Shm,
    ) !PixelData {
        const len = size.width * size.height * 4;

        const fd = try std.posix.memfd_create("fe-wl_shm", 0);
        try std.posix.ftruncate(fd, len);

        const pixels = try std.posix.mmap(
            null,
            len,
            std.posix.PROT.READ | std.posix.PROT.WRITE,
            std.posix.MAP{ .TYPE = .SHARED },
            fd,
            0,
        );

        const pool = try wl_shared_memory.createPool(fd, @intCast(len));
        defer pool.destroy();

        const wl_buffer = try pool.createBuffer(
            0,
            @intCast(size.width),
            @intCast(size.height),
            @intCast(size.width * 4),
            .argb8888,
        );

        return .{
            .wl_buffer = wl_buffer,
            .pixels = pixels,
            .size = size,
        };
    }

    pub fn deinit(data: PixelData) void {
        data.wl_buffer.destroy();
    }

    pub fn reconfigure(
        data: *PixelData,
        size: Size(u32),
        wl_shared_memory: *wl.Shm,
    ) !void {
        if (data.size.width != size.width or data.size.height != size.height) {
            data.deinit();
            data.* = try configure(size, wl_shared_memory);
        }
    }
};
