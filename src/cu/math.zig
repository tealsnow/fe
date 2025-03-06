const std = @import("std");

pub fn Vec2(comptime T: type) type {
    return extern union {
        xy: extern struct {
            x: T,
            y: T,
        },
        arr: [2]T,

        pub const zero = std.mem.zeroes(@This());
        pub const inf = vec2(T, std.math.inf(T), std.math.inf(T));
    };
}

pub fn vec2(comptime T: type, x: T, y: T) Vec2(T) {
    return .{ .arr = .{ x, y } };
}

// pub fn Vec2(comptime T: type) type {
//     return extern struct {
//         x: T,
//         y: T,

//         const Self = @This();

//         pub const zero = std.mem.zeroes(@This());
//         pub const inf = vec2(T, std.math.inf(T), std.math.inf(T));

//         pub inline fn arr(self: Self) [2]T {
//             return .{ self.x, self.y };
//         }
//     };
// }

// pub fn vec2(comptime T: type, x: T, y: T) Vec2(T) {
//     return .{ .x = x, .y = y };
// }

pub const AxisKind = enum(u2) {
    x = 0,
    y,
    none = std.math.maxInt(u2),

    pub const w = AxisKind.x;
    pub const h = AxisKind.y;

    pub const array = [2]AxisKind{ .x, .y };
};

pub fn Axis2(comptime T: type) type {
    return extern union {
        vec: extern struct {
            x: T,
            y: T,
        },
        sz: extern struct {
            w: T,
            h: T,
        },
        arr: [2]T,

        pub const zero = std.mem.zeroes(@This());
    };
}

pub fn axis2(comptime T: type, x: T, y: T) Axis2(T) {
    return .{ .arr = .{ x, y } };
}

pub fn Range2(comptime T: type) type {
    return extern union {
        minmax: extern struct {
            min: Vec2(T),
            max: Vec2(T),
        },
        pt: extern struct {
            p0: Vec2(T),
            p1: Vec2(T),
        },
        xy: extern struct {
            x0: T,
            y0: T,
            x1: T,
            y1: T,
        },
        arr: [2]Vec2(T),
        // parr: [4]T,
        // pmat: [2][2]T,

        pub const zero = std.mem.zeroes(@This());

        pub fn contains(self: @This(), vec: Vec2(T)) bool {
            return vec.xy.x > self.xy.x0 and
                vec.xy.x < self.xy.x1 and
                vec.xy.y > self.xy.y0 and
                vec.xy.y < self.xy.y1;
        }
    };
}

// pub fn range3(comptime T: type, p0: Vec2(T), p1: Vec2(T)) Range2(T) {
//     return .{ .arr = .{ p0, p1 } };
// }
