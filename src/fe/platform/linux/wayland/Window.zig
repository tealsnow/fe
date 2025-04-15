const Window = @This();

const std = @import("std");

const wl = @import("wayland").client.wl;

const Size = @import("../../../math.zig").Size;
const Bounds = @import("../../../math.zig").Bounds;
const Point = @import("../../../math.zig").Point;

const Event = @import("events.zig").Event;

size: Size(u32),
inset: ?u32,
tiling: Event.ToplevelConfigureState,

pixel_data: PixelData,

pub fn init(size: Size(u32), pixel_data: PixelData) Window {
    return .{
        .size = size,
        .inset = null,
        .tiling = .{},
        .pixel_data = pixel_data,
    };
}

pub fn deinit(window: Window) void {
    window.pixel_data.deinit();
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

pub const PixelData = struct {
    wl_buffer: *wl.Buffer,
    pixels: []u8,
    size: Size(u32),

    pub fn configure(
        size: Size(u32),
        wl_shared_memory: *wl.Shm,
    ) !PixelData {
        const len = size.width * size.height * 4;

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

        const pool = try wl_shared_memory.createPool(fd, @intCast(len));
        defer pool.destroy();

        const wl_buffer = try pool.createBuffer(
            0,
            @intCast(size.width),
            @intCast(size.height),
            @intCast(size.width * 4),
            .argb8888,
        );

        return .{
            .wl_buffer = wl_buffer,
            .pixels = pixels,
            .size = size,
        };
    }

    pub fn deinit(data: PixelData) void {
        data.wl_buffer.destroy();
        std.posix.munmap(@alignCast(data.pixels));
    }

    pub fn reconfigure(
        data: *PixelData,
        size: Size(u32),
        wl_shared_memory: *wl.Shm,
    ) !void {
        if (data.size.width != size.width or data.size.height != size.height) {
            data.deinit();
            data.* = try configure(size, wl_shared_memory);
        }
    }
};

pub fn computeOuterSize(
    window_inset: ?u32,
    new_size: Size(u32),
    tiling: Event.ToplevelConfigureState,
) Size(u32) {
    const inset = window_inset orelse return new_size;

    var size = new_size;

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

pub fn insetBounds(
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
