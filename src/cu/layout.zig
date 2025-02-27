const std = @import("std");
const assert = std.debug.assert;

const cu = @import("cu.zig");
const Atom = cu.Atom;
const AxisKind = cu.AxisKind;
const TextData = cu.TextData;
const SizeKind = cu.SizeKind;

const TermColor = @import("../TermColor.zig");

pub fn layout(root: *Atom) !void {
    for (AxisKind.Array) |axis| {
        standalone(root, axis);
        upwardsDependent(root, axis);
        downwardsDependnt(root, axis);
        solveViolations(root, axis);
        position(root, axis);
    }
}

fn standalone(atom: *Atom, axis: AxisKind) void {
    // any-order

    const axis_i = @intFromEnum(axis);
    const size = atom.size.arr[axis_i];
    switch (size.kind) {
        .none => {},
        .pixels => {
            atom.fixed_size.arr[axis_i] = size.value;
        },
        .text_content => {
            const data = TextData.init(atom.string) catch @panic("oom");
            atom.text_data = data;

            atom.fixed_size.arr[axis_i] = @floatFromInt(data.size.arr[axis_i]);
        },
        else => {},
    }

    if (atom.children) |children| {
        var maybe_child: ?*Atom = children.first;
        while (maybe_child) |child| : (maybe_child = child.siblings.next) {
            standalone(child, axis);
        }
    }
}

fn upwardsDependent(atom: *Atom, axis: AxisKind) void {
    // pre-order

    const axis_i = @intFromEnum(axis);
    const size = atom.size.arr[axis_i];

    switch (size.kind) {
        .percent_of_parent => {
            assert(atom.parent != null);
            assert(size.value >= 0 and size.value <= 1);

            const parent = atom.parent.?;
            atom.fixed_size.arr[axis_i] = parent.fixed_size.arr[axis_i] * size.value;
        },
        else => {},
    }

    if (atom.children) |children| {
        var maybe_child: ?*Atom = children.first;
        while (maybe_child) |child| : (maybe_child = child.siblings.next) {
            upwardsDependent(child, axis);
        }
    }
}

fn downwardsDependnt(atom: *Atom, axis: AxisKind) void {
    // post-order

    if (atom.children) |children| {
        var maybe_child: ?*Atom = children.first;
        while (maybe_child) |child| : (maybe_child = child.siblings.next) {
            downwardsDependnt(child, axis);
        }
    }

    const axis_i = @intFromEnum(axis);
    const size = atom.size.arr[axis_i];

    switch (size.kind) {
        .children_sum => {
            assert(atom.children != null);
            const children = atom.children.?;

            var accum: f32 = 0;
            var maybe_child: ?*Atom = children.first;
            while (maybe_child) |child| : (maybe_child = child.siblings.next) {
                accum += child.fixed_size.arr[axis_i];
            }

            atom.fixed_size.arr[axis_i] = accum;
        },
        else => {},
    }
}

fn solveViolations(atom: *Atom, axis: AxisKind) void {
    // https://github.com/EpicGamesExt/raddebugger/blob/a1e7ec5a0e9c8674f5b0271ce528f6b651d43564/src/ui/ui_core.c#L1705C1-L1705C44

    // pre-order

    if (atom.children == null) return;
    const children = atom.children.?;
    assert(atom.layout_axis != .none);

    const axis_i = @intFromEnum(axis);

    // non-layout axis
    if (atom.layout_axis != axis) {
        const allowed_size = atom.fixed_size.arr[axis_i];
        var maybe_child: ?*Atom = children.first;
        while (maybe_child) |child| : (maybe_child = child.siblings.next) {
            const child_size = child.fixed_size.arr[axis_i];
            const violation = child_size - allowed_size;
            const max_fixup = child_size;
            // const fixup = std.math.clamp(0, violation, max_fixup);
            const fixup = @max(violation, @min(0, max_fixup));
            if (fixup > 0)
                child.fixed_size.arr[axis_i] -= fixup;
        }
    }
    // layout axis
    else {
        const total_allowed_size = atom.fixed_size.arr[axis_i];
        var total_size: f32 = 0;
        var total_weighted_size: f32 = 0;

        // scope bc andrew refuses adding a proper c-style for loop
        // prevent 'maybe_child' from poisening the scope
        {
            var maybe_child: ?*Atom = children.first;
            while (maybe_child) |child| : (maybe_child = child.siblings.next) {
                total_size += child.fixed_size.arr[axis_i];
                total_weighted_size += child.fixed_size.arr[axis_i] * (1 - child.size.arr[axis_i].strictness);
            }
        }

        // if there is a violation we need to subtact some amount from all children
        const violation = total_size - total_allowed_size;
        if (violation > 0) {
            // figure out how much we can take in total
            // var child_fixup_sum: f32 = 0;
            const child_fixups = cu.state.alloc_temp.alloc(f32, children.count) catch @panic("oom");
            defer cu.state.alloc_temp.free(child_fixups);
            {
                var child_idx: usize = 0;
                var maybe_child: ?*Atom = children.first;
                while (maybe_child) |child| : (maybe_child = child.siblings.next) {
                    var fixup_size_this_child = child.fixed_size.arr[axis_i] * (1 - child.size.arr[axis_i].strictness);
                    fixup_size_this_child = @max(0, fixup_size_this_child);
                    child_fixups[child_idx] = fixup_size_this_child;
                    // child_fixup_sum += fixup_size_this_child;

                    child_idx += 1;
                }
            }

            // fixup child sizes
            {
                var child_idx: usize = 0;
                var maybe_child: ?*Atom = children.first;
                while (maybe_child) |child| : (maybe_child = child.siblings.next) {
                    var fixup_pct = (violation / total_weighted_size);
                    fixup_pct = @max(fixup_pct, 0);
                    child.fixed_size.arr[axis_i] -= child_fixups[child_idx] * fixup_pct;

                    child_idx += 1;
                }
            }
        }
    }

    // @FIXME: only if overflow is allowed
    // // fix upwards depentent sizes
    // {
    //     var maybe_child: ?*Atom = children.first;
    //     while (maybe_child) |child| : (maybe_child = child.siblings.next) {
    //         if (child.size.arr[axis_i].kind == .percent_of_parent) {
    //             child.fixed_size.arr[axis_i] = root.fixed_size.arr[axis_i] * child.size.arr[axis_i].value;
    //         }
    //     }
    // }

    // recurse
    {
        var maybe_child: ?*Atom = children.first;
        while (maybe_child) |child| : (maybe_child = child.siblings.next) {
            solveViolations(child, axis);
        }
    }
}

fn position(atom: *Atom, axis: AxisKind) void {
    // pre-order

    if (atom.children == null) return;
    const children = atom.children.?;

    const axis_i = @intFromEnum(axis);

    var bounds: f32 = 0;
    {
        var layout_position: f32 = 0;
        var maybe_child: ?*Atom = children.first;
        while (maybe_child) |child| : (maybe_child = child.siblings.next) {
            // // grab original position
            // var original_position = @min(child.rect.p.p0.arr[axis_i], child.rect.p.p1.arr[axis_i]);

            child.rel_position.arr[axis_i] = layout_position;
            if (atom.layout_axis == axis) {
                layout_position += child.fixed_size.arr[axis_i];
                bounds += child.fixed_size.arr[axis_i];
            } else {
                bounds = @max(bounds, child.fixed_size.arr[axis_i]);
            }

            child.rect.pt.p0.arr[axis_i] = atom.rect.pt.p0.arr[axis_i] + child.rel_position.arr[axis_i];
            child.rect.pt.p1.arr[axis_i] = child.rect.pt.p0.arr[axis_i] + child.fixed_size.arr[axis_i];

            child.rect.pt.p0.vec.x = @floor(child.rect.pt.p0.vec.x);
            child.rect.pt.p0.vec.y = @floor(child.rect.pt.p0.vec.y);
            child.rect.pt.p1.vec.x = @floor(child.rect.pt.p1.vec.x);
            child.rect.pt.p1.vec.y = @floor(child.rect.pt.p1.vec.y);

            // // grab new position
            // const new_position = @min(child.rect.p.p0.arr[axis_i], child.rect.p.p1.arr[axis_i]);

            // store position delta
            // ...
        }
    }

    // store view bounds
    {
        atom.view_bounds.arr[axis_i] = bounds;
    }

    // recurse
    {
        var maybe_child: ?*Atom = children.first;
        while (maybe_child) |child| : (maybe_child = child.siblings.next) {
            position(child, axis);
        }
    }
}

pub const DebugPrintTreeOptions = struct {
    children: bool = true,
    size: bool = true,
    computed_size: bool = true,
    rel_position: bool = false,
    rect: bool = false,

    targeted_size_kind: ?[]const SizeKind = null,
};

pub fn debugPrintTree(atom: *Atom, depth: usize, options: DebugPrintTreeOptions) void {
    const red_bg = TermColor{
        .color = .red,
        .layer = .background,
        .bright = true,
    };
    const red = TermColor{ .color = .red };
    const bold = TermColor{ .style = .{ .bold = true } };
    const reset = TermColor.Reset;

    const targeted: bool = if (options.targeted_size_kind) |targets|
        for (targets) |target|
            if (atom.size.sz.w.kind == target or
                atom.size.sz.h.kind == target)
                break true
            else {}
        else
            false
    else
        false;

    for (0..depth) |_| std.debug.print("    ", .{});
    if (targeted)
        std.debug.print("- {}{s}{}\n", .{ red_bg, atom.string, reset })
    else
        std.debug.print("- {s}\n", .{atom.string});

    const has_children = atom.children != null;
    const layout_axis = atom.layout_axis;

    for (0..depth) |_| std.debug.print("    ", .{});
    std.debug.print("   has children: {}\n", .{has_children});
    for (0..depth) |_| std.debug.print("    ", .{});
    std.debug.print("   layout axis: {}\n", .{layout_axis});

    if (options.size) {
        const size = atom.size;

        const kinds: []const []const u8 = &.{ "w", "h" };

        for (0..depth) |_| std.debug.print("    ", .{});
        std.debug.print("   size: {{\n", .{});
        for (size.arr, 0..) |s, idx| {
            for (0..depth) |_| std.debug.print("    ", .{});

            const target = if (options.targeted_size_kind) |targets|
                for (targets) |target|
                    if (s.kind == target)
                        break true
                    else {}
                else
                    false
            else
                false;

            if (target)
                std.debug.print(
                    "     {s}: {{ {}.kind = .{s}{}, .value = {d}, .strictness = {d} }}\n",
                    .{ kinds[idx], red, @tagName(s.kind), reset, s.value, s.strictness },
                )
            else
                std.debug.print(
                    "     {s}: {{ .kind = .{s}, .value = {d}, .strictness = {d} }}\n",
                    .{ kinds[idx], @tagName(s.kind), s.value, s.strictness },
                );
        }
        for (0..depth) |_| std.debug.print("    ", .{});
        std.debug.print("   }}\n", .{});
    }

    if (options.computed_size) {
        const computed_size = atom.fixed_size;
        for (0..depth) |_| std.debug.print("    ", .{});
        if (targeted)
            std.debug.print(
                "   {}computed size: {d} x {d}{}\n",
                .{ bold, computed_size.sz.w, computed_size.sz.h, reset },
            )
        else
            std.debug.print(
                "   computed size: {d} x {d}\n",
                .{ computed_size.sz.w, computed_size.sz.h },
            );
    }

    if (options.rel_position) {
        const rel_position = atom.rel_position;
        for (0..depth) |_| std.debug.print("    ", .{});
        std.debug.print(
            "   relative position: {d} x {d}\n",
            .{ rel_position.vec.x, rel_position.vec.y },
        );
    }

    if (options.rect) {
        const rect = atom.rect;
        for (0..depth) |_| std.debug.print("    ", .{});
        std.debug.print(
            "   rect: {d} x {d} @ {d} x {d}\n",
            .{ rect.pt.p0.vec.x, rect.pt.p0.vec.y, rect.pt.p1.vec.x, rect.pt.p1.vec.y },
        );
    }

    if (options.children and has_children) {
        const children = atom.children.?;
        var maybe_child: ?*Atom = children.first;
        while (maybe_child) |child| : (maybe_child = child.siblings.next) {
            debugPrintTree(child, depth + 1, options);
        }
    }
}
