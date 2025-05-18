const Connection = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const log = std.log.scoped(.@"wayland.connection");

const wl = @import("wayland").client.wl;
const xdg = @import("wayland").client.xdg;
const wp = @import("wayland").client.wp;

const xkb = @import("xkbcommon");

const listeners = @import("listeners.zig");
const events = @import("events.zig");
const xdp = @import("xdg_desktop_portal.zig");

const CursorManager = @import("cursor_manager.zig").CursorManager;
const CursorKind = @import("cursor_manager.zig").CursorKind;

//- fields

wl_display: *wl.Display,

wl_registry_listener_data: *listeners.WlRegistryListenerData,
wl_registry: *wl.Registry,

wl_compositor: *wl.Compositor,
wl_shm: *wl.Shm,
wl_seat: *wl.Seat,
wl_output: *wl.Output,

event_queue: *events.EventQueue,

xkb_context: *xkb.Context,
wl_keyboard_listener_data: *listeners.WlKeyboardListenerData,
wl_keyboard: *wl.Keyboard,

wl_pointer_listener_data: *listeners.WlPointerListenerData,
wl_pointer: *wl.Pointer,

wp_cursor_shape_manager: ?*wp.CursorShapeManagerV1,
cursor_manager: CursorManager,

xdg_wm_base: *xdg.WmBase,

hdpi: f32,
vdpi: f32,

last_pointer_button_serial: u32 = 0,
last_pointer_focus_enter_serial: u32 = 0,

//- methods

pub fn init(gpa: Allocator) !*Connection {
    const wl_display_name =
        if (try getEnvVarOwned(gpa, "WAYLAND_DISPLAY")) |name| blk: {
            defer gpa.free(name);
            break :blk try gpa.dupeZ(u8, name);
        } else null;
    defer if (wl_display_name) |name| gpa.free(name);

    // the `orelse null` is nessesary for the slice coercion
    const wl_display = try wl.Display.connect(wl_display_name orelse null);

    const wl_registry = try wl_display.getRegistry();

    const wl_registry_listener_data =
        try gpa.create(listeners.WlRegistryListenerData);
    errdefer gpa.destroy(wl_registry_listener_data);
    wl_registry_listener_data.* = .empty;
    wl_registry.setListener(
        *listeners.WlRegistryListenerData,
        listeners.wlRegistryListener,
        wl_registry_listener_data,
    );

    //- gather globals
    if (wl_display.roundtrip() != .SUCCESS) return error.wl;

    const wl_compositor = wl_registry_listener_data.wl_compositor orelse {
        log.err("failed to get wl_compositor", .{});
        return error.wl;
    };

    const wl_shm = wl_registry_listener_data.wl_shared_memory orelse {
        log.err("failed to get wl_shared_memory", .{});
        return error.wl;
    };

    const wl_seat = wl_registry_listener_data.wl_seat orelse {
        log.err("failed to get wl_seat", .{});
        return error.wl;
    };

    const wl_output = wl_registry_listener_data.wl_output orelse {
        log.err("failed to get wl_output", .{});
        return error.wl;
    };

    //- output
    var wl_output_listener_data = listeners.WlOutputListenerData.empty;
    wl_output.setListener(
        *listeners.WlOutputListenerData,
        listeners.wlOutputListener,
        &wl_output_listener_data,
    );

    //- wl_seat setup

    const xkb_context = xkb.Context.new(.no_flags) orelse return error.xkb;

    const event_queue = try gpa.create(events.EventQueue);
    errdefer gpa.destroy(event_queue);
    event_queue.* = .empty;

    var wl_seat_listener_data = listeners.WlSeatListenerData.empty;
    wl_seat.setListener(
        *listeners.WlSeatListenerData,
        listeners.wlSeatListener,
        &wl_seat_listener_data,
    );

    //- gather wl_seat and wl_output data
    if (wl_display.roundtrip() != .SUCCESS) return error.wl;

    //- output calculations
    const hdpi, const vdpi = dpi: {
        const width: f32 = @floatFromInt(wl_output_listener_data.width);
        const height: f32 = @floatFromInt(wl_output_listener_data.height);

        const physical_width_mm: f32 =
            @floatFromInt(wl_output_listener_data.physical_width_mm);
        const physical_height_mm: f32 =
            @floatFromInt(wl_output_listener_data.physical_height_mm);

        const physical_width_inch = physical_width_mm / 25.4;
        const physical_height_inch = physical_height_mm / 25.4;

        const hdpi = width / physical_width_inch;
        const vdpi = height / physical_height_inch;

        break :dpi .{ hdpi, vdpi };
    };

    //- input setup

    const wl_keyboard = wl_seat_listener_data.wl_keyboard orelse {
        log.err("failed to get wl_keyboard", .{});
        return error.wl;
    };

    const wl_keyboard_listener_data =
        try gpa.create(listeners.WlKeyboardListenerData);
    errdefer gpa.destroy(wl_keyboard_listener_data);
    wl_keyboard_listener_data.* = .{
        .event_queue = event_queue,
        .xkb_context = xkb_context,
    };
    wl_keyboard.setListener(
        *listeners.WlKeyboardListenerData,
        &listeners.wlKeyboardListener,
        wl_keyboard_listener_data,
    );

    const wl_pointer = wl_seat_listener_data.wl_pointer orelse {
        log.err("failed to get wl_pointer", .{});
        return error.wl;
    };

    const wl_pointer_listener_data =
        try gpa.create(listeners.WlPointerListenerData);
    errdefer gpa.destroy(wl_pointer_listener_data);
    wl_pointer_listener_data.* = .{
        .event_queue = event_queue,
    };
    wl_pointer.setListener(
        *listeners.WlPointerListenerData,
        &listeners.wlPointerListener,
        wl_pointer_listener_data,
    );

    //- xdp
    log.debug("xdp: opening xdg-desktop-portal settings proxy", .{});
    const xdp_settings = try xdp.XdpSettings.init();

    const wp_cursor_shape_manager =
        wl_registry_listener_data.wp_cursor_shape_manager;

    const cursor_manager = if (wp_cursor_shape_manager) |manager|
        try CursorManager.initCursorShapeManager(
            wl_pointer,
            manager,
        )
    else manager: {
        log.debug("xdp: getting cursor theme", .{});
        const cursor_theme = try xdp_settings.getCursorTheme(gpa);
        defer gpa.free(cursor_theme);
        log.debug("xdp: got cursor theme: '{s}'", .{cursor_theme});

        log.debug("xdp: getting cursor size", .{});
        const cursor_size = try xdp_settings.getCursorSize();
        log.debug("xdp: got cursor size: {d}", .{cursor_size});

        break :manager try CursorManager.initPointerManager(
            gpa,
            wl_compositor,
            wl_pointer,
            cursor_theme,
            cursor_size,
            wl_shm,
        );
    };
    errdefer cursor_manager.deinit();

    //- xdg wm base

    const xdg_wm_base = wl_registry_listener_data.xdg_wm_base orelse {
        log.err("failed to get xdg_wm_base", .{});
        return error.wl;
    };

    xdg_wm_base.setListener(
        ?*void,
        listeners.xdgWmBaseListener,
        null,
    );

    if (wl_display.roundtrip() != .SUCCESS) return error.wl;

    const con = try gpa.create(Connection);
    con.* = .{
        .wl_display = wl_display,

        .wl_registry_listener_data = wl_registry_listener_data,
        .wl_registry = wl_registry,

        .wl_compositor = wl_compositor,
        .wl_shm = wl_shm,
        .wl_seat = wl_seat,
        .wl_output = wl_output,

        .event_queue = event_queue,

        .xkb_context = xkb_context,
        .wl_keyboard_listener_data = wl_keyboard_listener_data,
        .wl_keyboard = wl_keyboard,

        .wl_pointer_listener_data = wl_pointer_listener_data,
        .wl_pointer = wl_pointer,

        .wp_cursor_shape_manager = wp_cursor_shape_manager,
        .cursor_manager = cursor_manager,

        .xdg_wm_base = xdg_wm_base,

        .hdpi = hdpi,
        .vdpi = vdpi,
    };
    return con;
}

pub fn deinit(conn: *Connection, gpa: Allocator) void {
    defer gpa.destroy(conn);

    defer conn.wl_display.disconnect();

    defer gpa.destroy(conn.wl_registry_listener_data);
    defer conn.wl_registry.destroy();

    defer conn.wl_compositor.destroy();
    defer conn.wl_shm.destroy();
    defer conn.wl_seat.destroy();
    defer conn.wl_output.destroy();

    defer gpa.destroy(conn.event_queue);

    defer conn.xkb_context.unref();

    defer if (conn.wl_keyboard_listener_data.xkb_state) |state| state.unref();
    defer if (conn.wl_keyboard_listener_data.xkb_keymap) |map| map.unref();
    defer gpa.destroy(conn.wl_keyboard_listener_data);
    defer conn.wl_keyboard.destroy();

    defer gpa.destroy(conn.wl_pointer_listener_data);
    defer conn.wl_pointer.destroy();

    defer if (conn.wp_cursor_shape_manager) |manager| manager.destroy();
    defer conn.cursor_manager.deinit();

    defer conn.xdg_wm_base.destroy();
}

pub fn dispatch(conn: *Connection) !void {
    if (conn.wl_display.dispatch() != .SUCCESS) {
        log.err("wl_display.dispatch() failed", .{});
        return error.wl;
    }

    var i: usize = 0;
    while (conn.event_queue.indexBack(i)) |event| : (i += 1) {
        switch (event.kind) {
            .pointer_button => |button| {
                conn.last_pointer_button_serial = button.serial;
            },
            .pointer_focus => |focus| {
                switch (focus.state) {
                    .enter => //
                    conn.last_pointer_focus_enter_serial = focus.serial,

                    else => {},
                }
            },
            else => {},
        }
    }
}

pub fn setCursor(conn: Connection, kind: CursorKind) !void {
    return conn.cursor_manager
        .setCursor(conn.last_pointer_focus_enter_serial, kind);
}

pub const GetEnvVarOwnedError = error{
    OutOfMemory,

    /// On Windows, environment variable keys provided by the user must be valid WTF-8.
    /// https://simonsapin.github.io/wtf-8/
    InvalidWtf8,
};

/// Wrapper arround std.process.getEnvVarOwned returning a ?[]u8
/// for more ergonomic usage when handling not found variables
pub fn getEnvVarOwned(allocator: Allocator, key: []const u8) GetEnvVarOwnedError!?[]u8 {
    return std.process.getEnvVarOwned(allocator, key) catch |err|
        switch (err) {
            error.EnvironmentVariableNotFound => null,
            error.OutOfMemory => return error.OutOfMemory,
            error.InvalidWtf8 => return error.InvalidWtf8,
        };
}
