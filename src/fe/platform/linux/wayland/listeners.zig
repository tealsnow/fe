const std = @import("std");
const mem = std.mem;
const assert = std.debug.assert;
const log = std.log.scoped(.@"wl[listeners]");

const wl = @import("wayland").client.wl;
const xdg = @import("wayland").client.xdg;
const wp = @import("wayland").client.wp;

const xkb = @import("xkbcommon");

const Size = @import("../../../math.zig").Size;

const EventQueue = @import("events.zig").EventQueue;
const Event = @import("events.zig").Event;

//= wl registry

pub const WlRegistryListenerData = struct {
    wl_compositor: ?*wl.Compositor,
    wl_shared_memory: ?*wl.Shm,
    wl_output: ?*wl.Output,
    wl_seat: ?*wl.Seat,
    xdg_wm_base: ?*xdg.WmBase,
    wp_cursor_shape_manager: ?*wp.CursorShapeManagerV1,

    pub const empty = WlRegistryListenerData{
        .wl_compositor = null,
        .wl_shared_memory = null,
        .wl_output = null,
        .wl_seat = null,
        .xdg_wm_base = null,
        .wp_cursor_shape_manager = null,
    };
};

pub fn wlRegistryListener(
    registry: *wl.Registry,
    event: wl.Registry.Event,
    data: *WlRegistryListenerData,
) void {
    const global = switch (event) {
        .global => |global| global,
        .global_remove => |remove| {
            log.warn("got registry remove event for: {d}", .{remove.name});
            return;
        },
    };

    log.debug(
        "got global interface: '{s}', version: {d}, 'name': {d}",
        .{ global.interface, global.version, global.name },
    );

    // wl_compositor
    if (mem.orderZ(
        u8,
        global.interface,
        wl.Compositor.interface.name,
    ) == .eq) {
        data.wl_compositor = registry.bind(
            global.name,
            wl.Compositor,
            5,
        ) catch @panic("could not bind wayland compositor");

        log.debug("bound interface: '{s}'", .{global.interface});
    }
    // wl_shm
    else if (mem.orderZ(
        u8,
        global.interface,
        wl.Shm.interface.name,
    ) == .eq) {
        data.wl_shared_memory = registry.bind(
            global.name,
            wl.Shm,
            2,
        ) catch @panic("could not bind wayland shared memory");

        log.debug("bound interface: '{s}'", .{global.interface});
    }
    // wl_output
    else if (mem.orderZ(
        u8,
        global.interface,
        wl.Output.interface.name,
    ) == .eq) {
        data.wl_output = registry.bind(
            global.name,
            wl.Output,
            4,
        ) catch @panic("could not bind wayland output");

        log.debug("bound interface: '{s}'", .{global.interface});
    }
    // wl_seat
    else if (mem.orderZ(
        u8,
        global.interface,
        wl.Seat.interface.name,
    ) == .eq) {
        data.wl_seat = registry.bind(
            global.name,
            wl.Seat,
            8,
        ) catch @panic("could not bind wayland seat");

        log.debug("bound interface: '{s}'", .{global.interface});
    }
    // xdg_wm_base
    else if (mem.orderZ(
        u8,
        global.interface,
        xdg.WmBase.interface.name,
    ) == .eq) {
        data.xdg_wm_base = registry.bind(
            global.name,
            xdg.WmBase,
            6,
        ) catch @panic("could not bind xdg wm_base");

        log.debug("bound interface: '{s}'", .{global.interface});
    }
    // wp_cursor_shape_manager
    else if (mem.orderZ(
        u8,
        global.interface,
        wp.CursorShapeManagerV1.interface.name,
    ) == .eq) {
        data.wp_cursor_shape_manager = registry.bind(
            global.name,
            wp.CursorShapeManagerV1,
            1,
        ) catch @panic("could not bind wp cursor_shape_manager");

        log.debug("bound interface: '{s}'", .{global.interface});
    }
}

//= wl output

pub const WlOutputListenerData = struct {
    width: i32,
    height: i32,
    physical_width_mm: i32,
    physical_height_mm: i32,

    // @TODO: scale

    pub const empty = std.mem.zeroes(WlOutputListenerData);
};

pub fn wlOutputListener(
    wl_output: *wl.Output,
    event: wl.Output.Event,
    data: *WlOutputListenerData,
) void {
    _ = wl_output;

    switch (event) {
        .geometry => |geometry| {
            log.debug(
                "wl_output geometry: x: {d}, y: {d}, " ++
                    "physical_width: {d}mm, physical_height: {d}mm, " ++
                    "subpixel: {}, make: '{s}', model: '{s}', transform: {}",
                .{
                    geometry.x,
                    geometry.y,
                    geometry.physical_width,
                    geometry.physical_height,
                    geometry.subpixel,
                    geometry.make,
                    geometry.model,
                    geometry.transform,
                },
            );

            data.physical_width_mm = geometry.physical_width;
            data.physical_height_mm = geometry.physical_height;
        },
        .mode => |mode| {
            log.debug(
                "wl_output mode: flags: {{ current: {}, preferred: {} }}, " ++
                    "width: {d}, height: {d}, refresh: {d}",
                .{
                    mode.flags.current,
                    mode.flags.preferred,
                    mode.width,
                    mode.height,
                    mode.refresh,
                },
            );

            data.width = mode.width;
            data.height = mode.height;
        },
        .done => {
            log.debug("wl_output done", .{});
        },
        .scale => |scale| {
            log.debug("wl_output scale: {d}", .{scale.factor});
        },
        .name => |name| {
            log.debug("wl_output name: '{s}'", .{name.name});
        },
        .description => |description| {
            log.debug(
                "wl_output description: '{s}'",
                .{description.description},
            );
        },
    }
}

//= xdg wm base

pub fn xdgWmBaseListener(
    xdg_wm_base: *xdg.WmBase,
    event: xdg.WmBase.Event,
    data: ?*void,
) void {
    _ = data;
    switch (event) {
        .ping => |ping| {
            xdg_wm_base.pong(ping.serial);
        },
    }
}

//= xdg surface

pub const XdgSurfaceListenerData = struct {
    event_queue: *EventQueue,

    wl_surface: *wl.Surface,
};

pub fn xdgSurfaceListener(
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

//= xdg toplevel

pub const XdgToplevelListenerData = struct {
    event_queue: *EventQueue,
};

pub fn xdgToplevelListener(
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

            // log.debug(
            //     "configure bounds: {d}x{d}",
            //     .{ configure_bounds.width, configure_bounds.height },
            // );
        },
        .wm_capabilities => {},
    }
}

// //= xdg popup

// pub const XdgPopupListenerData = struct {
//     event_queue: *EventQueue,
// };

// pub fn xdgPopupListener(
//     popup: *xdg.Popup,
//     event: xdg.Popup.Event,
//     data: *XdgPopupListenerData,
// ) void {
//     _ = popup;
//     switch (event) {
//         .configure => |configure| {
//             data.event_queue.queue(.{ .kind = .{
//                 .popup_configure = .{
//                     .position = .{
//                         .x = @intCast(configure.x),
//                         .y = @intCast(configure.y),
//                     },
//                     .size = .{
//                         .width = @intCast(configure.width),
//                         .height = @intCast(configure.height),
//                     },
//                 },
//             } });
//         },
//         .popup_done => {
//             data.event_queue.queue(.{ .kind = .{
//                 .popup_done = .{},
//             } });
//         },
//         .repositioned => |repositioned| {
//             data.event_queue.queue(.{ .kind = .{
//                 .popup_repositioned = .{ .token = repositioned.token },
//             } });
//         },
//     }
// }

//= wl frame callback

pub const WlFrameCallbackListenerData = struct {
    event_queue: *EventQueue,

    wl_surface: *wl.Surface,
};

pub fn wlFrameCallbackListener(
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

//= wl seat

pub const WlSeatListenerData = struct {
    wl_keyboard: ?*wl.Keyboard,
    wl_pointer: ?*wl.Pointer,

    pub const empty = WlSeatListenerData{
        .wl_keyboard = null,
        .wl_pointer = null,
    };
};

pub fn wlSeatListener(
    wl_seat: *wl.Seat,
    event: wl.Seat.Event,
    data: *WlSeatListenerData,
) void {
    switch (event) {
        .capabilities => |capabilities| {
            const capability = capabilities.capabilities;

            if (capability.keyboard) {
                data.wl_keyboard = wl_seat.getKeyboard() catch {
                    log.err("failed to get wl_keyboard", .{});
                    return;
                };
                log.debug("got wl keyboard", .{});
            }

            if (capability.pointer) {
                data.wl_pointer = wl_seat.getPointer() catch {
                    log.err("failed to get wl_pointer", .{});
                    return;
                };
                log.debug("got wl pointer", .{});
            }
        },
        .name => {},
    }
}

//= wl keyboard

pub const WlKeyboardListenerData = struct {
    event_queue: *EventQueue,

    xkb_context: *xkb.Context,
    xkb_keymap: ?*xkb.Keymap = null,
    xkb_state: ?*xkb.State = null,

    modifier_indices: XkbModifierIndices = undefined,
};

pub const XkbModifierIndices = struct {
    shift: u32,
    caps_lock: u32,
    ctrl: u32,
    alt: u32,
    logo: u32,
};

pub fn wlKeyboardListener(
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

//= wl pointer

pub const WlPointerListenerData = struct {
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

pub fn wlPointerListener(
    wl_pointer: *wl.Pointer,
    event: wl.Pointer.Event,
    data: *WlPointerListenerData,
) void {
    _ = wl_pointer;

    switch (event) {
        .enter => |enter| {
            // It makes more sense to put all motion interpreting in one place
            data.motion = .{
                .point = .{
                    .x = enter.surface_x.toDouble(),
                    .y = enter.surface_y.toDouble(),
                },
            };

            data.focus = .{
                .state = .enter,
                .serial = enter.serial,
                .wl_surface = enter.surface,
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
            //  (-)120 ((-)1 adjusted) for this with my mouse (my touchpad does
            //  not emit this event) thus I have opted to mulitply this value
            //  by ten. So that when it is prefferd during a frame event the
            //  value matches what axis would have emited.
            //
            //  Since the normal axis event emits 10, it seems to me that a
            //  step is 10 and that my mouse emits a descrete scroll of 1 step
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
                // ...if stop is not true
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
