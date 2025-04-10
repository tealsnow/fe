// @TODO:
//   @[ ]: disabled state for atoms
//   @[ ]: pre-reserve mmaped memory for allocators
//   @[ ]: Migrate to github issue tracker for all of these
//   @[ ]: investigate using gtk for windowing and events
//   @[ ]: tooltips/dropdowns - general popups
//   @[ ]: focus behaviour
//   @[ ]: texture/image rendering
//   @[ ]: migrate to wgpu rendering
//     harfbuzz for shaping
//     freetype(SDF?) for rastering, have to implement atlas packing
//     icu for layout
//   @[ ]: scrolling
//     @[x]: overflow
//     @[x]: clip
//     @[ ]: builder support
//       @[ ]: event handling
//   @[ ]: better rendering
//     @[x]: text alignment
//     @[x]: backgrounds
//     @[x]: borders
//     @[x]: clipping
//     @[ ]: drop shadow
//     @[ ]: truncate text with ellipses
//     @[ ]: rounding
//   @[x]: floating
//   @[x]: text padding
//   @[x]: rename general purpose allocator instances to gpa,
//     this is aligned with zig's std and is more convienient
//   @[x]: plugins: pass guest function to host to call
//   @[x]: Intergrate tracing with tracy
//   @[x]: toggle switch component
//   @[x]: animations

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
        // .{ .scope = .@"wgpu renderer", .level = .debug },
        .{ .scope = .@"wgpu renderer", .level = .warn },
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
        .glfw => @import("glfw_entry.zig").entry,
        .wayland => @import("wayland_entry.zig").entry,
    };

    try entry(gpa);
}
