const State = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const assert = std.debug.assert;

const sdl = @import("../sdl/sdl.zig");

const cu = @import("cu.zig");
const Atom = cu.Atom;

current_build_index: u64 = 0,
build_atom_count: u64 = 0,

font: *sdl.ttf.Font,

arena: std.heap.ArenaAllocator,
alloc_temp: Allocator,
alloc_persistent: Allocator, // currently only used for atom_map

atom_pool: AtomPool,
atom_map: AtomMap = .empty,
parent_stack: ParentStack = .empty,

scope_locals: std.StringArrayHashMapUnmanaged(*cu.ScopeLocalNode) = .empty,

ui_root: *Atom = undefined, // undefined until `startBuild` is called

hot_atom_key: Atom.Key = .nil, // currenly over (event consuming) atom
active_atom_key: Atom.Key = .nil, // currently interacting atom

event_pool: EventPool,
event_node_pool: EventNodePool,
event_list: EventList = .{},

mouse: cu.Vec2(f32) = .inf,

pub const MaxAtoms = 4000; // max 4000 atoms total, not measured in memory

pub const AtomPool = std.heap.MemoryPoolExtra(Atom, .{ .growable = false });
pub const ParentStack = std.ArrayListUnmanaged(*Atom);
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
    font: *sdl.ttf.Font,
) !void {
    self.* = .{
        .font = font,
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

pub inline fn pushParent(self: *State, atom: *Atom) void {
    self.parent_stack.append(self.alloc_temp, atom) catch @panic("oom");
}

pub inline fn popParent(self: *State) ?*Atom {
    return self.parent_stack.pop();
}

pub inline fn currentParent(self: *State) ?*Atom {
    return self.parent_stack.getLastOrNull();
}

pub fn pushEvent(self: *State, event: cu.Event) void {
    const evt = self.event_pool.create() catch @panic("oom");
    evt.* = event;
    const node = self.event_node_pool.create() catch @panic("oom");
    node.* = .{ .data = evt };
    self.event_list.append(node);
}
