pub fn Point(comptime T: type) type {
    return extern struct {
        x: T,
        y: T,

        const Self = @This();

        pub fn point(x: T, y: T) Self {
            return .{ .x = x, .y = y };
        }

        pub fn intCast(self: Self, comptime NT: type) Point(NT) {
            return .{
                .x = @intCast(self.x),
                .y = @intCast(self.y),
            };
        }

        pub fn floatFromInt(self: Self, comptime NT: type) Point(NT) {
            return .{
                .x = @floatFromInt(self.x),
                .y = @floatFromInt(self.y),
            };
        }
    };
}

pub fn Size(comptime T: type) type {
    return extern struct {
        width: T,
        height: T,

        const Self = @This();

        pub fn size(width: T, height: T) Self {
            return .{ .width = width, .height = height };
        }

        pub fn intCast(self: Self, comptime NT: type) Size(NT) {
            return @bitCast(@as(Point(T), @bitCast(self)).intCast(NT));
        }

        pub fn floatFromInt(self: Self, comptime NT: type) Size(NT) {
            return @bitCast(@as(Point(T), @bitCast(self)).floatFromInt(NT));
        }
    };
}

pub fn Bounds(comptime T: type) type {
    return extern struct {
        origin: Point(T),
        size: Size(T),

        const Self = @This();

        pub fn bounds(origin: Point(T), size: Size(T)) Self {
            return .{ .origin = origin, .size = size };
        }

        pub fn intCast(self: Self, comptime NT: type) Bounds(NT) {
            return .{
                .origin = self.origin.intCast(NT),
                .size = self.size.intCast(NT),
            };
        }

        pub fn floatFromInt(self: Self, comptime NT: type) Bounds(NT) {
            return .{
                .origin = self.origin.floatFromInt(NT),
                .size = self.size.floatFromInt(NT),
            };
        }
    };
}

pub fn Rect(comptime T: type) type {
    return extern struct {
        p0: Point(T),
        p1: Point(T),

        const Self = @This();

        pub fn rect(p0: Point(T), p1: Point(T)) Self {
            return .{ .p0 = p0, .p1 = p1 };
        }

        pub fn intCast(self: Self, comptime NT: type) Rect(NT) {
            return .{
                .p0 = self.p0.intCast(NT),
                .p1 = self.p1.intCast(NT),
            };
        }

        pub fn floatFromInt(self: Self, comptime NT: type) Rect(NT) {
            return .{
                .p0 = self.p0.floatFromInt(NT),
                .p1 = self.p1.floatFromInt(NT),
            };
        }
    };
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
};
