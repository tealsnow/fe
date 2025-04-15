const Window = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;

const wl = @import("wayland").client.wl;
const xdg = @import("wayland").client.xdg;

const Size = @import("../../../math.zig").Size;
const Bounds = @import("../../../math.zig").Bounds;
const Point = @import("../../../math.zig").Point;

const Event = @import("events.zig").Event;
const Connection = @import("Connection.zig");
const listeners = @import("listeners.zig");

conn: *Connection,

inset: ?u32,
tiling: Event.ToplevelConfigureState,

wl_surface: *wl.Surface,
wl_frame_callback_listener_data: *listeners.WlFrameCallbackListenerData,

xdg_surface_listener_data: *listeners.XdgSurfaceListenerData,
xdg_surface: *xdg.Surface,

// @TODO: we'll create another type for popups
xdg_toplevel_listener_data: *listeners.XdgToplevelListenerData,
xdg_toplevel: *xdg.Toplevel,

size: Size(u32),

pub fn init(
    gpa: Allocator,
    conn: *Connection,
    size: Size(u32),
) !*Window {
    const wl_surface = try conn.wl_compositor.createSurface();

    const xdg_surface = try conn.xdg_wm_base.getXdgSurface(wl_surface);

    const xdg_surface_listener_data =
        try gpa.create(listeners.XdgSurfaceListenerData);
    xdg_surface_listener_data.* = .{
        .event_queue = conn.event_queue,
        .wl_surface = wl_surface,
    };
    xdg_surface.setListener(
        *listeners.XdgSurfaceListenerData,
        listeners.xdgSurfaceListener,
        xdg_surface_listener_data,
    );

    const xdg_toplevel = try xdg_surface.getToplevel();

    xdg_toplevel.setTitle("fe wayland 2");

    const xdg_toplevel_listener_data =
        try gpa.create(listeners.XdgToplevelListenerData);
    xdg_toplevel_listener_data.* = .{
        .event_queue = conn.event_queue,
    };
    xdg_toplevel.setListener(
        *listeners.XdgToplevelListenerData,
        listeners.xdgToplevelListener,
        xdg_toplevel_listener_data,
    );

    const wl_frame_callback = try wl_surface.frame();

    const wl_frame_callback_listener_data =
        try gpa.create(listeners.WlFrameCallbackListenerData);
    wl_frame_callback_listener_data.* = .{
        .event_queue = conn.event_queue,
        .wl_surface = wl_surface,
    };
    wl_frame_callback.setListener(
        *listeners.WlFrameCallbackListenerData,
        listeners.wlFrameCallbackListener,
        wl_frame_callback_listener_data,
    );

    const window = try gpa.create(Window);
    window.* = .{
        .conn = conn,

        .inset = null,
        .tiling = .{},

        .wl_surface = wl_surface,
        .wl_frame_callback_listener_data = wl_frame_callback_listener_data,

        .xdg_surface_listener_data = xdg_surface_listener_data,
        .xdg_surface = xdg_surface,

        .xdg_toplevel_listener_data = xdg_toplevel_listener_data,
        .xdg_toplevel = xdg_toplevel,

        .size = size,
    };
    return window;
}

pub fn deinit(window: *Window, gpa: Allocator) void {
    defer gpa.destroy(window);

    defer window.wl_surface.destroy();
    defer gpa.destroy(window.wl_frame_callback_listener_data);

    defer gpa.destroy(window.xdg_surface_listener_data);
    defer window.xdg_surface.destroy();

    defer gpa.destroy(window.xdg_toplevel_listener_data);
    defer window.xdg_toplevel.destroy();
}

pub fn innerBounds(window: Window) Bounds(i32) {
    return insetBounds(
        .{
            .origin = .{ .x = 0, .y = 0 },
            .size = window.size,
        },
        window.inset,
        window.tiling,
    );
}

pub fn createSurface(window: *Window) !WindowSurface {
    return WindowSurface.init(window);
}

pub fn commit(window: Window) void {
    window.wl_surface.damageBuffer(
        0,
        0,
        @intCast(window.size.width),
        @intCast(window.size.height),
    );
    window.wl_surface.commit();
}

pub fn getEdge(window: Window, point: Point(f64)) ?Edge {
    return if (window.inset) |inset|
        Edge.fromPoint(point, window.size, inset, window.tiling)
    else
        null;
}

pub fn startResize(window: Window, mouse_button_serial: u32, edge: Edge) void {
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

    window.xdg_toplevel.resize(
        window.conn.wl_seat,
        mouse_button_serial,
        resize,
    );
}

pub fn startMove(window: Window, mouse_button_serial: u32) void {
    window.xdg_toplevel.move(window.conn.wl_seat, mouse_button_serial);
}

pub fn handleSurfaceConfigureEvent(
    window: *Window,
    conf: Event.SurfaceConfigure,
) void {
    window.xdg_surface.ackConfigure(conf.serial);

    // window gemetry excludes CSD
    const gemoetry = window.innerBounds();

    window.xdg_surface.setWindowGeometry(
        gemoetry.origin.x,
        gemoetry.origin.y,
        gemoetry.size.width,
        gemoetry.size.height,
    );
}

pub fn computeOuterSize(
    window_inset: ?u32,
    new_size_inner: Size(u32),
    tiling: Event.ToplevelConfigureState,
) Size(u32) {
    const inset = window_inset orelse return new_size_inner;

    var size = new_size_inner;

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

pub const Edge = enum {
    left,
    right,
    top,
    bottom,
    top_left,
    top_right,
    bottom_left,
    bottom_right,

    pub fn fromPoint(
        point: Point(f64),
        window_size: Size(u32),
        window_inset: u32,
        tiling: Event.ToplevelConfigureState,
    ) ?Edge {
        const x = point.x;
        const y = point.y;

        const width: f64 =
            @floatFromInt(window_size.width);
        const height: f64 =
            @floatFromInt(window_size.height);

        const inset: f64 = @floatFromInt(window_inset);

        const left = x < inset and !tiling.tiled_left;
        const right = x >= width - inset and !tiling.tiled_right;
        const top = y < inset and !tiling.tiled_top;
        const bottom = y >= height - inset and !tiling.tiled_bottom;

        return if (top and left)
            .top_left
        else if (top and right)
            .top_right
        else if (bottom and left)
            .bottom_left
        else if (bottom and right)
            .bottom_right
        else if (left)
            .left
        else if (right)
            .right
        else if (top)
            .top
        else if (bottom)
            .bottom
        else
            null;
    }
};

pub const WindowSurface = struct {
    window: *Window,
    wl_buffer: *wl.Buffer,
    pixels: []u8,

    pub fn init(
        window: *Window,
    ) !WindowSurface {
        const len = window.size.width * window.size.height * 4;

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

        const pool = try window.conn.wl_shm.createPool(fd, @intCast(len));
        defer pool.destroy();

        const wl_buffer = try pool.createBuffer(
            0,
            @intCast(window.size.width),
            @intCast(window.size.height),
            @intCast(window.size.width * 4),
            .argb8888,
        );

        return .{
            .window = window,
            .wl_buffer = wl_buffer,
            .pixels = pixels,
        };
    }

    pub fn deinit(surface: WindowSurface) void {
        surface.wl_buffer.destroy();
        std.posix.munmap(@alignCast(surface.pixels));
    }

    pub fn reconfigure(
        surface: *WindowSurface,
    ) !void {
        const window = surface.window;
        surface.deinit();
        surface.* = try WindowSurface.init(window);
    }

    pub fn attach(surface: WindowSurface) void {
        surface.window.wl_surface.attach(surface.wl_buffer, 0, 0);
    }
};
