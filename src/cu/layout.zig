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

    for (Axis2D.array) |axis| {
        sizeText(root, axis);
        standalone(root, axis);
        upwardsDependent(root, axis);
        downwardsDependent(root, axis);
        solveViolations(root, axis);
        position(root, axis);
    }
}

fn sizeText(root: *Atom, axis_kind: Axis2D) void {
    // any-order

    const trace = tracy.beginZone(@src(), .{ .name = "size text" });
    defer trace.end();

    var iter = root.tree.depthFirstPreOrderIterator();
    while (iter.next()) |atom| {
        if (atom.flags.contains(.draw_text) and atom.display_string.len != 0)
            switch (axis_kind) {
                .none => unreachable,
                .x => {
                    atom.text_size.width = cu.state.callbacks.measureText(
                        atom.display_string,
                        atom.font,
                    ).width;
                },
                .y => {
                    atom.text_size.height =
                        cu.state.callbacks.lineHeight(atom.font);
                },
            };
    }
}

// pixels
// text_content
// em
fn standalone(root: *Atom, axis_kind: Axis2D) void {
    // any-order

    const trace = tracy.beginZone(@src(), .{ .name = "standalone" });
    defer trace.end();

    var iter = root.tree.depthFirstPreOrderIterator();
    while (iter.next()) |atom| {
        const axis = @intFromEnum(axis_kind);
        const size = atom.pref_size.arr()[axis];
        switch (size.kind) {
            .none => {},
            .pixels => {
                atom.fixed_size.arr()[axis] = size.value;
            },
            .percent_of_parent => {},
            .text_content => {
                const padding = size.value;
                const text_size = atom.text_size.arr()[axis];
                atom.fixed_size.arr()[axis] = padding + text_size;
            },
            .em => {
                const text_size = atom.text_size.arr()[axis];
                atom.fixed_size.arr()[axis] = text_size * size.value;
            },
            .children_sum => {},
        }
    }
}

// percent_of_parent
fn upwardsDependent(root: *Atom, axis_kind: Axis2D) void {
    // depth-first pre-order

    const trace = tracy.beginZone(@src(), .{ .name = "upwards dependent" });
    defer trace.end();

    var iter = root.tree.depthFirstPreOrderIterator();
    while (iter.next()) |atom| {
        const axis = @intFromEnum(axis_kind);
        const size = atom.pref_size.arr()[axis];

        switch (size.kind) {
            .none => {},
            .pixels => {},
            .percent_of_parent => {
                debugAssert(
                    atom.tree.parent != null,
                    "Attempt to get percent of parent without a parent: {}",
                    .{atom},
                );
                debugAssert(
                    size.value >= 0 and size.value <= 1,
                    "percent must be between 0 and 1: {}",
                    .{atom},
                );

                const parent = atom.tree.parent.?;
                atom.fixed_size.arr()[axis] =
                    parent.fixed_size.arr()[axis] * size.value;
            },
            .text_content => {},
            .em => {},
            .children_sum => {},
        }
    }
}

fn downwardsDependent(root: *Atom, axis_kind: Axis2D) void {
    const trace = tracy.beginZone(@src(), .{ .name = "downwards dependent" });
    defer trace.end();

    downwardsDependentRec(root, axis_kind);
}

// children_sum
fn downwardsDependentRec(root: *Atom, axis_kind: Axis2D) void {
    // post-order

    //- recurse
    {
        var maybe_child = root.tree.children.first;
        while (maybe_child) |child| : (maybe_child = child.tree.siblings.next) {
            downwardsDependentRec(child, axis_kind);
        }
    }

    const axis = @intFromEnum(axis_kind);
    const pref_size = root.pref_size.arr()[axis];

    switch (pref_size.kind) {
        .none => {},
        .pixels => {},
        .percent_of_parent => {},
        .text_content => {},
        .em => {},
        .children_sum => {
            const child_spacing = pref_size.value;

            var accum: f32 = 0;
            var count: usize = 0;
            var child_iter = root.tree.childIterator();
            while (child_iter.next()) |child| : (count += 1) {
                if (!child.flags.contains(.floatingForAxis(axis_kind))) {
                    if (axis_kind == root.layout_axis) {
                        accum += child.fixed_size.arr()[axis];
                    } else {
                        accum = @max(accum, child.fixed_size.arr()[axis]);
                    }
                }
            }

            if (axis_kind == root.layout_axis) {
                const num = @as(f32, @floatFromInt(count -| 1)); // saturating sub
                accum += num * child_spacing;
            }

            root.fixed_size.arr()[axis] = accum;
        },
    }
}

fn solveViolations(root: *Atom, axis_kind: Axis2D) void {
    // https://github.com/EpicGamesExt/raddebugger/blob/a1e7ec5a0e9c8674f5b0271ce528f6b651d43564/src/ui/ui_core.c#L1705C1-L1705C44

    // depth-first pre-order

    const trace = tracy.beginZone(@src(), .{ .name = "solve violations" });
    defer trace.end();

    var iter = root.tree.depthFirstPreOrderIterator();
    while (iter.next()) |atom| {
        if (atom.tree.children.len == 0) continue;
        debugAssert(
            atom.layout_axis != .none,
            "Cannot have no layout axis with children: {}",
            .{atom},
        );
        var child_iter = atom.tree.childIterator();

        const axis = @intFromEnum(axis_kind);

        const allow_overflow = switch (axis_kind) {
            .x => atom.flags.contains(.allow_overflow_x),
            .y => atom.flags.contains(.allow_overflow_y),
            else => unreachable,
        };

        //- non-layout axis
        // work out allowed size
        // iterate over children
        //   if child size is greater than allowed size
        //      reduce it by an amount
        if (atom.layout_axis != axis_kind and !allow_overflow) {
            const allowed_size = atom.fixed_size.arr()[axis];
            child_iter.reset();
            while (child_iter.next()) |child| {
                if (!child.flags.contains(.floatingForAxis(axis_kind))) {
                    const child_size = child.fixed_size.arr()[axis];
                    const violation = child_size - allowed_size;
                    const max_fixup = child_size;
                    const fixup = std.math.clamp(violation, 0, max_fixup);
                    if (fixup > 0)
                        child.fixed_size.arr()[axis] -= fixup;
                }
            }
        }
        //- layout axis
        else if (!allow_overflow) {
            const total_allowed_size = atom.fixed_size.arr()[axis];
            var total_size: f32 = 0;
            var total_weighted_size: f32 = 0;

            //- total up sizes
            {
                child_iter.reset();
                while (child_iter.next()) |child| {
                    if (!child.flags.contains(.floatingForAxis(axis_kind))) {
                        total_size += child.fixed_size.arr()[axis];
                        total_weighted_size += child.fixed_size.arr()[axis] *
                            (1 - child.pref_size.arr()[axis].strictness);
                    }
                }
            }

            //- solve violations
            // if there is a violation we need to subtact some amount from all children
            const violation = total_size - total_allowed_size;
            if (violation > 0) {
                // figure out how much we can take in total
                // var child_fixup_sum: f32 = 0;
                const child_fixups =
                    cu.state.arena.alloc(f32, atom.tree.children.len) catch
                        @panic("oom");
                {
                    var child_idx: usize = 0;
                    child_iter.reset();
                    while (child_iter.next()) |child| : (child_idx += 1) {
                        if (!child.flags.contains(.floatingForAxis(axis_kind))) {
                            var fixup_size_this_child =
                                child.fixed_size.arr()[axis] *
                                (1 - child.pref_size.arr()[axis].strictness);
                            fixup_size_this_child = @max(0, fixup_size_this_child);
                            child_fixups[child_idx] = fixup_size_this_child;
                            // child_fixup_sum += fixup_size_this_child;
                        }
                    }
                }

                //- fixup child sizes
                {
                    var child_idx: usize = 0;
                    child_iter.reset();
                    while (child_iter.next()) |child| : (child_idx += 1) {
                        if (!child.flags.contains(.floatingForAxis(axis_kind))) {
                            var fixup_pct = (violation / total_weighted_size);
                            fixup_pct = @max(fixup_pct, 0);
                            child.fixed_size.arr()[axis] -=
                                child_fixups[child_idx] * fixup_pct;
                        }
                    }
                }
            }
        }

        //- fix upwards depentent sizes
        if (allow_overflow) {
            child_iter.reset();
            while (child_iter.next()) |child| {
                const pref_size = child.pref_size.arr()[axis];
                switch (pref_size.kind) {
                    .percent_of_parent => {
                        child.fixed_size.arr()[axis] =
                            atom.fixed_size.arr()[axis] * pref_size.value;
                    },
                    else => {},
                }
            }
        }
    }
}

fn position(root: *Atom, axis_kind: Axis2D) void {
    // depth-first pre-order

    const trace = tracy.beginZone(@src(), .{ .name = "position" });
    defer trace.end();

    const axis = @intFromEnum(axis_kind);

    var iter = root.tree.depthFirstPreOrderIterator();
    while (iter.next()) |atom| {
        //- position text
        {
            const text_size = atom.text_size.arr()[axis];
            switch (atom.text_align.arr()[axis]) {
                .start => {
                    // text_rect[top/left] = rect[top/left]
                    // text_rect[bottom/right] = text_rect[top/left] + text_size

                    atom.text_rect.p0.arr()[axis] = atom.rect.p0.arr()[axis];
                    atom.text_rect.p1.arr()[axis] =
                        atom.text_rect.p0.arr()[axis] + text_size;
                },
                .center => {
                    // text_rect[top/left] = rect[top/left] + (rect_size - text_size)/2
                    // text_rect[bottom/right] = text_rect[top/left] + text_size

                    const rect_size =
                        atom.rect.p1.arr()[axis] - atom.rect.p0.arr()[axis];
                    atom.text_rect.p0.arr()[axis] =
                        atom.rect.p0.arr()[axis] + (rect_size - text_size) / 2;
                    atom.text_rect.p1.arr()[axis] =
                        atom.text_rect.p0.arr()[axis] + text_size;
                },
                .end => {
                    // text_rect[top/left] = rect[bottom/right] - text_size
                    // text_rect[bottom/right] = rect[bottom/right]

                    atom.text_rect.p1.arr()[axis] = atom.rect.p1.arr()[axis];
                    atom.text_rect.p0.arr()[axis] =
                        atom.text_rect.p1.arr()[axis] - text_size;
                },
            }

            atom.text_rect.p0.x = @floor(atom.text_rect.p0.x);
            atom.text_rect.p0.y = @floor(atom.text_rect.p0.y);
            atom.text_rect.p1.x = @floor(atom.text_rect.p1.x);
            atom.text_rect.p1.y = @floor(atom.text_rect.p1.y);
        }

        if (atom.tree.children.len == 0) continue;

        //- position
        var bounds: f32 = 0;
        {
            const pref_size = atom.pref_size.arr()[axis];
            const child_spacing =
                if (pref_size.kind == .children_sum) pref_size.value else 0;

            var layout_position: f32 = 0;
            var child_iter = atom.tree.childIterator();
            while (child_iter.next()) |child| {
                if (child.flags.contains(.floatingForAxis(axis_kind))) continue;

                // // grab original position
                // var original_position = @min(child.rect.p.p0.arr[axis_i], child.rect.p.p1.arr[axis_i]);

                //- position children
                child.rel_position.arr()[axis] = layout_position;

                if (atom.layout_axis == axis_kind) {
                    layout_position += child.fixed_size.arr()[axis];
                    bounds += child.fixed_size.arr()[axis];

                    if (child.tree.siblings.next != null) {
                        layout_position += child_spacing;
                        bounds += child_spacing;
                    }
                } else {
                    bounds = @max(bounds, child.fixed_size.arr()[axis]);
                }

                // // grab new position
                // const new_position = @min(child.rect.p.p0.arr[axis_i], child.rect.p.p1.arr[axis_i]);

                // store position delta
                // ...
            }

            //- convert from rel_position + size to on screen rect
            child_iter.reset();
            while (child_iter.next()) |child| {
                child.rect.p0.arr()[axis] =
                    atom.rect.p0.arr()[axis] + child.rel_position.arr()[axis];
                child.rect.p1.arr()[axis] =
                    child.rect.p0.arr()[axis] + child.fixed_size.arr()[axis];

                child.rect.p0.x = @floor(child.rect.p0.x);
                child.rect.p0.y = @floor(child.rect.p0.y);
                child.rect.p1.x = @floor(child.rect.p1.x);
                child.rect.p1.y = @floor(child.rect.p1.y);
            }
        }

        //- store view bounds
        atom.view_bounds.arr()[axis] = bounds;
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
