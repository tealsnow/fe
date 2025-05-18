const Window = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;

const wl = @import("wayland").client.wl;
const xdg = @import("wayland").client.xdg;

const mt = @import("cu").math;

const Event = @import("events.zig").Event;
const Connection = @import("Connection.zig");
const listeners = @import("listeners.zig");

conn: *Connection,

wl_surface: *wl.Surface,
wl_frame_callback_listener_data: *listeners.WlFrameCallbackListenerData,

xdg_surface_listener_data: *listeners.XdgSurfaceListenerData,
xdg_surface: *xdg.Surface,

// @TODO: we'll create another type for popups
xdg_toplevel_listener_data: *listeners.XdgToplevelListenerData,
xdg_toplevel: *xdg.Toplevel,

size: mt.Size(u32),

/// This is in terms of window gemetry - excludes the inset
minimium_size: ?mt.Size(u32) = null,
inset: ?u32 = null,
tiling: Event.ToplevelConfigureState = .{},

pub fn init(
    gpa: Allocator,
    conn: *Connection,
    size: mt.Size(u32),
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

pub fn innerBounds(window: Window) mt.Bounds(i32) {
    return insetBounds(
        .bounds(.zero, window.size),
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

pub fn getEdge(window: Window, point: mt.Point(f64)) ?Edge {
    return if (window.inset) |inset|
        Edge.fromPoint(point, window.size, inset, window.tiling)
    else
        null;
}

pub fn startResize(window: Window, edge: Edge) void {
    const resize_edge: xdg.Toplevel.ResizeEdge = switch (edge) {
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
        window.conn.last_pointer_button_serial,
        resize_edge,
    );
}

pub fn startMove(window: Window) void {
    window.xdg_toplevel
        .move(window.conn.wl_seat, window.conn.last_pointer_button_serial);
}

pub fn toggleMaximized(window: Window) void {
    if (window.tiling.maximized) {
        window.xdg_toplevel.unsetMaximized();
    } else {
        window.xdg_toplevel.setMaximized();
    }
}

pub fn minimize(window: Window) void {
    window.xdg_toplevel.setMinimized();
}

pub fn showWindowMenu(window: Window, origin: mt.Point(i32)) void {
    window.xdg_toplevel.showWindowMenu(
        window.conn.wl_seat,
        window.conn.last_pointer_button_serial,
        origin.x,
        origin.y,
    );
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

/// Returns the new size if changed
pub fn handleToplevelConfigureEvent(
    window: *Window,
    conf: Event.ToplevelConfigure,
) ?mt.Size(u32) {
    window.tiling = conf.state;

    // This configure event is in terms on window geometry
    // so we need to add back our inset for the real size
    const new_size_geometry = conf.size orelse window.size;

    const new_size_wo_inset: mt.Size(u32) = if (window.minimium_size) |min|
        .{
            .width = @max(min.width, new_size_geometry.width),
            .height = @max(min.height, new_size_geometry.height),
        }
    else
        new_size_geometry;

    // add back inset
    const new_size = computeOuterSize(
        window.inset,
        new_size_wo_inset,
        window.tiling,
    );

    return if (new_size.width != window.size.width or
        new_size.height != window.size.height)
    blk: {
        window.size = new_size;

        break :blk new_size;
    } else null;
}

pub fn computeOuterSize(
    window_inset: ?u32,
    new_size_inner: mt.Size(u32),
    tiling: Event.ToplevelConfigureState,
) mt.Size(u32) {
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
    bounds: mt.Bounds(u32),
    window_inset: ?u32,
    tiling: Event.ToplevelConfigureState,
) mt.Bounds(i32) {
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
        point: mt.Point(f64),
        window_size: mt.Size(u32),
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
