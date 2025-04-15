pub fn Point(comptime T: type) type {
    return struct {
        x: T,
        y: T,

        const Self = @This();

        pub fn intCast(point: Self, comptime NT: type) Point(NT) {
            return .{
                .x = @intCast(point.x),
                .y = @intCast(point.y),
            };
        }
    };
}

pub fn Size(comptime T: type) type {
    return struct {
        width: T,
        height: T,

        const Self = @This();

        pub fn intCast(size: Self, comptime NT: type) Size(NT) {
            return .{
                .width = @intCast(size.width),
                .height = @intCast(size.height),
            };
        }
    };
}

pub fn Bounds(comptime T: type) type {
    return struct {
        origin: Point(T),
        size: Size(T),

        const Self = @This();

        pub fn intCast(bounds: Self, comptime NT: type) Bounds(NT) {
            return .{
                .origin = bounds.origin.intCast(NT),
                .size = bounds.size.intCast(NT),
            };
        }
    };
}
