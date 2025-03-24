const std = @import("std");

pub const PluginSchema = @import("plugin-schema").PluginSchema;

var allocator = std.heap.wasm_allocator;
const allocator_log = std.log.scoped(.Allocator);

pub fn mkLogFn(
    comptime id: []const u8,
) fn (
    comptime message_level: std.log.Level,
    comptime scope: @TypeOf(.enum_literal),
    comptime format: []const u8,
    args: anytype,
) void {
    return struct {
        pub fn logFn(
            comptime message_level: std.log.Level,
            comptime scope: @TypeOf(.enum_literal),
            comptime format: []const u8,
            args: anytype,
        ) void {
            const scope_str = " [plugin] " ++ if (scope == .default) id else id ++ "::" ++ @tagName(scope);

            var buffer: [1024 * 4]u8 = undefined;
            const message = std.fmt.bufPrint(&buffer, format, args) catch return;

            hostLogFn(@intFromEnum(message_level), scope_str, scope_str.len, message.ptr, message.len);
        }
    }.logFn;
}

extern "fe" fn hostLogFn(
    level: usize,
    scope_ptr: [*]const u8,
    scope_len: usize,
    message_ptr: [*]const u8,
    message_len: usize,
) void;

export fn Allocator_alloc(len: usize, alignment_int: usize) ?[*]u8 {
    const alignment = std.mem.Alignment.fromByteUnits(alignment_int);
    allocator_log.debug("alloc(len: {d}, alignment: {s})", .{ len, @tagName(alignment) });
    const ret = allocator.rawAlloc(len, alignment, 0);
    allocator_log.debug(" -- return: {?*}", .{ret});
    return ret;
}

export fn Allocator_resize(memory_ptr: [*]u8, memory_len: usize, alignment_int: usize, new_len: usize) bool {
    const memory = memory_ptr[0..memory_len];
    const alignment = std.mem.Alignment.fromByteUnits(alignment_int);
    allocator_log.debug("resize(memory: {*}, alignment: {s}, new_len: {d})", .{ memory, @tagName(alignment), new_len });
    const ret = allocator.rawResize(memory, alignment, new_len, 0);
    allocator_log.debug(" -- return: {}", .{ret});
    return ret;
}

export fn Allocator_remap(memory_ptr: [*]u8, memory_len: usize, alignment_int: usize, new_len: usize) ?[*]u8 {
    const memory = memory_ptr[0..memory_len];
    const alignment = std.mem.Alignment.fromByteUnits(alignment_int);
    allocator_log.debug("remap(memory: {*}, alignment: {s}, new_len: {d})", .{ memory, @tagName(alignment), new_len });
    const ret = allocator.rawRemap(memory, alignment, new_len, 0);
    allocator_log.debug(" -- return: {?*}", .{ret});
    return ret;
}

export fn Allocator_free(memory_ptr: [*]u8, memory_len: usize, alignment_int: usize) void {
    const memory = memory_ptr[0..memory_len];
    const alignment = std.mem.Alignment.fromByteUnits(alignment_int);
    allocator_log.debug("free(memory: {*}, alignment: {s})", .{ memory, @tagName(alignment) });
    allocator.rawFree(memory, alignment, 0);
}
