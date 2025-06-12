const std = @import("std");
const print = std.debug.print;
const Allocator = std.mem.Allocator;

const cu = @import("cu.zig");
const Atom = cu.Atom;
const b = cu.builder;

//= text tree

fn println(comptime fmt: []const u8, args: anytype) void {
    print(fmt ++ "\n", args);
}

pub fn printTree(root: *Atom) void {
    var iter = root.tree.depthFirstPreOrderIterator();
    var indent: usize = 0;
    while (iter.next()) |atom| {
        for (0..indent) |_| {
            print("  ", .{});
        }
        indent += iter.rec.push_count;
        indent -= iter.rec.pop_count;

        println("{}", .{atom});
    }
}

//= ui

pub const DebugUIState = struct {
    split_percent: f32,

    tree_scroll_offset: f32,
    tree_scroll_item_count: usize,

    selected_atom: ?*Atom,

    pub const init = DebugUIState{
        .split_percent = 0.5,

        .tree_scroll_offset = 0,
        .tree_scroll_item_count = 0,

        .selected_atom = null,
    };
};

pub fn buildDebugUI(
    state: *DebugUIState,
    arena: Allocator,
    cu_state: *cu.State,
) void {
    b.stacks.pref_size.push(.square(.grow));
    b.stacks.layout_axis.push(.x);
    const container = b.open("###debug ui root");
    defer b.close(container);

    buildDebugUITree(state, cu_state);
    buildDebugUIDetails(state, arena);
}

fn buildDebugUITree(state: *DebugUIState, cu_state: *cu.State) void {
    b.stacks.layout_axis.push(.x);
    b.stacks.pref_size.push(.size(.percent(state.split_percent), .fill));
    const tree_view = b.open("###tree view");
    defer b.close(tree_view);

    //- scroll+bar
    {
        //- scroll
        const item_height = b.fontHeight(.mono) * 1.2;
        const max_height =
            item_height *
            @as(f32, @floatFromInt(state.tree_scroll_item_count)) + item_height;
        var scroll_handle: b.scroll_area.basic.Handle = undefined;
        {
            b.stacks.pref_size.push(.square(.grow));
            scroll_handle = b.scroll_area.basic.begin(.{
                .scroll_axis = .y,
                .item_size_px = item_height,
                .ptr_offset_px = &state.tree_scroll_offset,
            });
            defer b.scroll_area.basic.end(scroll_handle);
            state.tree_scroll_offset = @min(
                state.tree_scroll_offset,
                max_height - scroll_handle.view.fixed_size.height,
            );

            b.stacks.pref_size.pushForMany(.square(.text));
            defer _ = b.stacks.pref_size.pop();

            var iter = cu_state.ui_root.tree.depthFirstPreOrderIterator();
            var indent: usize = 0;
            var i: usize = 0;
            while (iter.next()) |atom| : ({
                i += 1;
                indent += iter.rec.push_count;
                indent -= iter.rec.pop_count;
            }) {
                if (i < scroll_handle.index_range.min) continue;
                // continue here so we can count all the items
                if (i >= scroll_handle.index_range.max) continue;

                b.stacks.text_align.pushForMany(.size(.start, .center));
                defer _ = b.stacks.text_align.pop();
                b.stacks.pref_size.pushForMany(.size(.fit, .px(item_height)));
                defer _ = b.stacks.pref_size.pop();

                b.stacks.flags.push(.init(&.{
                    .clickable,
                    .draw_side_bottom,
                    .draw_background,
                }));
                b.stacks.layout_axis.push(.x);
                b.stacks.pref_size.push(.size(
                    .px(scroll_handle.view.fixed_size.width),
                    .px(item_height),
                ));
                b.stacks.hover_pointer.push(.clickable);
                const row = b.openf("###dbg item {d}", .{i});
                defer b.close(row);

                const inter = row.interaction();

                if (inter.hovering())
                    row.palette.set(.background, row.palette.get(.hot));
                if (inter.dragging())
                    row.palette.set(.background, row.palette.get(.active));
                if (inter.clicked())
                    state.selected_atom = atom;

                b.stacks.pref_size.push(.size(
                    .px(@as(f32, @floatFromInt(indent)) * item_height),
                    .px(item_height),
                ));
                _ = b.spacer();

                b.stacks.font.push(.mono);
                b.stacks.flags.push(.draw_text);
                const lbl = b.buildf("###atom str {d}", .{i});

                lbl.display_string = if (atom.string.len != 0)
                    b.format("'{s}' - [{}]", .{ atom.string, atom.key })
                else
                    b.format("[{}]", .{atom.key});
            }
            state.tree_scroll_item_count = i;
        }

        const track_width = 16;

        const scroll_view_height_px = scroll_handle.view.fixed_size.height;

        b.stacks.pref_size.push(.size(
            .px(track_width),
            .px(scroll_view_height_px),
        ));
        b.stacks.layout_axis.push(.y);
        b.stacks.flags.push(.draw_side_left);
        b.stacks.padding.push(.horizontal(2));
        const scroll_track = b.open("###scroll track");
        defer b.close(scroll_track);

        const pre_pad_pct =
            state.tree_scroll_offset / max_height;
        const track_handle_pct =
            scroll_view_height_px / max_height;

        const pre_pad_px =
            pre_pad_pct * scroll_view_height_px;
        const track_handle_px =
            track_handle_pct * scroll_view_height_px;

        b.stacks.pref_size.push(.size(
            .grow,
            .px(pre_pad_px),
        ));
        _ = b.build("###track spacer");

        b.stacks.flags.push(.init(&.{
            .draw_background,
            .draw_border,
            .clickable,
        }));
        b.stacks.pref_size.push(.size(
            .grow,
            .px(track_handle_px),
        ));
        _ = b.build("###track handle");
    }
}

fn buildDebugUIDetails(state: *DebugUIState, arena: Allocator) void {
    b.stacks.flags.push(.init(&.{ .draw_side_left, .clip_rect }));
    b.stacks.layout_axis.push(.y);
    b.stacks.pref_size.push(.size(.grow, .fill));
    const details_view = b.open("###details view");
    defer b.close(details_view);

    b.stacks.pref_size.pushForMany(.square(.text));
    defer _ = b.stacks.pref_size.pop();
    // b.stacks.font.pushForMany(.label);
    // defer _ = b.stacks.font.pop();

    const atom = if (state.selected_atom) |atom| atom else {
        _ = b.label("no atom selected");
        return;
    };

    if (b.button("clear").clicked()) {
        state.selected_atom = null;
    }

    b.stacks.font.pushForMany(.mono);
    defer _ = b.stacks.font.pop();
    b.stacks.text_align.pushForMany(.size(.start, .center));
    defer _ = b.stacks.text_align.pop();

    _ = b.lineSpacer();

    b.stacks.flags.push(.init(&.{ .draw_text, .draw_side_bottom }));
    const atom_label = b.build("###atom label");
    atom_label.display_string = b.format("{}", .{atom});

    _ = b.lineSpacer();

    //- key
    b.stacks.flags.push(.init(&.{.draw_text}));
    _ = b.buildf("key: {}", .{atom.key});

    //- string
    b.stacks.flags.push(.init(&.{.draw_text}));
    const atom_str_lbl = b.build("###atom string");
    atom_str_lbl.display_string = b.format("string: '{s}'", .{atom.string});

    //- display string
    b.stacks.flags.push(.init(&.{.draw_text}));
    const atom_display_str_lbl = b.build("###atom display string");
    atom_display_str_lbl.display_string = atom.display_string;
    atom_display_str_lbl.display_string =
        b.format("display string: '{s}'", .{atom.display_string});

    //- flags
    {
        var sb_list = std.ArrayListUnmanaged(u8).empty;
        const sb = sb_list.writer(arena);

        sb.writeAll("[ ") catch {};

        var iter = atom.flags.enum_set.iterator();
        while (iter.next()) |entry| {
            sb.print(".{s}, ", .{@tagName(entry)}) catch {};
        }
        if (sb_list.items.len > 2) // check that there are any flags
            sb_list.items.len -= 2; // remove last ', '

        sb.writeAll(" ]") catch {};

        b.stacks.flags.push(.init(&.{.draw_text}));
        _ = b.buildf("flags: {s}", .{sb_list.items});
    }

    _ = b.lineSpacer();

    //- pref size
    {
        var pref_size_strs: [2][]const u8 = undefined;

        for (Atom.LayoutAxis.array) |axis| {
            var sb_list = std.ArrayListUnmanaged(u8).empty;
            const sb = sb_list.writer(arena);

            const pref_size = atom.pref_size.arr()[@intFromEnum(axis)];

            switch (pref_size.kind) {
                .none => {
                    sb.writeAll("none") catch {};
                },
                .pixels => {
                    sb.print(
                        "pixels{{ px: {d}, strictness: {d} }}",
                        .{ pref_size.value, pref_size.strictness },
                    ) catch {};
                },
                .percent_of_parent => {
                    sb.print(
                        "percent_of_parent{{ percent: {d}, strictness: {d} }}",
                        .{ pref_size.value, pref_size.strictness },
                    ) catch {};
                },
                .text_content => {
                    sb.print(
                        "text_content{{ padding_px: {d} }}",
                        .{pref_size.value},
                    ) catch {};
                },
                .em => {
                    sb.print(
                        "em{{ value: {d} }}",
                        .{pref_size.value},
                    ) catch {};
                },
                .children_sum => {
                    sb.print(
                        "childrem_sum{{ child_spacing_px: {d}, strictness: {d} }}",
                        .{ pref_size.value, pref_size.strictness },
                    ) catch {};
                },
            }

            pref_size_strs[@intFromEnum(axis)] = sb_list.items;
        }

        b.stacks.flags.push(.init(&.{.draw_text}));
        _ = b.build("pref_size:");

        for (Atom.LayoutAxis.array) |axis| {
            b.stacks.pref_size.push(.size(.grow, .fit));
            b.stacks.layout_axis.push(.x);
            const row = b.openf("###pref_size row {s}", .{@tagName(axis)});
            defer b.close(row);

            b.stacks.pref_size.push(.size(.px(b.em(1)), .grow));
            _ = b.spacer();

            b.stacks.flags.push(.init(&.{.draw_text}));
            _ = b.buildf(
                ".{s} = {s}",
                .{ @tagName(axis), pref_size_strs[@intFromEnum(axis)] },
            );
        }
    }

    //- layout_axis
    b.stacks.flags.push(.init(&.{.draw_text}));
    _ = b.buildf("layout_axis: {s}", .{@tagName(atom.layout_axis)});

    //- hover_pointer
    b.stacks.flags.push(.init(&.{.draw_text}));
    _ = b.buildf(
        "hover_pointer: {s}",
        .{if (atom.hover_pointer) |kind| @tagName(kind) else "null"},
    );

    //- text align
    {
        b.stacks.flags.push(.init(&.{.draw_text}));
        _ = b.build("text_align:");

        for (Atom.LayoutAxis.array) |axis| {
            b.stacks.pref_size.push(.size(.grow, .fit));
            b.stacks.layout_axis.push(.x);
            const row = b.openf(
                "###text_align row {s}",
                .{@tagName(axis)},
            );
            defer b.close(row);

            b.stacks.pref_size.push(.size(.px(b.em(1)), .grow));
            _ = b.spacer();

            b.stacks.flags.push(.init(&.{.draw_text}));
            _ = b.buildf(".{s} = {s}", .{
                @tagName(axis),
                @tagName(atom.text_align.arr()[@intFromEnum(axis)]),
            });
        }
    }

    //- alignment
    {
        b.stacks.flags.push(.init(&.{.draw_text}));
        _ = b.build("child_alignment:");

        for (Atom.LayoutAxis.array) |axis| {
            b.stacks.pref_size.push(.size(.grow, .fit));
            b.stacks.layout_axis.push(.x);
            const row = b.openf(
                "###child_ailgnemtn row {s}",
                .{@tagName(axis)},
            );
            defer b.close(row);

            b.stacks.pref_size.push(.size(.px(b.em(1)), .grow));
            _ = b.spacer();

            b.stacks.flags.push(.init(&.{.draw_text}));
            _ = b.buildf(".{s} = {s}", .{
                @tagName(axis),
                @tagName(atom.alignment.arr()[@intFromEnum(axis)]),
            });
        }
    }

    //- padding
    b.stacks.flags.push(.init(&.{.draw_text}));
    _ = b.buildf(
        "padding: {{ .left = {d}, .top = {d}, .right = {d}, .bottom = {d} }}",
        .{
            atom.padding.left,
            atom.padding.top,
            atom.padding.right,
            atom.padding.bottom,
        },
    );

    _ = b.lineSpacer();

    //- palette
    {
        b.stacks.flags.push(.init(&.{.draw_text}));
        _ = b.build("palette:");

        var iter = atom.palette.list.iterator();
        while (iter.next()) |item| {
            b.stacks.pref_size.push(.size(.grow, .fit));
            b.stacks.layout_axis.push(.x);
            const row = b.openf(
                "###palette row {s}",
                .{@tagName(item.key)},
            );
            defer b.close(row);

            b.stacks.pref_size.push(.size(.px(b.em(1)), .grow));
            _ = b.spacer();

            b.stacks.flags.push(.init(&.{.draw_text}));
            _ = b.buildf(".{s} = {}", .{
                @tagName(item.key),
                item.value,
            });

            const circle_size = b.em(1);
            b.stacks.flags.push(.init(&.{ .draw_background, .draw_border }));
            b.stacks.palette.push(.init(.{ .background = item.value.* }));
            b.stacks.pref_size.push(.square(.px(circle_size)));
            _ = b.build("###color circle");
        }
    }

    //- font
    {
        var iter = cu.state.font_kind_map.iterator();
        const kind: ?cu.FontKind = while (iter.next()) |entry| {
            if (entry.value.* == atom.font) break entry.key;
        } else null;

        b.stacks.flags.push(.init(&.{.draw_text}));
        _ = b.buildf("font: {s}", .{if (kind) |k| @tagName(k) else "null"});
    }

    //- border width
    b.stacks.flags.push(.init(&.{.draw_text}));
    _ = b.buildf("border_width: {d}", .{atom.border_width});

    //- corner_radius
    b.stacks.flags.push(.init(&.{.draw_text}));
    _ = b.buildf("corner_radius: {d}", .{atom.corner_radius});

    _ = b.lineSpacer();

    //- fixed size
    {
        b.stacks.flags.push(.init(&.{.draw_text}));
        _ = b.build("fixed_size:");

        for (Atom.LayoutAxis.array) |axis| {
            b.stacks.pref_size.push(.size(.grow, .fit));
            b.stacks.layout_axis.push(.x);
            const row = b.openf(
                "###fixed_size row {s}",
                .{@tagName(axis)},
            );
            defer b.close(row);

            b.stacks.pref_size.push(.size(.px(b.em(1)), .grow));
            _ = b.spacer();

            b.stacks.flags.push(.init(&.{.draw_text}));
            _ = b.buildf(".{s} = {d}", .{
                @tagName(axis),
                atom.fixed_size.arr()[@intFromEnum(axis)],
            });
        }
    }

    //- rel position
    {
        b.stacks.flags.push(.init(&.{.draw_text}));
        _ = b.build("rel_position:");

        for (Atom.LayoutAxis.array) |axis| {
            b.stacks.pref_size.push(.size(.grow, .fit));
            b.stacks.layout_axis.push(.x);
            const row = b.openf(
                "###rel_position row {s}",
                .{@tagName(axis)},
            );
            defer b.close(row);

            b.stacks.pref_size.push(.size(.px(b.em(1)), .grow));
            _ = b.spacer();

            b.stacks.flags.push(.init(&.{.draw_text}));
            _ = b.buildf(".{s} = {d}", .{
                @tagName(axis),
                atom.rel_position.arr()[@intFromEnum(axis)],
            });
        }
    }
}
