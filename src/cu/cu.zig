/// # Attribution
///
/// Much of the design of this it taken from a series of blogs on UI by
/// Ryan Fleury (https://rfleury.com/i/146446067/ui-programming-series)
/// with some parts taken from the implementation of the ui layer of raddebugger
/// (https://github.com/EpicGamesExt/raddebugger) (Copyright (c) 2024 Epic Games Tools)
///
const std = @import("std");
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const assert = std.debug.assert;

const fontconfig = @import("../fontconfig.zig");
const sdl = @import("../sdl/sdl.zig");

pub const layout = @import("layout.zig");

pub const GlobalState = struct {
    current_build_index: u64 = 0,
    build_atom_count: u64 = 0,

    input: InputState = .{},

    renderer: *sdl.Renderer,
    font: *sdl.ttf.Font,

    arena: std.heap.ArenaAllocator,
    alloc_temp: Allocator,
    alloc_persistent: Allocator, // currently only used for atom_map

    atom_pool: AtomPool,
    atom_map: AtomMap = .empty,
    parent_stack: ParentStack = .empty,

    scope_locals: std.StringArrayHashMapUnmanaged(*ScopeLocalNode) = .empty,

    ui_root: *Atom = undefined, // undefined until `startBuild` is called

    pub const MaxAtoms = 4000; // max 4000 atoms total, not measured in memory

    pub const AtomPool = std.heap.MemoryPoolExtra(Atom, .{ .growable = false });
    pub const ParentStack = std.ArrayListUnmanaged(*Atom);
    pub const AtomMap = std.ArrayHashMapUnmanaged(
        Key,
        *Atom,
        Key.KeyContext,
        false,
    );

    inline fn allocAtom(self: *GlobalState) *Atom {
        return self.atom_pool.create() catch @panic("oom");
    }

    inline fn pushParent(self: *GlobalState, atom: *Atom) void {
        self.parent_stack.append(self.alloc_temp, atom) catch @panic("oom");
    }

    inline fn popParent(self: *GlobalState) ?*Atom {
        return self.parent_stack.pop();
    }

    inline fn currentParent(self: *GlobalState) ?*Atom {
        return self.parent_stack.getLastOrNull();
    }
};

pub var state: GlobalState = undefined;

pub fn init(
    allocator: Allocator,
    renderer: *sdl.Renderer,
    font: *sdl.ttf.Font,
) !void {
    state = .{
        .renderer = renderer,
        .font = font,
        .arena = std.heap.ArenaAllocator.init(allocator),
        .alloc_temp = undefined,
        .alloc_persistent = allocator,
        .atom_pool = try GlobalState.AtomPool.initPreheated(allocator, GlobalState.MaxAtoms),
    };

    // workaround to ensure that the allocator vtable references the arena stored in gs, not in the stack
    state.alloc_temp = state.arena.allocator();
}

pub fn deinit() void {
    state.parent_stack.deinit(state.alloc_temp);
    state.atom_map.deinit(state.alloc_persistent);

    state.arena.deinit();
    state.atom_pool.deinit();
}

pub const InputState = struct {
    mouse_position: Vec2(f32) = Vec2(f32).Zero,

    // read as array with the length of the amount of mouse buttons
    // set all set to released by default
    mouse_buttons: [std.meta.fields(sdl.MouseButton).len - 1]sdl.KeyButtonState =
        [_]sdl.KeyButtonState{.released} ** (std.meta.fields(sdl.MouseButton).len - 1),
};

const ScopeLocalNode = struct {
    ptr: *const anyopaque,
    prev: ?*ScopeLocalNode = null,
};

pub const ScopeLocalHandle = struct {
    name: []const u8,

    pub inline fn pop(self: ScopeLocalHandle) void {
        const node = state.scope_locals.get(self.name) orelse unreachable;

        if (node.prev) |prev| {
            node.ptr = prev.ptr;
            node.prev = null;
        } else {
            assert(state.scope_locals.swapRemove(self.name));
        }
    }
};

pub fn pushScopeLocal(comptime T: type, value: *const T) ScopeLocalHandle {
    const name = @typeName(T);

    if (state.scope_locals.get(name)) |node| {
        const old_ptr = node.ptr;
        const prev = state.alloc_temp.create(ScopeLocalNode) catch @panic("oom");
        prev.* = .{ .ptr = old_ptr };
        node.prev = prev;
        node.ptr = @alignCast(@ptrCast(value));
    } else {
        const node = state.alloc_temp.create(ScopeLocalNode) catch @panic("oom");
        node.* = .{ .ptr = @alignCast(@ptrCast(value)) };

        state.scope_locals.put(state.alloc_temp, name, node) catch @panic("oom");
    }

    return .{ .name = name };
}

pub fn getScopeLocal(comptime T: type) *const T {
    const name = @typeName(T);

    const node = state.scope_locals.get(name) orelse @panic("not such scope local");

    return @alignCast(@ptrCast(node.ptr));
}

pub fn Vec2(comptime T: type) type {
    return extern union {
        xy: extern struct {
            x: T,
            y: T,
        },
        arr: [2]T,

        pub const Zero = std.mem.zeroes(@This());
    };
}

pub fn vec2(comptime T: type, x: T, y: T) Vec2(T) {
    return .{ .arr = .{ x, y } };
}

pub const AxisKind = enum(u2) {
    x = 0,
    y,
    none = std.math.maxInt(u2),

    pub const Array = [2]AxisKind{ .x, .y };
};

pub fn Axis2(comptime T: type) type {
    return extern union {
        vec: extern struct {
            x: T,
            y: T,
        },
        sz: extern struct {
            w: T,
            h: T,
        },
        arr: [2]T,

        pub const Zero = std.mem.zeroes(@This());
    };
}

pub fn axis2(comptime T: type, x: T, y: T) Axis2(T) {
    return .{ .arr = .{ x, y } };
}

pub fn Range2(comptime T: type) type {
    return extern union {
        minmax: extern struct {
            min: Vec2(T),
            max: Vec2(T),
        },
        pt: extern struct {
            p0: Vec2(T),
            p1: Vec2(T),
        },
        xy: extern struct {
            x0: T,
            y0: T,
            x1: T,
            y1: T,
        },
        arr: [2]Vec2(T),
        // parr: [4]T,
        // pmat: [2][2]T,

        pub const Zero = std.mem.zeroes(@This());

        pub fn contains(self: @This(), vec: Vec2(T)) bool {
            return vec.xy.x > self.xy.x0 and
                vec.xy.x < self.xy.x1 and
                vec.xy.y > self.xy.y0 and
                vec.xy.y < self.xy.y1;
        }
    };
}

// pub fn range2(comptime T: type, p0: Vec2(T), p1: Vec2(T)) Range2(T) {
//     return .{ .arr = .{ p0, p1 } };
// }

pub const SizeKind = enum(u8) {
    none,
    pixels, // value px
    percent_of_parent, // value %
    text_content,
    children_sum,
};

pub const Size = extern struct {
    kind: SizeKind = .none,
    /// pixels: px, percent_of_parent: %
    value: f32 = 0,
    /// what percent of final size do we refuse to give up
    strictness: f32 = 0,

    /// kind: percent_of_parent,
    /// value: 1,
    /// strictness: 0,
    pub const grow = percent_relaxed(1);

    /// kind: percent_of_parent,
    /// value: 1,
    /// strictness: 1,
    pub const full = percent(1);

    /// kind: children_sum
    pub const fit = Size{ .kind = .children_sum };

    /// kind: text_content
    pub const text = Size{ .kind = .text_content };

    /// kind: pixels,
    /// value: pxs,
    /// strictness: 1,
    pub fn px(pxs: f32) Size {
        return .{
            .kind = .pixels,
            .value = pxs,
            .strictness = 1,
        };
    }

    /// kind: pixels,
    /// value: px,
    /// strictness: 0,
    pub fn px_relaxed(pxs: f32) Size {
        return .{
            .kind = .pixels,
            .value = pxs,
            .strictness = 0,
        };
    }

    /// kind: percent_of_parent,
    /// value: pct,
    /// strictness: 1,
    pub fn percent(pct: f32) Size {
        return .{
            .kind = .percent_of_parent,
            .value = pct,
            .strictness = 1,
        };
    }

    /// kind: percent_of_parent,
    /// value: pct,
    /// strictness: 0,
    pub fn percent_relaxed(pct: f32) Size {
        return .{
            .kind = .percent_of_parent,
            .value = pct,
            .strictness = 0,
        };
    }
};

pub const Color = sdl.Color;

pub fn colorRgba(r: u8, g: u8, b: u8, a: u8) Color {
    return .{ .r = r, .g = g, .b = b, .a = a };
}

pub fn colorRgb(r: u8, g: u8, b: u8) Color {
    return colorRgba(r, g, b, 255);
}

/// 0xRRGGBB
pub fn colorHexRgb(hex: u24) Color {
    return colorRgb(
        @truncate(hex >> 16),
        @truncate(hex >> 8),
        @truncate(hex),
    );
}

/// 0xRRGGBBAA
pub fn colorHexRgba(hex: u32) Color {
    return colorRgba(
        @truncate(hex >> 24),
        @truncate(hex >> 16),
        @truncate(hex >> 8),
        @truncate(hex),
    );
}

pub const Key = enum(u32) {
    _,

    pub const Zero: Key = @enumFromInt(0);

    pub const KeyContext = struct {
        pub fn hash(self: @This(), key: Key) u32 {
            _ = self;
            return key.asInt();
        }

        pub fn eql(self: @This(), a: Key, b: Key, b_index: usize) bool {
            _ = self;
            _ = b_index;
            return Key.eql(a, b);
        }
    };

    pub inline fn asInt(self: Key) u32 {
        return @intFromEnum(self);
    }

    pub inline fn eql(left: Key, right: Key) bool {
        return left.asInt() == right.asInt();
    }

    // @TODO: Use parent id as seed
    pub fn processString(
        seed: u32,
        string: []const u8,
    ) struct {
        displayString: []const u8,
        key: Key,
    } {
        if (string.len == 0) {
            return .{
                .displayString = "",
                .key = Key.Zero,
            };
        }

        // hash whole string, only display before '##'
        const two_hash = "##";
        // only hash after '###', only display before '###'
        const three_hash = "###";
        // or just hash the string

        return if (std.mem.indexOf(u8, string, two_hash)) |index| blk: {
            const hash = hashString(seed, string);

            const str = string[0..index];
            break :blk .{
                .displayString = str,
                .key = @enumFromInt(hash),
            };
        } else if (std.mem.indexOf(u8, string, three_hash)) |index| blk: {
            const slice = string[(index + three_hash.len)..];
            const hash = hashString(seed, slice);

            const str = string[0..index];
            break :blk .{
                .displayString = str,
                .key = @enumFromInt(hash),
            };
        } else blk: {
            const hash = hashString(seed, string);

            break :blk .{
                .displayString = string,
                .key = @enumFromInt(hash),
            };
        };
    }

    inline fn hashString(seed: u32, string: []const u8) u32 {
        return std.hash.XxHash32.hash(seed, string);
    }
};

pub const Atom = struct {
    // per-build links
    children: ?struct {
        first: *Atom,
        last: *Atom,
        count: u32,
    } = null,
    siblings: struct {
        next: ?*Atom = null,
        prev: ?*Atom = null,
    } = .{},
    parent: ?*Atom = null,

    // per-build equipment
    key: Key,
    string: []const u8 = "",
    displayString: []const u8 = "",
    flags: AtomFlags = .{},
    size: Axis2(Size) = Axis2(Size).Zero,
    layout_axis: AxisKind = .none, // ensure this is set if children are added, if not an assertion will fail
    // hover_cursor
    // group_key
    // custom_draw_func
    // custom_draw_data

    // @FIXME: these could be scope locals, its worth looking into performance implications first though
    text_align: TextAlignment = .left,
    // pallete (background, text, text_weak, border, overlay, cursor, selection)
    // font (+size)
    // corner_radii: [4]f32
    // transparency: f32 = 1.0,
    color: sdl.Color = .{ .r = 255, .g = 255, .b = 255, .a = 255 },

    // per-build artifacts
    fixed_size: Axis2(f32) = Axis2(f32).Zero,
    rel_position: Axis2(f32) = Axis2(f32).Zero,
    rect: Range2(f32) = Range2(f32).Zero,
    text_data: ?TextData = null,

    // persistant data
    build_index_touched_first: u64,
    build_index_touched_last: u64,
    // build_index_first_disabled: u64,
    view_bounds: Axis2(f32) = Axis2(f32).Zero,

    /// Sets `size.{w, h}` to `text_content`
    /// and sets the `draw_text` flag
    pub inline fn equipDisplayString(self: *Atom) void {
        self.size.sz = .{ .w = .text, .h = .text };
        self.flags.draw_text = true;
    }

    pub inline fn end(self: *Atom) void {
        const atom = state.popParent().?;
        assert(Key.eql(self.key, atom.key)); // hit if mismatched ui/end called, likely forgot a defer
    }

    pub inline fn interation(self: *Atom) Interation {
        return interationFromAtom(self);
    }

    pub fn format(self: *Atom, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        try writer.print(
            "atom['{s}'#{d}]",
            .{ self.string, self.key.asInt() },
        );
    }
};

pub const AtomFlags = packed struct(u32) {
    const Self = @This();

    // interation
    mouse_clickable: bool = false,
    keyboard_clickable: bool = false,
    drop_site: bool = false,
    view_scroll: bool = false,
    focusable: bool = false,
    disabled: bool = false,

    // layout
    floating_x: bool = false,
    floating_y: bool = false,
    // fixed_width: bool = false,
    // fixed_height: bool = false,
    allow_overflow_x: bool = false,
    allow_overflow_y: bool = false,

    // appearance
    draw_drop_shadow: bool = false,
    draw_background: bool = false,
    draw_border: bool = false,
    draw_side_top: bool = false,
    draw_side_bottom: bool = false,
    draw_side_left: bool = false,
    draw_side_right: bool = false,
    draw_text: bool = false,
    draw_text_weak: bool = false,
    clip: bool = false,
    text_truncate_ellipsis: bool = false,

    // hot_animation: bool = false,
    // have_animation: bool = false,

    // render_custom: bool = false,

    _padding: enum(u11) { zero } = .zero,

    pub const clickable = AtomFlags{
        .mouse_clickable = true,
        .keyboard_clickable = true,
    };

    pub const floating = AtomFlags{
        .floating_x = true,
        .floating_y = true,
    };

    pub const allow_overflow = AtomFlags{
        .allow_overflow_x = true,
        .allow_overflow_y = true,
    };

    pub const draw_sides = AtomFlags{
        .draw_side_top = true,
        .draw_side_bottom = true,
        .draw_side_left = true,
        .draw_side_right = true,
    };

    inline fn asInt(self: Self) u32 {
        return @bitCast(self);
    }

    inline fn fromInt(value: u32) Self {
        return @bitCast(value);
    }

    inline fn bitOr(self: Self, other: Self) u32 {
        return fromInt(self.asInt() | other.asInt());
    }

    inline fn bitAnd(self: Self, other: Self) Self {
        return fromInt(self.asInt() & other.asInt());
    }

    pub inline fn combine(self: Self, other: Self) Self {
        return bitOr(self, other);
    }

    pub inline fn containsAny(self: Self, other: Self) bool {
        return bitAnd(self, other).asInt() > 0;
    }
};

pub const TextAlignment = enum {
    left,
    center,
    right,
};

pub const TextData = struct {
    zstring: [:0]const u8, // @Icky
    size: Axis2(c_int),

    pub fn init(text: []const u8) !TextData {
        const zstring = try state.alloc_temp.dupeZ(u8, text);

        var w: c_int = 0;
        var h: c_int = 0;
        try state.font.sizeText(zstring, &w, &h);

        return .{
            .zstring = zstring,
            .size = axis2(c_int, w, h),
        };
    }
};

pub const InteractionFlags = packed struct(u32) {
    const Self = @This();

    // mouse press -> atom pressed while hovering
    left_pressed: bool = false,
    middle_pressed: bool = false,
    right_pressed: bool = false,

    // released -> atom was pressed & released, in or out of bounds
    left_released: bool = false,
    middle_released: bool = false,
    right_released: bool = false,

    // clicked -> atom was pressed & released, in bounds
    left_clicked: bool = false,
    middle_clicked: bool = false,
    right_clicked: bool = false,

    // dragging -> atom was pressed, still holding
    left_dragging: bool = false,
    middle_dragging: bool = false,
    right_dragging: bool = false,

    // double clicked -> atom was clicked, pressed again
    left_double_clicked: bool = false,
    middle_double_clicked: bool = false,
    right_double_clicked: bool = false,

    // double dragging -> atom was double-clicked, still holding
    left_double_dragging: bool = false,
    middle_double_dragging: bool = false,
    right_double_dragging: bool = false,

    // triple clicked -> atom was double-clicked, pressed again
    left_triple_clicked: bool = false,
    middle_triple_clicked: bool = false,
    right_triple_clicked: bool = false,

    // triple dragging -> atom was triple-clicked, still holding
    left_triple_dragging: bool = false,
    middle_triple_dragging: bool = false,
    right_triple_dragging: bool = false,

    // keyboard pressed -> atom has focus, activated via keyboard
    keyboard_pressed: bool = false,

    hovering: bool = false, // hovering specifically over this atom
    mouse_over: bool = false, // mouse is over, but may be occluded

    _padding: enum(u5) { zero } = .zero,

    pub const pressed = InteractionFlags{
        .left_pressed = true,
        .keyboard_pressed = true,
    };

    pub const released = InteractionFlags{
        .left_released = true,
    };

    pub const clicked = InteractionFlags{
        .left_clicked = true,
        .keyboard_pressed = true,
    };

    pub const double_clicked = InteractionFlags{
        .left_double_clicked = true,
    };

    pub const triple_clicked = InteractionFlags{
        .left_triple_clicked = true,
    };

    pub const dragging = InteractionFlags{
        .left_dragging = true,
    };

    inline fn asInt(self: Self) u32 {
        return @bitCast(self);
    }

    inline fn fromInt(value: u32) Self {
        return @bitCast(value);
    }

    inline fn bitOr(self: Self, other: Self) Self {
        return fromInt(self.asInt() | other.asInt());
    }

    inline fn bitAnd(self: Self, other: Self) Self {
        return fromInt(self.asInt() & other.asInt());
    }

    pub inline fn combine(self: Self, other: Self) Self {
        return bitOr(self, other);
    }

    pub inline fn containsAny(self: Self, other: Self) bool {
        return bitAnd(self, other).asInt() > 0;
    }

    pub inline fn isPressed(self: InteractionFlags) bool {
        return self.containsAny(.pressed);
    }

    pub inline fn isReleased(self: InteractionFlags) bool {
        return self.containsAny(.released);
    }

    pub inline fn isClicked(self: InteractionFlags) bool {
        return self.containsAny(.clicked);
    }

    pub inline fn isDoubleClicked(self: InteractionFlags) bool {
        return self.containsAny(.double_clicked);
    }

    pub inline fn isTripleClicked(self: InteractionFlags) bool {
        return self.containsAny(.triple_clicked);
    }

    pub inline fn isDragging(self: InteractionFlags) bool {
        return self.containsAny(.dragging);
    }
};

pub const Interation = struct {
    atom: *Atom,
    scroll: Vec2(f32),
    modifiers: sdl.Keysym.ModFlags,
    f: InteractionFlags,
};

// one frame behind is it?
pub fn interationFromAtom(atom: *Atom) Interation {
    const mouse_over = atom.rect.contains(state.input.mouse_position);
    var hovering = mouse_over;

    if (atom.children) |children| {
        var maybe_child: ?*Atom = children.first;
        while (maybe_child) |child| : (maybe_child = child.siblings.next) {
            if (!child.key.eql(Key.Zero) and child.rect.contains(state.input.mouse_position)) {
                hovering = false;
            }
        }
    }

    return .{
        .atom = atom,
        .scroll = Vec2(f32).Zero,
        .modifiers = .{},
        .f = .{
            .hovering = hovering,
            .mouse_over = mouse_over,
        },
    };
}

pub fn tryAtomFromKey(key: Key) ?*Atom {
    var result: ?*Atom = null;
    if (!key.eql(Key.Zero)) {
        if (state.atom_map.get(key)) |atom| {
            result = atom;
        }
    }
    return result;
}

pub fn buildAtomFromKey(key: Key) *Atom {
    state.build_atom_count +%= 1; // wrapping add

    const atom = if (Key.eql(key, Key.Zero)) blk: {
        const atom = state.alloc_temp.create(Atom) catch @panic("oom");
        atom.* = .{
            .key = key,
            .build_index_touched_first = state.current_build_index,
            .build_index_touched_last = state.current_build_index,
        };
        break :blk atom;
    } else if (tryAtomFromKey(key)) |atom| blk: {
        atom.key = key;
        atom.build_index_touched_last = state.current_build_index;
        break :blk atom;
    } else blk: {
        const atom = state.allocAtom();
        atom.* = .{
            .key = key,
            .build_index_touched_first = state.current_build_index,
            .build_index_touched_last = state.current_build_index,
        };

        const bad_atom = state.atom_map.fetchPut(state.alloc_persistent, key, atom) catch @panic("oom");
        assert(bad_atom == null);

        break :blk atom;
    };

    // zero out per build info
    atom.children = null;
    atom.siblings.next = null;
    atom.siblings.prev = null;
    atom.parent = null;

    // add to parent
    if (state.currentParent()) |parent| {
        atom.parent = parent;

        if (parent.children) |*children| {
            const last = children.last;
            last.siblings.next = atom;
            atom.siblings.prev = last;
            children.last = atom;

            children.count += 1;
        } else {
            parent.children = .{
                .first = atom,
                .last = atom,
                .count = 1,
            };
        }
    }

    return atom;
}

pub fn buildAtomFromString(string: []const u8) *Atom {
    const seed = if (state.currentParent()) |parent| @intFromEnum(parent.key) else 0;
    const key_str = Key.processString(seed, string);

    const atom = buildAtomFromKey(key_str.key);
    atom.string = string;
    atom.displayString = key_str.displayString;

    return atom;
}

pub fn buildAtomFromStringF(comptime fmt: []const u8, args: anytype) *Atom {
    const string = std.fmt.allocPrint(state.alloc_temp, fmt, args) catch @panic("oom");
    const atom = buildAtomFromString(string);
    return atom;
}

// pub fn startFrame() void {}

// pub fn endFrame() void {}

pub fn startBuild(window: *sdl.Window) void {
    state.scope_locals.clearAndFree(state.alloc_temp); // @FIXME: not sure if this is needed
    _ = state.arena.reset(.retain_capacity);

    const root = buildAtomFromStringF("###root-window-id:{x}", .{window.getID()});

    const window_size = window.size();
    root.size.sz = .{
        .w = Size.px(@floatFromInt(window_size.w)),
        .h = Size.px(@floatFromInt(window_size.h)),
    };
    root.rect.pt = .{
        .p0 = vec2(f32, 0, 0),
        .p1 = vec2(f32, @floatFromInt(window_size.w), @floatFromInt(window_size.h)),
    };
    root.layout_axis = .x;

    state.pushParent(root);
    state.ui_root = root;
}

pub fn endBuild() void {
    var to_remove = std.ArrayList(Key)
        .initCapacity(state.alloc_temp, GlobalState.MaxAtoms / 2) catch @panic("oom");

    for (state.atom_map.values()) |atom| {
        if (atom.build_index_touched_last < state.current_build_index) {
            to_remove.append(atom.key) catch @panic("oom");
        }
    }

    for (to_remove.items) |key| {
        const atom = state.atom_map.fetchSwapRemove(key).?.value;
        state.atom_pool.destroy(atom);
    }

    const root = state.popParent().?;
    assert(state.parent_stack.items.len == 0); // ensure stack is empty after build
    assert(state.ui_root.key.eql(root.key));

    layout.layout(root) catch @panic("oom");

    state.current_build_index +%= 1; // wrapping add
}

pub fn ui(flags: AtomFlags, string: []const u8) *Atom {
    const atom = buildAtomFromString(string);
    atom.flags = flags;
    state.pushParent(atom);
    return atom;
}

pub fn uif(flags: AtomFlags, comptime fmt: []const u8, args: anytype) *Atom {
    const atom = buildAtomFromStringF(fmt, args);
    atom.flags = flags;
    state.pushParent(atom);
    return atom;
}

pub fn label(string: []const u8) *Atom {
    const atom = ui(.{}, string);
    atom.end();
    atom.equipDisplayString();
    return atom;
}

pub fn labelf(comptime fmt: []const u8, args: anytype) *Atom {
    const atom = uif(.{}, fmt, args);
    atom.end();
    atom.equipDisplayString();
    return atom;
}

// pub fn makeButton(string: []const u8) *Atom {
//     return ui(
//         AtomFlags.clickable.combine(.{
//             .draw_border = true,
//             .draw_text = true,
//             .draw_background = true,
//         }),
//         string,
//     );
// }

// pub fn button(string: []const u8) Interation {
//     const btn = makeButton(string);
//     btn.end();
//     return btn.interation();
// }
