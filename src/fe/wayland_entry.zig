const std = @import("std");
const assert = std.debug.assert;
const mem = std.mem;
const Allocator = mem.Allocator;

const log = std.log.scoped(.@"fe[wl]");

const wayland = @import("wayland2");
const wl = wayland.client.wl;
const xdg = wayland.client.xdg;

const xkb = @import("xkbcommon");

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

    var wl_keyboard_listener_data = WlKeyboardListenerData{
        .xkb_context = xkb_context,
        .xkb_keymap = null, // set in keyboard listener
        .xkb_state = null, // set in keyboard listener
    };
    defer {
        if (wl_keyboard_listener_data.xkb_state) |xkb_state|
            xkb_state.unref();
        if (wl_keyboard_listener_data.xkb_keymap) |xkb_keymap|
            xkb_keymap.unref();
    }

    var event_queue = EventQueue.init;

    var wl_pointer_listener_data = WlPointerListenerData{
        .event_queue = &event_queue,
    };

    var wl_seat_listener_data = WlSeatListenerData{
        .wl_keyboard_listener_data = &wl_keyboard_listener_data,
        .wl_pointer_listener_data = &wl_pointer_listener_data,
    };
    wl_seat.setListener(*WlSeatListenerData, wlSeatListener, &wl_seat_listener_data);
    defer {
        if (wl_seat_listener_data.wl_keyboard) |wl_keyboard|
            wl_keyboard.destroy();
        if (wl_seat_listener_data.wl_pointer) |wl_pointer|
            wl_pointer.destroy();
    }

    const xdg_wm_base = wl_registry_listener_data.xdg_wm_base.?;
    defer xdg_wm_base.destroy();

    xdg_wm_base.setListener(?*void, &xdgWmBaseListener, null);

    const wl_surface = try wl_compositor.createSurface();
    defer wl_surface.destroy();

    const xdg_surface = try xdg_wm_base.getXdgSurface(wl_surface);
    defer xdg_surface.destroy();

    var xdg_surface_listener_data = XdgSurfaceListenerData{
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

    const initial_width = 800;
    const initial_height = 600;

    var xdg_toplevel_listener_data = XdgToplevelListenerData{
        .initial_width = initial_width,
        .initial_height = initial_height,
    };
    xdg_toplevel.setListener(
        *XdgToplevelListenerData,
        &xdgToplevelListener,
        &xdg_toplevel_listener_data,
    );

    const wl_frame_callback = try wl_surface.frame();

    var wl_frame_callback_listener_data = WlFrameCallbackListenerData.init;
    wl_frame_callback.setListener(
        *WlFrameCallbackListenerData,
        &wlFrameCallbackListener,
        &wl_frame_callback_listener_data,
    );

    var buffer_data = try BufferData.configure(
        initial_width,
        initial_height,
        wl_shared_memory,
    );
    defer buffer_data.deinit();

    wl_surface.commit();

    var alpha: u8 = 0;

    log.info("starting main loop", .{});

    while (true) {
        // run listeners
        if (wl_display.dispatch() != .SUCCESS) {
            log.err("wl_display.dispatch() failed", .{});
            break;
        }

        while (event_queue.poll()) |event| {
            switch (event.kind) {
                .pointer_focus => |focus| {
                    log.debug(
                        "pointer_focus: state: {s}, serial: {d}",
                        .{ @tagName(focus.state), focus.serial },
                    );
                },
                .pointer_motion => |motion| {
                    log.debug(
                        "pointer_motion: {d}x{d}",
                        .{ motion.x, motion.y },
                    );
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

        if (xdg_toplevel_listener_data.close_request) break;

        var do_draw = false;

        if (xdg_toplevel_listener_data.configure_request) |configure_request| {
            xdg_toplevel_listener_data.configure_request = null;

            try buffer_data.reconfigure(
                configure_request.width,
                configure_request.height,
                wl_shared_memory,
            );

            do_draw = true;
        }

        if (wl_frame_callback_listener_data.frame_request) {
            wl_frame_callback_listener_data.frame_request = false;

            const callback = try wl_surface.frame();
            callback.setListener(
                *WlFrameCallbackListenerData,
                wlFrameCallbackListener,
                &wl_frame_callback_listener_data,
            );

            do_draw = true;
        }

        if (do_draw) {
            const pixels_u32 = @as([*]u32, @ptrCast(@alignCast(buffer_data.pixels.ptr)))[0..(buffer_data.width * buffer_data.height)];
            @memset(pixels_u32, 0x00f4597b | (@as(u32, @intCast(alpha)) << 24));
            alpha +%= 1;

            wl_surface.attach(buffer_data.wl_buffer, 0, 0);
            wl_surface.damageBuffer(
                0,
                0,
                @intCast(buffer_data.width),
                @intCast(buffer_data.height),
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

fn xdgWmBaseListener(
    wm_base: *xdg.WmBase,
    event: xdg.WmBase.Event,
    data: ?*void,
) void {
    _ = data;

    switch (event) {
        .ping => |serial| {
            wm_base.pong(serial.serial);
        },
    }
}

// =============================================================================
// = xdg surface

const XdgSurfaceListenerData = struct {
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

    xdg_surface.ackConfigure(configure.serial);

    // not sure if this is the right thing to put here
    // my undustanding is this is a 'render' event
    // saying that the surface needs updating
    //
    // we could use this for optimiziation of not updating if not needed
    data.wl_surface.commit();
}

// =============================================================================
// = xdg toplevel

const XdgToplevelListenerData = struct {
    initial_width: u32,
    initial_height: u32,

    configure_request: ?ConfigureRequest = null,
    close_request: bool = false,
};

const ConfigureRequest = struct {
    width: u32,
    height: u32,
};

fn xdgToplevelListener(
    toplevel: *xdg.Toplevel,
    event: xdg.Toplevel.Event,
    data: *XdgToplevelListenerData,
) void {
    _ = toplevel;

    switch (event) {
        .configure => |configure| {
            const width: u32 = if (configure.width == 0)
                data.initial_width
            else
                @intCast(configure.width);

            const height: u32 = if (configure.height == 0)
                data.initial_height
            else
                @intCast(configure.height);

            data.configure_request = .{
                .width = width,
                .height = height,
            };
        },
        .close => {
            data.close_request = true;
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
    frame_request: bool,

    pub const init = WlFrameCallbackListenerData{
        .frame_request = false,
    };
};

fn wlFrameCallbackListener(
    callback: *wl.Callback,
    event: wl.Callback.Event,
    data: *WlFrameCallbackListenerData,
) void {
    _ = event;

    callback.destroy();

    data.frame_request = true;
}

// =============================================================================
// = BufferData

const BufferData = struct {
    wl_buffer: *wl.Buffer,
    pixels: []u8,
    width: u32,
    height: u32,

    pub fn configure(
        width: u32,
        height: u32,
        wl_shared_memory: *wl.Shm,
    ) !BufferData {
        const size = width * height * 4;

        const fd = try std.posix.memfd_create("fe-wl_shm", 0);
        try std.posix.ftruncate(fd, size);

        const pixels = try std.posix.mmap(
            null,
            size,
            std.posix.PROT.READ | std.posix.PROT.WRITE,
            std.posix.MAP{ .TYPE = .SHARED },
            fd,
            0,
        );

        const pool = try wl_shared_memory.createPool(fd, @intCast(size));
        defer pool.destroy();

        const wl_buffer = try pool.createBuffer(
            0,
            @intCast(width),
            @intCast(height),
            @intCast(width * 4),
            .argb8888,
        );

        return .{
            .wl_buffer = wl_buffer,
            .pixels = pixels,
            .width = width,
            .height = height,
        };
    }

    pub fn deinit(data: BufferData) void {
        data.wl_buffer.destroy();
    }

    pub fn reconfigure(
        data: *BufferData,
        width: u32,
        height: u32,
        wl_shared_memory: *wl.Shm,
    ) !void {
        if (data.width != width or data.height != height) {
            data.deinit();
            data.* = try configure(width, height, wl_shared_memory);
        }
    }
};

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
    xkb_context: *xkb.Context,
    xkb_keymap: ?*xkb.Keymap,
    xkb_state: ?*xkb.State,

    modifier_indices: XkbModifierIndices = undefined,
};

const XkbModifierIndices = struct {
    shift: u32,
    caps_lock: u32,
    ctrl: u32,
    alt: u32,
    gui: u32,
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
                .shift = xkb_keymap.modGetIndex("Shift"),
                .caps_lock = xkb_keymap.modGetIndex("Lock"),
                .ctrl = xkb_keymap.modGetIndex("Control"),
                .alt = xkb_keymap.modGetIndex("Mod1"),
                .gui = xkb_keymap.modGetIndex("Super"),
            };
        },
        .enter => |enter| {
            _ = enter;

            // gain focus for surface

            log.debug("gained keyboard focus", .{});
        },
        .leave => |leave| {
            _ = leave;

            // lose focus for surface

            log.debug("lost keyboard focus", .{});
        },
        .key => |key| {
            const pressed = key.state == .pressed;

            const xkb_state = data.xkb_state.?;
            const xkb_scancode = key.key + 8;
            const keysym = xkb_state.keyGetOneSym(xkb_scancode);
            const codepoint: u21 = @intCast(xkb_state.keyGetUtf32(xkb_scancode));

            var buffer: [4]u8 = undefined;
            const len = std.unicode.utf8Encode(codepoint, &buffer) catch
                @panic("got invalid utf8 from xkb");
            const utf8_slice = buffer[0..len];

            const utf8 = if (len == 1)
                // filter out ascii control chars
                // there may be more that we need to filter out
                if (std.ascii.isPrint(utf8_slice[0]))
                    utf8_slice
                else
                    null
            else
                utf8_slice;

            // key:
            //  state
            //  scancode
            //  keysym
            //  codepoint
            //
            // text: (on press)
            //  codepoint
            //  utf8

            log.debug(
                "pressed: {}, scancode: {d}, keysym: {}, codepoint: 0x{x}, utf8: '{?s}'",
                .{
                    pressed,
                    xkb_scancode,
                    keysym,
                    codepoint,
                    if (utf8) |s| std.fmt.fmtSliceEscapeLower(s) else null,
                },
            );
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
                data.modifier_indices.gui,
                component,
            ) == 1;

            const mod_state = ModifierState{
                .shift = shift,
                .caps_lock = caps_lock,
                .ctrl = ctrl,
                .alt = alt,
                .gui = gui,
            };

            log.debug(
                "mods: shift: {}, caps_lock: {}, ctrl: {}, alt: {}, gui: {}",
                .{
                    mod_state.shift,
                    mod_state.caps_lock,
                    mod_state.ctrl,
                    mod_state.alt,
                    mod_state.gui,
                },
            );
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
                .x = enter.surface_x.toDouble(),
                .y = enter.surface_y.toDouble(),
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
            // _ = motion.time;

            data.motion = .{
                .x = motion.surface_x.toDouble(),
                .y = motion.surface_y.toDouble(),
            };
        },
        .button => |button| button: {
            // _ = button.time;

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
                _ => unreachable,
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
            _ = axis.time;

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
            _ = axis_stop.time;

            data.scroll_axis = switch (axis_stop.axis) {
                .vertical_scroll => .vertical,
                .horizontal_scroll => .horizontal,
                else => unreachable,
            };
            data.scroll_stop = true;
        },
        .frame => {
            // we batch input until we get this event, then send it

            if (data.focus) |focus| {
                data.focus = null;
                data.event_queue.queue.queue(.{
                    .kind = .{ .pointer_focus = focus },
                });
            }

            if (data.motion) |motion| {
                data.motion = null;
                data.event_queue.queue.queue(.{
                    .kind = .{ .pointer_motion = motion },
                });
            }

            if (data.button) |button| {
                data.button = null;
                data.event_queue.queue.queue(.{
                    .kind = .{ .pointer_button = button },
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

                data.event_queue.queue.queue(.{ .kind = .{
                    .pointer_scroll = .{
                        .axis = axis,
                        .source = source,
                        .value = value,
                    },
                } });

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

pub fn CircleBufferQueue(comptime Size: usize, comptime T: type) type {
    return struct {
        buffer: [Size]T,
        head: usize,
        tail: usize,

        const Queue = @This();

        pub const init = Queue{
            .buffer = undefined,
            .head = 0,
            .tail = 0,
        };

        pub fn queue(self: *Queue, item: T) void {
            self.buffer[self.head] = item;
            self.head = (self.head + 1) % Size;
        }

        pub fn dequeue(self: *Queue) ?T {
            if (self.tail == self.head) return null;

            const item = self.buffer[self.tail];
            self.tail = (self.tail + 1) % Size;
            return item;
        }
    };
}

pub const EventQueue = struct {
    queue: CircleBufferQueue(32, Event),

    pub const init = EventQueue{ .queue = .init };

    pub fn poll(self: *EventQueue) ?Event {
        return self.queue.dequeue();
    }
};

pub const Event = struct {
    kind: Kind,

    pub const Kind = union(enum) {
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

    pub const PointerFocus = struct {
        state: FocusState,
        serial: u32,
        wl_surface: ?*wl.Surface,
    };

    pub const PointerMotion = struct {
        x: f64,
        y: f64,
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

pub const ModifierState = packed struct(u8) {
    shift: bool = false,
    caps_lock: bool = false,
    ctrl: bool = false,
    alt: bool = false,
    gui: bool = false, // super
    _padding: u3 = 0,
};
