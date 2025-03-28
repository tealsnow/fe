const std = @import("std");

const cu = @import("cu.zig");
const debugAssert = cu.debugAssert;
const Atom = cu.Atom;

pub fn startBuild(window_id: u32) void {
    cu.state.palette_stack.clearAndReset();
    cu.state.font_stack.clearAndFree();

    cu.state.scope_locals.clearAndFree(cu.state.alloc_temp); // @FIXME: not sure if this is needed
    _ = cu.state.arena.reset(.retain_capacity);

    cu.state.palette_stack.push(cu.state.default_palette);
    cu.state.font_stack.push(cu.state.default_font);

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

    cu.state.atom_parent_stack.push(cu.state.ui_root);

    cu.state.next_ctx_menu_open = cu.state.ctx_menu_open;
}

pub fn endBuild() void {
    var to_remove = std.ArrayList(Atom.Key)
        .initCapacity(cu.state.alloc_temp, cu.State.MaxAtoms / 4) catch @panic("oom");

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

    const root = cu.state.atom_parent_stack.pop().?;
    debugAssert(
        cu.state.atom_parent_stack.stack.items.len == 0,
        "Parent stack not empty after build; likely forgot a defer -- last: {}",
        .{root},
    );
    debugAssert(
        cu.state.ui_root.key.eql(root.key),
        "Last item on parent stack was not ui root; instead found: {}",
        .{root},
    );
    cu.state.atom_parent_stack.clearAndFree();

    cu.layout(root) catch @panic("oom");
    cu.layout(cu.state.ui_ctx_menu_root) catch @panic("oom");
    // cu.layout(cu.state.ui_tooltip_root) catch @panic("oom");

    cu.state.hot_atom_key = .nil;

    cu.state.ctx_menu_open = cu.state.next_ctx_menu_open;

    cu.state.current_build_index += 1;
    _ = cu.state.event_pool.reset(.retain_capacity);
    _ = cu.state.event_node_pool.reset(.retain_capacity);
    cu.state.event_list = .{};

    cu.state.ui_built = true;
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
        const atom = cu.state.alloc_temp.create(Atom) catch @panic("oom");
        is_first_frame = true;
        break :blk atom;
    } else if (tryAtomFromKey(key)) |atom| blk: {
        atom.key = key;
        break :blk atom;
    } else blk: {
        const atom = cu.state.atom_pool.create() catch @panic("oom");
        is_first_frame = true;
        const bad_atom = cu.state.atom_map.fetchPut(cu.state.alloc_persistent, key, atom) catch @panic("oom");
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
    atom.flags = .{};
    atom.pref_size = .zero;
    atom.layout_axis = .none;
    atom.text_align = .square(.center);

    // per build info
    atom.font = cu.state.font_stack.top().?;
    atom.palette = cu.state.palette_stack.dupeTop().?;

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
    const string = std.fmt.allocPrint(cu.state.alloc_temp, fmt, args) catch @panic("oom");
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
    cu.state.atom_parent_stack.push(atom);
    return atom;
}

pub fn openf(comptime fmt: []const u8, args: anytype) *Atom {
    const atom = buildf(fmt, args);
    cu.state.atom_parent_stack.push(atom);
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
    atom.pref_size = .square(.text);
    atom.display_string = string;
    atom.flags = atom.flags.drawText();
    return atom;
}

pub fn labelf(comptime fmt: []const u8, args: anytype) *Atom {
    const string = std.fmt.allocPrint(cu.state.alloc_temp, fmt, args) catch @panic("oom");
    return label(string);
}

pub fn spacer(pref_size: cu.Axis2(Atom.PrefSize)) *Atom {
    const atom = buildFromKey(.nil);
    atom.pref_size = pref_size;
    return atom;
}

// =-= stacks

pub inline fn pushFont(fontid: cu.FontId) void {
    cu.state.font_stack.push(fontid);
}

pub inline fn popFont() void {
    _ = cu.state.font_stack.pop().?;
}

pub inline fn pushPalette(palette: Atom.Palette) void {
    cu.state.palette_stack.push(palette);
}

pub inline fn popPalette() void {
    _ = cu.state.palette_stack.pop().?;
}

pub fn pushTextColor(color: cu.Color) void {
    const current = cu.state.palette_stack.top().?;
    var palette = current.*;
    palette.text = color;
    pushPalette(palette);
}

pub fn pushBackgroundColor(color: cu.Color) void {
    const current = cu.state.palette_stack.top().?;
    var palette = current.*;
    palette.background = color;
    pushPalette(palette);
}
