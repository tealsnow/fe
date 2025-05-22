const builtin = @import("builtin");

const build_options = @import("build_options");

const std = @import("std");
const assert = std.debug.assert;
const log = std.log;

const tracy = @import("tracy");

const logFn = @import("logFn.zig");

pub const std_options = std.Options{
    .logFn = logFn.logFn,
    .log_level = @enumFromInt(@intFromEnum(build_options.log_level)),
    .log_scope_levels = &.{
        .{ .scope = .@"wayland.listeners", .level = .info },
        .{ .scope = .@"wayland.connection", .level = .info },
        .{ .scope = .WgpuRenderer, .level = .info },
    },
};

var debug_allocator = std.heap.DebugAllocator(.{
    // .never_unmap = true,
    // .retain_metadata = true,
    // .verbose_log = true,
    // .backing_allocator_zeroes = false,
}).init;

pub fn main() !void {
    log.info("starting fe", .{});

    if (tracy.isConnected())
        log.debug("tracing enabled", .{});

    // =-= allocator setup =-=
    const root_allocator, const is_debug = gpa: {
        if (builtin.os.tag == .wasi) break :gpa .{ std.heap.wasm_allocator, false };
        break :gpa switch (builtin.mode) {
            .Debug, .ReleaseSafe => .{ debug_allocator.allocator(), true },
            .ReleaseFast, .ReleaseSmall => .{ std.heap.smp_allocator, false },
        };
    };
    // if (is_debug and builtin.link_libc)
    //     debug_allocator.backing_allocator = std.heap.c_allocator;
    defer if (is_debug) {
        _ = debug_allocator.deinit();
    };

    var tracing_allocator = tracy.TracingAllocator.init(root_allocator);
    const gpa = tracing_allocator.allocator();

    const entry = switch (build_options.entry_point) {
        .sdl => @import("sdl_entry.zig").entry,
        .wayland => @import("wayland_entry.zig").entry,
    };

    try entry(gpa);
}
