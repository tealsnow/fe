const State = @This();

const std = @import("std");
const log = std.log.scoped(.@"cu.State");
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const assert = std.debug.assert;
const builder = @import("builder.zig");

const cu = @import("cu.zig");
const math = cu.math;
const Atom = cu.Atom;
const Color = cu.Color;
const MouseButton = cu.input.MouseButton;

current_build_index: u64 = 0,
build_atom_count: u64 = 0,

animation_speed: f32 = 40,

callbacks: Callbacks,

arena_allocator: std.heap.ArenaAllocator,
arena: Allocator,
gpa: Allocator,

atom_pool: AtomPool,
atom_map: AtomMap = .empty,
atom_parent_stack: Stack(*Atom) = .empty, // arena
atom_stale_list: std.ArrayListUnmanaged(Atom.Key), // gpa

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
pointer_pos: math.Point(f32) = .nan,
cursor_shape: ?CursorShape = null,
pointer_pos_start_drag: math.Point(f32) = .nan,
drag_data: []u8,

font_kind_map: FontKindMap,

press_history_key: std.EnumArray(
    MouseButton,
    cu.CircleBuffer(HistoySize, Atom.Key),
) = .initFill(.empty),
press_history_timestamp_us: std.EnumArray(
    MouseButton,
    cu.CircleBuffer(HistoySize, u64),
) = .initFill(.empty),

root_palette: Atom.Palette,
interaction_styles: builder.InteractionStyles,

const HistoySize = 8;

pub const AtomPool = std.heap.MemoryPoolExtra(Atom, .{ .growable = true });
pub const AtomMap = std.ArrayHashMapUnmanaged(
    Atom.Key,
    *Atom,
    Atom.Key.KeyContext,
    false,
);

pub const InitParams = struct {
    callbacks: Callbacks,
    font_kind_map: FontKindMap,

    interaction_styles: builder.InteractionStyles,
    root_palette: Atom.Palette,
};

pub fn init(gpa: Allocator, params: InitParams) !*State {
    const state = try gpa.create(State);
    state.* = .{
        .callbacks = params.callbacks,

        .font_kind_map = params.font_kind_map,

        .arena_allocator = std.heap.ArenaAllocator.init(gpa),
        .arena = undefined,
        .gpa = gpa,

        .atom_pool = undefined,
        .atom_stale_list = try std.ArrayListUnmanaged(Atom.Key)
            .initCapacity(gpa, 1024),

        .graphics_info = undefined,

        .drag_data = undefined,

        .interaction_styles = params.interaction_styles,
        .root_palette = params.root_palette,
    };
    state.arena = state.arena_allocator.allocator();

    state.atom_pool = .init(state.gpa);

    state.graphics_info = state.callbacks.getGraphicsInfo();

    state.drag_data = try gpa.alloc(u8, 1024);

    return state;
}

pub fn deinit(state: *State) void {
    cu.state = state;
    const gpa = state.gpa;

    state.atom_map.deinit(gpa);

    state.arena_allocator.deinit();
    state.atom_pool.deinit();
    state.atom_stale_list.deinit(gpa);

    gpa.free(state.drag_data);

    gpa.destroy(state);
}

pub fn select(state: *State) void {
    cu.state = state;
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

pub fn storeDragData(state: *State, ptr: anytype) void {
    const slice = std.mem.asBytes(ptr);
    assert(slice.len <= state.drag_data.len);
    @memcpy(state.drag_data[0..slice.len], slice);
}

pub fn getDragData(state: *State, comptime T: type) *T {
    return @ptrCast(@alignCast(state.drag_data));
}

pub fn dragDelta(state: *const State) math.Point(f32) {
    return state.pointer_pos.sub(state.pointer_pos_start_drag);
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
        lineHeight: *const fn (context: *anyopaque, font: FontHandle) f32,
        getGraphicsInfo: *const fn (context: *anyopaque) GraphicsInfo,
    };

    pub fn measureText(
        self: *Callbacks,
        text: []const u8,
        font: FontHandle,
    ) math.Size(f32) {
        return self.vtable.measureText(self.context, text, font);
    }

    pub fn lineHeight(self: *Callbacks, font: FontHandle) f32 {
        return self.vtable.lineHeight(self.context, font);
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

pub const FontHandle = *const anyopaque;

pub const FontKind = enum {
    body,
    label,
    button,
    mono,
};

pub const FontKindMap = std.EnumArray(FontKind, FontHandle);

pub const CursorShape = enum {
    default,
    context_menu,
    help,
    pointer,
    progress,
    wait,
    cell,
    crosshair,

    text,

    dnd_alias,
    dnd_copy,
    dnd_move,
    dnd_no_drop,
    dnd_not_allowed,
    dnd_grab,
    dnd_grabbing,

    resize_e,
    resize_n,
    resize_ne,
    resize_nw,
    resize_s,
    resize_se,
    resize_sw,
    resize_w,
    resize_ew,
    resize_ns,
    resize_nesw,
    resize_nwse,
    resize_col,
    resize_row,

    zoom_in,
    zoom_out,
};
