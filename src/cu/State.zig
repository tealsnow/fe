const State = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const assert = std.debug.assert;

const cu = @import("cu.zig");
const Atom = cu.Atom;
const Color = cu.Color;
const MouseButton = cu.MouseButton;

current_build_index: u64 = 0,
build_atom_count: u64 = 0,

font_manager: cu.FontManager = .empty,
callbacks: Callbacks,

arena_allocator: std.heap.ArenaAllocator,
arena: Allocator,
gpa: Allocator,

atom_pool: AtomPool,
atom_map: AtomMap = .empty,
atom_parent_stack: Stack(*Atom),

default_palette: Atom.Palette = undefined,
palette_stack: PoolStack(Atom.Palette),
default_font: cu.FontId = undefined,
font_stack: Stack(cu.FontId),

scope_locals: std.StringArrayHashMapUnmanaged(*cu.ScopeLocalNode) = .empty,

// All `ui_*` atoms are undefined unless `ui_built` is true.
// `ui_built` is true once `endFrame` is called once and stays true.
// The `ui_*` atoms are set most of the time, using `ui_built` is useful for
// when logic is needed that may or may not run until the first frame is built.
ui_built: bool = false,
ui_root: *Atom = undefined,
ui_ctx_menu_root: *Atom = undefined,
// ui_tooltip_root: *Atom = undefined,

ctx_menu_open: bool = false,
next_ctx_menu_open: bool = false,

active_atom_key: [MouseButton.array.len]Atom.Key = @splat(.nil), // currently interacting atom for button
hot_atom_key: Atom.Key = .nil, // currenly over (event consuming) atom

event_pool: EventPool,
event_node_pool: EventNodePool,
event_list: EventList = .{},

graphics_info: GraphicsInfo,

window_size: cu.Axis2(f32) = .zero,
mouse: cu.Vec2(f32) = .nan,
start_drag_pos: cu.Vec2(f32) = .nan,

press_history_timestamp_us: [MouseButton.array.len]HistoryRingBuffer(u64, HistoySize) = @splat(.empty),
press_history_key: [MouseButton.array.len]HistoryRingBuffer(Atom.Key, HistoySize) = @splat(.empty),

const HistoySize = 8;

// @FIXME: possibly allow the consumer to specify this?
pub const MaxAtoms = 4000;
pub const AtomPool = std.heap.MemoryPoolExtra(Atom, .{ .growable = true });
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
    state: *State,
    gpa: Allocator,
    callbacks: Callbacks,
) !void {
    state.* = .{
        .callbacks = callbacks,

        .arena_allocator = std.heap.ArenaAllocator.init(gpa),
        .arena = undefined,
        .gpa = gpa,

        .atom_pool = undefined,
        .atom_parent_stack = undefined,

        .palette_stack = undefined,
        .font_stack = undefined,

        .event_pool = undefined,
        .event_node_pool = undefined,

        .graphics_info = undefined,
    };

    // workaround to ensure that the allocator vtable references the arena stored in state, not in the stack
    state.arena = state.arena_allocator.allocator();

    // self.atom_pool = try .initPreheated(self.alloc_persistent, State.MaxAtoms);
    state.atom_pool = .init(state.gpa);
    state.atom_parent_stack = .init(state.arena);

    state.palette_stack = .init(state.arena, state.arena);
    state.font_stack = .init(state.arena);

    state.event_pool = .init(state.gpa);
    state.event_node_pool = .init(state.gpa);

    state.graphics_info = state.callbacks.getGraphicsInfo();
}

pub fn deinit(state: *State) void {
    state.font_manager.deinit();

    // state.parent_stack.deinit(state.alloc_temp);
    state.atom_map.deinit(state.gpa);

    state.arena_allocator.deinit();
    state.atom_pool.deinit();
    state.event_pool.deinit();
    state.event_node_pool.deinit();

    state.* = undefined;
}

pub fn pushEvent(state: *State, event: cu.Event) void {
    const evt = state.event_pool.create() catch @panic("oom");
    evt.* = event;
    evt.timestamp_us = @intCast(std.time.microTimestamp());
    const node = state.event_node_pool.create() catch @panic("oom");
    node.* = .{ .data = evt };
    state.event_list.append(node);
}

pub const Callbacks = struct {
    context: *anyopaque,
    vtable: VTable,

    pub const VTable = struct {
        measureText: *const fn (context: *anyopaque, text: []const u8, font: cu.FontHandle) cu.Axis2(f32),
        fontSize: *const fn (context: *anyopaque, font: cu.FontHandle) f32,
        getGraphicsInfo: *const fn (context: *anyopaque) GraphicsInfo,
    };

    pub fn measureText(self: *Callbacks, text: []const u8, font: cu.FontHandle) cu.Axis2(f32) {
        return self.vtable.measureText(self.context, text, font);
    }

    pub fn fontSize(self: *Callbacks, font: cu.FontHandle) f32 {
        return self.vtable.fontSize(self.context, font);
    }

    pub fn getGraphicsInfo(self: *Callbacks) GraphicsInfo {
        return self.vtable.getGraphicsInfo(self.context);
    }
};

fn Stack(comptime T: type) type {
    return struct {
        const Self = @This();
        pub const empty = Self{};

        stack: std.ArrayList(T),

        pub fn init(allocator: Allocator) Self {
            return .{ .stack = .init(allocator) };
        }

        pub fn push(self: *Self, item: T) void {
            self.stack.append(item) catch @panic("oom");
        }

        pub fn pop(self: *Self) ?T {
            return self.stack.pop();
        }

        pub fn top(self: *Self) ?T {
            return self.stack.getLastOrNull();
        }

        pub fn clearAndFree(self: *Self) void {
            self.stack.clearAndFree();
        }
    };
}

fn PoolStack(comptime T: type) type {
    return struct {
        const Self = @This();

        pool: std.heap.MemoryPoolExtra(T, .{}),
        stack: Stack(*T),

        pub fn init(pool_allocator: Allocator, stack_allocator: Allocator) Self {
            return .{
                .pool = .init(pool_allocator),
                .stack = .init(stack_allocator),
            };
        }

        pub fn push(self: *Self, item: T) void {
            const ptr = self.pool.create() catch @panic("oom");
            ptr.* = item;
            self.stack.push(ptr);
        }

        pub fn pop(self: *Self) ?*T {
            return self.stack.pop();
        }

        pub fn top(self: *Self) ?*T {
            return self.stack.top();
        }

        pub fn dupeTop(self: *Self) ?*T {
            const t = self.top() orelse return null;
            const dup = self.pool.create() catch @panic("oom");
            dup.* = t.*;
            return dup;
        }

        pub fn clearAndReset(self: *Self) void {
            self.stack.clearAndFree();
            _ = self.pool.reset(.free_all);
        }
    };
}

pub const GraphicsInfo = struct {
    double_click_time_us: u64,
    // caret_blink_time_ns: u64,
    // default_refresh_rate: f32,
};

pub fn HistoryRingBuffer(
    Elem: type,
    Size: usize,
) type {
    return struct {
        const Self = @This();

        buffer: [Size]Elem,
        head: usize,
        count: usize,

        pub const empty = Self{ .buffer = undefined, .head = 0, .count = 0 };

        pub fn push(self: *Self, value: Elem) void {
            self.buffer[self.head] = value;
            self.head = (self.head + 1) % Size;
            self.count = @min(self.count + 1, Size);
        }

        pub fn indexBack(self: Self, idx: usize) ?Elem {
            if (idx >= self.count) return null;

            const pos = (self.head + Size - 1 - idx) % Size;
            return self.buffer[pos];
        }

        pub fn slice(self: *Self) []Elem {
            return self.buffer[0..self.count];
        }
    };
}
