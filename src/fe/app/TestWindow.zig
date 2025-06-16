const TestWindow = @This();

const App = @import("App.zig");

const cu = @import("cu");
const b = cu.builder;

app: *App,
window: *App.BackendWindow,
cu_state: *cu.State,

test_toggle: bool = false,
test_scroll_offset: f32 = 0,

pub fn init(app: *App) !*TestWindow {
    const window = try app.newWindow("Test");
    const cu_state = try cu.State.init(app.gpa, .{
        .callbacks = window.callbacks(),
        .font_kind_map = window.font_kind_map,
        .interaction_styles = app.interaction_styles,
        .root_palette = app.root_palette,
    });

    const self = try app.gpa.create(TestWindow);
    self.* =
        .{
            .app = app,
            .window = window,
            .cu_state = cu_state,
        };
    return self;
}

pub fn deinit(self: *TestWindow) void {
    self.cu_state.deinit();

    const gpa = self.app.gpa;
    gpa.destroy(self);
}

pub fn appWindow(self: *TestWindow) App.AppWindow {
    return .{
        .id = self.window.getId(),
        .context = self,
        .vtable = &.{
            .deinit = &vtable.deinit,
            .getWindow = &vtable.getWindow,
            .getCuState = &vtable.getCuState,
            .buildUI = &vtable.buildUI,
        },
    };
}

pub const vtable = struct {
    fn deinit(ctx: *anyopaque) void {
        const self: *TestWindow = @ptrCast(@alignCast(ctx));
        self.deinit();
    }
    fn getWindow(ctx: *anyopaque) *App.BackendWindow {
        const self: *TestWindow = @ptrCast(@alignCast(ctx));
        return self.window;
    }
    fn getCuState(ctx: *anyopaque) *cu.State {
        const self: *TestWindow = @ptrCast(@alignCast(ctx));
        return self.cu_state;
    }
    fn buildUI(ctx: *anyopaque) void {
        const self: *TestWindow = @ptrCast(@alignCast(ctx));
        self.buildUI();
    }
};

fn buildUI(self: *TestWindow) void {
    self.cu_state.select();

    b.startBuild(@intFromPtr(self.window));
    defer b.endBuild();

    self.window.startBuild(menu_bar.menuBar(self));
    defer self.window.endBuild();

    self.buildMainUI();
}

const menu_bar = struct {
    const MenuBar = App.MenuBar;

    pub fn menuBar(self: *TestWindow) MenuBar {
        return .{
            .context = self,
            .root = &.{
                test_.button,
                edit.button,
                help.button,
            },
        };
    }

    pub const test_ = struct {
        pub const button = MenuBar.MenuList{
            .name = "Test",
            .items = &.{
                .{ .button = .{ .name = "close", .action = close } },
                .{ .button = .{ .name = "quit", .action = quit } },
            },
        };

        pub fn close(ctx: *anyopaque) void {
            const self: *TestWindow = @ptrCast(@alignCast(ctx));
            self.app.action_queue.queue(.{
                .close_window = self.window.getId(),
            });
        }

        pub fn quit(ctx: *anyopaque) void {
            const self: *TestWindow = @ptrCast(@alignCast(ctx));
            self.app.action_queue.queue(.quit);
        }
    };

    pub const edit = struct {
        pub const button = MenuBar.MenuList{
            .name = "Edit",
            .items = &.{
                .{ .button = .{ .name = "open file", .action = noop } },
                .{ .button = .{ .name = "close file", .action = noop } },
            },
        };
    };

    pub const help = struct {
        pub const button = MenuBar.MenuList{
            .name = "Help",
            .items = &.{
                .{ .button = .{ .name = "foo", .action = noop } },
                .{ .button = .{ .name = "bar", .action = noop } },
                .{ .button = .{ .name = "baz", .action = noop } },
            },
        };
    };

    pub fn noop(ctx: *anyopaque) void {
        _ = ctx;
    }
};

fn buildMainUI(state: *TestWindow) void {
    b.stacks.layout_axis.push(.x);
    b.stacks.pref_size.push(.square(.grow));
    const main_pane = b.open("main pain");
    defer b.close(main_pane);

    buildLeftPane();

    state.buildRightPane();

    buildRightBar();
}

fn buildLeftPane() void {
    b.stacks.flags.push(.draw_side_right);
    b.stacks.layout_axis.push(.y);
    b.stacks.pref_size.push(.size(.percent(0.4), .fill));
    const pane = b.open("###left pane");
    defer b.close(pane);

    //- header
    {
        b.stacks.flags
            .push(.init(&.{ .draw_side_bottom, .draw_text }));
        b.stacks.text_align.push(.size(.end, .center));
        b.stacks.pref_size.push(.size(.grow, .text));
        _ = b.label("Left Header");
    }

    //- content

    b.stacks.flags
        .push(.init(&.{ .clip_rect, .allow_overflow }));
    b.stacks.layout_axis.push(.y);
    b.stacks.pref_size.push(.square(.grow));
    b.stacks.padding.push(.all(4));
    const content = b.open("###left content");
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
    _ = b.labelf("hot atom: {?}", .{hot});

    _ = b.lineSpacer();

    _ = b.labelf("ctx_menu_open: {}", .{cu.state.ctx_menu_open});
}

fn buildRightPane(state: *TestWindow) void {
    b.stacks.layout_axis.push(.y);
    b.stacks.pref_size.push(.size(.grow, .fill));
    const pane = b.open("###right pane");
    defer b.close(pane);

    //- header
    {
        b.stacks.flags
            .push(.init(&.{ .draw_side_bottom, .draw_text, .clickable }));
        b.stacks.layout_axis.push(.x);
        b.stacks.text_align.push(.square(.center));
        b.stacks.pref_size.push(.size(.grow, .text));
        b.stacks.font.push(.label);
        b.stacks.hover_cursor_shape.push(.context_menu);
        const header = b.open("Right Header");
        defer b.close(header);

        const inter = header.interaction();

        if (inter.clicked()) {
            b.ctx_menu.openMenu(
                header.key,
                cu.state.ui_root.key,
                cu.state.pointer_pos,
            );
        }

        if (b.ctx_menu.begin(header.key)) |ctx_menu| {
            defer b.ctx_menu.end(ctx_menu);

            b.stacks.flags.push(.init(&.{ .draw_background, .draw_border }));
            b.stacks.layout_axis.push(.y);
            b.stacks.pref_size.push(.square(.fit));
            const menu = b.open("ctx menu");
            defer b.close(menu);

            b.stacks.pref_size.push(.square(.text_pad(8)));
            _ = b.button("foo");
            b.stacks.pref_size.push(.square(.text_pad(8)));
            _ = b.button("bar");
        }

        if (inter.hovering() and !cu.state.ctx_menu_open) {
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
    b.stacks.padding.push(.all(4));
    const content = b.open("###right content");
    defer b.close(content);

    b.stacks.corner_radius.push(b.em(0.8));
    _ = b.toggleSwitch(&state.test_toggle);

    _ = b.lineSpacer();

    //- scroll test offset + buttons
    {
        b.stacks.layout_axis.push(.y);
        b.stacks.pref_size.push(.size(.grow, .fit));
        const counter_container = b.open("###scroll test offset");
        defer b.close(counter_container);

        b.stacks.pref_size.push(.square(.text));
        _ = b.labelf(
            "scroll offset (px): {d}",
            .{state.test_scroll_offset},
        );

        {
            b.stacks.layout_axis.push(.x);
            b.stacks.pref_size.push(.square(.fit_spaced(2)));
            const btns = b.open("###buttons");
            defer b.close(btns);

            b.stacks.font.pushForMany(.mono);
            defer _ = b.stacks.font.pop();
            b.stacks.pref_size.pushForMany(.square(.px_strict(b.em(2))));
            defer _ = b.stacks.pref_size.pop();

            if (b.button("+").clicked()) {
                state.test_scroll_offset += 10;
            }

            if (b.button("-").clicked()) {
                state.test_scroll_offset -= 10;
            }
        }
    }

    _ = b.lineSpacer();

    //- scroll test
    {
        const item_size = b.fontHeight(.label);

        b.stacks.pref_size.push(.square(.grow));
        b.stacks.flags.push(.draw_border);
        const scroll_handle = b.scroll_area.basic.begin(.{
            .scroll_axis = .y,
            .item_size_px = item_size,
            .ptr_offset_px = &state.test_scroll_offset,
        });
        defer b.scroll_area.basic.end(scroll_handle);

        b.stacks.text_align.pushForMany(.size(.start, .center));
        defer _ = b.stacks.text_align.pop();
        b.stacks.pref_size.pushForMany(.size(.grow, .px(item_size)));
        defer _ = b.stacks.pref_size.pop();

        for (scroll_handle.index_range.min.. //
            scroll_handle.index_range.max) |i|
        {
            _ = b.labelf("item {d}", .{i});
        }
    }
}

fn buildRightBar() void {
    //- right bar
    {
        // const icon_size = cu.Atom.PrefSize.px(24);

        b.stacks.flags.push(.draw_side_left);
        b.stacks.layout_axis.push(.y);
        b.stacks.pref_size.push(.size(.fit_strict, .grow));
        b.stacks.alignment.push(.square(.center));
        const bar = b.open("###right bar");
        defer b.close(bar);

        //- inner
        {
            b.stacks.layout_axis.push(.y);
            b.stacks.pref_size.push(.size(.fit, .fit_spaced(4)));
            b.stacks.padding.push(.horizontal(4));
            const inner = b.open("###right bar inner");
            defer b.close(inner);

            for (0..5) |i| {
                b.stacks.flags.push(.init(&.{ .draw_border, .clickable }));
                b.stacks.pref_size.push(.square(.px(24)));
                b.stacks.hover_cursor_shape.push(.pointer);
                const icon = b.buildf("###right bar icon {d}", .{i});

                const inter = icon.interaction();
                if (inter.hovering())
                    icon.palette.set(.border, .hexRgb(0xFF0000));
            }
        }
    }
}
