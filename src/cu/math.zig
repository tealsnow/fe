const std = @import("std");

pub fn Vec2(comptime T: type) type {
    return extern struct {
        x: T,
        y: T,

        const Self = @This();
        pub const zero = std.mem.zeroes(Self);
        pub const inf = vec(std.math.inf(T), std.math.inf(T));

        pub inline fn vec(x: T, y: T) Self {
            return .{ .x = x, .y = y };
        }

        pub inline fn arr(self: *Self) *[2]T {
            return @ptrCast(self);
        }
    };
}

pub fn vec2(x: anytype, y: @TypeOf(x)) Vec2(@TypeOf(x)) {
    return .vec(x, y);
}

pub fn Axis2(comptime T: type) type {
    return extern struct {
        w: T,
        h: T,

        const Self = @This();
        pub const zero = std.mem.zeroes(Self);
        pub const inf = axis(std.math.inf(T), std.math.inf(T));

        pub const Kind = enum(u2) {
            x = 0,
            y,
            none = std.math.maxInt(u2),

            pub const w = Kind.x;
            pub const h = Kind.y;

            pub const array = [2]Kind{ .x, .y };
        };

        pub fn axis(w: T, h: T) Self {
            return .{ .w = w, .h = h };
        }

        pub inline fn arr(self: *Self) *[2]T {
            return @ptrCast(self);
        }

        pub inline fn asArr(self: Self) [2]T {
            return @bitCast(self);
        }
    };
}

pub fn axis2(w: anytype, h: @TypeOf(w)) Axis2(@TypeOf(w)) {
    return .axis(w, h);
}

pub fn Range2(comptime T: type) type {
    return extern struct {
        p0: Vec2(T),
        p1: Vec2(T),

        const Self = @This();
        pub const zero = std.mem.zeroes(Self);
        pub const inf = range(.inf, .inf);

        pub fn range(p0: Vec2(T), p1: Vec2(T)) Self {
            return Self{ .p0 = p0, .p1 = p1 };
        }

        pub inline fn arr(self: *Self) *[2]Vec2(T) {
            return @ptrCast(self);
        }

        pub fn contains(self: Self, point: Vec2(T)) bool {
            return point.x > self.p0.x and
                point.x < self.p1.x and
                point.y > self.p0.y and
                point.y < self.p1.y;
        }
    };
}

pub fn range2(comptime T: type, p0: Vec2(T), p1: Vec2(T)) Range2(T) {
    return .range(p0, p1);
}

pub fn range2pts(x0: anytype, y0: @TypeOf(x0), x1: @TypeOf(x0), y1: @TypeOf(x0)) Range2(Vec2(@TypeOf(x0))) {
    return .range(Vec2(x0, y0), Vec2(x1, y1));
}
