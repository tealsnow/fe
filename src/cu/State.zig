const State = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const assert = std.debug.assert;

const cu = @import("cu.zig");
const Atom = cu.Atom;
const Color = cu.Color;

current_build_index: u64 = 0,
build_atom_count: u64 = 0,

font_manager: cu.FontManager = .empty,
default_font: cu.FontId = undefined,

callbacks: Callbacks,

arena: std.heap.ArenaAllocator,
alloc_temp: Allocator,
alloc_persistent: Allocator, // currently only used for atom_map

atom_pool: AtomPool,
atom_map: AtomMap = .empty,
atom_parent_stack: GenericStack(*Atom, "atom_parent_stack", .temporary) = .empty,

palette_stack: GenericStack(*Atom.Palette, "palette_stack", .temporary) = .empty,

scope_locals: std.StringArrayHashMapUnmanaged(*cu.ScopeLocalNode) = .empty,

ui_root: *Atom = undefined, // undefined until `startBuild` is called

hot_atom_key: Atom.Key = .nil, // currenly over (event consuming) atom
active_atom_key: Atom.Key = .nil, // currently interacting atom

event_pool: EventPool,
event_node_pool: EventNodePool,
event_list: EventList = .{},

window_size: cu.Axis2(f32) = .zero,
mouse: cu.Vec2(f32) = .inf,

pub const MaxAtoms = 4000; // max 4000 atoms total
pub const AtomPool = std.heap.MemoryPoolExtra(Atom, .{ .growable = false });
pub const AtomMap = std.ArrayHashMapUnmanaged(
    Atom.Key,
    *Atom,
    Atom.Key.KeyContext,
    false,
);

pub const EventList = std.DoublyLinkedList(*cu.Event);
pub const EventNodePool = std.heap.MemoryPoolExtra(EventList.Node, .{ .growable = true });
pub const EventPool = std.heap.MemoryPoolExtra(cu.Event, .{ .growable = true });

pub fn init(
    self: *State,
    allocator: Allocator,
    callbacks: Callbacks,
) !void {
    self.* = .{
        .callbacks = callbacks,
        .arena = std.heap.ArenaAllocator.init(allocator),
        .alloc_temp = undefined,
        .alloc_persistent = allocator,
        .atom_pool = try State.AtomPool.initPreheated(allocator, State.MaxAtoms),
        .event_pool = State.EventPool.init(allocator),
        .event_node_pool = State.EventNodePool.init(allocator),
    };

    // workaround to ensure that the allocator vtable references the arena stored in gs, not in the stack
    self.alloc_temp = self.arena.allocator();
}

pub fn deinit(self: *State) void {
    self.font_manager.deinit();

    // state.parent_stack.deinit(state.alloc_temp);
    self.atom_map.deinit(self.alloc_persistent);

    self.arena.deinit();
    self.atom_pool.deinit();
    self.event_pool.deinit();
    self.event_node_pool.deinit();

    self.* = undefined;
}

pub inline fn allocAtom(self: *State) *Atom {
    return self.atom_pool.create() catch @panic("oom");
}

pub fn pushEvent(self: *State, event: cu.Event) void {
    const evt = self.event_pool.create() catch @panic("oom");
    evt.* = event;
    const node = self.event_node_pool.create() catch @panic("oom");
    node.* = .{ .data = evt };
    self.event_list.append(node);
}

pub const Callbacks = struct {
    context: *anyopaque,
    vtable: VTable,

    pub const VTable = struct {
        measureText: *const fn (context: *anyopaque, text: [:0]const u8, font: cu.FontHandle) cu.Axis2(f32),
    };

    pub fn measureText(self: *Callbacks, text: [:0]const u8, font: cu.FontHandle) cu.Axis2(f32) {
        return self.vtable.measureText(self.context, text, font);
    }
};

const AllocKind = enum {
    temporary,
    persistent,
};

fn GenericStack(
    comptime T: type,
    comptime field_name: []const u8,
    comptime alloc_kind: AllocKind,
) type {
    return struct {
        const Self = @This();
        pub const empty = Self{};

        stack: std.ArrayListUnmanaged(T) = .empty,

        fn getAlloc(self: *Self) Allocator {
            const state: *State = @fieldParentPtr(field_name, self);
            return switch (alloc_kind) {
                .temporary => state.alloc_temp,
                .persistent => state.alloc_persistent,
            };
        }

        pub fn push(self: *Self, item: T) void {
            self.stack.append(self.getAlloc(), item) catch @panic("oom");
        }

        pub fn pop(self: *Self) ?T {
            return self.stack.pop();
        }

        pub fn top(self: *Self) ?T {
            return self.stack.getLastOrNull();
        }

        pub fn clearAndFree(self: *Self) void {
            self.stack.clearAndFree(self.getAlloc());
        }
    };
}
