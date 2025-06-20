// @TODO: I wonder if it would be beneficial to just provide the connection
//   as the listener data to all of this and simplify it that way?

const std = @import("std");
const mem = std.mem;
const assert = std.debug.assert;
const log = std.log.scoped(.@"wayland.listeners");
const Allocator = mem.Allocator;

const wl = @import("wayland").client.wl;
const xdg = @import("wayland").client.xdg;
const wp = @import("wayland").client.wp;
const zwp = @import("wayland").client.zwp;

const xkb = @import("xkbcommon");

const Size = @import("cu").math.Size;

const Connection = @import("Connection.zig");
const OutputId = Connection.OutputId;

const events = @import("events.zig");
const EventQueue = events.EventQueue;
const Event = events.Event;

const Window = @import("Window.zig");
const WindowId = Window.WindowId;

//= wl registry

pub const WlRegistryListenerData = struct {
    gpa: Allocator,
    event_queue: *EventQueue,

    wl_compositor: ?*wl.Compositor = null,
    wl_shared_memory: ?*wl.Shm = null,
    wl_seat: ?*wl.Seat = null,
    xdg_wm_base: ?*xdg.WmBase = null,
    wp_cursor_shape_manager: ?*wp.CursorShapeManagerV1 = null,
    zwp_pointer_gestures: ?*zwp.PointerGesturesV1 = null,

    outputs: std.AutoArrayHashMapUnmanaged(OutputId, OutputHandle) = .empty,
};

pub fn wlRegistryListener(
    registry: *wl.Registry,
    event: wl.Registry.Event,
    data: *WlRegistryListenerData,
) void {
    const global = switch (event) {
        .global => |global| global,
        .global_remove => |remove| {
            log.debug("got registry remove event for: {d}", .{remove.name});

            var removed = false;

            const maybe_output_id: ?OutputId =
                for (data.outputs.keys()) |key| {
                    if (key.name == remove.name)
                        break key;
                } else null;

            if (maybe_output_id) |id| {
                const output = data.outputs.fetchSwapRemove(id).?.value;
                output.deinit(data.gpa);

                data.event_queue.queue(.{ .kind = .{
                    .output_unavailable = id,
                } });

                removed = true;
            }

            if (removed)
                log.debug("global removed: {d}", .{remove.name})
            else
                log.debug("ignored global remove: {d}", .{remove.name});

            return;
        },
    };

    log.debug(
        "got global interface: '{s}', version: {d}, 'name': {d}",
        .{ global.interface, global.version, global.name },
    );

    var bound = false;

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

        bound = true;
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

        bound = true;
    }
    // wl_output
    else if (mem.orderZ(
        u8,
        global.interface,
        wl.Output.interface.name,
    ) == .eq) {
        const wl_output = registry.bind(
            global.name,
            wl.Output,
            4,
        ) catch @panic("could not bind wayland output");

        const id = OutputId{
            .name = global.name,
            .id = wl_output.getId(),
        };

        const info = OutputHandle.init(
            data.gpa,
            wl_output,
            id,
            data.event_queue,
        ) catch @panic("oom");

        data.outputs.put(data.gpa, id, info) catch
            @panic("oom");

        bound = true;
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

        bound = true;
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

        bound = true;
    }
    // wp_cursor_shape_manager_v1
    else if (mem.orderZ(
        u8,
        global.interface,
        wp.CursorShapeManagerV1.interface.name,
    ) == .eq) {
        data.wp_cursor_shape_manager = registry.bind(
            global.name,
            wp.CursorShapeManagerV1,
            1,
        ) catch @panic("could not bind wp cursor_shape_manager_v1");

        bound = true;
    }
    // zwp_pointer_gestures_v1
    else if (mem.orderZ(
        u8,
        global.interface,
        zwp.PointerGesturesV1.interface.name,
    ) == .eq) {
        data.zwp_pointer_gestures = registry.bind(
            global.name,
            zwp.PointerGesturesV1,
            3,
        ) catch @panic("could not bind zwp pointer_gestures_v1");

        bound = true;
    }

    if (bound)
        log.debug("bound global interface: '{s}'", .{global.interface});
}

//= wl output

pub const OutputHandle = struct {
    wl_output: *wl.Output,
    listener_data: *WlOutputListenerData,

    pub fn init(
        gpa: Allocator,
        wl_output: *wl.Output,
        id: OutputId,
        event_queue: *EventQueue,
    ) !OutputHandle {
        const listener_data = try gpa.create(WlOutputListenerData);
        listener_data.* = .{
            .gpa = gpa,
            .event_queue = event_queue,
            .id = id,
        };

        wl_output.setListener(
            *WlOutputListenerData,
            wlOutputListener,
            listener_data,
        );

        return .{
            .wl_output = wl_output,
            .listener_data = listener_data,
        };
    }

    pub fn deinit(self: OutputHandle, gpa: Allocator) void {
        self.wl_output.destroy();
        self.listener_data.deinit();
        gpa.destroy(self.listener_data);
    }
};

pub const WlOutputListenerData = struct {
    gpa: Allocator,
    event_queue: *EventQueue,
    id: OutputId,

    dirty: bool = true,
    info: Connection.OutputInfo = .{
        .name = null,
        .description = null,
        .geometry = null,
        .modes = &.{},
        .current_mode_idx = null,
        .preferred_mode_idx = null,
        .scale = null,
    },

    modes: std.ArrayListUnmanaged(Connection.OutputInfo.Mode) = .empty,

    pub fn deinit(self: *WlOutputListenerData) void {
        const gpa = self.gpa;

        if (self.info.name) |name| gpa.free(name);
        if (self.info.description) |desc| gpa.free(desc);

        if (self.info.geometry) |geom| {
            gpa.free(geom.make);
            gpa.free(geom.model);
        }

        gpa.free(self.info.modes);
        self.modes.deinit(gpa);
    }
};

pub fn wlOutputListener(
    wl_output: *wl.Output,
    event: wl.Output.Event,
    data: *WlOutputListenerData,
) void {
    _ = wl_output;

    switch (event) {
        .name => |name| {
            log.debug("wl_output name: '{s}'", .{name.name});

            if (data.info.name) |str| data.gpa.free(str);

            const slice = std.mem.sliceTo(name.name, 0);
            data.info.name = data.gpa.dupeZ(u8, slice) catch @panic("oom");

            data.dirty = true;
        },
        .description => |description| {
            log.debug(
                "wl_output description: '{s}'",
                .{description.description},
            );

            if (data.info.description) |str| data.gpa.free(str);

            const slice = std.mem.sliceTo(description.description, 0);
            data.info.description =
                data.gpa.dupeZ(u8, slice) catch @panic("oom");

            data.dirty = true;
        },
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

            if (data.info.geometry) |geom| {
                data.gpa.free(geom.make);
                data.gpa.free(geom.model);
            }
            const make =
                data.gpa.dupeZ(u8, std.mem.sliceTo(geometry.make, 0)) catch
                    @panic("oom");
            const model =
                data.gpa.dupeZ(u8, std.mem.sliceTo(geometry.model, 0)) catch
                    @panic("oom");

            data.info.geometry = .{
                .x = geometry.x,
                .y = geometry.y,
                .physical_width_mm = geometry.physical_width,
                .physical_height_mm = geometry.physical_height,
                .subpixel = geometry.subpixel,
                .make = make,
                .model = model,
                .transform = geometry.transform,
            };

            data.dirty = true;
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

            const idx = data.modes.items.len;
            data.modes.append(data.gpa, .{
                .width = mode.width,
                .height = mode.height,
                .refresh = mode.refresh,
            }) catch @panic("oom");
            if (mode.flags.current)
                data.info.current_mode_idx = idx;
            if (mode.flags.preferred)
                data.info.preferred_mode_idx = idx;

            data.dirty = true;
        },
        .scale => |scale| {
            log.debug("wl_output scale: {d}", .{scale.factor});

            data.info.scale = scale.factor;

            data.dirty = true;
        },
        .done => {
            log.debug("wl_output done", .{});

            if (data.dirty) {
                data.gpa.free(data.info.modes);
                data.info.modes = data.modes.toOwnedSlice(data.gpa) catch
                    @panic("oom");

                data.event_queue.queue(.{ .kind = .{
                    .output_available = data.id,
                } });

                data.dirty = false;
            }
        },
    }
}

//= wl surface

pub const WlSurfaceListener = struct {
    conn: *Connection,
    window_id: WindowId,

    pub fn setup(self: *WlSurfaceListener, wl_surface: *wl.Surface) void {
        wl_surface.setListener(*WlSurfaceListener, listener, self);
    }

    pub fn listener(
        wl_surface: *wl.Surface,
        event: wl.Surface.Event,
        self: *WlSurfaceListener,
    ) void {
        _ = wl_surface;

        const output, const focus_state: Event.FocusState = ev: switch (event) {
            .enter => |enter| {
                const output = enter.output orelse return;
                break :ev .{ output, .enter };
            },
            .leave => |leave| {
                const output = leave.output orelse return;
                break :ev .{ output, .leave };
            },
        };

        const output_id = output.getId();
        const id =
            for (self.conn.wl_registry_listener_data.outputs.keys()) |key| {
                if (key.id == output_id) break key;
            } else return;

        self.conn.event_queue.queue(.{ .kind = .{ .toplevel_output_change = .{
            .window_id = self.window_id,
            .output_id = id,
            .focus = focus_state,
        } } });
    }
};

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
    window_id: WindowId,
};

pub fn xdgSurfaceListener(
    xdg_surface: *xdg.Surface,
    event: xdg.Surface.Event,
    data: *XdgSurfaceListenerData,
) void {
    _ = xdg_surface;

    const configure = switch (event) {
        .configure => |configure| configure,
    };

    data.event_queue.queue(.{ .kind = .{ .surface_configure = .{
        .serial = configure.serial,
        .window_id = data.window_id,
    } } });
}

//= xdg toplevel

pub const XdgToplevelListenerData = struct {
    event_queue: *EventQueue,
    window_id: WindowId,
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

            data.event_queue.queue(.{ .kind = .{ .toplevel_configure = .{
                .window_id = data.window_id,
                .size = size,
                .state = state,
            } } });
        },
        .close => {
            data.event_queue.queue(.{ .kind = .{ .toplevel_close = .{
                .window_id = data.window_id,
            } } });
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
    window: *Window,
};

pub fn wlFrameCallbackListener(
    callback: *wl.Callback,
    event: wl.Callback.Event,
    data: *const WlFrameCallbackListenerData,
) void {
    assert(event == .done);

    data.event_queue.queue(.{ .kind = .{ .frame = .{
        .window_id = data.window.id,
    } } });

    callback.destroy();
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
    surface_to_window_map: *const std.AutoArrayHashMapUnmanaged(
        *wl.Surface,
        *Window,
    ),

    xkb_context: *xkb.Context,
    xkb_keymap: ?*xkb.Keymap = null,
    xkb_state: ?*xkb.State = null,

    modifier_indices: XkbModifierIndices = undefined,

    focused_window: ?*Window = null,
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
            const surface = enter.surface orelse
                @panic("no surface for enter event");
            const window =
                data.surface_to_window_map.get(surface) orelse
                @panic("surface has no window");

            data.focused_window = window;

            data.event_queue.queue(.{ .kind = .{ .keyboard_focus = .{
                .serial = enter.serial,
                .window_id = window.id,
                .state = .enter,
            } } });

            const keys = enter.keys.slice(u32);
            for (keys) |key| {
                const xkb_state = data.xkb_state.?;
                const scancode = key + 8;
                const keysym = xkb_state.keyGetOneSym(scancode);
                const codepoint: u21 = @intCast(xkb_state.keyGetUtf32(scancode));

                data.event_queue.queue(.{ .kind = .{ .key = .{
                    .serial = enter.serial,
                    .state = .pressed,
                    .scancode = scancode,
                    .keysym = keysym,
                    .codepoint = codepoint,
                } } });
            }
        },
        .leave => |leave| {
            const focused_window = data.focused_window orelse
                @panic("leave event when no surface focused");
            data.focused_window = null;

            // window might have been closed, thus no surface present
            if (leave.surface) |surface| {
                assert(focused_window.wl_surface == surface);
            }

            data.event_queue.queue(.{ .kind = .{ .keyboard_focus = .{
                .serial = leave.serial,
                .window_id = focused_window.id,
                .state = .leave,
            } } });
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
                .kind = .{ .key = .{
                    .serial = key.serial,
                    .state = state,
                    .scancode = scancode,
                    .keysym = keysym,
                    .codepoint = codepoint,
                } },
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
                        .kind = .{ .text = .{
                            .codepoint = codepoint,
                            .utf8 = text,
                        } },
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
                    .serial = modifiers.serial,
                    .state = mod_state,
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
    surface_to_window_map: *const std.AutoArrayHashMapUnmanaged(
        *wl.Surface,
        *Window,
    ),

    time: ?u32 = null,
    focus: ?Event.PointerFocus = null,
    motion: ?Event.PointerMotion = null,
    button: ?Event.PointerButton = null,

    scroll_axis: ?Event.PointerScrollAxis = null,
    scroll_source: ?Event.PointerScrollSource = null,
    scroll_value: ?f64 = null,
    scroll_value120: ?f64 = null,
    scroll_stop: bool = false,

    focused_window: ?*Window = null,
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

            const surface = enter.surface orelse
                @panic("no surface for enter event");
            const window = data.surface_to_window_map.get(surface) orelse
                @panic("surface has no window");

            data.focused_window = window;

            data.focus = .{
                .serial = enter.serial,
                .window_id = window.id,
                .state = .enter,
            };
        },
        .leave => |leave| {
            const focused_window = data.focused_window orelse
                @panic("leave event when no surface focused");
            data.focused_window = null;

            // window might have been closed, thus no surface given
            if (leave.surface) |surface| {
                assert(focused_window.wl_surface == surface);
            }

            data.focus = .{
                .serial = leave.serial,
                .window_id = focused_window.id,
                .state = .leave,
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
            // thus scroll by a quarter of a logical step
            //
            // replaces axis_discrete from version 8 of wl_pointer

            data.scroll_axis = switch (axis_value120.axis) {
                .vertical_scroll => .vertical,
                .horizontal_scroll => .horizontal,
                else => unreachable,
            };

            // @NOTE:
            //  on my machine running gnome 47 I get (-)10 for axis events and
            //  (-)120 ((-)1 adjusted) for this with my mouse (my touchpad does
            //  not emit this event) thus I have opted to multiply this value
            //  by ten. So that when it is proffered during a frame event the
            //  value matches what axis would have emitted.
            //
            //  Since the normal axis event emits 10, it seems to me that a
            //  step is 10 and that my mouse emits a discrete scroll of 1 step
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

pub const WlPointerGesturesListenerData = struct {
    event_queue: *EventQueue,
};

pub fn wlPointerGesturesSwipeListener(
    wl_pointer_gesture_swipe: *zwp.PointerGestureSwipeV1,
    event: zwp.PointerGestureSwipeV1.Event,
    data: *WlPointerGesturesListenerData,
) void {
    _ = wl_pointer_gesture_swipe;

    switch (event) {
        .begin => |begin| {
            data.event_queue.queue(.{
                .kind = .{ .pointer_gesture_swipe = .{ .begin = .{
                    .serial = begin.serial,
                    .surface = begin.surface,
                    .fingers = begin.fingers,
                } } },
                .time = begin.time,
            });
        },
        .update => |update| {
            data.event_queue.queue(.{
                .kind = .{ .pointer_gesture_swipe = .{ .update = .{
                    .dx = update.dx.toDouble(),
                    .dy = update.dy.toDouble(),
                } } },
                .time = update.time,
            });
        },
        .end => |end| {
            data.event_queue.queue(.{
                .kind = .{ .pointer_gesture_swipe = .{ .end = .{
                    .serial = end.serial,
                    .cancelled = if (end.cancelled == 0) false else true,
                } } },
                .time = end.time,
            });
        },
    }
}

pub fn wlPointerGesturesPinchListener(
    wl_pointer_gesture_pinch: *zwp.PointerGesturePinchV1,
    event: zwp.PointerGesturePinchV1.Event,
    data: *WlPointerGesturesListenerData,
) void {
    _ = wl_pointer_gesture_pinch;

    switch (event) {
        .begin => |begin| {
            data.event_queue.queue(.{
                .kind = .{ .pointer_gesture_pinch = .{ .begin = .{
                    .serial = begin.serial,
                    .surface = begin.surface,
                    .fingers = begin.fingers,
                } } },
                .time = begin.time,
            });
        },
        .update => |update| {
            data.event_queue.queue(.{
                .kind = .{ .pointer_gesture_pinch = .{ .update = .{
                    .dx = update.dx.toDouble(),
                    .dy = update.dy.toDouble(),
                    .scale = update.scale.toDouble(),
                    .rotation = update.rotation.toDouble(),
                } } },
                .time = update.time,
            });
        },
        .end => |end| {
            data.event_queue.queue(.{
                .kind = .{ .pointer_gesture_pinch = .{ .end = .{
                    .serial = end.serial,
                    .cancelled = if (end.cancelled == 0) false else true,
                } } },
                .time = end.time,
            });
        },
    }
}

pub fn wlPointerGesturesHoldListener(
    wl_pointer_gesture_hold: *zwp.PointerGestureHoldV1,
    event: zwp.PointerGestureHoldV1.Event,
    data: *WlPointerGesturesListenerData,
) void {
    _ = wl_pointer_gesture_hold;

    switch (event) {
        .begin => |begin| {
            data.event_queue.queue(.{
                .kind = .{ .pointer_gesture_hold = .{ .begin = .{
                    .serial = begin.serial,
                    .surface = begin.surface,
                    .fingers = begin.fingers,
                } } },
                .time = begin.time,
            });
        },
        .end => |end| {
            data.event_queue.queue(.{
                .kind = .{ .pointer_gesture_hold = .{ .end = .{
                    .serial = end.serial,
                    .cancelled = if (end.cancelled == 0) false else true,
                } } },
                .time = end.time,
            });
        },
    }
}
