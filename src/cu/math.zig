const std = @import("std");

const cu = @import("cu.zig");

pub fn Vec2(comptime T: type) type {
    return extern struct {
        x: T,
        y: T,

        const Self = @This();
        pub const zero = std.mem.zeroes(Self);
        pub const inf = splat(std.math.inf(T));
        pub const nan = splat(std.math.nan(T));

        pub inline fn vec(x: T, y: T) Self {
            return .{ .x = x, .y = y };
        }

        pub inline fn square(s: T) Self {
            return .splat(s);
        }

        pub inline fn splat(v: T) Self {
            return .vec(v, v);
        }

        pub inline fn intoAxis(self: Self) Axis2(T) {
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

        pub inline fn vecExpSmoothBare(value: Self, target: Self, speed: anytype, dt: anytype) Self {
            return .{
                .x = expSmoothBare(value.x, target.x, speed, dt),
                .y = expSmoothBare(value.y, target.y, speed, dt),
            };
        }

        pub inline fn vecExpSmooth(value: Self, target: Self) Self {
            return .{
                .x = expSmooth(value.x, target.x),
                .y = expSmooth(value.y, target.y),
            };
        }

        pub fn format(self: *const Self, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
            _ = options;
            try writer.print("Vec2({s}){{ .x = {" ++ fmt ++ "}, .y = {" ++ fmt ++ "} }}", .{ @typeName(T), self.x, self.y });
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
        pub const inf = splat(std.math.inf(T));
        pub const nan = splat(std.math.nan(T));

        pub inline fn vec(x: T, y: T, z: T) Self {
            return .{ .x = x, .y = y, .z = z };
        }

        pub inline fn splat(v: T) Self {
            return .vec(v, v, v);
        }

        pub inline fn arr(self: *Self) *[3]T {
            return @ptrCast(self);
        }

        pub fn format(self: *const Self, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
            _ = options;
            try writer.print(
                "Vec3({s}){{ .x = {" ++ fmt ++ "}, .y = {" ++ fmt ++ "}, .z = {" ++ fmt ++ "} }}",
                .{ @typeName(T), self.x, self.y, self.z },
            );
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
        pub const inf = splat(std.math.inf(T));
        pub const nan = splat(std.math.nan(T));

        pub inline fn vec(x: T, y: T, z: T, w: T) Self {
            return .{ .x = x, .y = y, .z = z, .w = w };
        }

        pub inline fn splat(v: T) Self {
            return .vec(v, v, v, v);
        }

        pub inline fn arr(self: *Self) *[4]T {
            return @ptrCast(self);
        }

        pub fn format(self: *const Self, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
            _ = options;
            try writer.print(
                "Vec4({s}){{ .x = {" ++ fmt ++ "}, .y = {" ++ fmt ++ "}, .z = {" ++ fmt ++ "}, .w = {" ++ fmt ++ "} }}",
                .{ @typeName(T), self.x, self.y, self.z, self.w },
            );
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
        pub const inf = splat(std.math.inf(T));
        pub const nan = splat(std.math.nan(T));

        pub const Kind = enum(u2) {
            none = std.math.maxInt(u2),
            x = 0,
            y,

            pub const w = Kind.x;
            pub const h = Kind.y;

            pub const array = [2]Kind{ .x, .y };
        };

        pub inline fn axis(w: T, h: T) Self {
            return .{ .w = w, .h = h };
        }

        pub inline fn splat(v: T) Self {
            return axis(v, v);
        }

        pub inline fn square(l: T) Self {
            return splat(l);
        }

        pub inline fn arr(self: *Self) *[2]T {
            return @ptrCast(self);
        }

        pub inline fn intoVec(self: Self) Vec2(T) {
            return .{ .x = self.w, .y = self.h };
        }

        pub inline fn intoArr(self: Self) [2]T {
            return @bitCast(self);
        }

        pub inline fn intoPxPrefSize(self: Self) Axis2(cu.Atom.PrefSize) {
            return .axis(.px(self.w), .px(self.h));
        }

        pub fn format(self: *const Self, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
            _ = options;
            try writer.print("Axis2({s}){{ .w = {" ++ fmt ++ "}, .h = {" ++ fmt ++ "} }}", .{ @typeName(T), self.w, self.h });
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

        pub inline fn rangepts(x0: T, y0: T, x1: T, y1: T) Self {
            return .range(.vec(x0, y0), .vec(x1, y1));
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

        pub fn intersect(a: Self, b: Self) Self {
            return .rangepts(
                @max(a.p0.x, b.p0.x),
                @max(a.p0.y, b.p0.y),
                @min(a.p1.x, b.p1.x),
                @min(a.p1.y, b.p1.y),
            );
        }

        pub fn format(self: *const Self, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
            _ = options;
            try writer.print(
                "Range2({s}){{ .p0 = {" ++ fmt ++ "}, .p1 = {" ++ fmt ++ "} }}",
                .{ @typeName(T), self.p0, self.p1 },
            );
        }
    };
}

pub inline fn range2(comptime T: type, p0: Vec2(T), p1: Vec2(T)) Range2(T) {
    return .range(p0, p1);
}

pub inline fn range2pts(
    x0: anytype,
    y0: @TypeOf(x0),
    x1: @TypeOf(x0),
    y1: @TypeOf(x0),
) Range2(@TypeOf(x0)) {
    return .rangepts(x0, y0, x1, y1);
}

/// usage (during frame): `value = expSmoothBare(value, target, speed, dt)`
pub inline fn expSmoothBare(
    value: anytype,
    target: anytype,
    speed: anytype,
    dt: anytype,
) @TypeOf(value, target, speed, dt) {
    return value + (target - value) * (1 - @exp(-speed * dt));
}

/// usage (during frame): `value = expSmooth(value, target)`
pub inline fn expSmooth(value: anytype, target: anytype) @TypeOf(value, target) {
    return expSmoothBare(value, target, cu.state.animation_speed, cu.state.dt_s);
}
