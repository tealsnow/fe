const TestWindow = @This();

const AppState = @import("State.zig");
const Window = AppState.Window;
const WindowInsetWrapper = @import("WindowInsetWrapper.zig");
const titlebar = @import("titlebar.zig");

const cu = @import("cu");
const b = cu.builder;

app: *AppState,

test_toggle: bool = false,
test_scroll_offset: f32 = 0,

window: *Window = undefined,

pub fn windowInterface(self: *TestWindow) Window.Interface {
    return .{
        .context = @ptrCast(self),
        .vtable = &.{
            .build = vtable.build,
            .close = vtable.close,
        },
    };
}

pub const vtable = struct {
    fn build(ctx: *anyopaque, window: *Window) void {
        const state: *TestWindow = @ptrCast(@alignCast(ctx));
        state.window = window;
        state.build();
    }

    fn close(ctx: *anyopaque, window: *Window) void {
        _ = ctx;
        _ = window;
    }
};

fn build(state: *TestWindow) void {
    const window_rounding = state.app.window_rounding;

    const tiling = state.window.wl_window.tiling;
    b.stacks.flags.push(flags: {
        var flags = cu.AtomFlags.draw_background;

        if (!tiling.isTiled()) {
            flags.insert(.draw_border);
            b.stacks.corner_radius.push(window_rounding);
        } else {
            flags.setPresent(.draw_side_top, !tiling.tiled_top);
            flags.setPresent(.draw_side_bottom, !tiling.tiled_bottom);
            flags.setPresent(.draw_side_left, !tiling.tiled_left);
            flags.setPresent(.draw_side_right, !tiling.tiled_right);
        }

        break :flags flags;
    });
    b.stacks.layout_axis.push(.y);
    const window_inset_wrapper =
        WindowInsetWrapper.begin(state.window.wl_window);
    defer window_inset_wrapper.end();

    const menu_bar = titlebar_buttons.menuBar(state);

    titlebar.buildTitlebar(
        state.window.wl_window,
        state.app.window_rounding,
        *TestWindow,
        menu_bar,
    );

    state.buildMainUI();
}

const titlebar_buttons = struct {
    const MenuBar = titlebar.TitlebarButtons(*TestWindow);

    pub fn menuBar(state: *TestWindow) MenuBar {
        return .{
            .context = state,
            .buttons = &buttons,
        };
    }

    pub const buttons = [_]MenuBar.Button{
        test_.button,
        edit.button,
        help.button,
    };

    pub const test_ = struct {
        pub const button = MenuBar.Button{
            .name = "Test",
            .items = &.{
                .{ .name = "close", .action = close },
                .{ .name = "quit", .action = quit },
            },
        };

        pub fn close(state: *TestWindow) void {
            state.app.action_queue.queue(.{
                .close_window = state.window.wl_window.id,
            });
        }

        pub fn quit(state: *TestWindow) void {
            state.app.action_queue.queue(.quit);
        }
    };

    pub const edit = struct {
        pub const button = MenuBar.Button{
            .name = "Edit",
            .items = &.{
                .{ .name = "open file", .action = noop },
                .{ .name = "close file", .action = noop },
            },
        };
    };

    pub const help = struct {
        pub const button = MenuBar.Button{
            .name = "Help",
            .items = &.{
                .{ .name = "foo", .action = noop },
                .{ .name = "bar", .action = noop },
                .{ .name = "baz", .action = noop },
            },
        };
    };

    pub fn noop(state: *TestWindow) void {
        _ = state;
    }
};

fn buildMainUI(state: *TestWindow) void {
    b.stacks.layout_axis.push(.x);
    b.stacks.pref_size.push(.square(.grow));
    const main_pane = b.open("main pain");
    defer b.close(main_pane);

    buildLeftPane();

    state.buildRightPane();

    //- right bar
    {
        const icon_size = cu.Atom.PrefSize.px(24);

        b.stacks.flags.push(.draw_side_left);
        b.stacks.layout_axis.push(.y);
        b.stacks.pref_size.push(.size(icon_size, .grow));
        const bar = b.open("###right bar");
        defer b.close(bar);

        //- inner
        {
            b.stacks.layout_axis.push(.y);
            b.stacks.pref_size.push(.size(icon_size, .fit_spaced(4)));
            const inner = b.open("###right bar inner");
            defer b.close(inner);

            for (0..5) |i| {
                b.stacks.flags.push(.draw_border);
                b.stacks.pref_size.push(.square(icon_size));
                _ = b.buildf("###right bar icon {d}", .{i});
            }
        }
    }
}

fn buildLeftPane() void {
    b.stacks.flags.push(.draw_side_right);
    b.stacks.layout_axis.push(.y);
    b.stacks.pref_size.push(.size(.percent(0.4), .fill));
    const pane = b.open("left pane");
    defer b.close(pane);

    //- header
    {
        b.stacks.flags
            .push(.init(&.{ .draw_side_bottom, .draw_text }));
        b.stacks.text_align.push(.size(.end, .center));
        b.stacks.pref_size.push(.size(.grow, .text));
        _ = b.label("Left Header gylp");
    }

    //- content

    b.stacks.flags
        .push(.init(&.{ .clip_rect, .allow_overflow }));
    b.stacks.layout_axis.push(.y);
    b.stacks.pref_size.push(.square(.grow));
    const content = b.open("left content");
    defer b.close(content);

    b.stacks.pref_size.pushForMany(.square(.text));
    defer _ = b.stacks.pref_size.pop();

    _ = b.label("Hello, World!");

    _ = b.lineSpacer();

    b.stacks.font.pushForMany(.mono);
    defer _ = b.stacks.font.pop();

    _ = b.label("This is a set of text");
    _ = b.label("in monospace font");

    _ = b.lineSpacer();

    // {
    //     b.stacks.palette
    //         .pushForMany(.init(.{ .text = .hexRgb(0xff0000) }));
    //     defer _ = b.stacks.palette.pop();
    //
    //     _ = b.labelf("fps: {d:.2}", .{state.fps});
    //     _ = b.labelf("ave fps: {d:.2}", .{state.fps_buffer.average()});
    //     _ = b.labelf("frame time: {d:.2}ms", .{state.delta_time_ms});
    //     _ = b.labelf("uptime: {d:.2}s", .{state.uptime_s});
    // }
    // _ = b.lineSpacer();

    _ = b.labelf("build count: {d}", .{cu.state.current_build_index});
    _ = b.labelf("atom build count: {d}", .{cu.state.build_atom_count});

    _ = b.lineSpacer();

    _ = b.labelf("current atom count: {d}", .{cu.state.atom_map.count()});
    _ = b.labelf("event count: {d}", .{cu.state.event_list.len});

    _ = b.lineSpacer();

    var an_active_atom = false;
    for (cu.state.active_atom_key.values, 0..) |key, i| {
        if (key != .nil) {
            const button: cu.input.MouseButton = @enumFromInt(i);
            const active = cu.state.atom_map.get(key).?;
            _ = b.labelf(
                "active atom: [{s}] {?}",
                .{ @tagName(button), active },
            );

            an_active_atom = true;
        }
    }
    if (!an_active_atom)
        _ = b.label("active atom: none");

    const hot = cu.state.atom_map.get(cu.state.hot_atom_key);
    b.stacks.flags.push(.draw_text_weak);
    _ = b.labelf("hot atom: {?}", .{hot});

    _ = b.lineSpacer();

    _ = b.labelf("ctx_menu_open: {}", .{cu.state.ctx_menu_open});
}

fn buildRightPane(state: *TestWindow) void {
    b.stacks.layout_axis.push(.y);
    b.stacks.pref_size.push(.size(.grow, .fill));
    const pane = b.open("right pane");
    defer b.close(pane);

    //- header
    {
        b.stacks.flags
            .push(.init(&.{ .draw_side_bottom, .draw_text }));
        b.stacks.layout_axis.push(.x);
        b.stacks.text_align.push(.square(.center));
        b.stacks.pref_size.push(.size(.grow, .text));
        b.stacks.font.push(.label);
        const header = b.open("Right Header");
        defer b.close(header);

        if (header.interaction().f.contains(.mouse_over)) {
            b.stacks.flags
                .push(.init(&.{ .draw_background, .draw_border }));
            b.stacks.layout_axis.push(.y);
            b.stacks.pref_size.push(.square(.fit));
            b.stacks.corner_radius.push(5);

            const tooltip = b.tooltip.begin();
            defer b.tooltip.end(tooltip);

            b.stacks.pref_size.pushForMany(.square(.text_pad(8)));
            defer _ = b.stacks.pref_size.pop();

            _ = b.label("tool tip!");
            _ = b.label("extra tips!");
        }
    }

    //- content
    b.stacks.layout_axis.push(.y);
    b.stacks.pref_size.push(.square(.grow));
    const content = b.open("right content");
    defer b.close(content);

    b.stacks.corner_radius.push(b.em(0.8));
    _ = b.toggleSwitch(&state.test_toggle);

    _ = b.lineSpacer();

    {
        b.stacks.layout_axis.push(.y);
        b.stacks.pref_size.push(.size(.grow, .fit));
        const counter_container = b.open("counter");
        defer b.close(counter_container);

        b.stacks.pref_size.push(.square(.text));
        _ = b.labelf(
            "scroll offset (px): {d}",
            .{state.test_scroll_offset},
        );

        {
            b.stacks.layout_axis.push(.x);
            b.stacks.pref_size.push(.square(.fit_spaced(2)));
            const btns = b.open("buttons");
            defer b.close(btns);

            b.stacks.font.pushForMany(.mono);
            defer _ = b.stacks.font.pop();

            b.stacks.pref_size.push(.square(.px(b.em(2))));
            if (b.button("+").clicked()) {
                state.test_scroll_offset += 10;
            }

            b.stacks.pref_size.push(.square(.px(b.em(2))));
            if (b.button("-").clicked()) {
                state.test_scroll_offset -= 10;
            }
        }
    }

    _ = b.lineSpacer();

    // scroll test
    {
        b.stacks.font.pushForMany(.label);
        defer _ = b.stacks.font.pop();

        const item_size = b.em(1);

        b.stacks.pref_size.push(.square(.grow));
        b.stacks.flags.push(.draw_border);
        const scroll_data = b.scroll_area.begin(
            .y,
            item_size,
            &state.test_scroll_offset,
        );
        defer b.scroll_area.end(scroll_data);

        b.stacks.text_align.pushForMany(.size(.start, .center));
        defer _ = b.stacks.text_align.pop();
        b.stacks.pref_size.pushForMany(.size(.grow, .px(item_size)));
        defer _ = b.stacks.pref_size.pop();

        for (scroll_data.index_range.min.. //
            scroll_data.index_range.max) |i|
        {
            _ = b.labelf("item {d}", .{i});
        }
    }
}
