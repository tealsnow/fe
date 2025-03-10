const std = @import("std");
const assert = std.debug.assert;

const cu = @import("cu.zig");
const Atom = cu.Atom;

pub fn startBuild(window_id: u32) void {
    cu.state.palette_stack.clearAndReset();
    cu.state.font_stack.clearAndFree();

    cu.state.scope_locals.clearAndFree(cu.state.alloc_temp); // @FIXME: not sure if this is needed
    _ = cu.state.arena.reset(.retain_capacity);

    cu.state.palette_stack.push(cu.state.default_palette);
    cu.state.font_stack.push(cu.state.default_font);

    const root = buildAtomFromStringF("###root-window-id:{x}", .{window_id});

    root.pref_size = .{
        .w = .px(cu.state.window_size.w),
        .h = .px(cu.state.window_size.h),
    };
    root.layout_axis = .x;
    root.rect = .range(.vec(0, 0), cu.state.window_size.asVec());

    cu.state.atom_parent_stack.push(root);
    cu.state.ui_root = root;
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
        const atom = cu.state.atom_map.fetchSwapRemove(key).?.value;
        cu.state.atom_pool.destroy(atom);
    }

    const root = cu.state.atom_parent_stack.pop().?;
    assert(cu.state.atom_parent_stack.stack.items.len == 0); // ensure stack is empty after build
    assert(cu.state.ui_root.key.eql(root.key));
    cu.state.atom_parent_stack.clearAndFree();

    cu.layout(root) catch @panic("oom");

    if (cu.state.active_atom_key.eql(.nil)) {
        cu.state.hot_atom_key = .nil;
    }

    cu.state.current_build_index += 1;

    _ = cu.state.event_pool.reset(.retain_capacity);
    _ = cu.state.event_node_pool.reset(.retain_capacity);
    cu.state.event_list = .{};
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

pub fn buildAtomFromKey(key: Atom.Key) *Atom {
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
        const atom = cu.state.allocAtom();
        is_first_frame = true;
        const bad_atom = cu.state.atom_map.fetchPut(cu.state.alloc_persistent, key, atom) catch @panic("oom");
        assert(bad_atom == null);

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

pub fn buildAtomFromString(string: []const u8) *Atom {
    const seed = if (cu.state.atom_parent_stack.top()) |parent| @intFromEnum(parent.key) else 0;
    const display_string, const key = Atom.Key.processString(seed, string);

    const atom = buildAtomFromKey(key);
    atom.string = string;
    atom.display_string = display_string;

    return atom;
}

pub fn buildAtomFromStringF(comptime fmt: []const u8, args: anytype) *Atom {
    const string = std.fmt.allocPrint(cu.state.alloc_temp, fmt, args) catch @panic("oom");
    const atom = buildAtomFromString(string);
    return atom;
}

pub fn ui(flags: Atom.Flags, string: []const u8) *Atom {
    const atom = buildAtomFromString(string);
    atom.flags = flags;
    cu.state.atom_parent_stack.push(atom);
    return atom;
}

pub fn uif(flags: Atom.Flags, comptime fmt: []const u8, args: anytype) *Atom {
    const atom = buildAtomFromStringF(fmt, args);
    atom.flags = flags;
    cu.state.atom_parent_stack.push(atom);
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

pub fn growSpacer() *Atom {
    const a = ui(.{}, "");
    a.end();
    a.pref_size = .{ .w = .grow, .h = .grow };
    return a;
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

pub inline fn pushTextColor(color: cu.Color) void {
    const current = cu.state.palette_stack.top().?;
    var palette = current.*;
    palette.text = color;
    pushPalette(palette);
}

pub inline fn pushBackgroundColor(color: cu.Color) void {
    const current = cu.state.palette_stack.top().?;
    var palette = current.*;
    palette.background = color;
    pushPalette(palette);
}
