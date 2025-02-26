/// # Attribution
///
/// Much of the design of this it taken from a series of blogs on ui by
/// Ryan Fleury (rfleury.com/i/146446067/ui-programming-series)
/// with some parts taken from the implementation of the ui layer of raddebugger
/// github.com/EpicGamesExt/raddebugger (Copyright (c) 2024 Epic Games Tools)
///
const std = @import("std");
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const assert = std.debug.assert;

const fontconfig = @import("../fontconfig.zig");
const sdl = @import("../sdl/sdl.zig");

pub const layout = @import("layout.zig");

pub const GlobalState = struct {
    current_frame_index: u64 = 0,
    build_atom_count: u64 = 0,

    renderer: *sdl.Renderer,
    font: *sdl.ttf.Font,

    arena: std.heap.ArenaAllocator,

    alloc_temp: Allocator,
    alloc_persistent: Allocator,

    atom_pool: AtomPool,
    atom_stack: AtomStack = .{},
    atom_map: AtomMap = .empty,

    ui_root: *Atom = undefined, // initalized after `startBuild`

    pub const MaxAtoms = 1024 * 4;

    pub const AtomPool = std.heap.MemoryPoolExtra(Atom, .{ .growable = false });
    pub const AtomStack = std.ArrayListUnmanaged(*Atom);
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
        self.atom_stack.append(self.alloc_persistent, atom) catch @panic("oom");
    }

    inline fn popParent(self: *GlobalState) ?*Atom {
        return self.atom_stack.pop();
    }

    inline fn currentParent(self: *GlobalState) ?*Atom {
        return self.atom_stack.getLastOrNull();
    }
};

pub var state: GlobalState = undefined;

pub fn init(
    allocator: Allocator,
    renderer: *sdl.Renderer,
    font: *sdl.ttf.Font,
) !void {
    const arena = std.heap.ArenaAllocator.init(allocator);
    const atom_pool = try GlobalState.AtomPool.initPreheated(allocator, GlobalState.MaxAtoms);

    state = .{
        .renderer = renderer,
        .font = font,
        .arena = arena,
        .alloc_temp = undefined,
        .alloc_persistent = allocator,
        .atom_pool = atom_pool,
    };

    // workaround to ensure that the allocator vtable references the arena stored in gs, not in the stack
    state.alloc_temp = state.arena.allocator();
}

pub fn deinit() void {
    state.atom_stack.deinit(state.alloc_persistent);
    state.atom_map.deinit(state.alloc_persistent);

    state.arena.deinit();
    state.atom_pool.deinit();
}

pub fn startFrame() void {
    //
}

pub fn endFrame() void {
    _ = state.arena.reset(.retain_capacity);
}

pub fn Vec2(comptime T: type) type {
    return extern union {
        vec: extern struct {
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
        vec: extern struct {
            x0: T,
            y0: T,
            x1: T,
            y1: T,
        },
        arr: [2]Vec2(T),
        // parr: [4]T,
        // pmat: [2][2]T,

        pub const Zero = std.mem.zeroes(@This());
    };
}

pub fn range2(comptime T: type, p0: Vec2(T), p1: Vec2(T)) Range2(T) {
    return .{ .arr = .{ p0, p1 } };
}

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

    /// kind: percent_of_parent
    /// value: 1
    /// strictness: 0
    pub const grow = percent_relaxed(1);

    /// kind: percent_of_parent
    /// value: 1
    /// strictness: 1
    pub const full = percent(1);

    /// kind: children_sum
    pub const sum = Size{ .kind = .children_sum };

    /// kind: text_content
    pub const text = Size{ .kind = .text_content };

    /// kind: pixels
    /// value: pxs
    /// strictness: 1
    pub fn px(pxs: f32) Size {
        return .{
            .kind = .pixels,
            .value = pxs,
            .strictness = 1,
        };
    }

    /// kind: pixels
    /// value: px
    /// strictness: 0
    pub fn px_relaxed(pxs: f32) Size {
        return .{
            .kind = .pixels,
            .value = pxs,
            .strictness = 0,
        };
    }

    /// kind: percent_of_parent
    /// value: pct
    /// strictness: 1
    pub fn percent(pct: f32) Size {
        return .{
            .kind = .percent_of_parent,
            .value = pct,
            .strictness = 1,
        };
    }

    /// kind: percent_of_parent
    /// value: pct
    /// strictness: 0
    pub fn percent_relaxed(pct: f32) Size {
        return .{
            .kind = .percent_of_parent,
            .value = pct,
            .strictness = 0,
        };
    }
};

pub const Key = enum(u64) {
    _,

    pub const Zero: Key = @enumFromInt(0);

    pub const KeyContext = struct {
        pub fn hash(self: @This(), key: Key) u32 {
            _ = self;
            // return @intFromEnum(key);
            _ = key;
            unreachable;
        }

        pub fn eql(self: @This(), a: Key, b: Key, b_index: usize) bool {
            _ = self;
            _ = b_index;
            return Key.eql(a, b);
        }
    };

    pub fn eql(left: Key, right: Key) bool {
        return @intFromEnum(left) == @intFromEnum(right);
    }

    // @TODO: Use parent id as seed
    pub fn processString(
        seed: u64,
        string: []const u8,
    ) struct {
        string: []const u8,
        key: Key,
    } {
        // hash whole string, only display before '##'
        const two_hash = "##";
        // only hash after '###', only display before '###'
        const three_hash = "###";
        // or just hash the string

        return if (std.mem.indexOf(u8, string, two_hash)) |index| blk: {
            const hash = std.hash.Wyhash.hash(seed, string);

            const str = string[0..index];
            break :blk .{
                .string = str,
                .key = @enumFromInt(hash),
            };
        } else if (std.mem.indexOf(u8, string, three_hash)) |index| blk: {
            const slice = string[(index + three_hash.len)..];
            const hash = std.hash.Wyhash.hash(seed, slice);

            const str = string[0..index];
            break :blk .{
                .string = str,
                .key = @enumFromInt(hash),
            };
        } else blk: {
            const hash = std.hash.Wyhash.hash(seed, string);

            break :blk .{
                .string = string,
                .key = @enumFromInt(hash),
            };
        };
    }
};

pub const Atom = struct {
    // tree links
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

    // // hash links
    // hash_next: ?*Widget = null,
    // hash_prev: ?*Widget = null,

    // key+generation info
    key: Key,
    first_frame_touched: u64,
    last_frame_touched: u64,

    string: []const u8,
    text_data: ?TextData = null,

    flags: AtomFlags,
    color: sdl.Color = .{},

    layout_axis: AxisKind = .none,
    size: Axis2(Size) = Axis2(Size).Zero,

    // recomputed every frame
    fixed_size: Axis2(f32) = Axis2(f32).Zero,
    rel_position: Axis2(f32) = Axis2(f32).Zero,
    rect: Range2(f32) = Range2(f32).Zero,
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
};

pub const AtomFlags = packed struct {
    clickable: bool = false,
    view_scroll: bool = false,
    focusable: bool = false,
    disabled: bool = false,

    floating_on_x: bool = false,
    floating_on_y: bool = false,

    overflow_x: bool = false,
    overflow_y: bool = false,

    clip: bool = false,

    draw_text: bool = false,
    draw_border: bool = false,
    draw_background: bool = false,
    draw_drop_shadow: bool = false,

    text_centered: bool = false,
    text_trunkate_ellipsis: bool = false,

    hot_animation: bool = false,
    have_animation: bool = false,

    custom_rendering: bool = false,
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

    const atom = if (tryAtomFromKey(key)) |atom|
        atom
    else blk: {
        const atom = state.allocAtom();
        atom.first_frame_touched = state.current_frame_index;

        const bad_atom = state.atom_map.fetchPut(state.alloc_persistent, key, atom) catch @panic("oom");
        assert(bad_atom == null);

        break :blk atom;
    };

    atom.parent = null;
    atom.siblings.next = null;
    atom.siblings.prev = null;
    atom.children = null;

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

    atom.key = key;
    atom.last_frame_touched = state.current_frame_index;

    return atom;
}

pub fn buildAtomFromString(string: []const u8) *Atom {
    const seed = if (state.currentParent()) |parent| @intFromEnum(parent.key) else 0;
    const key_str = Key.processString(seed, string);

    const atom = buildAtomFromKey(key_str.key);
    atom.string = key_str.string;

    return atom;
}

pub fn buildAtomFromStringF(comptime fmt: []const u8, args: anytype) *Atom {
    const string = std.fmt.allocPrint(state.alloc_temp, fmt, args) catch @panic("oom");
    const atom = buildAtomFromString(string);
    return atom;
}

pub fn startBuild(window: *sdl.Window) void {
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
    state.atom_map.lockPointers();
    defer state.atom_map.unlockPointers();

    for (state.atom_map.values()) |atom| {
        if (atom.last_frame_touched < state.current_frame_index or atom.key.eql(Key.Zero)) {
            const removed = state.atom_map.swapRemove(atom.key);
            assert(removed);
            state.atom_pool.destroy(atom);
        }
    }

    const root = state.popParent().?;
    assert(state.atom_stack.items.len == 0); // ensure stack is empty after build
    assert(state.ui_root.key.eql(root.key));

    layout.layout(root) catch @panic("oom");

    state.current_frame_index +%= 1; // wrapping add
}

pub inline fn ui(flags: AtomFlags, string: []const u8) *Atom {
    const atom = buildAtomFromString(string);
    atom.flags = flags;
    state.pushParent(atom);
    return atom;
}

pub inline fn uif(flags: AtomFlags, comptime fmt: []const u8, args: anytype) *Atom {
    const atom = buildAtomFromStringF(fmt, args);
    atom.flags = flags;
    state.pushParent(atom);
    return atom;
}
