const State = @This();

const std = @import("std");
const log = std.log.scoped(.@"cu.State");
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const assert = std.debug.assert;

const cu = @import("cu.zig");
const math = cu.math;
const Atom = cu.Atom;
const Color = cu.Color;
const MouseButton = cu.input.MouseButton;

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
atom_parent_stack: Stack(*Atom) = .empty, // arena
atom_stale_list: std.ArrayListUnmanaged(Atom.Key), // gpa

default_palette: Atom.pallete.Pallete = undefined,
default_font: FontId = undefined,

// scope_locals: std.StringArrayHashMapUnmanaged(*cu.ScopeLocalNode) = .empty,

next_atom_orphan: bool = false,

// All `ui_*` atoms are undefined unless `ui_built` is true.
// `ui_built` is true once `endFrame` is called once and stays true.
// The `ui_*` atoms are set most of the time, using `ui_built` is useful for
// when logic is needed that may or may not run until the first frame is built.
ui_built: bool = false,
ui_root: *Atom = undefined,
ui_ctx_menu_root: *Atom = undefined,
ui_tooltip_root: *Atom = undefined,

next_ctx_menu_open: bool = false,
ctx_menu_open: bool = false,
ctx_menu_key: Atom.Key = .nil,
next_ctx_menu_anchor_key: Atom.Key = .nil,
ctx_menu_anchor_offset: math.Point(f32) = .zero,

// currenly over (event consuming) atom
// (about to be interacting with this item)
hot_atom_key: Atom.Key = .nil,
// currently interacting atom for mouse button
active_atom_key: std.EnumArray(MouseButton, Atom.Key) = .initFill(.nil),

event_list: std.BoundedArray(cu.input.Event, 32) = .{},

graphics_info: GraphicsInfo,

window_size: math.Size(f32) = .zero,
mouse: math.Point(f32) = .nan,
start_drag_pos: math.Point(f32) = .nan,

fonthandles: std.ArrayListUnmanaged(FontHandle) = .empty,

press_history_key: std.EnumArray(
    MouseButton,
    cu.CircleBuffer(HistoySize, Atom.Key),
) = .initFill(.empty),
press_history_timestamp_us: std.EnumArray(
    MouseButton,
    cu.CircleBuffer(HistoySize, u64),
) = .initFill(.empty),

const HistoySize = 8;

pub const AtomPool = std.heap.MemoryPoolExtra(Atom, .{ .growable = true });
pub const AtomMap = std.ArrayHashMapUnmanaged(
    Atom.Key,
    *Atom,
    Atom.Key.KeyContext,
    false,
);

pub fn init(gpa: Allocator, callbacks: Callbacks) !*State {
    const state = try gpa.create(State);
    state.* = .{
        .callbacks = callbacks,

        .frame_previous_time = std.time.Instant.now() catch
            @panic("no std.time.Instant support"),

        .arena_allocator = std.heap.ArenaAllocator.init(gpa),
        .arena = undefined,
        .gpa = gpa,

        .atom_pool = undefined,
        .atom_stale_list = try std.ArrayListUnmanaged(Atom.Key)
            .initCapacity(gpa, 1024),

        .graphics_info = undefined,
    };
    state.arena = state.arena_allocator.allocator();

    state.atom_pool = .init(state.gpa);

    state.graphics_info = state.callbacks.getGraphicsInfo();

    return state;
}

pub fn deinit(state: *State) void {
    state.atom_map.deinit(state.gpa);

    state.arena_allocator.deinit();
    state.atom_pool.deinit();
    state.atom_stale_list.deinit(cu.state.gpa);

    state.fonthandles.deinit(cu.state.gpa);

    const gpa = state.gpa;
    gpa.destroy(state);
}

pub fn pushEvent(state: *State, kind: cu.input.EventKind) void {
    state.event_list.append(.{
        .kind = kind,
        .timestamp_us = @intCast(std.time.microTimestamp()),
        .consumed = false,
    }) catch {
        log.warn("event list overflow", .{});
    };
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
        measureText: *const fn (
            context: *anyopaque,
            text: []const u8,
            font: FontHandle,
        ) math.Size(f32),
        fontSize: *const fn (context: *anyopaque, font: FontHandle) f32,
        getGraphicsInfo: *const fn (context: *anyopaque) GraphicsInfo,
    };

    pub fn measureText(
        self: *Callbacks,
        text: []const u8,
        font: FontHandle,
    ) math.Size(f32) {
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

pub const GraphicsInfo = struct {
    double_click_time_us: u64,
    // caret_blink_time_ns: u64,
    // default_refresh_rate: f32,
    cursor_size_px: f32,
};

pub const FontHandle = *anyopaque;
pub const FontId = enum(u32) { _ };
