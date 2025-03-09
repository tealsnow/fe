const std = @import("std");
const math = std.math;

const cu = @import("cu.zig");

pub const Color = extern struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8,

    /// 0xRRGGBBAA
    pub fn asHex(self: Color) u32 {
        return std.mem.nativeToBig(u32, @bitCast(self));
    }

    pub fn rgba(r: u8, g: u8, b: u8, a: u8) Color {
        return .{ .r = r, .g = g, .b = b, .a = a };
    }

    pub fn rgb(r: u8, g: u8, b: u8) Color {
        return rgba(r, g, b, 255);
    }

    /// 0xRRGGBB
    pub fn hexRgb(hex: u24) Color {
        return rgb(
            @truncate(hex >> 16),
            @truncate(hex >> 8),
            @truncate(hex),
        );
    }

    /// 0xRRGGBBAA
    pub fn hexRgba(hex: u32) Color {
        return rgba(
            @truncate(hex >> 24),
            @truncate(hex >> 16),
            @truncate(hex >> 8),
            @truncate(hex),
        );
    }

    pub fn vec3f32(vec3: cu.Vec3(f32)) Color {
        return rgba(
            @intFromFloat(vec3.x * 255),
            @intFromFloat(vec3.y * 255),
            @intFromFloat(vec3.z * 255),
            255,
        );
    }

    pub fn vec4f32(vec4: cu.Vec4(f32)) Color {
        return rgba(
            @intFromFloat(vec4.x * 255),
            @intFromFloat(vec4.y * 255),
            @intFromFloat(vec4.z * 255),
            @intFromFloat(vec4.w * 255),
        );
    }
};
