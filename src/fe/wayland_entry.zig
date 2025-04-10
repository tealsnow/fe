const std = @import("std");
const assert = std.debug.assert;
const mem = std.mem;
const Allocator = mem.Allocator;

const log = std.log.scoped(.@"fe[wl]");

const wayland = @import("wayland2");
const wl = wayland.client.wl;
const xdg = wayland.client.xdg;

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

    var wl_seat_listener_data = WlSeatListenerData.init;
    wl_seat.setListener(*WlSeatListenerData, wlSeatListener, &wl_seat_listener_data);
    defer if (wl_seat_listener_data.wl_keyboard) |wl_keyboard| {
        wl_keyboard.destroy();
    };

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
        ) catch @panic("could not get wayland compositor");
    } else if (mem.orderZ(
        u8,
        global.interface,
        wl.Shm.interface.name,
    ) == .eq) {
        data.wl_shared_memory = registry.bind(
            global.name,
            wl.Shm,
            2,
        ) catch @panic("could not get wayland shared memory");
    } else if (mem.orderZ(
        u8,
        global.interface,
        wl.Seat.interface.name,
    ) == .eq) {
        data.wl_seat = registry.bind(
            global.name,
            wl.Seat,
            8,
        ) catch @panic("could not get wayland seat");
    } else if (mem.orderZ(
        u8,
        global.interface,
        xdg.WmBase.interface.name,
    ) == .eq) {
        data.xdg_wm_base = registry.bind(
            global.name,
            xdg.WmBase,
            6,
        ) catch @panic("could not get xdg wm_base");
    }
}

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

        const fd = try std.posix.memfd_create("fe-shared-memory", 0);
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

const WlSeatListenerData = struct {
    wl_keyboard: ?*wl.Keyboard,

    pub const init = WlSeatListenerData{ .wl_keyboard = null };
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
                const wl_keyboard = wl_seat.getKeyboard() catch unreachable;
                data.wl_keyboard = wl_keyboard;

                wl_keyboard.setListener(?*void, &wlKeyboardListener, null);
            }
        },
        .name => {},
    }
}

fn wlKeyboardListener(
    wl_keyboard: *wl.Keyboard,
    event: wl.Keyboard.Event,
    data: ?*void,
) void {
    _ = wl_keyboard;
    _ = data;

    switch (event) {
        .key => |key| {
            log.debug("scancode: {d}", .{key.key});
        },
        else => {},
    }
}
