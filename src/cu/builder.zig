const std = @import("std");
const Allocator = std.mem.Allocator;
const log = std.log.scoped(.@"cu.builder");

const cu = @import("cu.zig");
const math = cu.math;
const debugAssert = cu.debugAssert;
const Atom = cu.Atom;
const AtomFlags = cu.AtomFlags;
const FontHandle = cu.FontHandle;
const FontKind = cu.FontKind;

const tracy = @import("tracy");

var trace_build: tracy.ZoneContext = undefined;

const b = @This();

pub fn startFrame() void {
    const current_time = std.time.Instant.now() catch
        @panic("no std.time.Instant support");

    const dt_ns = current_time.since(cu.state.frame_previous_time);
    cu.state.frame_previous_time = current_time;

    cu.state.dt_s =
        @as(f32, @floatFromInt(dt_ns)) / @as(f32, std.time.ns_per_s);
}

pub fn endFrame() void {
    //
}

pub fn startBuild(window_id: usize) void {
    trace_build = tracy.beginZone(@src(), .{ .name = "ui build" });
    const trace_start = tracy.beginZone(@src(), .{ .name = "ui build setup" });
    defer trace_start.end();

    // reset arena
    // _ = cu.state.arena_allocator.reset(.free_all);
    _ = cu.state.arena_allocator.reset(.retain_capacity);

    // cu.state.scope_locals.clearAndFree(cu.state.arena);

    //- reset stacks
    {
        stacks = .empty;

        stacks.palette
            .pushForMany(Atom.pallete.fullToPartial(cu.state.default_palette));
        stacks.font.pushForMany(.body);
        stacks.pref_size.pushForMany(.square(.fill));
        stacks.layout_axis.pushForMany(.x);
        // stacks.hover_cursor intentialally left out
        stacks.flags.pushForMany(.none);
        stacks.text_align.pushForMany(.square(.center));
        stacks.alignment.pushForMany(.square(.start));
        stacks.padding.pushForMany(.zero);
        stacks.border_width.pushForMany(1);
        stacks.corner_radius.pushForMany(0);
    }

    dbg.idx = 0;

    //- setup ui roots
    {
        stacks.layout_axis.push(.x);
        stacks.pref_size.push(cu.state.window_size.intoPxPrefSize());
        stacks.flags.push(.clickable);
        const ui_root =
            buildFromStringF("###ui_root window-id:{x}", .{window_id});
        ui_root.rect = .rect(.point(0, 0), cu.state.window_size.intoPoint());
        cu.state.ui_root = ui_root;

        stacks.layout_axis.push(.x);
        stacks.pref_size.push(.square(.fit));
        const ctx_menu_root =
            buildFromStringF("###ctx_menu_root window-id:{x}", .{window_id});
        ctx_menu_root.rect = .zero;
        cu.state.ui_ctx_menu_root = ctx_menu_root;

        stacks.layout_axis.push(.x);
        stacks.pref_size.push(.square(.fit));
        const tooltip_root =
            buildFromStringF("###tooltip_root window-id:{x}", .{window_id});
        tooltip_root.rect = .zero;
        cu.state.ui_tooltip_root = tooltip_root;
    }

    //- setup atom stack
    {
        cu.state.atom_parent_stack = .empty;
        cu.state.atom_parent_stack.push(cu.state.arena, cu.state.ui_root);
    }

    cu.state.next_ctx_menu_open = cu.state.ctx_menu_open;
}

pub fn endBuild() void {
    defer trace_build.end();
    const trace_end = tracy.beginZone(@src(), .{ .name = "ui build end" });
    defer trace_end.end();

    //- remove stale atoms
    {
        const trace =
            tracy.beginZone(@src(), .{ .name = "remove stale atoms" });
        defer trace.end();

        cu.state.atom_stale_list
            .clearRetainingCapacity();

        // @PERF: #toProfile it might be faster to do two loops one checking
        //   for the number of stale atoms, allocate, then the next to collect
        for (cu.state.atom_map.values()) |atom| {
            if (atom.build_index_touched_last < cu.state.current_build_index) {
                cu.state.atom_stale_list.append(cu.state.gpa, atom.key) catch
                    @panic("oom");
            }
        }

        for (cu.state.atom_stale_list.items) |key| {
            if (key == .nil) continue;
            const atom = cu.state.atom_map.fetchSwapRemove(key).?.value;
            cu.state.atom_pool.destroy(atom);
        }
    }

    //- check stack
    const root = root: {
        const root = cu.state.atom_parent_stack.pop().?;
        debugAssert(
            cu.state.atom_parent_stack.list.items.len == 0,
            "Parent stack not empty after build; " ++
                "likely forgot a defer -- last: {}",
            .{root},
        );
        debugAssert(
            cu.state.ui_root.key.eql(root.key),
            "Last item on parent stack was not ui root; instead found: {}",
            .{root},
        );
        break :root root;
    };

    _ = root.interaction();

    //- layout
    {
        const trace = tracy.beginZone(@src(), .{ .name = "build layout" });
        defer trace.end();

        cu.layout(root) catch @panic("oom");
        cu.layout(cu.state.ui_ctx_menu_root) catch @panic("oom");
        cu.layout(cu.state.ui_tooltip_root) catch @panic("oom");
    }

    //- reset and cleanup state
    {
        cu.state.hot_atom_key = .nil;
        cu.state.ctx_menu_open = cu.state.next_ctx_menu_open;
        cu.state.current_build_index += 1;
        cu.state.ui_built = true;
        cu.state.event_list.len = 0;
    }

    //- work out the hover cursor
    {
        var pointer_kind: ?cu.PointerKind = null;

        findHoverPointerKindForRoot(cu.state.ui_root, &pointer_kind);
        findHoverPointerKindForRoot(cu.state.ui_ctx_menu_root, &pointer_kind);
        findHoverPointerKindForRoot(cu.state.ui_tooltip_root, &pointer_kind);

        cu.state.pointer_kind = pointer_kind;
    }
}

fn findHoverPointerKindForRoot(root: *Atom, pointer_kind: *?cu.PointerKind) void {
    var iter = root.tree.depthFirstPreOrderIterator();
    while (iter.next()) |atom| {
        if (atom.rect.contains(cu.state.pointer_pos)) {
            if (atom.hover_pointer) |kind|
                pointer_kind.* = kind;
        }
    }
}

pub fn tryAtomFromKey(key: Atom.Key) ?*Atom {
    if (!key.eql(.nil)) {
        if (cu.state.atom_map.get(key)) |atom| {
            return atom;
        }
    }
    return null;
}

pub fn buildFromKeyOrphan(key: Atom.Key) *Atom {
    cu.state.build_atom_count += 1;

    const atom, //
    const is_first_frame // if it was created this frame
    = if (Atom.Key.eql(key, .nil)) blk: {
        const atom = cu.state.arena.create(Atom) catch @panic("oom");
        break :blk .{ atom, true };
    } else if (tryAtomFromKey(key)) |atom| blk: {
        // atom.key = key;
        break :blk .{ atom, false };
    } else blk: {
        const atom = cu.state.atom_pool.create() catch @panic("oom");
        const bad_atom =
            cu.state.atom_map.fetchPut(cu.state.gpa, key, atom) catch
                @panic("oom");
        debugAssert(
            bad_atom == null,
            "got an atom for a key that was thought to not have a value" ++
                " - keying/hashing is broken",
            .{},
        );

        break :blk .{ atom, true };
    };

    if (is_first_frame) {
        atom.* = .{
            .key = key,
            .build_index_touched_first = cu.state.current_build_index,
            .build_index_touched_last = cu.state.current_build_index,
        };
    } else {
        atom.build_index_touched_last = cu.state.current_build_index;
    }

    // zero out per build info
    atom.tree = .{};

    atom.string = "";
    atom.display_string = "";

    // per build info
    atom.pref_size = stacks.pref_size.topVolatile().?;
    atom.layout_axis = stacks.layout_axis.topVolatile().?;
    atom.hover_pointer = stacks.hover_pointer.topVolatile(); // may be null
    atom.flags = stacks.flags.topVolatile().?;
    atom.text_align = stacks.text_align.topVolatile().?;
    atom.alignment = stacks.alignment.topVolatile().?;
    atom.padding = stacks.padding.topVolatile().?;
    atom.border_width = stacks.border_width.topVolatile().?;
    atom.corner_radius = stacks.corner_radius.topVolatile().?;

    {
        const kind = stacks.font.topVolatile().?;
        atom.font = cu.state.font_kind_map.get(kind);
    }

    {
        var partial = stacks.palette.topVolatile().?;
        var i: usize = 0;
        while (!Atom.pallete.partialIsFull(partial)) : (i += 1) {
            const next = stacks.palette.peek(i) orelse break;
            partial = Atom.pallete.mergePartials(partial, next);
        }
        atom.palette = Atom.pallete.partialToFull(partial) orelse
            @panic("could not contruct a full pallete from stack");
    }

    return atom;
}

pub fn buildFromKey(key: Atom.Key) *Atom {
    const atom = buildFromKeyOrphan(key);

    if (cu.state.next_atom_orphan) {
        cu.state.next_atom_orphan = false;
    } else {
        addToTopParent(atom);
    }

    return atom;
}

pub fn addToTopParent(atom: *Atom) void {
    const parent = cu.state.atom_parent_stack.top() orelse return;
    parent.tree.addChild(atom);
}

pub fn buildFromString(string: []const u8) *Atom {
    const seed =
        if (cu.state.atom_parent_stack.top()) |parent|
            @intFromEnum(parent.key)
        else
            0;
    const display_string, const key = Atom.Key.processString(seed, string);

    const atom = buildFromKey(key);
    atom.string = string;
    atom.display_string = display_string;

    return atom;
}

pub fn format(comptime fmt: []const u8, args: anytype) []const u8 {
    return std.fmt.allocPrint(cu.state.arena, fmt, args) catch @panic("oom");
}

pub fn buildFromStringF(comptime fmt: []const u8, args: anytype) *Atom {
    const string = std.fmt.allocPrint(cu.state.arena, fmt, args) catch
        @panic("oom");
    return buildFromString(string);
}

//= build shorthand

pub inline fn build(string: []const u8) *Atom {
    return buildFromString(string);
}

pub inline fn buildf(comptime fmt: []const u8, args: anytype) *Atom {
    return buildFromStringF(fmt, args);
}

//= hierarchy management

pub fn pushParent(atom: *Atom) void {
    cu.state.atom_parent_stack.push(cu.state.arena, atom);
}

pub fn open(string: []const u8) *Atom {
    const atom = build(string);
    pushParent(atom);
    return atom;
}

pub fn openf(comptime fmt: []const u8, args: anytype) *Atom {
    const atom = buildf(fmt, args);
    cu.state.atom_parent_stack.push(cu.state.arena, atom);
    return atom;
}

pub fn close(atom: *Atom) void {
    const top = cu.state.atom_parent_stack.pop().?;
    debugAssert(
        Atom.Key.eql(top.key, atom.key),
        "mismatched open/close; likely forgot a defer: expected {} but got {}",
        .{ atom, top },
    );
}

//= basic widgets

pub fn label(string: []const u8) *Atom {
    stacks.font.push(.label);
    const atom = buildFromKey(.nil);
    atom.display_string = string;
    atom.flags.insert(.draw_text);
    return atom;
}

pub fn labelf(comptime fmt: []const u8, args: anytype) *Atom {
    const string = std.fmt.allocPrint(cu.state.arena, fmt, args) catch
        @panic("oom");
    return label(string);
}

pub fn spacer() *Atom {
    return buildFromKey(.nil);
}

pub fn lineSpacer() *Atom {
    stacks.pref_size.push(.size(.grow, .px(em(1))));
    const line_spacer = spacer();
    line_spacer.display_string = " ";
    return line_spacer;
}

pub fn baseClickableInteractionStyles(inter: cu.Interaction) void {
    // @FIXME: the tranitions to and from no interation and hovering work,
    //  and from hovering to clicking, but not from clicking back to hovering

    const atom = inter.atom;

    const is_hot = cu.state.hot_atom_key.eql(atom.key);
    const is_active = for (cu.state.active_atom_key.values) |key| {
        if (key.eql(atom.key)) break true;
    } else false;

    atom.hot_t =
        math.expSmooth(atom.hot_t, @as(f32, if (is_hot) 1 else 0));
    atom.active_t =
        math.expSmooth(atom.active_t, @as(f32, if (is_active) 1 else 0));

    const palette = atom.palette;
    const from, const to, const lerp_t =
        if (is_active)
            .{ palette.get(.hot), palette.get(.active), atom.active_t }
        else
            .{ palette.get(.border), palette.get(.hot), atom.hot_t };

    atom.palette.set(.border, from.lerp(to, lerp_t));
}

pub fn button(string: []const u8) cu.Interaction {
    stacks.font.push(.button);
    stacks.hover_pointer.push(.clickable);
    const atom = build(string);
    atom.flags = .init(&.{ .clickable, .draw_text, .draw_border });

    const interaction = atom.interaction();
    baseClickableInteractionStyles(interaction);

    return interaction;
}

pub fn buttonf(comptime fmt: []const u8, args: anytype) cu.Interaction {
    const string = std.fmt.allocPrint(cu.state.arena, fmt, args) catch
        @panic("oom");
    return button(string);
}

pub fn toggleSwitch(toggled: *bool) cu.Interaction {
    stacks.pref_size.push(.size(.px_strict(em(3)), .px_strict(em(1.5))));
    stacks.flags.push(.init(&.{ .draw_border, .clickable }));
    stacks.layout_axis.push(.y);
    stacks.hover_pointer.push(.clickable);
    const toggle = open("toggle container");
    defer close(toggle);

    const size = toggle.fixed_size;
    const padding: f32 = size.height / 6;
    const middle_size: f32 = size.height - (2 * padding);

    stacks.pref_size.push(.size(.grow, .px(padding)));
    _ = spacer();

    {
        stacks.layout_axis.push(.x);
        stacks.pref_size.push(.square(.grow));
        const track = open("track");
        defer close(track);

        track.active_t = math.expSmooth(
            track.active_t,
            if (toggled.*)
                size.width - middle_size - padding
            else
                padding,
        );

        stacks.pref_size.push(.size(.px(track.active_t), .grow));
        _ = spacer();

        stacks.flags.push(.draw_background);
        stacks.palette.push(.init(.{
            .background = stacks.palette.topStable().?.get(.text),
        }));
        stacks.pref_size.push(.square(.px(middle_size)));
        stacks.corner_radius.push(toggle.corner_radius / 1.5);
        _ = build("middle");
    }

    const inter = toggle.interaction();
    baseClickableInteractionStyles(inter);

    if (inter.clicked())
        toggled.* = !toggled.*;

    return inter;
}

//= context menu

pub const ctx_menu = struct {
    pub fn openMenu(
        key: Atom.Key,
        anchor_key: Atom.Key,
        anchor_offset: math.Point(f32),
    ) void {
        if (cu.state.ctx_menu_open and cu.state.ctx_menu_key == key) {

            // ctx_menu_changed = true
            // ctx_menu_open_t = 0
            cu.state.next_ctx_menu_anchor_key = anchor_key;
            cu.state.ctx_menu_anchor_offset = anchor_offset;
            // ctx_menu_touched_this_frame = true
            // ctx_menu_anchor_atom_last_pos = .zero

            return;
        }

        cu.state.next_ctx_menu_open = true;

        // ctx_menu_changed = true
        // ctx_menu_open_t = 0
        cu.state.ctx_menu_key = key;
        cu.state.next_ctx_menu_anchor_key = anchor_key;
        cu.state.ctx_menu_anchor_offset = anchor_offset;
        // ctx_menu_touched_this_frame = true
        // ctx_menu_anchor_atom_last_pos = .zero
    }

    pub fn closeMenu() void {
        cu.state.next_ctx_menu_open = false;
    }

    pub fn begin(
        key: Atom.Key,
    ) ?*Atom {
        const is_open =
            cu.state.ctx_menu_open and
            Atom.Key.eql(key, cu.state.ctx_menu_key);
        // is_in_ctx_menu = is_open;

        if (!is_open)
            return null;

        stacks.flags.push(.floating);
        stacks.pref_size.push(.square(.fit));
        stacks.layout_axis.push(.y);
        cu.state.next_atom_orphan = true;
        const sub_root = open("ctx menu sub root");
        cu.state.ui_ctx_menu_root.tree.addChild(sub_root);

        if (cu.state.next_ctx_menu_anchor_key != .nil) {
            const anchor_atom =
                cu.state.atom_map.get(cu.state.next_ctx_menu_anchor_key) orelse
                @panic("invalid key");

            sub_root.rel_position = anchor_atom.rect.topLeft()
                .add(cu.state.ctx_menu_anchor_offset);

            cu.state.next_ctx_menu_anchor_key = .nil;
        }

        return sub_root;
    }

    pub fn end(atom: *Atom) void {
        close(atom);
    }
};

//= tool tip

pub const tooltip = struct {
    pub fn begin() *Atom {
        pushParent(cu.state.ui_tooltip_root);

        const sub_root = open("###tooltip sub root");
        sub_root.flags.insert(.floating);

        var pos = cu.state.pointer_pos;
        pos.y += cu.state.graphics_info.cursor_size_px;
        sub_root.rel_position = pos;

        return sub_root;
    }

    pub fn end(atom: *Atom) void {
        close(atom);
        close(cu.state.ui_tooltip_root);
    }
};

//= scroll area

pub const scroll_area = struct {
    pub const basic = struct {
        pub const Params = struct {
            scroll_axis: Atom.LayoutAxis,
            item_size_px: f32,
            ptr_offset_px: *f32,
        };

        pub const Handle = struct {
            view: *Atom,
            offset_container: *Atom,

            index_range: math.Range1D(usize),
        };

        pub fn begin(
            params: Params,
        ) Handle {
            const axis = params.scroll_axis;
            const item_size_px = params.item_size_px;
            const offset_px = params.ptr_offset_px;

            const view = open("###scroll view");
            view.layout_axis = axis;
            view.flags.insert(.clip_rect);
            view.flags.insert(.view_scroll);
            view.flags.insert(.allowOverflowForAxis(axis));

            offset_px.* += view.interaction().scroll.fromAxis(axis);
            if (offset_px.* < 0)
                offset_px.* = 0;

            const pixel_range = math.range1d(
                offset_px.*,
                offset_px.* + view.rect.lengthFromAxis(axis),
            );

            const index_range = math.range1d(
                @as(usize, @intFromFloat(pixel_range.min / item_size_px)),
                @as(usize, @intFromFloat(pixel_range.max / item_size_px)) + 1,
            );

            stacks.flags.push(.floatingForAxis(axis));
            stacks.layout_axis.push(axis);
            stacks.pref_size.push(.square(.fit));
            const offset_container = open("###scroll container");

            offset_container.rel_position = .withAxis(axis, -offset_px.*, 0);

            const space_before_px =
                @as(f32, @floatFromInt(index_range.min)) * item_size_px;
            // const space_after =
            //     @as(f32, @floatFromInt(index_range.max)) * item_size_px;

            stacks.pref_size.push(.withAxis(axis, .px(space_before_px), .grow));
            _ = spacer();

            return .{
                .view = view,
                .offset_container = offset_container,

                .index_range = index_range,
            };
        }

        pub fn end(data: Handle) void {
            close(data.offset_container);
            close(data.view);
        }
    };
};

//= center

pub const centered = struct {
    pub const CenteredData = struct {
        axis: Atom.LayoutAxis,
        outer: *Atom,
        inner: *Atom,
        padding: *Atom,
    };

    pub fn begin(axis: Atom.LayoutAxis) CenteredData {
        std.debug.assert(axis != .none);

        b.stacks.pref_size.push(.square(.grow));
        b.stacks.layout_axis.push(axis);
        const outer = b.open("outer");

        b.stacks.pref_size.push(.withAxis(axis, .none, .grow));
        const padding = b.spacer();

        b.stacks.pref_size.push(.withAxis(axis, .fit, .grow));
        b.stacks.layout_axis.push(axis);
        const inner = b.open("inner");

        return .{
            .axis = axis,
            .outer = outer,
            .inner = inner,
            .padding = padding,
        };
    }

    pub fn end(data: CenteredData) void {
        defer b.close(data.outer);
        defer b.close(data.inner);

        const outer_length = data.outer.rect.lengthFromAxis(data.axis);
        const inner_length = data.inner.rect.lengthFromAxis(data.axis);
        const padding_length = (outer_length - inner_length) / 2;
        switch (data.axis) {
            .none => unreachable,
            .x => data.padding.pref_size.width = .px(padding_length),
            .y => data.padding.pref_size.height = .px(padding_length),
        }
    }
};

//= stacks

pub const Stacks = struct {
    palette: VolatileStack(Atom.pallete.PalletePartial),
    font: VolatileStack(FontKind),
    pref_size: VolatileStack(math.Size(Atom.PrefSize)),
    layout_axis: VolatileStack(Atom.LayoutAxis),
    hover_pointer: VolatileStack(cu.PointerKind),
    flags: VolatileStack(Atom.Flags),
    text_align: VolatileStack(math.Size(Atom.Alignment)),
    alignment: VolatileStack(math.Size(Atom.Alignment)),
    padding: VolatileStack(Atom.Padding),
    border_width: VolatileStack(f32),
    corner_radius: VolatileStack(f32),

    const empty = Stacks{
        .palette = .empty,
        .pref_size = .empty,
        .font = .empty,
        .layout_axis = .empty,
        .hover_pointer = .empty,
        .flags = .empty,
        .text_align = .empty,
        .alignment = .empty,
        .padding = .empty,
        .border_width = .empty,
        .corner_radius = .empty,
    };

    pub fn VolatileStack(comptime T: type) type {
        return struct {
            const Self = @This();

            pub const StackItem = struct {
                item: T,
                once: bool,
            };

            stack: std.MultiArrayList(StackItem),

            pub const empty = Self{ .stack = .empty };

            /// Push an item that will be removed when read next
            pub fn push(self: *Self, item: T) void {
                self.pushRaw(.{ .item = item, .once = true });
            }

            /// Push an item that can be read multiple times.
            /// Reqires a pop to remove.
            pub fn pushForMany(self: *Self, item: T) void {
                self.pushRaw(.{ .item = item, .once = false });
            }

            pub fn pushRaw(self: *Self, item: StackItem) void {
                self.stack.append(cu.state.arena, item) catch @panic("oom");
            }

            /// Read the top item - possibly removing it from the stack
            pub fn topVolatile(self: *Self) ?T {
                const elem = self.topRaw() orelse return null;
                if (elem.once)
                    self.stack.len -= 1;
                return elem.item;
            }

            /// Read the top item - without possibly removing it from the stack
            pub fn topStable(self: Self) ?T {
                const elem = self.topRaw() orelse return null;
                return elem.item;
            }

            inline fn topRaw(self: Self) ?StackItem {
                if (self.stack.len == 0) {
                    @branchHint(.unlikely);
                    return null;
                }
                return self.stack.get(self.stack.len - 1);
            }

            pub fn peek(self: Self, i: usize) ?T {
                if (self.stack.len == 0) {
                    @branchHint(.unlikely);
                    return null;
                }
                if (self.stack.len <= i) return null;

                return self.stack.get(self.stack.len - 1 - i).item;
            }

            /// Remove the top item from the stack,
            /// irrespective of if its volatile or not
            pub fn pop(self: *Self) ?T {
                if (self.stack.pop()) |elem| {
                    @branchHint(.likely);
                    return elem.item;
                } else {
                    @branchHint(.unlikely);
                    return null;
                }
            }
        };
    }
};

pub var stacks: Stacks = .empty;

pub const dbg = struct {
    const colors = [_]math.RgbaU8{
        .hexRgb(0x0000ff), // blue
        .hexRgb(0x00ffff), // cyan
        .hexRgb(0x00ff00), // green
        .hexRgb(0xffff00), // yellow
        .hexRgb(0xff0000), // red
    };

    var idx: usize = 0;

    pub fn getColor() math.RgbaU8 {
        const color = colors[idx % colors.len];
        idx += 1;
        return color;
    }

    pub fn debugBorder(atom: *Atom) void {
        atom.flags.insert(.draw_border);
        atom.palette.set(.border, getColor());
    }
};

/// returns `value` multiplied by the top font size
pub fn em(value: f32) f32 {
    const top_font = stacks.font.topStable().?;
    const font_size = fontHeight(top_font);
    return value * font_size;
}

pub fn fontHeight(font_kind: FontKind) f32 {
    const font_handle = cu.state.font_kind_map.get(font_kind);
    const font_size = cu.state.callbacks.lineHeight(font_handle);
    return font_size;
}

// /// returns `value` multiplied by the root/default font size
// pub fn rem(value: f32) f32 {
//     const root_font = cu.state.default_font;
//     const font_handle = cu.state.font_kind_map.get(root_font);
//     const font_size = cu.state.callbacks.fontSize(font_handle);
//     return value * font_size;
// }
