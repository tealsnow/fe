const Atom = @This();

const std = @import("std");

const cu = @import("cu.zig");
const Color = cu.Color;

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
pref_size: cu.Axis2(PrefSize) = .zero,
layout_axis: cu.Axis2(void).Kind = .none, // ensure this is set if children are added, if not an assertion will fail
// hover_cursor
// group_key
// custom_draw_func
// custom_draw_data

// @FIXME: these could be scope locals, its worth looking into performance implications first though
text_align: cu.Axis2(TextAlignment) = .square(.center),
palette: *Palette = undefined,
font: cu.FontId = undefined,
// corner_radii: [4]f32
// transparency: f32 = 1.0,

// per-build artifacts
fixed_size: cu.Axis2(f32) = .zero,
rel_position: cu.Axis2(f32) = .zero,
rect: cu.Range2(f32) = .zero,
text_size: cu.Axis2(f32) = .zero,
text_rect: cu.Range2(f32) = .zero,

// persistant data
build_index_touched_first: u64,
build_index_touched_last: u64,
// build_index_first_disabled: u64,
view_bounds: cu.Axis2(f32) = .zero,

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
    pub const init = Self{};

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
        const top_font = cu.state.font_stack.top().?;
        const font_handle = cu.state.font_manager.getFont(top_font);
        const font_size = cu.state.callbacks.fontSize(font_handle);
        return .px(value * font_size);
    }
};

pub const Palette = struct {
    background: Color,
    text: Color,
    text_weak: Color,
    border: Color,
    // overlay: Color,
    // cursor: Color,
    // selection: Color,
};
