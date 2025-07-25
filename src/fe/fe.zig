const builtin = @import("builtin");

const build_options = @import("build_options");

const std = @import("std");
const assert = std.debug.assert;
const log = std.log;

const tracy = @import("tracy");

const logFn = @import("logFn.zig");

const entryPoint = @import("entry_point.zig").entryPoint;

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

pub const panic = std.debug.FullPanic(panicimpl);

pub fn panicimpl(msg: []const u8, start_addr: ?usize) noreturn {
    log.err("panic: {s}", .{msg});
    logFn.writeStackTrace(start_addr);
    logFn.deinit();
    @breakpoint();
    std.process.exit(1);
}

pub fn main() !void {
    std.debug.attachSegfaultHandler();
    try logFn.init("out.log");
    defer logFn.deinit();

    //- allocator setup
    const root_allocator, const is_debug = gpa: {
        if (builtin.os.tag == .wasi) switch (builtin.mode) {
            .Debug, .ReleaseSafe => {
                debug_allocator.backing_allocator = std.heap.wasm_allocator;
                break :gpa .{ debug_allocator.allocator(), true };
            },
            .ReleaseFast, .ReleaseSmall => {
                break :gpa .{ std.heap.wasm_allocator, false };
            },
        };

        break :gpa switch (builtin.mode) {
            .Debug, .ReleaseSafe => .{ debug_allocator.allocator(), true },
            .ReleaseFast, .ReleaseSmall => .{ std.heap.smp_allocator, false },
        };
    };
    if (build_options.valgrind and builtin.link_libc)
        debug_allocator.backing_allocator = std.heap.c_allocator;
    defer if (is_debug) {
        _ = debug_allocator.deinit();
    };

    //- entry_point
    return entryPoint(root_allocator);
}
