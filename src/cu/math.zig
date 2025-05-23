const std = @import("std");
const mem = std.mem;
const math = std.math;

const cu = @import("cu.zig");

pub fn Point(comptime T: type) type {
    return extern struct {
        x: T,
        y: T,

        const Self = @This();
        pub const zero = mem.zeroes(Self);
        pub const inf = splat(math.inf(T));
        pub const nan = splat(math.nan(T));

        pub inline fn point(x: T, y: T) Self {
            return .{ .x = x, .y = y };
        }

        pub inline fn splat(v: T) Self {
            return .point(v, v);
        }

        pub inline fn fromSize(sz: Size(T)) Self {
            return .point(sz.width, sz.height);
        }

        pub inline fn intoSize(self: Self) Size(T) {
            return .size(self.x, self.y);
        }

        pub inline fn arr(self: *Self) *[2]T {
            return @ptrCast(self);
        }

        pub inline fn add(self: Self, other: Self) Self {
            return .point(self.x + other.x, self.y + other.y);
        }

        pub inline fn sub(self: Self, other: Self) Self {
            return .point(self.x - other.x, self.y - other.y);
        }

        pub inline fn pointExpSmoothBare(
            value: Self,
            target: Self,
            speed: anytype,
            dt: anytype,
        ) Self {
            return .point(
                expSmoothBare(value.x, target.x, speed, dt),
                expSmoothBare(value.y, target.y, speed, dt),
            );
        }

        pub inline fn pointExpSmooth(value: Self, target: Self) Self {
            return .point(
                expSmooth(value.x, target.x),
                expSmooth(value.y, target.y),
            );
        }

        pub inline fn intCast(self: Self, comptime NT: type) Point(NT) {
            return .point(
                @intCast(self.x),
                @intCast(self.y),
            );
        }

        pub inline fn floatCast(self: Self, comptime NT: type) Point(NT) {
            return .point(
                @floatCast(self.x),
                @floatCast(self.y),
            );
        }

        pub inline fn floatFromInt(self: Self, comptime NT: type) Point(NT) {
            return .point(@floatFromInt(self.x), @floatFromInt(self.y));
        }

        pub inline fn intFromFloat(self: Self, comptime NT: type) Point(NT) {
            return .point(@intFromFloat(self.x), @intFromFloat(self.y));
        }

        pub inline fn floor(self: Self) Self {
            return .point(@floor(self.x), @floor(self.y));
        }

        pub inline fn round(self: Self) Self {
            return .point(@round(self.x), @round(self.y));
        }

        pub fn format(
            self: Self,
            comptime fmt: []const u8,
            options: std.fmt.FormatOptions,
            writer: anytype,
        ) !void {
            _ = options;
            try writer.print(
                "Point({s}){{ {" ++ fmt ++ "}, {" ++ fmt ++ "} }}",
                .{ @typeName(T), self.x, self.y },
            );
        }
    };
}

pub inline fn point(x: anytype, y: @TypeOf(x)) Point(@TypeOf(x)) {
    return .point(x, y);
}

pub const Dim2D = enum(u2) {
    none = std.math.maxInt(u2),

    x = 0,
    y,

    pub const width = Dim2D.x;
    pub const height = Dim2D.y;

    pub const array = [2]Dim2D{ .x, .y };
};

pub fn Size(comptime T: type) type {
    return extern struct {
        width: T,
        height: T,

        const Self = @This();
        pub const zero = mem.zeroes(Self);
        pub const inf = splat(std.math.inf(T));
        pub const nan = splat(std.math.nan(T));

        pub inline fn size(width: T, height: T) Self {
            return .{ .width = width, .height = height };
        }

        pub inline fn splat(v: T) Self {
            return .size(v, v);
        }

        pub inline fn square(len: T) Self {
            return splat(len);
        }

        pub inline fn fromPoint(p: Point(T)) Self {
            return .size(p.x, p.y);
        }

        pub inline fn intoPoint(self: Self) Point(T) {
            return .point(self.width, self.height);
        }

        pub fn arr(self: *Self) *[2]T {
            return @ptrCast(self);
        }

        pub fn intoArr(self: Self) [2]T {
            return @bitCast(self);
        }

        pub inline fn intoPxPrefSize(self: Self) Size(cu.Atom.PrefSize) {
            return .size(.px(self.width), .px(self.height));
        }

        pub inline fn intCast(self: Self, comptime NT: type) Size(NT) {
            return .size(@intCast(self.width), @intCast(self.height));
        }

        pub inline fn floatFromInt(self: Self, comptime NT: type) Size(NT) {
            return .size(@floatFromInt(self.width), @floatFromInt(self.height));
        }

        pub fn format(
            self: *const Self,
            comptime fmt: []const u8,
            options: std.fmt.FormatOptions,
            writer: anytype,
        ) !void {
            _ = options;
            try writer.print(
                "Size({s}){{ {" ++ fmt ++ "}x{" ++ fmt ++ "} }}",
                .{ @typeName(T), self.width, self.height },
            );
        }
    };
}

pub inline fn size(
    width: anytype,
    height: @TypeOf(width),
) Size(@TypeOf(width)) {
    return .size(width, height);
}

pub fn Bounds(comptime T: type) type {
    return extern struct {
        origin: Point(T),
        size: Size(T),

        const Self = @This();

        pub const zero = mem.zeroes(Self);

        pub inline fn bounds(origin: Point(T), sz: Size(T)) Self {
            return .{ .origin = origin, .size = sz };
        }

        pub inline fn fromRect(rct: Rect(T)) Self {
            return .bounds(rct.p0, rct.size());
        }

        pub inline fn intCast(self: Self, comptime NT: type) Bounds(NT) {
            return .{
                .origin = self.origin.intCast(NT),
                .size = self.size.intCast(NT),
            };
        }

        pub inline fn floatFromInt(self: Self, comptime NT: type) Bounds(NT) {
            return .{
                .origin = self.origin.floatFromInt(NT),
                .size = self.size.floatFromInt(NT),
            };
        }

        pub fn format(
            self: *const Self,
            comptime fmt: []const u8,
            options: std.fmt.FormatOptions,
            writer: anytype,
        ) !void {
            _ = options;
            try writer.print(
                "Bounds({s}){{ {" ++ fmt ++ "}, {" ++ fmt ++ "} }}",
                .{ @typeName(T), self.origin, self.size },
            );
        }
    };
}

pub fn bounds(comptime T: type, origin: Point(T), sz: Size(T)) Bounds(T) {
    return .bounds(origin, sz);
}

pub fn Rect(comptime T: type) type {
    return extern struct {
        p0: Point(T),
        p1: Point(T),

        const Self = @This();
        pub const zero = mem.zeroes(Self);
        pub const inf = splat(.inf);
        pub const nan = splat(.nan);

        pub inline fn rect(p0: Point(T), p1: Point(T)) Self {
            return .{ .p0 = p0, .p1 = p1 };
        }

        pub inline fn rectpts(x0: T, y0: T, x1: T, y1: T) Self {
            return .rect(.point(x0, y0), .point(x1, y1));
        }

        pub inline fn splat(v: T) Self {
            return .rect(.splat(v), splat(v));
        }

        pub inline fn fromBounds(bnds: Bounds(T)) Self {
            return .rect(
                bnds.origin,
                .point(
                    bnds.origin.x + bnds.size.width,
                    bnds.origin.y + bnds.size.height,
                ),
            );
        }

        pub inline fn intoBounds(self: Self) Bounds(T) {
            return .bounds(
                self.p0,
                self.size(),
            );
        }

        pub inline fn intCast(self: Self, comptime NT: type) Rect(NT) {
            return .rect(self.p0.intCast(NT), self.p1.intCast(NT));
        }

        pub inline fn floatFromInt(self: Self, comptime NT: type) Rect(NT) {
            return .rect(self.p0.floatFromInt(NT), self.p1.floatFromInt(NT));
        }

        pub inline fn intFromFloat(self: Self, comptime NT: type) Rect(NT) {
            return .rect(self.p0.intFromFloat(NT), self.p1.intFromFloat(NT));
        }

        pub inline fn round(self: Self) Self {
            return .rect(self.p0.round(), self.p1.round());
        }

        pub inline fn arr(self: *Self) *[4]T {
            return @ptrCast(self);
        }

        pub inline fn origin(self: Self) Point(T) {
            return self.p0;
        }

        pub inline fn topLeft(self: Self) Point(T) {
            return self.p0;
        }

        pub inline fn topRight(self: Self) Point(T) {
            return .point(self.p1.x, self.p0.y);
        }

        pub inline fn bottomLeft(self: Self) Point(T) {
            return .point(self.p0.x, self.p1.y);
        }

        pub inline fn bottomRight(self: Self) Point(T) {
            return self.p1;
        }

        pub inline fn size(self: Self) Size(T) {
            return .size(self.width(), self.height());
        }

        pub inline fn width(self: Self) T {
            return self.p1.x - self.p0.x;
        }

        pub inline fn height(self: Self) T {
            return self.p1.y - self.p0.y;
        }

        pub inline fn contains(self: Self, pt: Point(T)) bool {
            return pt.x > self.p0.x and
                pt.x < self.p1.x and
                pt.y > self.p0.y and
                pt.y < self.p1.y;
        }

        pub inline fn intersect(a: Self, b: Self) Self {
            return .rectpts(
                @max(a.p0.x, b.p0.x),
                @max(a.p0.y, b.p0.y),
                @min(a.p1.x, b.p1.x),
                @min(a.p1.y, b.p1.y),
            );
        }

        pub fn format(
            self: *const Self,
            comptime fmt: []const u8,
            options: std.fmt.FormatOptions,
            writer: anytype,
        ) !void {
            _ = options;
            try writer.print(
                "Rect({s}){{ {" ++ fmt ++ "}x{" ++ fmt ++ "} }}",
                .{ @typeName(T), self.p0, self.p1 },
            );
        }
    };
}

pub inline fn rect(comptime T: type, p0: Point(T), p1: Point(T)) Rect(T) {
    return .rect(p0, p1);
}

pub inline fn rect2pts(
    x0: anytype,
    y0: @TypeOf(x0),
    x1: @TypeOf(x0),
    y1: @TypeOf(x0),
) Rect(@TypeOf(x0)) {
    return .rectpts(x0, y0, x1, y1);
}

pub const RgbaF32 = extern struct {
    r: f32,
    g: f32,
    b: f32,
    a: f32,

    pub fn hexRgba(hex: u32) RgbaF32 {
        const r: u8 = @truncate(hex >> 24);
        const g: u8 = @truncate(hex >> 16);
        const b: u8 = @truncate(hex >> 8);
        const a: u8 = @truncate(hex);

        return .{
            .r = @as(f32, @floatFromInt(r)) / 255,
            .g = @as(f32, @floatFromInt(g)) / 255,
            .b = @as(f32, @floatFromInt(b)) / 255,
            .a = @as(f32, @floatFromInt(a)) / 255,
        };
    }

    pub fn hexRgb(hex: u24) RgbaF32 {
        const r: u8 = @truncate(hex >> 16);
        const g: u8 = @truncate(hex >> 8);
        const b: u8 = @truncate(hex);

        return .{
            .r = @as(f32, @floatFromInt(r)) / 255,
            .g = @as(f32, @floatFromInt(g)) / 255,
            .b = @as(f32, @floatFromInt(b)) / 255,
            .a = 1,
        };
    }

    pub fn lerp(self: RgbaF32, other: RgbaF32, t: f32) RgbaF32 {
        return .{
            .r = math.lerp(self.r, other.r, t),
            .g = math.lerp(self.g, other.g, t),
            .b = math.lerp(self.b, other.b, t),
            .a = math.lerp(self.a, other.a, t),
        };
    }
};

pub const RgbaU8 = extern struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8,

    /// 0xRRGGBBAA
    pub fn asHex(self: RgbaU8) u32 {
        return mem.nativeToBig(u32, @bitCast(self));
    }

    pub fn rgba(r: u8, g: u8, b: u8, a: u8) RgbaU8 {
        return .{ .r = r, .g = g, .b = b, .a = a };
    }

    pub fn rgb(r: u8, g: u8, b: u8) RgbaU8 {
        return rgba(r, g, b, 255);
    }

    /// 0xRRGGBB
    pub fn hexRgb(hex: u24) RgbaU8 {
        return rgb(
            @truncate(hex >> 16),
            @truncate(hex >> 8),
            @truncate(hex),
        );
    }

    /// 0xRRGGBBAA
    pub fn hexRgba(hex: u32) RgbaU8 {
        return rgba(
            @truncate(hex >> 24),
            @truncate(hex >> 16),
            @truncate(hex >> 8),
            @truncate(hex),
        );
    }

    pub fn toRgbaF32(color: RgbaU8) RgbaF32 {
        return .{
            .r = @as(f32, @floatFromInt(color.r)) / 256,
            .g = @as(f32, @floatFromInt(color.g)) / 256,
            .b = @as(f32, @floatFromInt(color.b)) / 256,
            .a = @as(f32, @floatFromInt(color.a)) / 256,
        };
    }

    pub fn lerp(self: RgbaU8, other: RgbaU8, t: f32) RgbaU8 {
        return .{
            .r = lerpU8(self.r, other.r, t),
            .g = lerpU8(self.g, other.g, t),
            .b = lerpU8(self.b, other.b, t),
            .a = lerpU8(self.a, other.a, t),
        };
    }

    fn lerpU8(a: u8, b: u8, t: f32) u8 {
        return @intFromFloat(
            math.lerp(
                @as(f32, @floatFromInt(a)),
                @as(f32, @floatFromInt(b)),
                t,
            ),
        );
    }
};

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
pub inline fn expSmooth(
    value: anytype,
    target: anytype,
) @TypeOf(value, target) {
    return expSmoothBare(
        value,
        target,
        cu.state.animation_speed,
        cu.state.dt_s,
    );
}
