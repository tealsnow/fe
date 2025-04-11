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

    var wl_pointer_listener_data = WlPointerListenerData{};

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
        if (wl_display.dispatch() != .SUCCESS) break;

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
        .configure_bounds => {},
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

            const xkb_scancode = key.key + 8;
            const xkb_state = data.xkb_state.?;
            const keysym = xkb_state.keyGetOneSym(xkb_scancode);

            var utf8: [127:0]u8 = @splat(0);
            const uft8_len = xkb_state.keyGetUtf8(xkb_scancode, &utf8);

            if (uft8_len > utf8.len) {
                log.warn("got more than 127 bytes of utf8 for single press", .{});
            }

            log.debug(
                "pressed: {}, scancode: {d}, keysym: {}, utf8: '{s}'",
                .{ pressed, xkb_scancode, keysym, utf8 },
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
            // @TODO: Implement repeat

            log.debug(
                "got repeat info: rate: {d}, delay: {d}",
                .{ repeat_info.rate, repeat_info.delay },
            );
        },
    }
}

// =============================================================================
// = ModifierState

pub const ModifierState = packed struct(u8) {
    shift: bool = false,
    caps_lock: bool = false,
    ctrl: bool = false,
    alt: bool = false,
    gui: bool = false, // super
    _padding: u3 = 0,
};

// =============================================================================
// = wl pointer

const WlPointerListenerData = struct {};

// https://github.com/torvalds/linux/blob/e618ee89561b6b0fdc69f79e6fd0c33375d3e6b4/include/uapi/linux/input-event-codes.h#L355
pub const RawLinuxButtons = struct {
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
    _ = data;

    switch (event) {
        .enter => |enter| {
            _ = enter;
            log.debug("pointer entered surface", .{});
        },
        .leave => |leave| {
            _ = leave;
            log.debug("pointer left surface", .{});
        },
        .motion => |motion| {
            log.debug(
                "pointer motion: {d}x{d}",
                .{ motion.surface_x.toDouble(), motion.surface_y.toDouble() },
            );
        },
        .button => |button| button: {
            const mbutton: MouseButton = switch (button.button) {
                RawLinuxButtons.left => .left,
                RawLinuxButtons.right => .right,
                RawLinuxButtons.middle => .middle,
                RawLinuxButtons.forward => .forward,
                RawLinuxButtons.back => .back,
                else => break :button,
            };

            const pressed = button.state == .pressed;

            log.debug(
                "pointer button: pressed: {}, button: {s}",
                .{ pressed, @tagName(mbutton) },
            );
        },
        .axis => |axis| {
            log.debug(
                "pointer axis: axis: {s}, value: {}",
                .{ @tagName(axis.axis), axis.value.toDouble() },
            );
        },
        .frame => {
            // batch input until we get this event, then process

            // log.debug("pointer frame", .{});
            std.debug.print("\n", .{});
        },
        .axis_source => |axis_source| {
            log.debug(
                "pointer axis source: source: {s}",
                .{@tagName(axis_source.axis_source)},
            );
        },
        .axis_stop => |axis_stop| {
            log.debug(
                "pointer axis stop: axis: {s}",
                .{@tagName(axis_stop.axis)},
            );
        },
        .axis_discrete => |axis_discrete| {
            log.debug(
                "pointer axis descrete: axis: {s}, discrete: {d}",
                .{ @tagName(axis_discrete.axis), axis_discrete.discrete },
            );
        },
        .axis_value120 => |axis_value120| {
            log.debug(
                "pointer axis value120: axis: {s}, value120: {d}",
                .{ @tagName(axis_value120.axis), axis_value120.value120 },
            );
        },
    }
}

// =============================================================================
// = MouseButton

pub const MouseButton = enum {
    left,
    right,
    middle,
    forward,
    back,
};
