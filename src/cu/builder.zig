const std = @import("std");
const log = std.log.scoped(.@"cu::builder");

const cu = @import("cu.zig");
const debugAssert = cu.debugAssert;
const Atom = cu.Atom;
const AtomFlags = cu.AtomFlags;

const tracy = @import("tracy");

var trace_build: tracy.ZoneContext = undefined;

pub fn startFrame() void {
    const current_time = std.time.Instant.now() catch @panic("no std.time.Instant support");

    const dt_ns = current_time.since(cu.state.frame_previous_time);
    cu.state.frame_previous_time = current_time;

    cu.state.dt_s = @as(f32, @floatFromInt(dt_ns)) / @as(f32, std.time.ns_per_s);
}

pub fn endFrame() void {
    //
}

pub fn startBuild(window_id: u32) void {
    trace_build = tracy.beginZone(@src(), .{ .name = "ui build" });
    const trace_start = tracy.beginZone(@src(), .{ .name = "ui build setup" });
    defer trace_start.end();

    cu.state.scope_locals.clearAndFree(cu.state.arena);

    { // clear stacks
        cu.state.stack_pref_size = .empty;
        cu.state.stack_font = .empty;
        cu.state.stack_palette = .empty;
        cu.state.stack_layout_axis = .empty;
        cu.state.stack_flags = .empty;
        cu.state.stack_text_align = .empty;
    }

    { // setup stacks
        cu.state.stack_pref_size.push(cu.state.arena, .axis(.fill, .fill), false);
        cu.state.stack_font.push(cu.state.arena, cu.state.default_font, false);
        cu.state.stack_palette.push(cu.state.arena, cu.state.default_palette, false);
        cu.state.stack_layout_axis.push(cu.state.arena, .none, false);
        cu.state.stack_flags.push(cu.state.arena, .{}, false);
        cu.state.stack_text_align.push(cu.state.arena, .square(.center), false);
    }

    { // setup ui roots

        const root = buildFromStringF("###root window-id:{x}", .{window_id});
        root.pref_size = .axis(.px(cu.state.window_size.w), .px(cu.state.window_size.h));
        root.rect = .range(.vec(0, 0), cu.state.window_size.intoVec());
        root.layout_axis = .x;
        cu.state.ui_root = root;

        const ctx_menu_root = buildFromStringF("###ctx_menu_root window-id:{x}", .{window_id});
        ctx_menu_root.pref_size = .square(.fit);
        ctx_menu_root.rect = .zero;
        ctx_menu_root.layout_axis = .x;
        cu.state.ui_ctx_menu_root = ctx_menu_root;

        // const tooltip_root = buildFromStringF("###tooltip_root window-id:{x}", .{window_id});
        // tooltip_root.pref_size = .square(.fit);
        // tooltip_root.rect = .zero;
        // tooltip_root.layout_axis = .x;
        // cu.state.ui_tooltip_root = tooltip_root;
    }

    { // setup atom stack
        cu.state.atom_parent_stack.clearAndFree(cu.state.arena);
        cu.state.atom_parent_stack.push(cu.state.arena, cu.state.ui_root);
    }

    cu.state.next_ctx_menu_open = cu.state.ctx_menu_open;
}

pub fn endBuild() void {
    defer trace_build.end();
    const trace_end = tracy.beginZone(@src(), .{ .name = "ui build end" });
    defer trace_end.end();

    // remove stale atoms
    {
        const trace = tracy.beginZone(@src(), .{ .name = "remove stale atoms" });
        defer trace.end();

        var to_remove = std.ArrayList(Atom.Key)
            .initCapacity(cu.state.arena, cu.state.atom_map.count() / 4) catch @panic("oom");

        for (cu.state.atom_map.values()) |atom| {
            if (atom.build_index_touched_last < cu.state.current_build_index) {
                to_remove.append(atom.key) catch @panic("oom");
            }
        }

        for (to_remove.items) |key| {
            if (key == .nil) continue;
            const atom = cu.state.atom_map.fetchSwapRemove(key).?.value;
            cu.state.atom_pool.destroy(atom);
        }
    }

    // check stack
    const root = root: {
        const root = cu.state.atom_parent_stack.pop().?;
        debugAssert(
            cu.state.atom_parent_stack.list.items.len == 0,
            "Parent stack not empty after build; likely forgot a defer -- last: {}",
            .{root},
        );
        debugAssert(
            cu.state.ui_root.key.eql(root.key),
            "Last item on parent stack was not ui root; instead found: {}",
            .{root},
        );
        break :root root;
    };

    // layout
    {
        const trace = tracy.beginZone(@src(), .{ .name = "layout" });
        defer trace.end();

        cu.layout(root) catch @panic("oom");
        cu.layout(cu.state.ui_ctx_menu_root) catch @panic("oom");
        // cu.layout(cu.state.ui_tooltip_root) catch @panic("oom");
    }

    // reset and cleanup state
    {
        cu.state.hot_atom_key = .nil;
        cu.state.ctx_menu_open = cu.state.next_ctx_menu_open;
        cu.state.current_build_index += 1;
        cu.state.ui_built = true;

        _ = cu.state.event_pool.reset(.retain_capacity);
        _ = cu.state.event_node_pool.reset(.retain_capacity);
        cu.state.event_list = .{};

        _ = cu.state.arena_allocator.reset(.retain_capacity);
    }
}

pub fn tryAtomFromKey(key: Atom.Key) ?*Atom {
    var result: ?*Atom = null;
    if (!key.eql(.nil)) {
        if (cu.state.atom_map.get(key)) |atom| {
            result = atom;
        }
    }
    return result;
}

pub fn buildFromKey(key: Atom.Key) *Atom {
    cu.state.build_atom_count += 1;

    var is_first_frame = false;

    const atom = if (Atom.Key.eql(key, .nil)) blk: {
        const atom = cu.state.arena.create(Atom) catch @panic("oom");
        is_first_frame = true;
        break :blk atom;
    } else if (tryAtomFromKey(key)) |atom| blk: {
        atom.key = key;
        break :blk atom;
    } else blk: {
        const atom = cu.state.atom_pool.create() catch @panic("oom");
        is_first_frame = true;
        const bad_atom = cu.state.atom_map.fetchPut(cu.state.gpa, key, atom) catch @panic("oom");
        debugAssert(
            bad_atom == null,
            "got an atom for a key that was thought to not have a value -- keying/hashing is broken",
            .{},
        );

        break :blk atom;
    };

    if (is_first_frame) {
        atom.* = .{
            .key = key,
            .build_index_touched_first = cu.state.current_build_index,
            .build_index_touched_last = cu.state.current_build_index,

            .hot_t = 0,
            .active_t = 0,
        };
    } else {
        atom.build_index_touched_last = cu.state.current_build_index;
    }

    // zero out per build info
    atom.children = null;
    atom.siblings.next = null;
    atom.siblings.prev = null;
    atom.parent = null;

    atom.string = "";
    atom.display_string = "";

    // per build info
    atom.pref_size = cu.state.stack_pref_size.top().?;
    atom.font = cu.state.stack_font.top().?;
    atom.palette = cu.state.stack_palette.top().?;
    atom.layout_axis = cu.state.stack_layout_axis.top().?;
    atom.flags = cu.state.stack_flags.top().?;
    atom.text_align = cu.state.stack_text_align.top().?;

    // add to parent
    if (cu.state.atom_parent_stack.top()) |parent| {
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

pub fn buildFromString(string: []const u8) *Atom {
    const seed = if (cu.state.atom_parent_stack.top()) |parent| @intFromEnum(parent.key) else 0;
    const display_string, const key = Atom.Key.processString(seed, string);

    const atom = buildFromKey(key);
    atom.string = string;
    atom.display_string = display_string;

    return atom;
}

pub fn buildFromStringF(comptime fmt: []const u8, args: anytype) *Atom {
    const string = std.fmt.allocPrint(cu.state.arena, fmt, args) catch @panic("oom");
    return buildFromString(string);
}

// =-= build shorthand

pub fn build(string: []const u8) *Atom {
    return buildFromString(string);
}

pub fn buildf(comptime fmt: []const u8, args: anytype) *Atom {
    return buildFromStringF(fmt, args);
}

// =-= context menu

pub fn ctxMenuOpen(key: Atom.Key, anchor_box_key: Atom.Key, anchor_off: cu.Vec2(f32)) void {
    _ = key; // autofix
    _ = anchor_box_key; // autofix
    _ = anchor_off; // autofix

    cu.state.next_ctx_menu_open = true;
    // ctx_menu_changed = true
    // ctx_menu_open_t = 0
    // ctx_menu_key = key
    // next_ctx_menu_anchor_key = anchor_box_key
    // ctx_menu_anchor_off = anchor_off
    // ctx_menu_touched_this_frame = true
    // ctx_menu_anchor_atom_last_pos = .zero
}

pub fn ctxMenuClose() void {
    cu.state.next_ctx_menu_open = false;
}

pub fn beginCtxMenu(key: Atom.Key) bool {
    _ = key; // autofix
    // const is_open = key.eql(ctx_menu_key) and cu.state.ctx_menu_open;
    // is_in_ctx_menu = is_open;
    //
}

pub fn endCtxMenu() void {
    // if (is_in_ctx_menu) {
    //     is_in_ctx_menu = false;
    // }
    //
}

// =-= hierarchy management

pub fn open(string: []const u8) *Atom {
    const atom = build(string);
    cu.state.atom_parent_stack.push(cu.state.arena, atom);
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
        Atom.Key.eql(atom.key, top.key),
        "mismatched open/close; likely forgot a defer: expected {} but got {}",
        .{ atom, top },
    );
}

// =-= basic widgets

pub fn label(string: []const u8) *Atom {
    const atom = buildFromKey(.nil);
    atom.pref_size = .square(.text); // should this stay? or let the user decide with pushPrefSize
    atom.display_string = string;
    atom.flags = atom.flags.drawText();
    return atom;
}

pub fn labelf(comptime fmt: []const u8, args: anytype) *Atom {
    const string = std.fmt.allocPrint(cu.state.arena, fmt, args) catch @panic("oom");
    return label(string);
}

pub fn spacer() *Atom {
    return buildFromKey(.nil);
}

pub fn lineSpacer() *Atom {
    pushPrefSize(.once(.axis(.grow, .text)));
    const line_spacer = spacer();
    line_spacer.display_string = " ";
    return line_spacer;
}

pub fn baseClickableInteractionStyles(inter: cu.Interation) void {
    // @FIXME: the tranitions to and from no interation and hovering work,
    //  and from hovering to clicking, but not from clicking back to hovering

    const atom = inter.atom;
    atom.hot_t = cu.expSmooth(atom.hot_t, @as(f32, if (inter.f.hovering) 1 else 0));
    atom.active_t = cu.expSmooth(atom.active_t, @as(f32, if (inter.f.containsAny(.any_dragging)) 1 else 0));

    const palette = atom.palette;
    const from, const to, const lerp_t =
        if (inter.f.containsAny(.any_dragging))
            .{ palette.hot, palette.active, atom.active_t }
        else
            .{ palette.border, palette.hot, atom.hot_t };

    atom.palette.border = from.lerp(to, lerp_t);
}

pub fn button(string: []const u8) cu.Interation {
    const atom = build(string);
    atom.flags = atom.flags.clickable().drawText().drawBorder();

    const interaction = atom.interaction();
    baseClickableInteractionStyles(interaction);

    return interaction;
}

pub fn buttonf(comptime fmt: []const u8, args: anytype) *Atom {
    const string = std.fmt.allocPrint(cu.state.arena, fmt, args) catch @panic("oom");
    return button(string);
}

pub fn toggleSwitch(toggled: *bool) cu.Interation {
    cu.pushFlags(.once(AtomFlags.none.drawBorder().clickable()));
    cu.pushLayoutAxis(.once(.y));
    const toggle = cu.open("toggle box");
    defer cu.close(toggle);

    const size = toggle.fixed_size;
    const padding: f32 = size.h / 5;
    const middle_size: f32 = size.h - (2 * padding);

    cu.pushPrefSize(.once(.axis(.grow, .px(padding))));
    _ = cu.spacer();

    {
        cu.pushLayoutAxis(.once(.x));
        cu.pushPrefSize(.once(.axis(.grow, .grow)));
        const track = cu.open("track");
        defer cu.close(track);

        track.active_t = cu.expSmooth(
            track.active_t,
            if (toggled.*) size.w - middle_size - padding else padding,
        );

        cu.pushPrefSize(.once(.axis(.px(track.active_t), .grow)));
        _ = cu.spacer();

        cu.pushFlags(.once(AtomFlags.none.drawBackground()));
        cu.pushBackgroundColor(.once(cu.topPalette().text));
        cu.pushPrefSize(.once(.square(.px(middle_size))));
        _ = cu.build("toggle middle");
    }

    const inter = toggle.interaction();
    cu.baseClickableInteractionStyles(inter);

    if (inter.f.isClicked())
        toggled.* = !toggled.*;

    return inter;
}

// =-=-=-=-=-=-=
// =-= stacks

pub fn StackPushType(comptime T: type) type {
    return union(enum) {
        transient: T,
        persistent: T,

        pub const Self = @This();

        pub fn once(item: T) Self {
            return .{ .transient = item };
        }

        pub fn keep(item: T) Self {
            return .{ .persistent = item };
        }

        fn destructure(self: Self) struct { T, bool } {
            return switch (self) {
                .transient => |item| .{ item, true },
                .persistent => |item| .{ item, false },
            };
        }
    };
}

inline fn genericOnceStackPush(comptime T: type, stack: *cu.State.OnceStack(T), push_type: StackPushType(T)) void {
    const item, const once = push_type.destructure();
    stack.push(cu.state.arena, item, once);
}

// =-= prefSize

pub inline fn pushPrefSize(pref_size: StackPushType(cu.Axis2(Atom.PrefSize))) void {
    genericOnceStackPush(cu.Axis2(Atom.PrefSize), &cu.state.stack_pref_size, pref_size);
}

pub inline fn popPrefSize() void {
    _ = cu.state.stack_pref_size.pop();
}

// =-= Font

pub inline fn pushFont(fontid: StackPushType(cu.State.FontId)) void {
    genericOnceStackPush(cu.State.FontId, &cu.state.stack_font, fontid);
}

pub inline fn popFont() void {
    _ = cu.state.stack_font.pop().?;
}

// =-= palette

pub inline fn pushPalette(palette: StackPushType(Atom.Palette)) void {
    genericOnceStackPush(Atom.Palette, &cu.state.stack_palette, palette);
}

pub inline fn popPalette() void {
    _ = cu.state.stack_palette.pop().?;
}

pub inline fn topPalette() Atom.Palette {
    return cu.state.stack_palette.topNoPop().?;
}

// =-= textColor

pub inline fn pushTextColor(color: StackPushType(cu.Color)) void {
    const item, const once = color.destructure();
    var palette = topPalette();
    palette.text = item;
    pushPalette(if (once) .once(palette) else .keep(palette));
}

// =-= backgroundColor

pub inline fn pushBackgroundColor(color: StackPushType(cu.Color)) void {
    const item, const once = color.destructure();
    var palette = topPalette();
    palette.background = item;
    pushPalette(if (once) .once(palette) else .keep(palette));
}

// =-= layoutAxis

pub inline fn pushLayoutAxis(axis: StackPushType(Atom.LayoutAxis)) void {
    genericOnceStackPush(Atom.LayoutAxis, &cu.state.stack_layout_axis, axis);
}

pub inline fn popLayoutAxis() void {
    _ = cu.state.stack_layout_axis.pop().?;
}

// =-= flags

pub inline fn pushFlags(flags: StackPushType(Atom.Flags)) void {
    const item, const once = flags.destructure();
    cu.state.stack_flags.push(cu.state.arena, item, once);
}

pub inline fn popFlags() void {
    _ = cu.state.stack_flags.pop().?;
}

// =-= textAlignment

pub inline fn pushTextAlignment(text_alignment: StackPushType(cu.Axis2(Atom.TextAlignment))) void {
    genericOnceStackPush(cu.Axis2(Atom.TextAlignment), &cu.state.stack_text_align, text_alignment);
}

pub inline fn popTextAlignment() void {
    _ = cu.state.stack_text_align.pop().?;
}
