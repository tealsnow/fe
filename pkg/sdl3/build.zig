const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    _ = b.addModule("sdl3", .{
        .root_source_file = b.path("sdl3.zig"),
        .target = target,
        .optimize = optimize,
    });
}
