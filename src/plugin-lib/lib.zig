const std = @import("std");

pub const PluginSchema = @import("plugin-schema").PluginSchema;

var allocator = std.heap.wasm_allocator;
const allocator_log = std.log.scoped(.Allocator);

// Mirrored in host and guest (this is guest) - with byte size changes.
//
// When proper mulivalue (multiple return values) support comes to zig we wont
// need this any more
pub fn PackedSlice(comptime T: type) type {
    const TypeInfo = @typeInfo(T);
    const ChildType, const is_const = switch (TypeInfo) {
        .pointer => |ptr| child: {
            if (ptr.size != .slice)
                @compileError("PackedSlice can only take slice");
            break :child .{ ptr.child, ptr.is_const };
        },
        else => @compileError("PackedSlice can only take slice"),
    };

    return packed struct(u64) {
        ptr: Ptr,
        len: u32,

        pub const Child = ChildType;
        pub const Ptr = if (is_const) [*]const ChildType else [*]ChildType; // 32 bits wide
        pub const Slice = T;

        const Self = @This();

        pub fn fromSlice(slice: Slice) Self {
            return .{
                .ptr = slice.ptr,
                .len = slice.len,
            };
        }

        pub fn toSlice(self: Self) Slice {
            return self.ptr[0..self.len];
        }
    };
}

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
            const scope_str = " [plugin] " ++ if (scope == .default) id else id ++ "." ++ @tagName(scope);

            var buffer: [1024 * 4]u8 = undefined;
            const message = std.fmt.bufPrint(&buffer, format, args) catch return;

            hostLogFn(@intFromEnum(message_level), .fromSlice(scope_str), .fromSlice(message));
        }
    }.logFn;
}

extern "fe" fn hostLogFn(
    level: usize,
    scope: PackedSlice([]const u8),
    message: PackedSlice([]const u8),
) void;

export fn Allocator_alloc(len: usize, alignment_int: usize) ?[*]u8 {
    const alignment = std.mem.Alignment.fromByteUnits(alignment_int);
    allocator_log.debug("alloc(len: {d}, alignment: {s})", .{ len, @tagName(alignment) });
    const ret = allocator.rawAlloc(len, alignment, 0);
    allocator_log.debug(" -- return: {?*}", .{ret});
    return ret;
}

export fn Allocator_resize(memory_packed: PackedSlice([]u8), alignment_int: usize, new_len: usize) bool {
    const memory = memory_packed.toSlice();
    const alignment = std.mem.Alignment.fromByteUnits(alignment_int);
    allocator_log.debug("resize(memory: {*}, alignment: {s}, new_len: {d})", .{ memory, @tagName(alignment), new_len });
    const ret = allocator.rawResize(memory, alignment, new_len, 0);
    allocator_log.debug(" -- return: {}", .{ret});
    return ret;
}

export fn Allocator_remap(memory_packed: PackedSlice([]u8), alignment_int: usize, new_len: usize) ?[*]u8 {
    const memory = memory_packed.toSlice();
    const alignment = std.mem.Alignment.fromByteUnits(alignment_int);
    allocator_log.debug("remap(memory: {*}, alignment: {s}, new_len: {d})", .{ memory, @tagName(alignment), new_len });
    const ret = allocator.rawRemap(memory, alignment, new_len, 0);
    allocator_log.debug(" -- return: {?*}", .{ret});
    return ret;
}

export fn Allocator_free(memory_packed: PackedSlice([]u8), alignment_int: usize) void {
    const memory = memory_packed.toSlice();
    const alignment = std.mem.Alignment.fromByteUnits(alignment_int);
    allocator_log.debug("free(memory: {*}, alignment: {s})", .{ memory, @tagName(alignment) });
    allocator.rawFree(memory, alignment, 0);
}
