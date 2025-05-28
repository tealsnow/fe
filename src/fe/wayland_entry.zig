const std = @import("std");
const assert = std.debug.assert;
const mem = std.mem;
const Allocator = mem.Allocator;
const log = std.log.scoped(.@"fe[wl]");

const wl = @import("platform/linux/wayland/wayland.zig");
const EventQueueCircleBuffer = wl.EventQueueCircleBuffer;

const WgpuRenderer = @import("wgpu/WgpuRenderer.zig");

const cu = @import("cu");
const mt = cu.math;
const b = cu.builder;

const xkb = @import("xkbcommon");

const tracy = @import("tracy");

// @TODO: Migrate to use ghostty/pkg/fontconfig
const fc = @import("fontconfig.zig");

const pretty = @import("pretty");

pub fn entryPoint(gpa: Allocator) !void {
    tracy.printAppInfo("fe", .{});
    const init_trace = tracy.beginZone(@src(), .{ .name = "init" });

    var action_queue = ActionQueue.empty;

    //- arena

    var arena_alloc = std.heap.ArenaAllocator.init(gpa);
    defer arena_alloc.deinit();
    var tracing_arena_alloc =
        tracy.TracingAllocator.initNamed("arena", arena_alloc.allocator());
    const arena = tracing_arena_alloc.allocator();

    //- windows

    var window_list = try WindowList.init(gpa);
    defer window_list.deinit();

    const def_font_path = try getFontFromFamilyName(gpa, "sans");
    defer gpa.free(def_font_path);
    const mono_font_path = try getFontFromFamilyName(gpa, "mono");
    defer gpa.free(mono_font_path);

    var app_state = AppState{
        .action_queue = &action_queue,
        .window_rounding = 10,
        .arena = arena,
    };

    var test_window_state = TestWindow{ .app = &app_state };
    var panel_window_state = PanelWindow{ .app = &app_state };

    _ = try Window.init(
        &window_list,
        .{
            .title = "Test",
            .app_id = "me.ketanr.fe",
            .initial_size = .size(1024, 576),
            .interface = test_window_state.windowInterface(),

            .font_size = 10,
            .fonts = &.{
                def_font_path,
                mono_font_path,
            },
        },
    );

    _ = try Window.init(
        &window_list,
        .{
            .title = "Fe",
            .app_id = "me.ketanr.fe",
            .initial_size = .size(800, 600),
            .interface = panel_window_state.windowInterface(),

            .font_size = 10,
            .fonts = &.{
                def_font_path,
                mono_font_path,
            },
        },
    );

    //- main loop

    var focus_window_keyboard: ?*Window = null;
    var focus_window_pointer: ?*Window = null;

    log.info("starting main loop", .{});

    for (window_list.slice()) |win| {
        win.wl_window.commit();
    }

    init_trace.end();

    main_loop: while (true) {
        tracy.frameMark();
        defer {
            // _ = arena_alloc.reset(.free_all);
            _ = arena_alloc.reset(.retain_capacity);
            tracing_arena_alloc.discard();
        }

        cu.state = undefined;

        try window_list.conn.dispatch();

        while (window_list.conn.event_queue.dequeue()) //
        |event| switch (event.kind) {
            .surface_configure => |configure| {
                const win = window_list.getWindow(configure.window_id);
                win.wl_window.handleSurfaceConfigureEvent(configure);

                win.present_frame = true;
            },
            .toplevel_configure => |conf| conf: {
                const win = window_list.getWindow(conf.window_id);
                const size =
                    win.wl_window.handleToplevelConfigureEvent(conf) orelse
                    // null means no resize
                    break :conf;

                win.renderer.reconfigure(size);

                win.cu_state.window_size = .size(
                    @floatFromInt(size.width),
                    @floatFromInt(size.height),
                );

                win.present_frame = true;
            },
            .toplevel_close => |close| {
                action_queue.queue(.{ .close_window = close.window_id });
            },
            .frame => |frame| frame: {
                const win = window_list.maybeGetWindow(frame.window_id) orelse
                    break :frame;

                // re-setup a callback, every callback is only valid once
                win.wl_window.setupFrameCallback();

                win.present_frame = true;
            },

            .keyboard_focus => |focus| {
                switch (focus.state) {
                    .enter => focus_window_keyboard =
                        window_list.getWindow(focus.window_id),
                    .leave => focus_window_keyboard = null,
                }
            },
            .key => |key| key: {
                const win = focus_window_keyboard.?;
                win.cu_state.pushEvent(.{ .key = .{
                    .scancode = @intCast(key.scancode),
                    .keycode = .unknown,
                    .mod = .{},
                    .state = if (key.state == .pressed)
                        .pressed
                    else
                        .released,
                } });

                if (key.state != .pressed) break :key;

                switch (@intFromEnum(key.keysym)) {
                    xkb.Keysym.q, xkb.Keysym.Escape => break :main_loop,

                    else => {},
                }
            },
            .modifier => |mods| {
                const win = focus_window_keyboard.?;
                win.cu_state.pushEvent(.{ .key = .{
                    .scancode = 0,
                    .keycode = .unknown,
                    .mod = .{
                        .shift = mods.state.shift,
                        .ctrl = mods.state.ctrl,
                        .alt = mods.state.alt,
                    },
                    .state = .none,
                } });
            },
            .text => |text| {
                const win = focus_window_keyboard.?;
                win.cu_state.pushEvent(.{
                    .text = text.slice(),
                });
            },

            .pointer_focus => |focus| {
                switch (focus.state) {
                    .enter => focus_window_pointer =
                        window_list.getWindow(focus.window_id),
                    .leave => {
                        if (focus_window_pointer) |win|
                            win.cu_state.pushEvent(.{ .mouse_move = .inf });

                        focus_window_pointer = null;
                    },
                }
            },
            .pointer_motion => |motion| {
                const win = focus_window_pointer.?;
                win.cu_state.pushEvent(.{
                    .mouse_move = motion.point.floatCast(f32),
                });
            },
            .pointer_button => |button| {
                const win = focus_window_pointer.?;
                win.cu_state.pushEvent(.{ .mouse_button = .{
                    .button = switch (button.button) {
                        .left => .left,
                        .middle => .middle,
                        .right => .right,
                        .forward => .forward,
                        .back => .back,
                    },
                    .state = if (button.state == .pressed)
                        .pressed
                    else
                        .released,
                } });
            },
            .pointer_scroll => |scroll| scroll: {
                const win = focus_window_pointer.?;
                const value = scroll.value orelse break :scroll;
                win.cu_state.pushEvent(.{
                    .scroll = if (scroll.axis == .vertical)
                        .point(0, @floatCast(value))
                    else
                        .point(@floatCast(value), 0),
                });
            },

            .pointer_gesture_swipe => |swipe| switch (swipe) {
                .begin => |begin| {
                    log.debug(
                        "pointer gesture swipe: begin: serial: {d}, fingers: {d}",
                        .{ begin.serial, begin.fingers },
                    );
                },
                .update => |update| {
                    log.debug(
                        "pointer gesture swipe: update: dx: {d}, dy: {d}",
                        .{ update.dx, update.dy },
                    );
                },
                .end => |end| {
                    log.debug(
                        "pointer gesture swipe: end: serial: {d}, cancelled: {}",
                        .{ end.serial, end.cancelled },
                    );
                },
            },
            .pointer_gesture_pinch => |pinch| switch (pinch) {
                .begin => |begin| {
                    log.debug(
                        "pointer gesture pinch: begin: serial: {d}, fingers: {d}",
                        .{ begin.serial, begin.fingers },
                    );
                },
                .update => |update| {
                    log.debug(
                        "pointer gesture pinch: update: dx: {d}, dy: {d}, scale: {d}, rotation: {d}",
                        .{ update.dx, update.dy, update.scale, update.rotation },
                    );
                },
                .end => |end| {
                    log.debug(
                        "pointer gesture pinch: end: serial: {d}, cancelled: {}",
                        .{ end.serial, end.cancelled },
                    );
                },
            },
            .pointer_gesture_hold => |hold| switch (hold) {
                .begin => |begin| {
                    log.debug(
                        "pointer gesture hold: begin: serial: {d}, fingers: {d}",
                        .{ begin.serial, begin.fingers },
                    );
                },
                .end => |end| {
                    log.debug(
                        "pointer gesture hold: end: serial: {d}, cancelled: {}",
                        .{ end.serial, end.cancelled },
                    );
                },
            },
        };

        while (action_queue.dequeue()) |action| switch (action) {
            .quit => break :main_loop,
            .close_window => |id| {
                const window = window_list.getWindow(id);
                if (focus_window_pointer == window)
                    focus_window_pointer = null;
                if (focus_window_keyboard == window)
                    focus_window_keyboard = null;

                window_list.closeWindow(id);
            },
        };

        for (window_list.slice()) |window| {
            if (!window.present_frame) continue;

            const frame_trace =
                tracy.startDiscontinuousFrame("window");
            defer frame_trace.end();
            tracy.print("window: {s}", .{window.title});

            window.present_frame = false;

            window.build();

            try window.renderer.render(arena);
            window.renderer.surface.present();
        }

        if (window_list.slice().len == 0)
            break :main_loop;
    }

    std.process.cleanExit(); // skips defers on release builds
}

//= action

pub const Action = union(enum) {
    quit,
    close_window: wl.WindowId,
};

pub const ActionQueue = EventQueueCircleBuffer(32, Action);

//= App state

pub const AppState = struct {
    action_queue: *ActionQueue,
    window_rounding: f32,
    arena: Allocator,
};

//= panel window

pub const PanelWindow = struct {
    app: *AppState,

    window: *Window = undefined,

    pub fn windowInterface(self: *PanelWindow) Window.Interface {
        return .{
            .context = @ptrCast(self),
            .vtable = &.{
                .build = vtable.build,
            },
        };
    }

    pub const vtable = struct {
        fn build(ctx: *anyopaque, window: *Window) void {
            const state: *PanelWindow = @ptrCast(@alignCast(ctx));
            state.window = window;
            state.build();
        }
    };

    const titlebar_buttons = struct {
        const MenuBar = MenuBarButtons(*PanelWindow);

        pub fn menuBar(state: *PanelWindow) MenuBar {
            return .{
                .context = state,
                .buttons = &buttons,
            };
        }

        pub const buttons = [_]MenuBar.Button{
            panel.button,
        };

        pub const panel = struct {
            pub const button = MenuBar.Button{
                .name = "Panel",
                .items = &.{
                    .{ .name = "close", .action = close },
                    .{ .name = "quit", .action = quit },
                },
            };

            pub fn close(state: *PanelWindow) void {
                state.app.action_queue.queue(.{
                    .close_window = state.window.wl_window.id,
                });
            }

            pub fn quit(state: *PanelWindow) void {
                state.app.action_queue.queue(.quit);
            }
        };
    };

    fn build(state: *PanelWindow) void {
        const tiling = state.window.wl_window.tiling;
        b.stacks.flags.push(flags: {
            var flags = cu.AtomFlags.draw_background;

            if (!tiling.isTiled()) {
                flags.insert(.draw_border);
                b.stacks.corner_radius.push(state.app.window_rounding);
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

        const menu_bar_buttons = titlebar_buttons.menuBar(state);

        buildTopbar(
            state.window.wl_window,
            state.app.window_rounding,
            *PanelWindow,
            menu_bar_buttons,
        );

        // b.stacks.pref_size.push(.square(.text_pad(8)));
        // _ = b.labelf("pointer: {d}", .{cu.state.mouse});
    }
};

//= test window

pub const TestWindow = struct {
    app: *AppState,

    test_toggle: bool = false,
    test_scroll_offset: f32 = 0,

    window: *Window = undefined,

    pub fn windowInterface(self: *TestWindow) Window.Interface {
        return .{
            .context = @ptrCast(self),
            .vtable = &.{
                .build = vtable.build,
            },
        };
    }

    pub const vtable = struct {
        fn build(ctx: *anyopaque, window: *Window) void {
            const state: *TestWindow = @ptrCast(@alignCast(ctx));
            state.window = window;
            state.build();
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

        buildTopbar(
            state.window.wl_window,
            state.app.window_rounding,
            *TestWindow,
            menu_bar,
        );

        const mono_font = state.window.font_list[1];
        state.buildMainUI(mono_font);
    }

    const titlebar_buttons = struct {
        const MenuBar = MenuBarButtons(*TestWindow);

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

    fn buildMainUI(state: *TestWindow, mono_font: cu.FontId) void {
        b.stacks.layout_axis.push(.x);
        b.stacks.pref_size.push(.square(.grow));
        const main_pane = b.open("main pain");
        defer b.close(main_pane);

        buildLeftPane(mono_font);

        state.buildRightPane(mono_font);

        //- right bar
        {
            const icon_size = cu.Atom.PrefSize.px(24);

            b.stacks.flags.push(.draw_side_left);
            b.stacks.layout_axis.push(.y);
            b.stacks.pref_size.push(.size(icon_size, .grow));
            const bar = b.open("right bar");
            defer b.close(bar);

            //- inner
            {
                b.stacks.layout_axis.push(.y);
                b.stacks.pref_size.push(.size(icon_size, .fit));
                const inner = b.open("right bar inner");
                defer b.close(inner);

                for (0..5) |i| {
                    {
                        b.stacks.flags
                            .push(.draw_border);
                        b.stacks.pref_size.push(.square(icon_size));
                        _ = b.buildf("right bar icon {d}", .{i});
                    }

                    b.stacks.pref_size.push(.size(icon_size, .px(4)));
                    _ = b.spacer();
                }
            }
        }
    }

    fn buildLeftPane(mono_font: cu.FontId) void {
        b.stacks.flags.push(.draw_side_right);
        b.stacks.layout_axis.push(.y);
        b.stacks.pref_size.push(.size(.percent(0.4), .fill));
        const pane = b.open("left pane");
        defer b.close(pane);

        //- header
        {
            b.stacks.flags
                .push(.unionWith(.draw_side_bottom, .draw_text));
            b.stacks.text_align.push(.size(.end, .center));
            b.stacks.pref_size.push(.size(.grow, .text));
            const header = b.build("left header");
            header.display_string = "Left Header gylp";
        }

        //- content

        b.stacks.flags
            .push(.unionWith(.clip_rect, .allow_overflow));
        b.stacks.layout_axis.push(.y);
        b.stacks.pref_size.push(.square(.grow));
        const content = b.open("left content");
        defer b.close(content);

        b.stacks.pref_size.pushForMany(.square(.text));
        defer _ = b.stacks.pref_size.pop();

        _ = b.label("Hello, World!");

        _ = b.lineSpacer();

        b.stacks.font.pushForMany(mono_font);
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

    fn buildRightPane(state: *TestWindow, mono_font: cu.FontId) void {
        b.stacks.layout_axis.push(.y);
        b.stacks.pref_size.push(.size(.grow, .fill));
        const pane = b.open("right pane");
        defer b.close(pane);

        //- header
        {
            b.stacks.flags
                .push(.unionWith(.draw_side_bottom, .draw_text));
            b.stacks.layout_axis.push(.x);
            b.stacks.text_align.push(.square(.center));
            b.stacks.pref_size.push(.size(.grow, .text));
            const header = b.open("right header");
            defer b.close(header);
            header.display_string = "Right Header";

            if (header.interaction().f.contains(.mouse_over)) {
                b.stacks.flags
                    .push(.unionWith(.draw_background, .draw_border));
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
                b.stacks.pref_size.push(.square(.fit));
                const btns = b.open("buttons");
                defer b.close(btns);

                b.stacks.font.pushForMany(mono_font);
                defer _ = b.stacks.font.pop();

                b.stacks.pref_size.push(.square(.text_pad(8)));
                if (b.button("+").clicked()) {
                    state.test_scroll_offset += 10;
                }

                b.stacks.pref_size.push(.square(.text_pad(8)));
                if (b.button("-").clicked()) {
                    state.test_scroll_offset -= 10;
                }
            }
        }

        _ = b.lineSpacer();

        // scroll test
        {
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
};

//= titlebar

pub fn MenuBarButtons(comptime Context: type) type {
    return struct {
        context: Context,
        buttons: []const Button,

        pub const Button = struct {
            name: []const u8,
            items: []const Item,
            // binding
        };

        pub const Item = struct {
            name: []const u8,
            action: *const fn (Context) void,
            // binding
        };
    };
}

fn buildTopbar(
    window: *wl.Window,
    rounding: f32,
    comptime MenuContext: type,
    menu_buttons: MenuBarButtons(MenuContext),
) void {
    const tiling = window.tiling;

    const height = b.em(1.5);

    b.stacks.flags.push(.draw_side_bottom);
    b.stacks.layout_axis.push(.x);
    b.stacks.pref_size.push(.size(.fill, .px(height)));
    const topbar = b.open("topbar");
    defer b.close(topbar);

    if (!tiling.isTiled()) {
        b.stacks.pref_size
            .push(.size(.px(rounding), .grow));
        _ = b.spacer();
    }

    for (menu_buttons.buttons) |menu_button| {
        b.stacks.flags
            .push(.unionWith(.clickable, .draw_text));
        b.stacks.pref_size.push(.size(.text_pad(8), .px(height)));
        const item = b.build(menu_button.name);

        const inter = item.interaction();
        if (inter.hovering()) {
            item.flags.insert(.draw_border);
        }

        if (inter.clicked()) {
            b.ctx_menu.openMenu(
                item.key,
                item.key,
                .point(0, height),
            );
        }

        if (b.ctx_menu.begin(item.key)) |ctx_menu| {
            defer b.ctx_menu.end(ctx_menu);

            b.stacks.flags.push(.unionWith(.draw_background, .draw_border));
            b.stacks.layout_axis.push(.y);
            b.stacks.pref_size.push(.square(.fit));
            const menu = b.open("ctx menu");
            defer b.close(menu);

            // b.stacks.pref_size.pushForMany(.square(.text_pad(8)));
            // defer _ = b.stacks.pref_size.pop();

            for (menu_button.items) |menu_item| {
                b.stacks.pref_size.push(.square(.text_pad(8)));
                if (b.button(menu_item.name).clicked()) {
                    menu_item.action(menu_buttons.context);
                }
            }
        }
    }

    //- spacer
    {
        b.stacks.flags.push(.clickable);
        b.stacks.pref_size.push(.size(.grow, .px(height)));
        const topbar_space = b.build("topbar spacer");

        const inter = topbar_space.interaction();
        if (inter.doubleClicked())
            window.toggleMaximized();
        if (inter.f.contains(.right_pressed))
            window.showWindowMenu(.point(
                @intFromFloat(cu.state.mouse.x),
                @intFromFloat(cu.state.mouse.y),
            ));
        if (inter.dragging()) {
            window.startMove();

            // @HACK:
            //  since we loose window focus after the we start
            //  a move/drag we never get a mouse button release
            //  event. So we push a synthetic one.
            window.conn.event_queue.queue(
                .{ .kind = .{ .pointer_button = .{
                    .button = .left,
                    .state = .released,
                    .serial = 0,
                } } },
            );
        }
    }

    //- window buttons
    for (0..3) |i| {
        b.stacks.flags
            .push(.unionWith(.clickable, .draw_border));
        b.stacks.pref_size
            .push(.square(.px(height)));
        const button = b.openf("top bar button {d}", .{i});
        defer b.close(button);

        const inter = button.interaction();
        if (inter.hovering())
            button.palette.set(.border, .hexRgb(0xFF0000));

        if (inter.clicked()) {
            switch (i) {
                0 => window.minimize(),
                1 => window.toggleMaximized(),
                2 => window.conn.event_queue.queue(
                    .{ .kind = .{ .toplevel_close = .{
                        .window_id = window.id,
                    } } },
                ),
                else => unreachable,
            }
        }
    }

    if (!tiling.isTiled()) {
        b.stacks.pref_size.push(.size(.px(rounding), .grow));
        _ = b.spacer();
    }
}

//= window inset

/// Insets atoms created between `begin` and `end` based on the window inset
/// with the current tiling
///
/// Handles resizing and cursor shape
///
// @TODO: use cu mouse cursor api when implemented
pub const WindowInsetWrapper = struct {
    window: *const wl.Window,
    inset: f32,
    vert_body: *cu.Atom,
    hori_body: *cu.Atom,

    pub fn begin(window: *const wl.Window) WindowInsetWrapper {
        const inset_int = window.inset orelse 0;
        const inset: f32 = @floatFromInt(inset_int);

        const tiling = window.tiling;

        // Since we create atoms before where we want to add this to the tree
        // we create this as an orphan here as we want to be able to use
        // any properties on the stacks.
        cu.state.next_atom_orphan = true;
        const hori_body = b.build("hori inset body");

        if (!tiling.tiled_top) {
            b.stacks.pref_size.push(.size(.fill, .px(inset)));
            b.stacks.layout_axis.push(.x);
            const top_inset_container = b.open("top inset container");
            defer b.close(top_inset_container);

            b.stacks.flags.pushForMany(.clickable);
            defer _ = b.stacks.flags.pop();

            b.stacks.pref_size.push(.square(.px(inset)));
            const top_left = b.build("top-left inset").interaction();

            b.stacks.pref_size.push(.square(.grow));
            const top_middle = b.build("top-middle inset").interaction();

            b.stacks.pref_size.push(.square(.px(inset)));
            const top_right = b.build("top-right inset").interaction();

            if (top_left.f.contains(.mouse_over))
                window.conn.setCursor(.resize_nwse) catch {};
            if (top_left.pressed())
                window.startResize(.top_left);

            if (top_middle.f.contains(.mouse_over))
                window.conn.setCursor(.resize_ns) catch {};
            if (top_middle.pressed())
                window.startResize(.top);

            if (top_right.f.contains(.mouse_over))
                window.conn.setCursor(.resize_nesw) catch {};
            if (top_right.pressed())
                window.startResize(.top_right);
        }

        b.stacks.layout_axis.push(.x);
        b.stacks.pref_size.push(.square(.grow));
        const vert_body = b.open("vert inset body");

        if (!tiling.tiled_left) {
            b.stacks.pref_size.push(.size(.px(inset), .fill));
            b.stacks.flags.push(.clickable);
            const left = b.build("left inset").interaction();

            if (left.f.contains(.mouse_over))
                window.conn.setCursor(.resize_ew) catch {};
            if (left.pressed())
                window.startResize(.left);
        }

        // We put the atom into the tree here and as a parent
        b.addToTopParent(hori_body);
        b.pushParent(hori_body);

        hori_body.pref_size = .square(.grow);

        const hori_inter = hori_body.interaction();
        if (hori_inter.f.contains(.mouse_over))
            window.conn.setCursor(.default) catch {};

        return .{
            .window = window,
            .inset = inset,
            .vert_body = vert_body,
            .hori_body = hori_body,
        };
    }

    pub fn end(win_inset: WindowInsetWrapper) void {
        const window = win_inset.window;
        const tiling = window.tiling;
        const inset = win_inset.inset;

        b.close(win_inset.hori_body);

        if (!tiling.tiled_right) {
            b.stacks.pref_size.push(.size(.px(inset), .fill));
            b.stacks.flags.push(.clickable);
            const right = b.build("right inset").interaction();

            if (right.f.contains(.mouse_over))
                window.conn.setCursor(.resize_ew) catch {};
            if (right.pressed())
                window.startResize(.right);
        }

        b.close(win_inset.vert_body);

        if (!tiling.tiled_bottom) {
            b.stacks.layout_axis.push(.x);
            b.stacks.pref_size.push(.size(.fill, .px(inset)));
            const bottom_inset_container = b.open("bottom inset container");
            defer b.close(bottom_inset_container);

            b.stacks.flags.pushForMany(.clickable);
            defer _ = b.stacks.flags.pop();

            b.stacks.pref_size.push(.square(.px(inset)));
            const bottom_left = b.build("bottom-left inset").interaction();

            b.stacks.pref_size.push(.square(.grow));
            const bottom_middle = b.build("bottom-middle inset").interaction();

            b.stacks.pref_size.push(.square(.px(inset)));
            const bottom_right = b.build("bottom-right inset").interaction();

            if (bottom_left.f.contains(.mouse_over))
                window.conn.setCursor(.resize_nesw) catch {};
            if (bottom_left.pressed())
                window.startResize(.bottom_left);

            if (bottom_middle.f.contains(.mouse_over))
                window.conn.setCursor(.resize_ns) catch {};
            if (bottom_middle.pressed())
                window.startResize(.bottom);

            if (bottom_right.f.contains(.mouse_over))
                window.conn.setCursor(.resize_nwse) catch {};
            if (bottom_right.pressed())
                window.startResize(.bottom_right);
        }
    }
};

//= get font helper

fn getFontFromFamilyName(
    gpa: Allocator,
    font_family: [:0]const u8,
) ![:0]const u8 {
    try fc.init();
    defer fc.deinit();

    const pattern = try fc.Pattern.create();
    defer pattern.destroy();
    try pattern.addString(.family, font_family);
    try pattern.addBool(.outline, .true);

    const config = try fc.Config.getCurrent();
    try config.substitute(pattern, .pattern);
    fc.defaultSubsitute(pattern);

    const match = try fc.fontMatch(config, pattern);
    defer match.destroy();

    const path = try match.getString(.file, 0);
    return try gpa.dupeZ(u8, path);
}

//= window

pub const Window = struct {
    wl_window: *wl.Window,
    title: [:0]const u8,
    renderer: *WgpuRenderer,
    cu_callbacks: *WgpuRenderer.CuCallbacks,
    cu_state: *cu.State,
    font_list: []const cu.FontId,
    interface: Interface,

    present_frame: bool = false,

    pub const Interface = struct {
        context: *anyopaque,
        vtable: *const VTable,

        pub const VTable = struct {
            build: *const fn (*anyopaque, *Window) void,
        };

        pub fn build(inter: Interface, window: *Window) void {
            inter.vtable.build(inter.context, window);
        }
    };

    pub const InitOpts = struct {
        title: [:0]const u8,
        app_id: ?[:0]const u8 = null,
        inset: ?u32 = 15,
        initial_size: mt.Size(u32),
        min_size: ?mt.Size(u32) = .square(200),
        interface: Interface,

        font_size: i32,
        fonts: []const [:0]const u8,
    };

    pub fn init(
        list: *WindowList,
        opts: InitOpts,
    ) !*Window {
        const wl_window = try wl.Window.init(
            list.gpa,
            list.conn,
            opts.initial_size,
        );
        wl_window.setTitle(opts.title);
        if (opts.app_id) |id| wl_window.setAppId(id);
        wl_window.inset = opts.inset;
        wl_window.setMinSize(if (opts.min_size) |s| s else .square(0));

        const gpa = list.gpa;
        const conn = list.conn;

        //- renderer

        var renderer = try WgpuRenderer.init(gpa, .{
            .surface_descriptor = //
            WgpuRenderer.wgpu.surfaceDescriptorFromWaylandSurface(.{
                .label = "wayland surface",
                .display = conn.wl_display,
                .surface = wl_window.wl_surface,
            }),
            .initial_surface_size = wl_window.size,
            .inspect = .{
                // .instance = gpa,
                // .adapter = gpa,
                // .device = gpa,
                // .surface = true,
            },
        });

        //- cu

        const cu_callbacks = try WgpuRenderer.CuCallbacks.init(
            renderer,
            @floatFromInt(conn.cursor_size),
        );

        const cu_state = try cu.State.init(gpa, cu_callbacks.callbacks());

        //- font loading
        const font_list = list: {
            const dpi = mt.Size(u16).size(
                @intFromFloat(@round(conn.hdpi)),
                @intFromFloat(@round(conn.vdpi)),
            );

            const font_list = try gpa.alloc(cu.FontId, opts.fonts.len);
            errdefer gpa.free(font_list);

            for (opts.fonts, 0..) |font_path, i| {
                const font_face = try renderer
                    .font_manager
                    .initFontFace(gpa, font_path, 0, opts.font_size, dpi);

                const font_id =
                    cu_state.registerFont(@alignCast(@ptrCast(font_face)));

                font_list[i] = font_id;
            }

            break :list font_list;
        };
        errdefer gpa.free(font_list);

        cu_state.default_palette = .init(.{
            .background = .hexRgb(0x1d2021), // gruvbox bg0
            .text = .hexRgb(0xebdbb2), // gruvbox fg1
            .text_weak = .hexRgb(0xbdae93), // gruvbox fg3
            .border = .hexRgb(0x3c3836), // gruvbox bg1
            .hot = .hexRgb(0x665c54), // grovbox bg3
            .active = .hexRgb(0xfbf1c7), // grovbox fg0
        });
        cu_state.default_font = font_list[0];

        //- return

        const window = try gpa.create(Window);
        window.* = .{
            .wl_window = wl_window,
            .title = opts.title,
            .renderer = renderer,
            .cu_callbacks = cu_callbacks,
            .cu_state = cu_state,
            .font_list = font_list,
            .interface = opts.interface,
        };

        try list.pushWindow(window);

        return window;
    }

    pub fn deinit(window: *Window, gpa: Allocator) void {
        window.cu_state.deinit();
        window.cu_callbacks.deinit();
        window.renderer.deinit();
        window.wl_window.deinit(gpa);
        gpa.free(window.font_list);
        gpa.destroy(window);
        window.* = undefined;
    }

    pub fn build(window: *Window) void {
        cu.state = window.cu_state;

        b.startFrame();
        defer b.endFrame();

        b.startBuild(@intFromPtr(window.wl_window));
        defer b.endBuild();
        cu.state.ui_root.layout_axis = .y;
        cu.state.ui_root.flags.insert(.draw_background);
        cu.state.ui_root.palette.set(.background, .hexRgba(0xffffff00));

        window.interface.build(window);
    }
};

const WindowList = struct {
    gpa: Allocator,
    conn: *wl.Connection,
    map: std.AutoArrayHashMapUnmanaged(wl.Window.WindowId, *Window),

    pub fn init(gpa: Allocator) !WindowList {
        const conn = try wl.Connection.init(gpa);
        return .{
            .gpa = gpa,
            .conn = conn,
            .map = .empty,
        };
    }

    pub fn deinit(self: *WindowList) void {
        for (self.slice()) |window| {
            window.deinit(self.gpa);
        }
        self.map.deinit(self.gpa);
        self.conn.deinit(self.gpa);
        self.* = undefined;
    }

    pub fn pushWindow(
        self: *WindowList,
        window: *Window,
    ) !void {
        try self.map.put(self.gpa, window.wl_window.id, window);
    }

    pub fn getWindow(self: WindowList, window_id: wl.WindowId) *Window {
        return self.map.get(window_id) orelse @panic("invalid window id");
    }

    pub fn maybeGetWindow(self: WindowList, window_id: wl.WindowId) ?*Window {
        return self.map.get(window_id);
    }

    pub fn closeWindow(
        self: *WindowList,
        window_id: wl.WindowId,
    ) void {
        const entry = self.map.fetchOrderedRemove(window_id) orelse
            @panic("invalid window id");
        const window = entry.value;
        window.deinit(self.gpa);
    }

    pub fn slice(self: WindowList) []*Window {
        return self.map.values();
    }
};
