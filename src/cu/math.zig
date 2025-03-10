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

        pub inline fn asAxis(self: Self) Axis2(T) {
            return .axis(self.x, self.y);
        }

        pub inline fn arr(self: *Self) *[2]T {
            return @ptrCast(self);
        }

        pub inline fn add(self: Self, other: Self) Self {
            return .{ .x = self.x + other.x, .y = self.y + other.y };
        }

        pub inline fn sub(self: Self, other: Self) Self {
            return .{ .x = self.x - other.x, .y = self.y - other.y };
        }
    };
}

pub inline fn vec2(x: anytype, y: @TypeOf(x)) Vec2(@TypeOf(x)) {
    return .vec(x, y);
}

pub fn Vec3(comptime T: type) type {
    return extern struct {
        x: T,
        y: T,
        z: T,

        const Self = @This();
        pub const zero = std.mem.zeroes(Self);
        pub const inf = vec(std.math.inf(T), std.math.inf(T), std.math.inf(T));

        pub inline fn vec(x: T, y: T, z: T) Self {
            return .{ .x = x, .y = y, .z = z };
        }

        pub inline fn arr(self: *Self) *[3]T {
            return @ptrCast(self);
        }
    };
}

pub fn vec3(x: anytype, y: @TypeOf(x), z: @TypeOf(x)) Vec3(@TypeOf(x)) {
    return .vec(x, y, z);
}

pub fn Vec4(comptime T: type) type {
    return extern struct {
        x: T,
        y: T,
        z: T,
        w: T,

        const Self = @This();
        pub const zero = std.mem.zeroes(Self);
        pub const inf = vec(std.math.inf(T), std.math.inf(T), std.math.inf(T), std.math.inf(T));

        pub inline fn vec(x: T, y: T, z: T, w: T) Self {
            return .{ .x = x, .y = y, .z = z, .w = w };
        }

        pub inline fn arr(self: *Self) *[4]T {
            return @ptrCast(self);
        }
    };
}

pub inline fn vec4(x: anytype, y: @TypeOf(x), z: @TypeOf(x), w: @TypeOf(x)) Vec4(@TypeOf(x)) {
    return .vec(x, y, z, w);
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

        pub inline fn axis(w: T, h: T) Self {
            return .{ .w = w, .h = h };
        }

        pub inline fn square(l: T) Self {
            return .{ .w = l, .h = l };
        }

        pub inline fn asVec(self: Self) Vec2(T) {
            return .{ .x = self.w, .y = self.h };
        }

        pub inline fn arr(self: *Self) *[2]T {
            return @ptrCast(self);
        }

        pub inline fn asArr(self: Self) [2]T {
            return @bitCast(self);
        }
    };
}

pub inline fn axis2(w: anytype, h: @TypeOf(w)) Axis2(@TypeOf(w)) {
    return .axis(w, h);
}

pub fn Range2(comptime T: type) type {
    return extern struct {
        p0: Vec2(T),
        p1: Vec2(T),

        const Self = @This();
        pub const zero = std.mem.zeroes(Self);
        pub const inf = range(.inf, .inf);

        pub inline fn range(p0: Vec2(T), p1: Vec2(T)) Self {
            return Self{ .p0 = p0, .p1 = p1 };
        }

        pub inline fn arr(self: *Self) *[2]Vec2(T) {
            return @ptrCast(self);
        }

        pub inline fn contains(self: Self, point: Vec2(T)) bool {
            return point.x > self.p0.x and
                point.x < self.p1.x and
                point.y > self.p0.y and
                point.y < self.p1.y;
        }

        pub fn topLeft(self: Self) Vec2(T) {
            return self.p0;
        }

        pub fn topRight(self: Self) Vec2(T) {
            return .vec(self.p1.x, self.p0.y);
        }

        pub fn bottomLeft(self: Self) Vec2(T) {
            return .vec(self.p0.x, self.p1.y);
        }

        pub fn bottomRight(self: Self) Vec2(T) {
            return self.p1;
        }
    };
}

pub inline fn range2(comptime T: type, p0: Vec2(T), p1: Vec2(T)) Range2(T) {
    return .range(p0, p1);
}

pub inline fn range2pts(x0: anytype, y0: @TypeOf(x0), x1: @TypeOf(x0), y1: @TypeOf(x0)) Range2(Vec2(@TypeOf(x0))) {
    return .range(Vec2(x0, y0), Vec2(x1, y1));
}
