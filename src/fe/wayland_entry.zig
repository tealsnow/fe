const std = @import("std");
const assert = std.debug.assert;
const mem = std.mem;
const Allocator = mem.Allocator;

const log = std.log.scoped(.@"fe[wl]");

const wl = @import("wayland.zig");

pub fn entry(gpa: Allocator) !void {
    run(gpa) catch |err| {
        switch (err) {
            error.wl => {
                log.err("got wayland error", .{});
            },
            else => {},
        }
        return err;
    };

    std.process.cleanExit();
}

pub fn run(gpa: Allocator) !void {
    _ = gpa;

    // -------------------------------------------------------------------------
    // - connect to wl display
    log.debug("connecting to wl display", .{});

    const wl_display = wl.wl_display_connect(null) orelse return error.wl;
    defer wl.wl_display_disconnect(wl_display);

    // -------------------------------------------------------------------------
    // - get wl registry
    log.debug("getting wl registry", .{});

    const wl_registry =
        wl.wl_display_get_registry(wl_display) orelse return error.wl;
    defer wl.wl_registry_destroy(wl_registry);

    // -------------------------------------------------------------------------
    // - add wl registry listner
    log.debug("adding wl registry listener", .{});

    var globals = WlGlobals.none;
    if (wl.wl_registry_add_listener(
        wl_registry,
        &wl_registry_listener,
        &globals,
    ) != 0) return error.wl;

    // -------------------------------------------------------------------------
    // - inform display manager that we are ready to get globals
    {
        log.debug("getting globals", .{});

        const num_events = wl.wl_display_roundtrip(wl_display);
        if (num_events == -1) return error.wl;
        log.debug("number events recieved: {d}", .{num_events});
    }

    // -------------------------------------------------------------------------
    // - check globals
    {
        log.debug("checking globals", .{});

        const globals_filled = globals.filled();
        assert(globals_filled);
        log.debug("all globals filled", .{});
    }

    const wl_compositor = globals.wl_compositor.?;
    defer wl.wl_compositor_destroy(wl_compositor);

    const wl_shared_memory = globals.wl_shared_memory.?;
    defer {
        wl.wl_shm_release(wl_shared_memory);
        // wl.wl_shm_destroy(wl_shared_memory); // @FIXME: wl assertion failure
    }

    const xdg_wm_base = globals.xdg_wm_base.?;
    defer wl.xdg_wm_base_destroy(xdg_wm_base);

    const wl_seat = globals.wl_seat.?;
    defer wl.wl_seat_destroy(wl_seat);

    // -------------------------------------------------------------------------
    // - add xdg wm base listener
    log.debug("adding xdg wm base listener", .{});

    if (wl.xdg_wm_base_add_listener(
        xdg_wm_base,
        &xdg_wm_base_listener,
        null,
    ) != 0) return error.wl;

    // -------------------------------------------------------------------------
    // - add wl seat listener
    log.debug("adding wl seat listener", .{});

    var wl_seat_listener_data = WlSeatListenerData.none;
    defer wl.wl_keyboard_destroy(wl_seat_listener_data.wl_keyboard);

    if (wl.wl_seat_add_listener(
        wl_seat,
        &wl_seat_listener,
        &wl_seat_listener_data,
    ) != 0) return error.wl;

    // -------------------------------------------------------------------------
    // - create wl surface
    log.debug("creating wl surface", .{});

    const wl_surface =
        wl.wl_compositor_create_surface(wl_compositor) orelse return error.wl;
    defer wl.wl_surface_destroy(wl_surface);

    // -------------------------------------------------------------------------
    // - get xdg surface
    log.debug("getting xdg surface", .{});

    const xdg_surface = wl.xdg_wm_base_get_xdg_surface(
        xdg_wm_base,
        wl_surface,
    ) orelse return error.wl;

    // -------------------------------------------------------------------------
    // - get xdg toplevel
    log.debug("getting xdg toplevel", .{});

    const xdg_toplevel =
        wl.xdg_surface_get_toplevel(xdg_surface) orelse return error.wl;

    wl.xdg_toplevel_set_title(xdg_toplevel, "fe! wayland!");

    // -------------------------------------------------------------------------
    // - add xdg toplevel listener
    log.debug("adding xdg toplevel listener", .{});

    var xdg_toplevel_listener_data = XdgToplevelListenerData{
        .initial_width = 800,
        .initial_height = 600,

        .configure_request = null,
        .close_request = false,
    };

    if (wl.xdg_toplevel_add_listener(
        xdg_toplevel,
        &xdg_toplevel_listener,
        &xdg_toplevel_listener_data,
    ) != 0) return error.wl;

    // -------------------------------------------------------------------------
    // - add xdg surface listener
    log.debug("adding xdg surface listener", .{});

    var xdg_surface_configure_data = XdgSurfaceListenerData{
        .configure_request = false,
    };
    if (wl.xdg_surface_add_listener(
        xdg_surface,
        &xdg_surface_listener,
        &xdg_surface_configure_data,
    ) != 0) return error.wl;

    // -------------------------------------------------------------------------
    // - add surface frame callback
    log.debug("adding surface frame callback", .{});

    var frame_callback_listener = wl.wl_callback_listener{
        .done = frameCallback,
    };
    var frame_callback_listener_data = FrameCallbackListenerData{
        .frame_request = false,
    };
    const wl_frame_callback =
        wl.wl_surface_frame(wl_surface) orelse return error.wl;
    if (wl.wl_callback_add_listener(
        wl_frame_callback,
        &frame_callback_listener,
        &frame_callback_listener_data,
    ) != 0) return error.wl;

    // -------------------------------------------------------------------------
    // - commit surface
    log.debug("commiting surface", .{});

    wl.wl_surface_commit(wl_surface);

    // -------------------------------------------------------------------------
    // - main loop

    var maybe_buffer_data: ?BufferData = null;
    defer if (maybe_buffer_data) |buffer_data| {
        buffer_data.deinit();
    };

    log.debug("starting main loop", .{});

    while (wl.wl_display_dispatch(wl_display) != 0) {
        var do_draw = false;

        //-
        if (xdg_toplevel_listener_data.close_request) {
            defer xdg_toplevel_listener_data.close_request = false;

            log.debug("close request", .{});
            break;
        }

        //-
        if (xdg_toplevel_listener_data.configure_request) |configure_request| {
            defer xdg_toplevel_listener_data.configure_request = null;

            if (maybe_buffer_data) |*buffer_data| {
                if (buffer_data.width != configure_request.width or
                    buffer_data.height != configure_request.height)
                {
                    try buffer_data.reconfigure(
                        configure_request.width,
                        configure_request.height,
                        wl_shared_memory,
                    );
                }
            } else {
                maybe_buffer_data = try BufferData.configure(
                    configure_request.width,
                    configure_request.height,
                    wl_shared_memory,
                );
            }

            do_draw = true;
        }

        //-
        if (xdg_surface_configure_data.configure_request) {
            xdg_surface_configure_data.configure_request = false;

            do_draw = true;
        }

        //-
        if (frame_callback_listener_data.frame_request) {
            defer frame_callback_listener_data.frame_request = false;

            const callback = wl.wl_surface_frame(wl_surface) orelse
                @panic("could not create frame callback within callback");
            if (wl.wl_callback_add_listener(
                callback,
                &frame_callback_listener,
                &frame_callback_listener_data,
            ) != 0)
                @panic("could not add callback listener");

            do_draw = true;
        }

        //-
        if (do_draw) {
            const buffer_data = maybe_buffer_data.?;

            draw(&buffer_data, wl_surface);
        }
    }
}

// =============================================================================
// = wl registry listener

const WlGlobals = struct {
    wl_compositor: ?*wl.wl_compositor,
    wl_shared_memory: ?*wl.wl_shm,
    xdg_wm_base: ?*wl.xdg_wm_base,
    wl_seat: ?*wl.wl_seat,

    pub const none = WlGlobals{
        .wl_compositor = null,
        .wl_shared_memory = null,
        .xdg_wm_base = null,
        .wl_seat = null,
    };

    pub fn filled(globals: *const WlGlobals) bool {
        return globals.wl_compositor != null and
            globals.wl_shared_memory != null and
            globals.xdg_wm_base != null and
            globals.wl_seat != null;
    }
};

const wl_registry_listener = wl.wl_registry_listener{
    .global = &wlRegistryGlobal,
    .global_remove = &wlRegistryGlobalRemove,
};

fn wlRegistryGlobal(
    data: ?*anyopaque,
    wl_registry: ?*wl.wl_registry,
    name: u32,
    interface: ?[*:0]const u8,
    version: u32,
) callconv(.c) void {
    const globals: *WlGlobals = @ptrCast(@alignCast(data.?));

    log.debug(
        "- global - name: {d}, interface: '{?s}', version: {d}",
        .{ name, interface, version },
    );

    const interface_slice: [:0]const u8 = mem.span(interface.?);

    if (mem.eql(
        u8,
        interface_slice,
        mem.span(wl.wl_compositor_interface.name),
    )) {
        log.debug("got wl_compositor", .{});
        globals.wl_compositor = @ptrCast(wl.wl_registry_bind(
            wl_registry,
            name,
            &wl.wl_compositor_interface,
            6,
        ));
    } else if (mem.eql(
        u8,
        interface_slice,
        mem.span(wl.wl_shm_interface.name),
    )) {
        log.debug("got wl_shared_memory", .{});
        globals.wl_shared_memory = @ptrCast(wl.wl_registry_bind(
            wl_registry,
            name,
            &wl.wl_shm_interface,
            2,
        ));
    } else if (mem.eql(
        u8,
        interface_slice,
        mem.span(wl.xdg_wm_base_interface.name),
    )) {
        log.debug("got xdg_wm_base", .{});
        globals.xdg_wm_base = @ptrCast(wl.wl_registry_bind(
            wl_registry,
            name,
            &wl.xdg_wm_base_interface,
            6,
        ));
    } else if (mem.eql(
        u8,
        interface_slice,
        mem.span(wl.wl_seat_interface.name),
    )) {
        log.debug("got wl_seat", .{});
        globals.wl_seat = @ptrCast(wl.wl_registry_bind(
            wl_registry,
            name,
            &wl.wl_seat_interface,
            8,
        ));
    }
}

fn wlRegistryGlobalRemove(
    data: ?*anyopaque,
    wl_registry: ?*wl.wl_registry,
    name: u32,
) callconv(.c) void {
    _ = data;
    _ = wl_registry;

    log.debug("- global remove - name: {d}", .{name});
}

// =============================================================================
// = xdg wm base listener

const xdg_wm_base_listener = wl.xdg_wm_base_listener{
    .ping = &xdgWmBasePing,
};

fn xdgWmBasePing(
    data: ?*anyopaque,
    xdg_wm_base: ?*wl.xdg_wm_base,
    serial: u32,
) callconv(.c) void {
    _ = data;

    wl.xdg_wm_base_pong(xdg_wm_base, serial);
}

// =============================================================================
// = BufferData

const BufferData = struct {
    wl_buffer: *wl.wl_buffer,
    pixels: []u8,
    width: u32,
    height: u32,

    pub fn configure(
        width: u32,
        height: u32,
        wl_shared_memory: *wl.wl_shm,
    ) !BufferData {
        const size = width * height * 4;

        // @FIXME: use random characters for name
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

        const pool = wl.wl_shm_create_pool(
            wl_shared_memory,
            fd,
            @intCast(size),
        ) orelse return error.wl;
        defer wl.wl_shm_pool_destroy(pool);

        const wl_buffer = wl.wl_shm_pool_create_buffer(
            pool,
            0,
            @intCast(width),
            @intCast(height),
            @intCast(width * 4),
            wl.WL_SHM_FORMAT_ARGB8888,
        ) orelse return error.wl;

        return .{
            .wl_buffer = wl_buffer,
            .pixels = pixels,
            .width = width,
            .height = height,
        };
    }

    pub fn deinit(data: BufferData) void {
        wl.wl_buffer_destroy(data.wl_buffer);
    }

    pub fn reconfigure(
        data: *BufferData,
        width: u32,
        height: u32,
        wl_shared_memory: *wl.wl_shm,
    ) !void {
        data.deinit();
        data.* = try configure(width, height, wl_shared_memory);
    }
};

// =============================================================================
// = xdg toplevel listener

const xdg_toplevel_listener = wl.xdg_toplevel_listener{
    .configure = &xdgToplevelConfigure,
    .close = &xdgToplevelClose,
    .configure_bounds = &xdgToplevelConfigureBounds,
    .wm_capabilities = &xdgToplevelWmCapabilities,
};

const XdgToplevelListenerData = struct {
    initial_width: u32,
    initial_height: u32,

    configure_request: ?ConfigureRequest,
    close_request: bool,
};

const ConfigureRequest = struct {
    width: u32,
    height: u32,
};

fn xdgToplevelConfigure(
    data_ptr: ?*anyopaque,
    xdg_toplevel: ?*wl.xdg_toplevel,
    asking_width: i32,
    asking_height: i32,
    states: ?*wl.wl_array,
) callconv(.c) void {
    _ = xdg_toplevel;
    _ = states;

    const data: *XdgToplevelListenerData = @ptrCast(@alignCast(data_ptr.?));

    const width: u32 = if (asking_width == 0) data.initial_width else @intCast(asking_width);
    const height: u32 = if (asking_height == 0) data.initial_height else @intCast(asking_height);

    data.configure_request = .{ .width = width, .height = height };
}

fn xdgToplevelClose(
    data_ptr: ?*anyopaque,
    xdg_toplevel: ?*wl.xdg_toplevel,
) callconv(.c) void {
    _ = xdg_toplevel;

    log.debug("xdg_toplevel.close", .{});

    const data: *XdgToplevelListenerData = @ptrCast(@alignCast(data_ptr.?));
    data.close_request = true;
}

fn xdgToplevelConfigureBounds(
    data: ?*anyopaque,
    xdg_toplevel: ?*wl.xdg_toplevel,
    width: i32,
    height: i32,
) callconv(.c) void {
    _ = width;
    _ = height;
    _ = data;
    _ = xdg_toplevel;
}

fn xdgToplevelWmCapabilities(
    data: ?*anyopaque,
    xdg_toplevel: ?*wl.xdg_toplevel,
    capabilities: ?*wl.wl_array,
) callconv(.c) void {
    _ = data;
    _ = xdg_toplevel;
    _ = capabilities;

    log.debug("xdg_toplevel.capabilities", .{});
}

// =============================================================================
// = xdg surface listener

const xdg_surface_listener = wl.xdg_surface_listener{
    .configure = &xdgSurfaceConfigure,
};

const XdgSurfaceListenerData = struct {
    configure_request: bool,
};

fn xdgSurfaceConfigure(
    data_ptr: ?*anyopaque,
    xdg_surface: ?*wl.xdg_surface,
    serial: u32,
) callconv(.c) void {
    const data: *XdgSurfaceListenerData = @ptrCast(@alignCast(data_ptr));

    wl.xdg_surface_ack_configure(xdg_surface, serial);

    data.configure_request = true;
}

// =============================================================================
// = wl seats

const wl_seat_listener = wl.wl_seat_listener{
    .capabilities = &wlSeatCapabilities,
    .name = &slSeatName,
};

const WlSeatListenerData = struct {
    wl_keyboard: ?*wl.wl_keyboard,

    pub const none = WlSeatListenerData{
        .wl_keyboard = null,
    };
};

fn wlSeatCapabilities(
    data_ptr: ?*anyopaque,
    wl_seat: ?*wl.wl_seat,
    capabilities: u32,
) callconv(.c) void {
    const data: *WlSeatListenerData = @ptrCast(@alignCast(data_ptr));

    log.debug("got seat capabilities: {b}", .{capabilities});

    if (capabilities & wl.WL_SEAT_CAPABILITY_KEYBOARD != 0) {
        log.debug("got keyboard", .{});

        data.wl_keyboard = wl.wl_seat_get_keyboard(wl_seat);

        // ---------------------------------------------------------------------
        // - add wl keyboard listener
        log.debug("adding wl keyboard listener", .{});

        if (wl.wl_keyboard_add_listener(
            data.wl_keyboard,
            &wl_keyboard_listener,
            null,
        ) != 0) @panic("failed to set keyboard listener");
    }
}

fn slSeatName(
    data: ?*anyopaque,
    wl_seat: ?*wl.wl_seat,
    name: [*c]const u8,
) callconv(.c) void {
    _ = data;
    _ = wl_seat;
    _ = name;
}

// =============================================================================
// = wl keyboard listener

const wl_keyboard_listener = wl.wl_keyboard_listener{
    .keymap = &wlKeyboardKeymap,
    .enter = &wlKeyboardEnter,
    .leave = &wlKeyboardLeave,
    .key = &wlKeyboardKey,
    .modifiers = &wlKeyboardModifiers,
    .repeat_info = &wlKeyboardRepeatInfo,
};

fn wlKeyboardKeymap(
    data: ?*anyopaque,
    wl_keyboard: ?*wl.wl_keyboard,
    format: u32,
    fd: i32,
    size: u32,
) callconv(.c) void {
    _ = data;
    _ = wl_keyboard;
    _ = format;
    _ = fd;
    _ = size;
}

fn wlKeyboardEnter(
    data: ?*anyopaque,
    wl_keyboard: ?*wl.wl_keyboard,
    serial: u32,
    surface: ?*wl.wl_surface,
    keys: [*c]wl.wl_array,
) callconv(.c) void {
    _ = data;
    _ = wl_keyboard;
    _ = serial;
    _ = surface;
    _ = keys;
}

fn wlKeyboardLeave(
    data: ?*anyopaque,
    wl_keyboard: ?*wl.wl_keyboard,
    serial: u32,
    wl_surface: ?*wl.wl_surface,
) callconv(.c) void {
    _ = data;
    _ = wl_keyboard;
    _ = serial;
    _ = wl_surface;
}

fn wlKeyboardKey(
    data: ?*anyopaque,
    wl_keyboard: ?*wl.wl_keyboard,
    serial: u32,
    time: u32,
    key: u32,
    state: u32,
) callconv(.c) void {
    _ = data;
    _ = wl_keyboard;
    _ = serial;
    _ = time;
    _ = state;

    log.debug("scancode: {d}", .{key});
}

fn wlKeyboardModifiers(
    data: ?*anyopaque,
    wl_keyboard: ?*wl.wl_keyboard,
    serial: u32,
    mods_depressed: u32,
    mods_latched: u32,
    mods_locked: u32,
    group: u32,
) callconv(.c) void {
    _ = data;
    _ = wl_keyboard;
    _ = serial;
    _ = mods_depressed;
    _ = mods_latched;
    _ = mods_locked;
    _ = group;
}

fn wlKeyboardRepeatInfo(
    data: ?*anyopaque,
    wl_keyboard: ?*wl.wl_keyboard,
    rate: i32,
    dely: i32,
) callconv(.c) void {
    _ = data;
    _ = wl_keyboard;
    _ = rate;
    _ = dely;
}

// =============================================================================
// = frame callback

const FrameCallbackListenerData = struct {
    frame_request: bool,
};

fn frameCallback(
    data_ptr: ?*anyopaque,
    old_callback: ?*wl.wl_callback,
    callback_data: u32,
) callconv(.c) void {
    _ = callback_data;

    wl.wl_callback_destroy(old_callback.?);

    const data: *FrameCallbackListenerData = @ptrCast(@alignCast(data_ptr.?));
    data.frame_request = true;
}

// =============================================================================
// = draw

var c: u8 = 0;

fn draw(buffer_data: *const BufferData, wl_surface: *wl.wl_surface) void {
    c +%= 1;

    @memset(buffer_data.pixels, c);

    wl.wl_surface_attach(wl_surface, buffer_data.wl_buffer, 0, 0);
    wl.wl_surface_damage(
        wl_surface,
        0,
        0,
        @intCast(buffer_data.width),
        @intCast(buffer_data.height),
    );
    wl.wl_surface_commit(wl_surface);
}
