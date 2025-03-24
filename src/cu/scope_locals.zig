const std = @import("std");
const assert = std.debug.assert;

const cu = @import("cu.zig");

pub const ScopeLocalNode = struct {
    ptr: *const anyopaque,
    prev: ?*ScopeLocalNode = null,
};

pub const ScopeLocalHandle = struct {
    name: []const u8,

    pub inline fn pop(self: ScopeLocalHandle) void {
        const node = cu.state.scope_locals.get(self.name) orelse unreachable;

        if (node.prev) |prev| {
            node.ptr = prev.ptr;
            node.prev = null;
        } else {
            assert(cu.state.scope_locals.swapRemove(self.name));
        }
    }
};

pub fn pushScopeLocal(comptime T: type, value: *const T) ScopeLocalHandle {
    const name = @typeName(T);

    if (cu.state.scope_locals.get(name)) |node| {
        const old_ptr = node.ptr;
        const prev = cu.state.alloc_temp.create(ScopeLocalNode) catch @panic("oom");
        prev.* = .{ .ptr = old_ptr };
        node.prev = prev;
        node.ptr = @alignCast(@ptrCast(value));
    } else {
        const node = cu.state.alloc_temp.create(ScopeLocalNode) catch @panic("oom");
        node.* = .{ .ptr = @alignCast(@ptrCast(value)) };

        cu.state.scope_locals.put(cu.state.alloc_temp, name, node) catch @panic("oom");
    }

    return .{ .name = name };
}

pub fn getScopeLocal(comptime T: type) *const T {
    const name = @typeName(T);
    const node = cu.state.scope_locals.get(name) orelse @panic("not such scope local");
    return @alignCast(@ptrCast(node.ptr));
}
