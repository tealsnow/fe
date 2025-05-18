const Atom = @This();

const std = @import("std");

const cu = @import("cu.zig");
const math = cu.math;

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
pref_size: math.Size(PrefSize) = .zero,
layout_axis: LayoutAxis = .none, // ensure this is set if children are added, if not an assertion will fail
// hover_cursor
// group_key
// custom_draw_func
// custom_draw_data

// @FIXME: these could be scope locals, its worth looking into performance implications first though
text_align: math.Size(TextAlignment) = .square(.center),
palette: pallete.Pallete = undefined,
font: cu.State.FontId = undefined,
// corner_radii: [4]f32
// transparency: f32 = 1.0,
border_width: f32 = 1, // draw_border, draw_side_top/bottom/left/right
corner_radius: f32 = 0, // draw_border, draw_background

// per-build artifacts
fixed_size: math.Size(f32) = .zero,
rel_position: math.Point(f32) = .zero,
rect: math.Rect(f32) = .zero,
text_size: math.Size(f32) = .zero,
text_rect: math.Rect(f32) = .zero,

// persistant data
build_index_touched_first: u64,
build_index_touched_last: u64,
// build_index_first_disabled: u64,
view_bounds: math.Size(f32) = .zero,
hot_t: f32,
active_t: f32,

pub const LayoutAxis = math.Dim2D;

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
            return key.asInt();
        }

        pub fn eql(self: @This(), a: Key, b: Key, b_index: usize) bool {
            _ = self;
            _ = b_index;
            return Key.eql(a, b);
        }
    };

    inline fn asInt(self: Key) u32 {
        return @intFromEnum(self);
    }

    pub inline fn eql(left: Key, right: Key) bool {
        if (left == .nil and right == .nil) return true;
        if (left == .nil or right == .nil) return false;
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

    pub fn format(key: Key, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        if (key == .nil)
            try writer.writeAll("nil")
        else
            try writer.print("{x}", .{key.asInt()});
    }
};

pub const Flags = packed struct(u32) {
    const Self = @This();
    pub const none = Self{};

    // interation
    mouse_clickable: bool = false,
    keyboard_clickable: bool = false,
    // drop_site: bool = false,
    // view_scroll: bool = false,
    // focusable: bool = false,
    // disabled: bool = false,

    // layout
    floating_x: bool = false,
    floating_y: bool = false,
    // fixed_width: bool = false,
    // fixed_height: bool = false,
    allow_overflow_x: bool = false,
    allow_overflow_y: bool = false,

    // appearance
    // draw_drop_shadow: bool = false,
    draw_background: bool = false,
    draw_border: bool = false,
    draw_side_top: bool = false,
    draw_side_bottom: bool = false,
    draw_side_left: bool = false,
    draw_side_right: bool = false,
    draw_text: bool = false,
    draw_text_weak: bool = false,
    clip_rect: bool = false,
    // text_truncate_ellipsis: bool = false,

    // hot_animation: bool = false,
    // have_animation: bool = false,

    // render_custom: bool = false,

    _padding: enum(u17) { zero } = .zero,

    pub fn mouseClickable(self: Self) Self {
        var this = self;
        this.mouse_clickable = true;
        return this;
    }

    pub fn keyboardClickable(self: Self) Self {
        var this = self;
        this.keyboard_clickable = true;
        return this;
    }

    pub fn clickable(self: Self) Self {
        var this = self;
        this.mouse_clickable = true;
        this.keyboard_clickable = true;
        return this;
    }

    pub fn floatingX(self: Self) Self {
        var this = self;
        this.floating_x = true;
        return this;
    }

    pub fn floatingY(self: Self) Self {
        var this = self;
        this.floating_y = true;
        return this;
    }

    pub fn floating(self: Self) Self {
        var this = self;
        this.floating_x = true;
        this.floating_y = true;
        return this;
    }

    pub fn allowOverflowX(self: Self) Self {
        var this = self;
        this.allow_overflow_x = true;
        return this;
    }

    pub fn allowOverflowY(self: Self) Self {
        var this = self;
        this.allow_overflow_y = true;
        return this;
    }

    pub fn allowOverflow(self: Self) Self {
        var this = self;
        this.allow_overflow_x = true;
        this.allow_overflow_y = true;
        return this;
    }

    pub fn drawBackground(self: Self) Self {
        var this = self;
        this.draw_background = true;
        return this;
    }

    pub fn drawBorder(self: Self) Self {
        var this = self;
        this.draw_border = true;
        return this;
    }

    pub fn drawSideTop(self: Self) Self {
        var this = self;
        this.draw_side_top = true;
        return this;
    }

    pub fn drawSideBottom(self: Self) Self {
        var this = self;
        this.draw_side_bottom = true;
        return this;
    }

    pub fn drawSideLeft(self: Self) Self {
        var this = self;
        this.draw_side_left = true;
        return this;
    }

    pub fn drawSideRight(self: Self) Self {
        var this = self;
        this.draw_side_right = true;
        return this;
    }

    pub fn drawText(self: Self) Self {
        var this = self;
        this.draw_text = true;
        return this;
    }

    pub fn drawTextWeak(self: Self) Self {
        var this = self;
        this.draw_text_weak = true;
        return this;
    }

    pub fn clipRect(self: Self) Self {
        var this = self;
        this.clip_rect = true;
        return this;
    }
};

pub const TextAlignment = enum(u8) {
    start,
    center,
    end,
};

pub const PrefSize = extern struct {
    kind: Kind = .none,
    /// pixels: px, percent_of_parent: %, text_content: padding(px)
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
    /// value(percent): 1,
    /// strictness: 0,
    pub const grow = percent_relaxed(1);

    /// kind: percent_of_parent,
    /// value(percent): 1,
    /// strictness: 1,
    pub const fill = percent(1);

    /// kind: children_sum,
    /// strictness: 0,
    pub const fit = PrefSize{ .kind = .children_sum };

    /// kind: text_content,
    /// value(padding(px)): 4,
    /// strictness: 1,
    pub const text = PrefSize{
        .kind = .text_content,
        .value = 2,
        .strictness = 1,
    };

    /// kind: pixels,
    /// value(pixels): pxs,
    /// strictness: 1,
    pub fn px(pxs: f32) PrefSize {
        return .{
            .kind = .pixels,
            .value = pxs,
            .strictness = 1,
        };
    }

    /// kind: pixels,
    /// value(pixels): pxs,
    /// strictness: 0,
    pub fn px_relaxed(pxs: f32) PrefSize {
        return .{
            .kind = .pixels,
            .value = pxs,
            .strictness = 0,
        };
    }

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
    pub fn em(value: f32) PrefSize {
        const font_size = fontSize();
        return .px(value * font_size);
    }

    /// Returns the font size (px) of the top font
    pub fn fontSize() f32 {
        const top_font = cu.stacks.font.topStable().?;
        const font_handle = cu.state.getFont(top_font);
        return cu.state.callbacks.fontSize(font_handle);
    }
};

pub const pallete = struct {
    pub const PalleteColor = enum {
        background,
        text,
        text_weak,
        border,
        hot,
        active,
        // overlay,
        // cursor,
        // selection,
    };

    pub const Pallete = struct {
        const List = std.EnumArray(PalleteColor, math.RgbaU8);

        list: List,

        pub fn init(
            init_values: std.enums.EnumFieldStruct(
                List.Key,
                List.Value,
                null,
            ),
        ) Pallete {
            return .{ .list = .init(init_values) };
        }

        pub fn get(self: Pallete, key: PalleteColor) math.RgbaU8 {
            return self.list.get(key);
        }

        pub fn set(self: *Pallete, key: PalleteColor, value: math.RgbaU8) void {
            return self.list.set(key, value);
        }
    };

    pub const PalletePartial = struct {
        const List = std.EnumArray(PalleteColor, ?math.RgbaU8);

        list: List,

        pub fn init(
            init_values: std.enums.EnumFieldStruct(
                List.Key,
                List.Value,
                @as(?math.RgbaU8, null),
            ),
        ) PalletePartial {
            return .{ .list = .initDefault(@as(?math.RgbaU8, null), init_values) };
        }

        pub fn get(self: PalletePartial, key: PalleteColor) ?math.RgbaU8 {
            return self.list.get(key);
        }

        pub fn set(
            self: *PalletePartial,
            key: PalleteColor,
            value: ?math.RgbaU8,
        ) void {
            return self.list.set(key, value);
        }
    };

    /// Merge the left with the right pallete, prioritizes the left one.
    pub fn mergePartials(
        left_: PalletePartial,
        right: PalletePartial,
    ) PalletePartial {
        var left = left_;

        inline for (0..PalletePartial.List.Indexer.count) |i| {
            const key = PalletePartial.List.Indexer.keyForIndex(i);
            left.set(key, left.get(key) orelse right.get(key));
        }

        return left;
    }

    pub fn partialIsFull(partial: PalletePartial) bool {
        inline for (0..PalletePartial.List.Indexer.count) |i| {
            const key = PalletePartial.List.Indexer.keyForIndex(i);
            if (partial.get(key) == null)
                return false;
        }
        return true;
    }

    pub fn partialToFull(partial: PalletePartial) ?Pallete {
        var list = Pallete{ .list = .initUndefined() };

        inline for (0..Pallete.List.Indexer.count) |i| {
            const key = Pallete.List.Indexer.keyForIndex(i);
            list.set(key, partial.get(key) orelse return null);
        }

        return list;
    }

    pub fn fullToPartial(full: Pallete) PalletePartial {
        var list = PalletePartial{ .list = .initUndefined() };

        inline for (0..PalletePartial.List.Indexer.count) |i| {
            const key = PalletePartial.List.Indexer.keyForIndex(i);
            list.set(key, full.get(key));
        }

        return list;
    }
};
