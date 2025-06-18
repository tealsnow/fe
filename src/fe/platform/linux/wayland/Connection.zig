const Connection = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const log = std.log.scoped(.@"wayland.connection");

const wl = @import("wayland").client.wl;
const xdg = @import("wayland").client.xdg;
const wp = @import("wayland").client.wp;
const zwp = @import("wayland").client.zwp;

const xkb = @import("xkbcommon");

const listeners = @import("listeners.zig");
const events = @import("events.zig");
const xdp = @import("xdg_desktop_portal.zig");

const CursorManager = @import("cursor_manager.zig").CursorManager;
const CursorKind = @import("cursor_manager.zig").CursorKind;

const Window = @import("Window.zig");
const WindowId = Window.WindowId;

//- fields

wl_display: *wl.Display,

wl_registry_listener_data: *listeners.WlRegistryListenerData,
wl_registry: *wl.Registry,

wl_compositor: *wl.Compositor,
wl_shm: *wl.Shm,
wl_seat: *wl.Seat,

pointer_gestures: PointerGestures,

event_queue: *events.EventQueue,

xkb_context: *xkb.Context,
wl_keyboard_listener_data: *listeners.WlKeyboardListenerData,
wl_keyboard: *wl.Keyboard,

wl_pointer_listener_data: *listeners.WlPointerListenerData,
wl_pointer: *wl.Pointer,

wp_cursor_shape_manager: ?*wp.CursorShapeManagerV1,
cursor_manager: CursorManager,

xdg_wm_base: *xdg.WmBase,

next_window_id: WindowId = @enumFromInt(1),
windows: std.AutoArrayHashMapUnmanaged(WindowId, *Window) = .empty,
surface_to_window_map: *std.AutoArrayHashMapUnmanaged(*wl.Surface, *Window),

cursor_size: i32,

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

    // the `orelse null` is necessary for the type coercion
    const wl_display = try wl.Display.connect(wl_display_name orelse null);

    const event_queue = try gpa.create(events.EventQueue);
    errdefer gpa.destroy(event_queue);
    event_queue.* = .empty;

    const wl_registry = try wl_display.getRegistry();

    const wl_registry_listener_data =
        try gpa.create(listeners.WlRegistryListenerData);
    errdefer gpa.destroy(wl_registry_listener_data);
    wl_registry_listener_data.* = .{
        .gpa = gpa,
        .event_queue = event_queue,
    };
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

    const zwp_pointer_gestures =
        wl_registry_listener_data.zwp_pointer_gestures orelse {
            log.err("failed to get zwp_pointer_gestures", .{});
            return error.wl;
        };

    //- wl_seat setup

    const xkb_context = xkb.Context.new(.no_flags) orelse return error.xkb;

    var wl_seat_listener_data = listeners.WlSeatListenerData.empty;
    wl_seat.setListener(
        *listeners.WlSeatListenerData,
        listeners.wlSeatListener,
        &wl_seat_listener_data,
    );

    //- gather wl_seat and wl_output data
    if (wl_display.roundtrip() != .SUCCESS) return error.wl;

    //- input setup

    const wl_keyboard = wl_seat_listener_data.wl_keyboard orelse {
        log.err("failed to get wl_keyboard", .{});
        return error.wl;
    };

    const surface_to_window_map =
        try gpa.create(std.AutoArrayHashMapUnmanaged(*wl.Surface, *Window));
    surface_to_window_map.* = .empty;

    const wl_keyboard_listener_data =
        try gpa.create(listeners.WlKeyboardListenerData);
    errdefer gpa.destroy(wl_keyboard_listener_data);
    wl_keyboard_listener_data.* = .{
        .event_queue = event_queue,
        .surface_to_window_map = surface_to_window_map,
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
        .surface_to_window_map = surface_to_window_map,
    };
    wl_pointer.setListener(
        *listeners.WlPointerListenerData,
        &listeners.wlPointerListener,
        wl_pointer_listener_data,
    );

    //- pointer gestures

    const pointer_gestures = try PointerGestures.init(
        gpa,
        zwp_pointer_gestures,
        wl_pointer,
        event_queue,
    );

    //- xdp
    log.debug("xdp: opening xdg-desktop-portal settings proxy", .{});
    const xdp_settings = try xdp.XdpSettings.init();

    log.debug("xdp: getting cursor size", .{});
    const cursor_size = try xdp_settings.getCursorSize();
    log.info("xdp: got cursor size: {d}", .{cursor_size});

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
        log.info("xdp: got cursor theme: '{s}'", .{cursor_theme});

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

    const conn = try gpa.create(Connection);
    conn.* = .{
        .wl_display = wl_display,

        .wl_registry_listener_data = wl_registry_listener_data,
        .wl_registry = wl_registry,

        .wl_compositor = wl_compositor,
        .wl_shm = wl_shm,
        .wl_seat = wl_seat,

        .pointer_gestures = pointer_gestures,

        .event_queue = event_queue,

        .xkb_context = xkb_context,
        .wl_keyboard_listener_data = wl_keyboard_listener_data,
        .wl_keyboard = wl_keyboard,

        .wl_pointer_listener_data = wl_pointer_listener_data,
        .wl_pointer = wl_pointer,

        .wp_cursor_shape_manager = wp_cursor_shape_manager,
        .cursor_manager = cursor_manager,

        .xdg_wm_base = xdg_wm_base,

        .surface_to_window_map = surface_to_window_map,

        .cursor_size = cursor_size,
    };
    return conn;
}

pub fn deinit(conn: *Connection, gpa: Allocator) void {
    defer gpa.destroy(conn);

    defer conn.wl_display.disconnect();

    defer gpa.destroy(conn.wl_registry_listener_data);
    defer {
        for (conn.wl_registry_listener_data.outputs.values()) |output|
            output.deinit(gpa);
        conn.wl_registry_listener_data.outputs.deinit(gpa);
    }
    defer conn.wl_registry.destroy();

    defer conn.wl_compositor.destroy();
    defer conn.wl_shm.destroy();
    defer conn.wl_seat.destroy();

    defer conn.pointer_gestures.deinit(gpa);

    defer gpa.destroy(conn.event_queue);

    defer conn.xkb_context.unref();

    defer conn.wl_keyboard.destroy();
    defer gpa.destroy(conn.wl_keyboard_listener_data);
    defer if (conn.wl_keyboard_listener_data.xkb_state) |state| state.unref();
    defer if (conn.wl_keyboard_listener_data.xkb_keymap) |map| map.unref();

    defer gpa.destroy(conn.wl_pointer_listener_data);
    defer conn.wl_pointer.destroy();

    defer if (conn.wp_cursor_shape_manager) |manager| manager.destroy();
    defer conn.cursor_manager.deinit();

    defer conn.xdg_wm_base.destroy();

    defer conn.windows.deinit(gpa);
    defer for (conn.windows.values()) |window| window.deinit(gpa);

    defer gpa.destroy(conn.surface_to_window_map);
    defer conn.surface_to_window_map.deinit(gpa);
}

/// blocks on events
pub fn dispatch(conn: *Connection) !void {
    if (conn.wl_display.dispatch() != .SUCCESS) {
        log.err("wl_display.dispatch() failed", .{});
        return error.wl;
    }
    conn.handleEventsInternal();
}

/// does not block on events
pub fn roundtrip(conn: *Connection) !void {
    if (conn.wl_display.roundtrip() != .SUCCESS) {
        log.err("wl_display.roundtrip() failed", .{});
        return error.wl;
    }
    conn.handleEventsInternal();
}

fn handleEventsInternal(conn: *Connection) void {
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

pub fn getWindow(conn: Connection, id: WindowId) *Window {
    return conn.windows.get(id);
}

pub fn getOutput(conn: Connection, id: OutputId) ?OutputInfo {
    const handle = conn.wl_registry_listener_data.outputs.get(id) orelse return null;
    return handle.listener_data.info;
}

pub const GetEnvVarOwnedError = error{
    OutOfMemory,

    /// On Windows, environment variable keys provided by the user must be valid WTF-8.
    /// https://simonsapin.github.io/wtf-8/
    InvalidWtf8,
};

/// Wrapper around std.process.getEnvVarOwned returning a ?[]u8
/// for more ergonomic usage when handling not found variables
pub fn getEnvVarOwned(allocator: Allocator, key: []const u8) GetEnvVarOwnedError!?[]u8 {
    return std.process.getEnvVarOwned(allocator, key) catch |err|
        switch (err) {
            error.EnvironmentVariableNotFound => null,
            error.OutOfMemory => return error.OutOfMemory,
            error.InvalidWtf8 => return error.InvalidWtf8,
        };
}

pub const PointerGestures = struct {
    zwp_pointer_gestures: *zwp.PointerGesturesV1,
    swipe: *zwp.PointerGestureSwipeV1,
    pinch: *zwp.PointerGesturePinchV1,
    hold: *zwp.PointerGestureHoldV1,
    listener_data: *listeners.WlPointerGesturesListenerData,

    pub fn init(
        gpa: Allocator,
        zwp_pointer_gestures: *zwp.PointerGesturesV1,
        wl_pointer: *wl.Pointer,
        event_queue: *events.EventQueue,
    ) !PointerGestures {
        const swipe =
            try zwp_pointer_gestures.getSwipeGesture(wl_pointer);
        const pinch =
            try zwp_pointer_gestures.getPinchGesture(wl_pointer);
        const hold =
            try zwp_pointer_gestures.getHoldGesture(wl_pointer);

        const listener_data = try gpa.create(listeners.WlPointerGesturesListenerData);
        errdefer gpa.destroy(listener_data);
        listener_data.* = .{ .event_queue = event_queue };

        swipe.setListener(
            *listeners.WlPointerGesturesListenerData,
            listeners.wlPointerGesturesSwipeListener,
            listener_data,
        );
        pinch.setListener(
            *listeners.WlPointerGesturesListenerData,
            listeners.wlPointerGesturesPinchListener,
            listener_data,
        );
        hold.setListener(
            *listeners.WlPointerGesturesListenerData,
            listeners.wlPointerGesturesHoldListener,
            listener_data,
        );

        return .{
            .zwp_pointer_gestures = zwp_pointer_gestures,
            .swipe = swipe,
            .pinch = pinch,
            .hold = hold,
            .listener_data = listener_data,
        };
    }

    pub fn deinit(self: PointerGestures, gpa: Allocator) void {
        defer self.swipe.destroy();
        defer self.pinch.destroy();
        defer self.hold.destroy();
        defer gpa.destroy(self.listener_data);
        defer self.zwp_pointer_gestures.destroy();
    }
};

pub const OutputId = struct {
    name: u32, // registry name
    id: u32, // output id
    // either one of these are valid to id an output,
    // the name comes from a registry event,
    // and the id is the it of the output itself `wl_output.getId()` allowing
    // to go from an wl_output object to its handle in the map

    pub fn format(
        self: @This(),
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        try writer.print(
            "OutputId({d}-{d})",
            .{ self.name, self.id },
        );
    }
};

pub const OutputInfo = struct {
    name: ?[:0]const u8,
    description: ?[:0]const u8,
    geometry: ?Geometry,
    modes: []Mode,
    current_mode_idx: ?usize,
    preferred_mode_idx: ?usize,
    scale: ?i32,

    pub const Geometry = struct {
        x: i32,
        y: i32,
        physical_width_mm: i32,
        physical_height_mm: i32,
        subpixel: wl.Output.Subpixel,
        make: [:0]const u8,
        model: [:0]const u8,
        transform: wl.Output.Transform,
    };

    pub const Mode = struct {
        width: i32,
        height: i32,
        refresh: i32,
    };

    pub fn currentMode(self: OutputInfo) ?Mode {
        const idx = self.current_mode_idx orelse return null;
        return self.modes[idx];
    }

    pub fn preferredMode(self: OutputInfo) ?Mode {
        const idx = self.preferred_mode_idx orelse return null;
        return self.modes[idx];
    }

    pub const Dpi = struct {
        horizontal: f32,
        vertical: f32,
    };

    // (horizontal dpi, vertical dpi)
    pub fn calculateDpi(self: OutputInfo) ?Dpi {
        const current_mode = self.currentMode() orelse return null;
        const geom = self.geometry orelse return null;

        const width_px: f32 = @floatFromInt(current_mode.width);
        const height_px: f32 = @floatFromInt(current_mode.height);

        const physical_width_mm: f32 = @floatFromInt(geom.physical_width_mm);
        const physical_height_mm: f32 = @floatFromInt(geom.physical_height_mm);

        const physical_width_inch = physical_width_mm / 25.4;
        const physical_height_inch = physical_height_mm / 25.4;

        const hdpi = width_px / physical_width_inch;
        const vdpi = height_px / physical_height_inch;

        return .{ .horizontal = hdpi, .vertical = vdpi };
    }
};
