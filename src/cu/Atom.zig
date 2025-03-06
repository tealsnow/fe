const Atom = @This();

const std = @import("std");
const assert = std.debug.assert;

const cu = @import("cu.zig");

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
display_string: []const u8 = "",
flags: Flags = .{},
size: cu.Axis2(PrefSize) = .zero,
layout_axis: cu.AxisKind = .none, // ensure this is set if children are added, if not an assertion will fail
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
color: cu.Color = .{ .r = 255, .g = 255, .b = 255, .a = 255 },

// per-build artifacts
fixed_size: cu.Axis2(f32) = .zero,
rel_position: cu.Axis2(f32) = .zero,
rect: cu.Range2(f32) = .zero,
text_data: ?TextData = null,

// persistant data
build_index_touched_first: u64,
build_index_touched_last: u64,
// build_index_first_disabled: u64,
view_bounds: cu.Axis2(f32) = .zero,

/// Sets `size.{w, h}` to `text_content`
/// and sets the `draw_text` flag
pub inline fn equipDisplayString(self: *Atom) void {
    self.size.sz = .{ .w = .text, .h = .text };
    self.flags.draw_text = true;
}

pub inline fn end(self: *Atom) void {
    const atom = cu.state.popParent().?;
    assert(Key.eql(self.key, atom.key)); // hit if mismatched ui/end called, likely forgot a defer
}

pub inline fn interation(self: *Atom) cu.Interation {
    return cu.interationFromAtom(self);
}

pub fn format(self: *Atom, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
    _ = fmt;
    _ = options;
    try writer.print(
        "atom['{s}'#{d}]",
        .{ self.string, self.key.asInt() },
    );
}

pub const Key = enum(u32) {
    _,

    pub const nil: Key = @enumFromInt(0);

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

    pub fn processString(
        seed: u32,
        string: []const u8,
    ) struct {
        []const u8,
        Key,
    } {
        if (string.len == 0)
            return .{ "", .nil };

        // hash whole string, only display before '##'
        const two_hash = "##";
        // only hash after '###', only display before '###'
        const three_hash = "###";
        // or just hash the string

        return if (std.mem.indexOf(u8, string, two_hash)) |index| blk: {
            const hash = hashString(seed, string);

            const str = string[0..index];
            break :blk .{ str, @enumFromInt(hash) };
        } else if (std.mem.indexOf(u8, string, three_hash)) |index| blk: {
            const slice = string[(index + three_hash.len)..];
            const hash = hashString(seed, slice);

            const str = string[0..index];
            break :blk .{ str, @enumFromInt(hash) };
        } else blk: {
            const hash = hashString(seed, string);

            break :blk .{ string, @enumFromInt(hash) };
        };
    }

    inline fn hashString(seed: u32, string: []const u8) u32 {
        return std.hash.XxHash32.hash(seed, string);
    }
};

pub const Flags = packed struct(u32) {
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

    pub const clickable = Self{
        .mouse_clickable = true,
        .keyboard_clickable = true,
    };

    pub const floating = Self{
        .floating_x = true,
        .floating_y = true,
    };

    pub const allow_overflow = Self{
        .allow_overflow_x = true,
        .allow_overflow_y = true,
    };

    pub const draw_sides = Self{
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
};

pub const TextAlignment = enum {
    left,
    center,
    right,
};

pub const TextData = struct {
    zstring: [:0]const u8, // @Icky
    size: cu.Axis2(c_int),

    pub fn init(text: []const u8) !TextData {
        const zstring = try cu.state.alloc_temp.dupeZ(u8, text);

        var w: c_int = 0;
        var h: c_int = 0;
        try cu.state.font.sizeText(zstring, &w, &h);

        return .{
            .zstring = zstring,
            .size = cu.axis2(c_int, w, h),
        };
    }
};

pub const PrefSize = extern struct {
    kind: Kind = .none,
    /// pixels: px, percent_of_parent: %
    value: f32 = 0,
    /// what percent of final size do we refuse to give up
    strictness: f32 = 0,

    pub const Kind = enum(u8) {
        none,
        pixels, // value px
        percent_of_parent, // value %
        text_content,
        children_sum,
    };

    /// kind: percent_of_parent,
    /// value: 1,
    /// strictness: 0,
    pub const grow = percent_relaxed(1);

    /// kind: percent_of_parent,
    /// value: 1,
    /// strictness: 1,
    pub const full = percent(1);

    /// kind: children_sum
    pub const fit = PrefSize{ .kind = .children_sum };

    /// kind: text_content
    pub const text = PrefSize{ .kind = .text_content };

    /// kind: pixels,
    /// value: pxs,
    /// strictness: 1,
    pub fn px(pxs: f32) PrefSize {
        return .{
            .kind = .pixels,
            .value = pxs,
            .strictness = 1,
        };
    }

    /// kind: pixels,
    /// value: px,
    /// strictness: 0,
    pub fn px_relaxed(pxs: f32) PrefSize {
        return .{
            .kind = .pixels,
            .value = pxs,
            .strictness = 0,
        };
    }

    /// kind: percent_of_parent,
    /// value: pct,
    /// strictness: 1,
    pub fn percent(pct: f32) PrefSize {
        return .{
            .kind = .percent_of_parent,
            .value = pct,
            .strictness = 1,
        };
    }

    /// kind: percent_of_parent,
    /// value: pct,
    /// strictness: 0,
    pub fn percent_relaxed(pct: f32) PrefSize {
        return .{
            .kind = .percent_of_parent,
            .value = pct,
            .strictness = 0,
        };
    }
};
