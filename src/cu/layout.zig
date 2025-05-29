const builtin = @import("builtin");
const std = @import("std");
const log = std.log.scoped(.@"cu.layout");

const cu = @import("cu.zig");
const debugAssert = cu.debugAssert;
const Atom = cu.Atom;
const math = cu.math;
const Axis2D = math.Axis2D;

const tracy = @import("tracy");

const TermColor = @import("../TermColor.zig");

const debug_print_atom = false;

pub fn layout(root: *Atom) !void {
    const trace = tracy.beginZone(@src(), .{ .name = "layout" });
    defer trace.end();
    tracy.print("{}", .{root});

    sizeText(root);
    for (Axis2D.array) |axis| {
        standalone(root, axis);
        upwardsDependent(root, axis);
        downwardsDependnt(root, axis);
        solveViolations(root, axis);
        position(root, axis);
    }
}

fn sizeText(root: *Atom) void {
    // any-order

    const trace = tracy.beginZone(@src(), .{ .name = "size text" });
    defer trace.end();
    tracy.print("{}", .{root});

    if (root.flags.contains(.draw_text) and root.display_string.len != 0)
        root.text_size =
            cu.state.callbacks.measureText(root.display_string, root.font);

    {
        var maybe_child = root.children.first;
        while (maybe_child) |child| : (maybe_child = child.siblings.next) {
            sizeText(child);
        }
    }
}

fn standalone(root: *Atom, axis_kind: Axis2D) void {
    // any-order

    const trace = tracy.beginZone(@src(), .{ .name = "standalone" });
    defer trace.end();
    tracy.print("{}", .{root});

    const axis = @intFromEnum(axis_kind);
    const size = root.pref_size.arr()[axis];
    switch (size.kind) {
        .none => {},
        .pixels => {
            root.fixed_size.arr()[axis] = size.value;
        },
        .percent_of_parent => {},
        .text_content => {
            const padding = size.value;
            const text_size = root.text_size.arr()[axis];
            root.fixed_size.arr()[axis] = padding + text_size;
        },
        .em => {
            const text_size = root.text_size.arr()[axis];
            root.fixed_size.arr()[axis] = text_size * size.value;
        },
        .children_sum => {},
    }

    {
        var maybe_child = root.children.first;
        while (maybe_child) |child| : (maybe_child = child.siblings.next) {
            standalone(child, axis_kind);
        }
    }
}

fn upwardsDependent(root: *Atom, axis_kind: Axis2D) void {
    // pre-order

    const trace = tracy.beginZone(@src(), .{ .name = "upwards dependent" });
    defer trace.end();
    tracy.print("{}", .{root});

    const axis = @intFromEnum(axis_kind);
    const size = root.pref_size.arr()[axis];

    switch (size.kind) {
        .none => {},
        .pixels => {},
        .percent_of_parent => {
            debugAssert(root.parent != null, "Attempt to get size on percent of parent without a parent: {}", .{root});
            debugAssert(size.value >= 0 and size.value <= 1, "percent must be between 0 and 1: {}", .{root});

            const parent = root.parent.?;
            root.fixed_size.arr()[axis] = parent.fixed_size.arr()[axis] * size.value;
        },
        .text_content => {},
        .em => {},
        .children_sum => {},
    }

    {
        var maybe_child = root.children.first;
        while (maybe_child) |child| : (maybe_child = child.siblings.next) {
            upwardsDependent(child, axis_kind);
        }
    }
}

fn downwardsDependnt(root: *Atom, axis_kind: Axis2D) void {
    // post-order

    const trace = tracy.beginZone(@src(), .{ .name = "downwards dependent" });
    defer trace.end();
    tracy.print("{}", .{root});

    {
        var maybe_child = root.children.first;
        while (maybe_child) |child| : (maybe_child = child.siblings.next) {
            downwardsDependnt(child, axis_kind);
        }
    }

    const axis = @intFromEnum(axis_kind);
    const size = root.pref_size.arr()[axis];

    switch (size.kind) {
        .none => {},
        .pixels => {},
        .percent_of_parent => {},
        .text_content => {},
        .em => {},
        .children_sum => {
            var accum: f32 = 0;
            var maybe_child = root.children.first;
            while (maybe_child) |child| : (maybe_child = child.siblings.next) {
                if (!floatingForAxis(child.flags, axis_kind)) {
                    if (axis_kind == root.layout_axis) {
                        accum += child.fixed_size.arr()[axis];
                    } else {
                        accum = @max(accum, child.fixed_size.arr()[axis]);
                    }
                }
            }

            root.fixed_size.arr()[axis] = accum;
        },
    }
}

inline fn floatingForAxis(flags: Atom.Flags, axis_kind: Axis2D) bool {
    return switch (axis_kind) {
        .x => flags.contains(.floating_x),
        .y => flags.contains(.floating_y),
        else => unreachable,
    };
}

fn solveViolations(root: *Atom, axis_kind: Axis2D) void {
    // https://github.com/EpicGamesExt/raddebugger/blob/a1e7ec5a0e9c8674f5b0271ce528f6b651d43564/src/ui/ui_core.c#L1705C1-L1705C44

    // pre-order

    const trace = tracy.beginZone(@src(), .{ .name = "solve violations" });
    defer trace.end();
    tracy.print("{}", .{root});

    if (root.children.count == 0) return;
    const first_child = root.children.first;
    debugAssert(root.layout_axis != .none, "Cannot have no layout axis with children: {}", .{root});

    const axis = @intFromEnum(axis_kind);

    const allow_overflow = switch (axis_kind) {
        .x => root.flags.contains(.allow_overflow_x),
        .y => root.flags.contains(.allow_overflow_y),
        else => unreachable,
    };

    // non-layout axis
    if (root.layout_axis != axis_kind and !allow_overflow) {
        const allowed_size = root.fixed_size.arr()[axis];
        var maybe_child = first_child;
        while (maybe_child) |child| : (maybe_child = child.siblings.next) {
            if (!floatingForAxis(child.flags, axis_kind)) {
                const child_size = child.fixed_size.arr()[axis];
                const violation = child_size - allowed_size;
                const max_fixup = child_size;
                const fixup = std.math.clamp(violation, 0, max_fixup);
                if (fixup > 0)
                    child.fixed_size.arr()[axis] -= fixup;
            }
        }
    }
    // layout axis
    else if (!allow_overflow) {
        const total_allowed_size = root.fixed_size.arr()[axis];
        var total_size: f32 = 0;
        var total_weighted_size: f32 = 0;

        // scope bc andrew refuses adding a proper c-style for loop
        // prevent 'maybe_child' from poisening the scope
        {
            var maybe_child = first_child;
            while (maybe_child) |child| : (maybe_child = child.siblings.next) {
                if (!floatingForAxis(child.flags, axis_kind)) {
                    total_size += child.fixed_size.arr()[axis];
                    total_weighted_size += child.fixed_size.arr()[axis] * (1 - child.pref_size.arr()[axis].strictness);
                }
            }
        }

        // if there is a violation we need to subtact some amount from all children
        const violation = total_size - total_allowed_size;
        if (violation > 0) {
            // figure out how much we can take in total
            // var child_fixup_sum: f32 = 0;
            const child_fixups = cu.state.arena.alloc(f32, root.children.count) catch @panic("oom");
            {
                var child_idx: usize = 0;
                var maybe_child = first_child;
                while (maybe_child) |child| : (maybe_child = child.siblings.next) {
                    if (!floatingForAxis(child.flags, axis_kind)) {
                        var fixup_size_this_child = child.fixed_size.arr()[axis] * (1 - child.pref_size.arr()[axis].strictness);
                        fixup_size_this_child = @max(0, fixup_size_this_child);
                        child_fixups[child_idx] = fixup_size_this_child;
                        // child_fixup_sum += fixup_size_this_child;
                    }
                    child_idx += 1;
                }
            }

            // fixup child sizes
            {
                var child_idx: usize = 0;
                var maybe_child = first_child;
                while (maybe_child) |child| : (maybe_child = child.siblings.next) {
                    if (!floatingForAxis(child.flags, axis_kind)) {
                        var fixup_pct = (violation / total_weighted_size);
                        fixup_pct = @max(fixup_pct, 0);
                        child.fixed_size.arr()[axis] -= child_fixups[child_idx] * fixup_pct;
                    }
                    child_idx += 1;
                }
            }
        }
    }

    // fix upwards depentent sizes
    if (allow_overflow) {
        var maybe_child = first_child;
        while (maybe_child) |child| : (maybe_child = child.siblings.next) {
            const pref_size = child.pref_size.arr()[axis];
            switch (pref_size.kind) {
                .percent_of_parent => {
                    child.fixed_size.arr()[axis] = root.fixed_size.arr()[axis] * pref_size.value;
                },
                else => {},
            }
        }
    }

    // recurse
    {
        var maybe_child = first_child;
        while (maybe_child) |child| : (maybe_child = child.siblings.next) {
            solveViolations(child, axis_kind);
        }
    }
}

fn position(root: *Atom, axis_kind: Axis2D) void {
    // pre-order

    const trace = tracy.beginZone(@src(), .{ .name = "position" });
    defer trace.end();
    tracy.print("{}", .{root});

    const axis = @intFromEnum(axis_kind);

    // position text
    {
        const text_size = root.text_size.arr()[axis];
        switch (root.text_align.arr()[axis]) {
            .start => {
                // text_rect[top/left] = rect[top/left]
                // text_rect[bottom/right] = text_rect[top/left] + text_size

                root.text_rect.p0.arr()[axis] = root.rect.p0.arr()[axis];
                root.text_rect.p1.arr()[axis] = root.text_rect.p0.arr()[axis] + text_size;
            },
            .center => {
                // text_rect[top/left] = rect[top/left] + (rect_size - text_size)/2
                // text_rect[bottom/right] = text_rect[top/left] + text_size

                const rect_size = root.rect.p1.arr()[axis] - root.rect.p0.arr()[axis];
                root.text_rect.p0.arr()[axis] = root.rect.p0.arr()[axis] + (rect_size - text_size) / 2;
                root.text_rect.p1.arr()[axis] = root.text_rect.p0.arr()[axis] + text_size;
            },
            .end => {
                // text_rect[top/left] = rect[bottom/right] - text_size
                // text_rect[bottom/right] = rect[bottom/right]

                root.text_rect.p1.arr()[axis] = root.rect.p1.arr()[axis];
                root.text_rect.p0.arr()[axis] = root.text_rect.p1.arr()[axis] - text_size;
            },
        }

        root.text_rect.p0.x = @floor(root.text_rect.p0.x);
        root.text_rect.p0.y = @floor(root.text_rect.p0.y);
        root.text_rect.p1.x = @floor(root.text_rect.p1.x);
        root.text_rect.p1.y = @floor(root.text_rect.p1.y);
    }

    if (root.children.count == 0) return;
    const first_child = root.children.first;

    var bounds: f32 = 0;
    {
        var layout_position: f32 = 0;
        var maybe_child = first_child;
        while (maybe_child) |child| : (maybe_child = child.siblings.next) {
            // // grab original position
            // var original_position = @min(child.rect.p.p0.arr[axis_i], child.rect.p.p1.arr[axis_i]);

            if (!floatingForAxis(child.flags, axis_kind)) {
                child.rel_position.arr()[axis] = layout_position;
                if (root.layout_axis == axis_kind) {
                    layout_position += child.fixed_size.arr()[axis];
                    bounds += child.fixed_size.arr()[axis];
                } else {
                    bounds = @max(bounds, child.fixed_size.arr()[axis]);
                }
            }

            child.rect.p0.arr()[axis] = root.rect.p0.arr()[axis] + child.rel_position.arr()[axis];
            child.rect.p1.arr()[axis] = child.rect.p0.arr()[axis] + child.fixed_size.arr()[axis];

            child.rect.p0.x = @floor(child.rect.p0.x);
            child.rect.p0.y = @floor(child.rect.p0.y);
            child.rect.p1.x = @floor(child.rect.p1.x);
            child.rect.p1.y = @floor(child.rect.p1.y);

            // // grab new position
            // const new_position = @min(child.rect.p.p0.arr[axis_i], child.rect.p.p1.arr[axis_i]);

            // store position delta
            // ...
        }
    }

    // store view bounds
    root.view_bounds.arr()[axis] = bounds;

    // recurse
    {
        var maybe_child = first_child;
        while (maybe_child) |child| : (maybe_child = child.siblings.next) {
            position(child, axis_kind);
        }
    }
}

// pub const DebugPrintTreeOptions = struct {
//     children: bool = true,
//     size: bool = true,
//     computed_size: bool = true,
//     rel_position: bool = false,
//     rect: bool = false,

//     targeted_size_kind: ?[]const Atom.Size.Kind = null,
// };

// pub fn debugPrintTree(atom: *Atom, depth: usize, options: DebugPrintTreeOptions) void {
//     const red_bg = TermColor{
//         .color = .red,
//         .layer = .background,
//         .bright = true,
//     };
//     const red = TermColor{ .color = .red };
//     const bold = TermColor{ .style = .{ .bold = true } };
//     const reset = TermColor.Reset;

//     const targeted: bool = if (options.targeted_size_kind) |targets|
//         for (targets) |target|
//             if (atom.size.sz.w.kind == target or
//                 atom.size.sz.h.kind == target)
//                 break true
//             else {}
//         else
//             false
//     else
//         false;

//     for (0..depth) |_| std.debug.print("    ", .{});
//     if (targeted)
//         std.debug.print("- {}{s}{}\n", .{ red_bg, atom.string, reset })
//     else
//         std.debug.print("- {s}\n", .{atom.string});

//     const has_children = atom.children != null;
//     const layout_axis = atom.layout_axis;

//     for (0..depth) |_| std.debug.print("    ", .{});
//     std.debug.print("   has children: {}\n", .{has_children});
//     for (0..depth) |_| std.debug.print("    ", .{});
//     std.debug.print("   layout axis: {}\n", .{layout_axis});

//     if (options.size) {
//         const size = atom.size;

//         const kinds: []const []const u8 = &.{ "w", "h" };

//         for (0..depth) |_| std.debug.print("    ", .{});
//         std.debug.print("   size: {{\n", .{});
//         for (size.arr, 0..) |s, idx| {
//             for (0..depth) |_| std.debug.print("    ", .{});

//             const target = if (options.targeted_size_kind) |targets|
//                 for (targets) |target|
//                     if (s.kind == target)
//                         break true
//                     else {}
//                 else
//                     false
//             else
//                 false;

//             if (target)
//                 std.debug.print(
//                     "     {s}: {{ {}.kind = .{s}{}, .value = {d}, .strictness = {d} }}\n",
//                     .{ kinds[idx], red, @tagName(s.kind), reset, s.value, s.strictness },
//                 )
//             else
//                 std.debug.print(
//                     "     {s}: {{ .kind = .{s}, .value = {d}, .strictness = {d} }}\n",
//                     .{ kinds[idx], @tagName(s.kind), s.value, s.strictness },
//                 );
//         }
//         for (0..depth) |_| std.debug.print("    ", .{});
//         std.debug.print("   }}\n", .{});
//     }

//     if (options.computed_size) {
//         const computed_size = atom.fixed_size;
//         for (0..depth) |_| std.debug.print("    ", .{});
//         if (targeted)
//             std.debug.print(
//                 "   {}computed size: {d} x {d}{}\n",
//                 .{ bold, computed_size.sz.w, computed_size.sz.h, reset },
//             )
//         else
//             std.debug.print(
//                 "   computed size: {d} x {d}\n",
//                 .{ computed_size.sz.w, computed_size.sz.h },
//             );
//     }

//     if (options.rel_position) {
//         const rel_position = atom.rel_position;
//         for (0..depth) |_| std.debug.print("    ", .{});
//         std.debug.print(
//             "   relative position: {d} x {d}\n",
//             .{ rel_position.vec.x, rel_position.vec.y },
//         );
//     }

//     if (options.rect) {
//         const rect = atom.rect;
//         for (0..depth) |_| std.debug.print("    ", .{});
//         std.debug.print(
//             "   rect: {d} x {d} @ {d} x {d}\n",
//             .{ rect.pt.p0.xy.x, rect.pt.p0.xy.y, rect.pt.p1.xy.x, rect.pt.p1.xy.y },
//         );
//     }

//     if (options.children and has_children) {
//         const children = atom.children.?;
//         var maybe_child: ?*Atom = children.first;
//         while (maybe_child) |child| : (maybe_child = child.siblings.next) {
//             debugPrintTree(child, depth + 1, options);
//         }
//     }
// }
