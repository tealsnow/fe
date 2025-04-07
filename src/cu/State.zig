const State = @This();

const std = @import("std");
const log = std.log.scoped(.@"cu::State");
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const assert = std.debug.assert;

const cu = @import("cu.zig");
const Atom = cu.Atom;
const Color = cu.Color;
const MouseButton = cu.MouseButton;

current_build_index: u64 = 0,
build_atom_count: u64 = 0,

frame_previous_time: std.time.Instant,
dt_s: f32 = 0,

animation_speed: f32 = 40,

callbacks: Callbacks,

arena_allocator: std.heap.ArenaAllocator,
arena: Allocator,
gpa: Allocator,

atom_pool: AtomPool,
atom_map: AtomMap = .empty,
atom_parent_stack: Stack(*Atom) = .empty,

default_palette: Atom.Palette = undefined,
default_font: FontId = undefined,

stack_pref_size: OnceStack(cu.Axis2(Atom.PrefSize)) = .empty,
stack_font: OnceStack(FontId) = .empty,
stack_palette: OnceStack(Atom.Palette) = .empty,
stack_layout_axis: OnceStack(Atom.LayoutAxis) = .empty,
stack_flags: OnceStack(Atom.Flags) = .empty,
stack_text_align: OnceStack(cu.Axis2(Atom.TextAlignment)) = .empty,

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

active_atom_key: [MouseButton.array.len]Atom.Key = @splat(.nil), // currently interacting atom for mouse button
hot_atom_key: Atom.Key = .nil, // currenly over (event consuming) atom

event_pool: EventPool,
event_node_pool: EventNodePool,
event_list: EventList = .{},

graphics_info: GraphicsInfo,

window_size: cu.Axis2(f32) = .zero,
mouse: cu.Vec2(f32) = .nan,
start_drag_pos: cu.Vec2(f32) = .nan,

fonthandles: std.ArrayListUnmanaged(FontHandle) = .empty,

press_history_key: [MouseButton.array.len]HistoryRingBuffer(Atom.Key, HistoySize) = @splat(.empty),
press_history_timestamp_us: [MouseButton.array.len]HistoryRingBuffer(u64, HistoySize) = @splat(.empty),

const HistoySize = 8;

pub const AtomPool = std.heap.MemoryPoolExtra(Atom, .{ .growable = true });
pub const AtomMap = std.ArrayHashMapUnmanaged(
    Atom.Key,
    *Atom,
    Atom.Key.KeyContext,
    false,
);

const EventList = std.DoublyLinkedList(*cu.Event);
const EventNodePool = std.heap.MemoryPoolExtra(EventList.Node, .{ .growable = true });
const EventPool = std.heap.MemoryPoolExtra(cu.Event, .{ .growable = true });

pub fn init(gpa: Allocator, callbacks: Callbacks) !*State {
    const state = try gpa.create(State);
    state.* = .{
        .callbacks = callbacks,

        .frame_previous_time = std.time.Instant.now() catch @panic("no std.time.Instant support"),

        .arena_allocator = std.heap.ArenaAllocator.init(gpa),
        .arena = undefined,
        .gpa = gpa,

        .atom_pool = undefined,

        .event_pool = undefined,
        .event_node_pool = undefined,

        .graphics_info = undefined,
    };
    state.arena = state.arena_allocator.allocator();

    state.atom_pool = .init(state.gpa);

    state.event_pool = .init(state.gpa);
    state.event_node_pool = .init(state.gpa);

    state.graphics_info = state.callbacks.getGraphicsInfo();

    return state;
}

pub fn deinit(state: *State) void {
    state.atom_map.deinit(state.gpa);

    state.arena_allocator.deinit();
    state.atom_pool.deinit();

    state.event_pool.deinit();
    state.event_node_pool.deinit();

    state.fonthandles.deinit(cu.state.gpa);

    const gpa = state.gpa;
    gpa.destroy(state);
}

pub fn pushEvent(state: *State, kind: cu.EventKind) void {
    const event = state.event_pool.create() catch @panic("oom");
    const node = state.event_node_pool.create() catch @panic("oom");
    event.* = .{
        .kind = kind,
        .timestamp_us = @intCast(std.time.microTimestamp()),
        .consumed = false,
    };
    node.* = .{ .data = event };
    state.event_list.append(node);
}

pub fn registerFont(state: *State, font: FontHandle) FontId {
    const id: FontId = @enumFromInt(state.fonthandles.items.len);
    state.fonthandles.append(state.gpa, font) catch @panic("oom");
    return id;
}

pub fn getFont(state: *const State, id: FontId) FontHandle {
    return state.fonthandles.items[@intFromEnum(id)];
}

pub const Callbacks = struct {
    context: *anyopaque,
    vtable: VTable,

    pub const VTable = struct {
        measureText: *const fn (context: *anyopaque, text: []const u8, font: FontHandle) cu.Axis2(f32),
        fontSize: *const fn (context: *anyopaque, font: FontHandle) f32,
        getGraphicsInfo: *const fn (context: *anyopaque) GraphicsInfo,
    };

    pub fn measureText(self: *Callbacks, text: []const u8, font: FontHandle) cu.Axis2(f32) {
        return self.vtable.measureText(self.context, text, font);
    }

    pub fn fontSize(self: *Callbacks, font: FontHandle) f32 {
        return self.vtable.fontSize(self.context, font);
    }

    pub fn getGraphicsInfo(self: *Callbacks) GraphicsInfo {
        return self.vtable.getGraphicsInfo(self.context);
    }
};

pub fn Stack(comptime T: type) type {
    return struct {
        const Self = @This();

        list: std.ArrayListUnmanaged(T),

        pub const empty = Self{ .list = .empty };

        pub fn push(self: *Self, allocator: Allocator, item: T) void {
            self.list.append(allocator, item) catch @panic("oom");
        }

        pub fn top(self: *Self) ?T {
            return self.list.getLastOrNull();
        }

        pub fn pop(self: *Self) ?T {
            return self.list.pop();
        }

        pub fn clearAndFree(self: *Self, allocator: Allocator) void {
            self.list.clearAndFree(allocator);
        }
    };
}

/// Allows items to put onto the stack that will be removed once they are read
pub fn OnceStack(comptime T: type) type {
    return struct {
        const Self = @This();

        pub const StackItem = struct {
            item: T,
            once: bool,
        };

        stack: std.MultiArrayList(StackItem),

        pub const empty = Self{ .stack = .empty };

        pub fn push(self: *Self, allocator: Allocator, item: T, once: bool) void {
            self.stack.append(allocator, .{ .once = once, .item = item }) catch @panic("oom");
        }

        pub fn top(self: *Self) ?T {
            if (self.stack.len == 0) {
                @branchHint(.unlikely);
                return null;
            }
            const elem = self.stack.get(self.stack.len - 1);
            if (elem.once)
                self.stack.len -= 1;
            return elem.item;
        }

        pub fn topNoPop(self: *Self) ?T {
            if (self.stack.len == 0) {
                @branchHint(.unlikely);
                return null;
            }
            const elem = self.stack.get(self.stack.len - 1);
            return elem.item;
        }

        pub fn pop(self: *Self) ?T {
            if (self.stack.pop()) |elem| {
                @branchHint(.likely);
                return elem.item;
            } else {
                @branchHint(.unlikely);
                return null;
            }
        }

        pub fn clearAndFree(self: *Self, allocator: Allocator) void {
            self.stack.clearAndFree(allocator);
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
            if (idx >= self.count) {
                @branchHint(.unlikely);
                return null;
            }

            const pos = (self.head + Size - 1 - idx) % Size;
            return self.buffer[pos];
        }

        pub fn slice(self: *Self) []Elem {
            return self.buffer[0..self.count];
        }
    };
}

pub const FontHandle = *anyopaque;
pub const FontId = enum(u32) { _ };
