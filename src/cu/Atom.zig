const Atom = @This();

const std = @import("std");

const cu = @import("cu.zig");
const math = cu.math;
const builder = cu.builder;

// per-build links
tree: cu.TreeMixin(Atom) = .{},

// per-build equipment
key: Key,
string: []const u8 = "",
display_string: []const u8 = "",
flags: Flags = .none,

pref_size: math.Size(PrefSize) = .zero,
layout_axis: LayoutAxis = .x,
hover_cursor_shape: ?cu.CursorShape = null,
// group_key
text_align: math.Size(Alignment) = .square(.center),
alignment: math.Size(Alignment) = .square(.start), // @FIXME: rename to children alignment
padding: Padding = .zero,

palette: Palette = undefined,
font: cu.FontHandle = undefined,
// corner_radii: [4]f32
// transparency: f32 = 1.0,
border_width: f32 = 1, // draw_border, draw_side_top/bottom/left/right
corner_radius: f32 = 0, // draw_border, draw_background
// custom_draw_func
// custom_draw_data

// build artifacts - persistent
fixed_size: math.Size(f32) = .zero, // computed size
rel_position: math.Point(f32) = .zero,
rect: math.Rect(f32) = .zero,
text_size: math.Size(f32) = .zero,
text_rect: math.Rect(f32) = .zero,

// persistent data
build_index_touched_first: u64,
build_index_touched_last: u64,
// build_index_first_disabled: u64,
view_bounds: math.Size(f32) = .zero,
hot_t: f32 = 0,
active_t: f32 = 0,

pub const LayoutAxis = math.Axis2D;
pub const Padding = math.SideOffsets2D(f32);

pub inline fn interaction(atom: *Atom) cu.Interaction {
    return cu.input.interactionFromAtom(atom);
}

pub fn format(
    self: *const Atom,
    comptime fmt: []const u8,
    options: std.fmt.FormatOptions,
    writer: anytype,
) !void {
    _ = fmt;
    _ = options;
    try writer.print("atom['{s}'#{}]", .{ self.string, self.key });
}

pub const Key = enum(u32) {
    nil = 0,
    _,

    pub const KeyContext = struct {
        pub fn hash(self: @This(), key: Key) u32 {
            _ = self;
            return @intFromEnum(key); // already hashed
        }

        pub fn eql(self: @This(), a: Key, b: Key, b_index: usize) bool {
            _ = self;
            _ = b_index;
            return Key.eql(a, b);
        }
    };

    pub inline fn eql(left: Key, right: Key) bool {
        if (left == .nil and right == .nil) return true;
        if (left == .nil or right == .nil) return false;
        return @intFromEnum(left) == @intFromEnum(right);
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

        return blk: {
            if (std.mem.indexOf(u8, string, two_hash)) |index| {
                const hash = hashString(seed, string);

                const str = string[0..index];
                break :blk .{ str, @enumFromInt(hash) };
            } else if (std.mem.indexOf(u8, string, three_hash)) |index| {
                const slice = string[(index + three_hash.len)..];
                const hash = hashString(seed, slice);

                const str = string[0..index];
                break :blk .{ str, @enumFromInt(hash) };
            } else {
                const hash = hashString(seed, string);

                break :blk .{ string, @enumFromInt(hash) };
            }
        };
    }

    inline fn hashString(seed: u32, string: []const u8) u32 {
        return std.hash.XxHash32.hash(seed, string);
    }

    pub fn format(
        key: Key,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        if (key == .nil)
            try writer.writeAll("nil")
        else
            try writer.print("{x}", .{@intFromEnum(key)});
    }
};

pub const Flag = enum(u32) {
    //- interaction
    mouse_clickable,
    keyboard_clickable,
    // drop_site: bool = false,
    view_scroll,
    // focusable: bool = false,
    // disabled: bool = false,

    //- layout
    floating_x,
    floating_y,
    // fixed_width: bool = false,
    // fixed_height: bool = false,
    allow_overflow_x,
    allow_overflow_y,

    //- appearance
    // draw_drop_shadow: bool = false,
    draw_background,
    draw_border,
    draw_side_top,
    draw_side_bottom,
    draw_side_left,
    draw_side_right,
    draw_text,
    clip_rect,
};

pub const Flags = struct {
    enum_set: std.EnumSet(Flag),

    pub const none = Flags{ .enum_set = .initEmpty() };

    //- interaction
    pub const mouse_clickable = initOne(.mouse_clickable);
    pub const keyboard_clickable = initOne(.keyboard_clickable);
    // drop_site: bool = false,
    pub const view_scroll = initOne(.view_scroll);
    // focusable: bool = false,
    // disabled: bool = false,
    pub const clickable = init(&.{ .mouse_clickable, .keyboard_clickable });

    //- layout
    pub const floating_x = initOne(.floating_x);
    pub const floating_y = initOne(.floating_y);
    pub const floating = init(&.{ .floating_x, .floating_y });
    // fixed_width: bool = false,
    // fixed_height: bool = false,
    pub const allow_overflow_x = initOne(.allow_overflow_x);
    pub const allow_overflow_y = initOne(.allow_overflow_y);
    pub const allow_overflow =
        init(&.{ .allow_overflow_x, .allow_overflow_y });

    //- appearance
    // draw_drop_shadow: bool = false,
    pub const draw_background = initOne(.draw_background);
    pub const draw_border = initOne(.draw_border);
    pub const draw_side_top = initOne(.draw_side_top);
    pub const draw_side_bottom = initOne(.draw_side_bottom);
    pub const draw_side_left = initOne(.draw_side_left);
    pub const draw_side_right = initOne(.draw_side_right);
    pub const draw_text = initOne(.draw_text);
    pub const clip_rect = initOne(.clip_rect);

    pub fn initOne(flag: Flag) Flags {
        return .{ .enum_set = .initOne(flag) };
    }

    pub fn init(flags: []const Flags) Flags {
        var out = Flags.none;
        for (flags) |flag| {
            out.insert(flag);
        }
        return out;
    }

    pub fn contains(self: Flags, flags: Flags) bool {
        var all = true;
        var iter = flags.enum_set.iterator();
        while (iter.next()) |flag| {
            if (!self.enum_set.contains(flag))
                all = false;
        }
        return all;
    }

    pub fn insert(self: *Flags, flags: Flags) void {
        var iter = flags.enum_set.iterator();
        while (iter.next()) |flag|
            self.enum_set.insert(flag);
    }

    pub fn remove(self: *Flags, flags: Flag) void {
        var iter = flags.enum_set.iterator();
        while (iter.next()) |flag|
            self.enum_set.remove(flag);
    }

    pub fn setPresent(self: *Flags, flags: Flags, present: bool) void {
        var iter = flags.enum_set.iterator();
        while (iter.next()) |flag|
            self.enum_set.setPresent(flag, present);
    }

    pub fn allowOverflowForAxis(axis: LayoutAxis) Flags {
        return switch (axis) {
            .x => .allow_overflow_x,
            .y => .allow_overflow_y,
        };
    }

    pub fn floatingForAxis(axis: LayoutAxis) Flags {
        return switch (axis) {
            .x => .floating_x,
            .y => .floating_y,
        };
    }
};

pub const Alignment = enum(u8) {
    start,
    center,
    end,
};

/// NOTE: Be careful about strictness, if the layout cannot be solved with the
///       provided strictness it will more or less just give up and provide
///       nan values for the screen rect. Resulting in either a crash with a
///       badly behaved renderer or in the atoms not being rendered in a better
///       behaved one.
pub const PrefSize = extern struct {
    kind: Kind = .none,
    /// pixels: px, percent_of_parent: %, text_content: padding(px)
    value: f32 = 0,
    /// what percent of final size do we refuse to give up
    strictness: f32 = 0,

    pub const Kind = enum(u8) {
        none = 0,
        pixels, // value px
        percent_of_parent, // value %
        text_content, // value padding px
        em, // value * font size
        children_sum, // value child_spacing px
    };

    pub const none = PrefSize{};

    /// kind: pixels,
    /// value(pixels): pxs,
    /// strictness: 0,
    pub fn px(pxs: f32) PrefSize {
        return .{
            .kind = .pixels,
            .value = pxs,
            .strictness = 0,
        };
    }

    /// kind: pixels,
    /// value(pixels): pxs,
    /// strictness: 1,
    pub fn px_strict(pxs: f32) PrefSize {
        return .{
            .kind = .pixels,
            .value = pxs,
            .strictness = 1,
        };
    }

    /// kind: percent_of_parent,
    /// value(percent): 1,
    /// strictness: 1,
    pub const fill = percent(1);

    /// kind: percent_of_parent,
    /// value(percent): 1,
    /// strictness: 0,
    pub const grow = percent_relaxed(1);

    /// kind: percent_of_parent,
    /// value(percent): pct,
    /// strictness: 1,
    pub fn percent(pct: f32) PrefSize {
        return .{
            .kind = .percent_of_parent,
            .value = pct,
            .strictness = 1,
        };
    }

    /// kind: percent_of_parent,
    /// value(percent): pct,
    /// strictness: 0,
    pub fn percent_relaxed(pct: f32) PrefSize {
        return .{
            .kind = .percent_of_parent,
            .value = pct,
            .strictness = 0,
        };
    }

    /// kind: text_content,
    /// value(padding(px)): 4,
    /// strictness: 1,
    pub const text = PrefSize{
        .kind = .text_content,
        .value = 2,
        .strictness = 1,
    };

    /// kind: text_content,
    /// value(padding(px)): padding,
    /// strictness: 1,
    pub fn text_pad(padding: f32) PrefSize {
        return .{
            .kind = .text_content,
            .value = padding,
            .strictness = 1,
        };
    }

    /// kind: px,
    /// value(px): value * top font size,
    /// strictness: 1,
    /// NOTE: The calculation is deferred to the layout phase,
    ///       ensuring that the final attached font is used.
    ///       This the different from `builder.em` which returns
    ///       a px value from the top font at the time of call
    pub fn em(value: f32) PrefSize {
        return .{
            .kind = .em,
            .value = value,
            .strictness = 1,
        };
    }

    /// kind: children_sum,
    /// value(child spacing): 0,
    /// strictness: 0,
    pub const fit = PrefSize{ .kind = .children_sum };

    /// kind: children_sum,
    /// value(child spacing): 0,
    /// strictness: 0,
    pub const fit_strict = PrefSize{
        .kind = .children_sum,
        .strictness = 1,
    };

    /// kind: children_sum,
    /// value(child spacing): child_spacing,
    /// strictness: 0,
    pub fn fit_spaced(child_spacing: f32) PrefSize {
        return .{
            .kind = .children_sum,
            .value = child_spacing,
            .strictness = 0,
        };
    }
};

pub const PaletteColor = enum {
    background,
    border,
    text,
};

pub const Palette = struct {
    const List = std.EnumArray(PaletteColor, math.RgbaU8);

    list: List,

    pub fn init(
        init_values: std.enums.EnumFieldStruct(
            List.Key,
            List.Value,
            null,
        ),
    ) Palette {
        return .{ .list = .init(init_values) };
    }

    pub fn get(self: Palette, key: PaletteColor) math.RgbaU8 {
        return self.list.get(key);
    }

    pub fn set(self: *Palette, key: PaletteColor, value: math.RgbaU8) void {
        return self.list.set(key, value);
    }
};

pub const PalettePartial = struct {
    const List = std.EnumArray(PaletteColor, ?math.RgbaU8);

    list: List,

    pub fn init(
        init_values: std.enums.EnumFieldStruct(
            List.Key,
            List.Value,
            @as(?math.RgbaU8, null),
        ),
    ) PalettePartial {
        return .{ .list = .initDefault(@as(?math.RgbaU8, null), init_values) };
    }

    pub fn get(self: PalettePartial, key: PaletteColor) ?math.RgbaU8 {
        return self.list.get(key);
    }

    pub fn set(
        self: *PalettePartial,
        key: PaletteColor,
        value: ?math.RgbaU8,
    ) void {
        return self.list.set(key, value);
    }
};

pub const palettes = struct {
    /// Merge the left with the right palette, prioritizes the left one.
    pub fn mergePartials(
        left: PalettePartial,
        right: PalettePartial,
    ) PalettePartial {
        var out = left;

        inline for (0..PalettePartial.List.Indexer.count) |i| {
            const key = PalettePartial.List.Indexer.keyForIndex(i);
            out.set(key, left.get(key) orelse right.get(key));
        }

        return out;
    }

    pub fn partialIsFull(partial: PalettePartial) bool {
        inline for (0..PalettePartial.List.Indexer.count) |i| {
            const key = PalettePartial.List.Indexer.keyForIndex(i);
            if (partial.get(key) == null)
                return false;
        }
        return true;
    }

    pub fn partialToFull(partial: PalettePartial) ?Palette {
        var list = Palette{ .list = .initUndefined() };

        inline for (0..Palette.List.Indexer.count) |i| {
            const key = Palette.List.Indexer.keyForIndex(i);
            list.set(key, partial.get(key) orelse return null);
        }

        return list;
    }

    pub fn fullToPartial(full: Palette) PalettePartial {
        var list = PalettePartial{ .list = .initUndefined() };

        inline for (0..PalettePartial.List.Indexer.count) |i| {
            const key = PalettePartial.List.Indexer.keyForIndex(i);
            list.set(key, full.get(key));
        }

        return list;
    }
};
