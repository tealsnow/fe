const std = @import("std");
const assert = std.debug.assert;
const mem = std.mem;
const Allocator = mem.Allocator;
const log = std.log.scoped(.@"fe[wl]");

const wl = @import("platform/linux/wayland/wayland.zig");

const WgpuRenderer = @import("wgpu/WgpuRenderer.zig");

const cu = @import("cu");
const mt = cu.math;
const b = cu.builder;

const xkb = @import("xkbcommon");

const tracy = @import("tracy");

// @TODO: Migrate to use ghostty/pkg/fontconfig
const fc = @import("fontconfig.zig");

const pretty = @import("pretty");

pub fn entry(gpa: Allocator) !void {
    tracy.printAppInfo("fe", .{});

    const init_trace = tracy.beginZone(@src(), .{ .name = "init" });

    //- window
    const conn = try wl.Connection.init(gpa);
    defer conn.deinit(gpa);

    var window_list = WindowList.empty;
    defer window_list.deinit(gpa);

    const main_window = try Window.init(gpa, conn, .size(1024, 576), "fe");
    defer main_window.deinit(gpa);
    try window_list.pushWindow(gpa, main_window);

    const test_window = try Window.init(gpa, conn, .size(800, 600), "fe test");
    defer test_window.deinit(gpa);
    try window_list.pushWindow(gpa, test_window);

    //- arena

    var arena_alloc = std.heap.ArenaAllocator.init(gpa);
    defer arena_alloc.deinit();
    var tracing_arena_alloc =
        tracy.TracingAllocator.initNamed("arena", arena_alloc.allocator());
    const arena = tracing_arena_alloc.allocator();

    //- main loop

    var focus_window_keyboard: ?*Window = null;
    var focus_window_pointer: ?*Window = null;

    var state = State{
        .window = main_window,
        .window_rounding = 10,
        .arena = arena,
    };

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

        try conn.dispatch();

        while (conn.event_queue.dequeue()) |event| switch (event.kind) {
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
                _ = close;

                log.debug("close request", .{});
                // std.process.exit(0);
                break :main_loop;
            },
            .frame => |frame| {
                const win = window_list.getWindow(frame.window_id);
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
                        focus_window_pointer.?.cu_state.mouse = .splat(-1);
                        focus_window_pointer.?.cu_state.pushEvent(.{
                            .mouse_move = .inf,
                        });
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

        if (main_window.present_frame) {
            const frame_trace =
                tracy.startDiscontinuousFrame("main window render");
            defer frame_trace.end();

            main_window.present_frame = false;

            buildWindowUI(main_window, &state);

            try main_window.renderer.render(state.arena);
            main_window.renderer.surface.present();
        }

        if (test_window.present_frame) {
            const frame_trace =
                tracy.startDiscontinuousFrame("test window render");
            defer frame_trace.end();

            test_window.present_frame = false;

            buildTestWindowUI(test_window);

            try test_window.renderer.render(state.arena);
            test_window.renderer.surface.present();
        }
    }

    std.process.cleanExit(); // skips defers on release builds
}

pub fn buildTestWindowUI(window: *Window) void {
    cu.state = window.cu_state;

    b.startFrame();
    defer b.endFrame();

    b.startBuild(@intFromPtr(window.wl_window));
    defer b.endBuild();
    cu.state.ui_root.layout_axis = .y;
    cu.state.ui_root.flags.insert(.draw_background);
    cu.state.ui_root.palette.set(.background, .hexRgba(0xffffff00));

    //- window inset
    {
        const window_rounding = 10;

        const tiling = window.wl_window.tiling;
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
            WindowInsetWrapper.begin(window.wl_window);
        defer window_inset_wrapper.end();

        buildTopbar(window.wl_window, window_rounding);

        //
    }
}

pub fn buildWindowUI(window: *Window, state: *State) void {
    cu.state = window.cu_state;

    b.startFrame();
    defer b.endFrame();

    b.startBuild(@intFromPtr(window.wl_window));
    defer b.endBuild();
    cu.state.ui_root.layout_axis = .y;
    cu.state.ui_root.flags.insert(.draw_background);
    cu.state.ui_root.palette.set(.background, .hexRgba(0xffffff00));

    //- window inset
    {
        const window_rounding = state.window_rounding;

        const tiling = window.wl_window.tiling;
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
            WindowInsetWrapper.begin(window.wl_window);
        defer window_inset_wrapper.end();

        buildTopbar(window.wl_window, state.window_rounding);

        buildUI(state);
    }
}

const State = struct {
    window: *Window,
    window_rounding: f32,
    arena: Allocator,

    test_toggle: bool = false,

    test_scroll_offset: f32 = 0,
};

fn buildTopbar(
    window: *wl.Window,
    rounding: f32,
) void {
    const tiling = window.tiling;

    b.stacks.flags.push(.draw_side_bottom);
    b.stacks.layout_axis.push(.x);
    b.stacks.pref_size.push(.size(.fill, .fit));
    const topbar = b.open("topbar");
    defer b.close(topbar);

    if (!tiling.isTiled()) {
        b.stacks.pref_size
            .push(.size(.px(rounding), .grow));
        _ = b.spacer();
    }

    //- menu items
    const menu_items = [_][]const u8{
        "Fe",
        "File",
        "Edit",
        "Help",
        "qypgj",
        "WERTYUI",
        "WAV",
    };

    for (menu_items) |item_str| {
        b.stacks.flags
            .push(.unionWith(.clickable, .draw_text));
        b.stacks.pref_size.push(.square(.text_pad(8)));
        const item = b.build(item_str);

        const inter = item.interaction();
        if (inter.hovering()) {
            item.flags.insert(.draw_border);
        }

        if (inter.clicked()) {
            b.ctx_menu.openMenu(
                item.key,
                item.key,
                .point(0, topbar.rect.height()),
            );
        }

        if (b.ctx_menu.begin(item.key)) |ctx_menu| {
            defer b.ctx_menu.end(ctx_menu);

            b.stacks.flags.push(.unionWith(.draw_background, .draw_border));
            b.stacks.layout_axis.push(.y);
            b.stacks.pref_size.push(.square(.fit));
            const menu = b.open("ctx menu");
            defer b.close(menu);

            b.stacks.pref_size.pushForMany(.square(.text_pad(8)));
            defer _ = b.stacks.pref_size.pop();

            _ = b.button("foo bar");
            _ = b.button("this is a button");
        }
    }

    //- spacer
    {
        b.stacks.flags.push(.clickable);
        b.stacks.pref_size.push(.square(.grow));
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
            .push(.square(.px(topbar.rect.height())));
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

pub fn buildUI(
    state: *State,
) void {
    b.stacks.layout_axis.push(.x);
    b.stacks.pref_size.push(.square(.grow));
    const main_pane = b.open("main pain");
    defer b.close(main_pane);

    //- left pane
    {
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
        {
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

            b.stacks.font.pushForMany(state.window.mono_font);
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
    }

    //- right pane
    {
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
        {
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
                _ = b.labelf("scroll offset (px): {d}", .{state.test_scroll_offset});

                {
                    b.stacks.layout_axis.push(.x);
                    b.stacks.pref_size.push(.square(.fit));
                    const btns = b.open("buttons");
                    defer b.close(btns);

                    b.stacks.font.pushForMany(state.window.mono_font);
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
    }

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

pub const Window = struct {
    wl_window: *wl.Window,
    title: [:0]const u8,
    renderer: *WgpuRenderer,
    cu_callbacks: *WgpuRenderer.CuCallbacks,
    cu_state: *cu.State,
    default_font: cu.FontId,
    mono_font: cu.FontId,

    present_frame: bool = false,

    pub fn init(
        gpa: Allocator,
        conn: *wl.Connection,
        initial_size: mt.Size(u32),
        title: [:0]const u8,
    ) !*Window {
        const wl_window = try wl.Window.init(gpa, conn, initial_size);
        wl_window.setTitle(title);
        wl_window.setAppId("me.ketanr.fe");
        wl_window.inset = 15;
        wl_window.setMinSize(.size(200, 100));

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

        //- font loading

        // log.info("display dpi: {d}x{d}", .{ conn.hdpi, conn.vdpi });
        const dpi = mt.Size(u16).size(
            @intFromFloat(@round(conn.hdpi)),
            @intFromFloat(@round(conn.vdpi)),
        );

        const def_font_path = try getFontFromFamilyName(gpa, "sans");
        defer gpa.free(def_font_path);
        const mono_font_path = try getFontFromFamilyName(gpa, "mono");
        defer gpa.free(mono_font_path);

        // log.debug("default font path (sans): {s}", .{def_font_path});
        // log.debug("mono font path (mono): {s}", .{mono_font_path});

        const font_size = 10;
        const def_font_face = try renderer
            .font_manager
            .initFontFace(gpa, def_font_path, 0, font_size, dpi);
        const mono_font_face = try renderer
            .font_manager
            .initFontFace(gpa, mono_font_path, 0, font_size, dpi);

        //- cu

        const cu_callbacks = try WgpuRenderer.CuCallbacks.init(
            renderer,
            gpa,
            @floatFromInt(conn.cursor_size),
        );

        const cu_state = try cu.State.init(gpa, cu_callbacks.callbacks());

        const default_font =
            cu_state.registerFont(@alignCast(@ptrCast(def_font_face)));

        const mono_font =
            cu_state.registerFont(@alignCast(@ptrCast(mono_font_face)));

        cu_state.default_palette = .init(.{
            .background = .hexRgb(0x1d2021), // gruvbox bg0
            .text = .hexRgb(0xebdbb2), // gruvbox fg1
            .text_weak = .hexRgb(0xbdae93), // gruvbox fg3
            .border = .hexRgb(0x3c3836), // gruvbox bg1
            .hot = .hexRgb(0x665c54), // grovbox bg3
            .active = .hexRgb(0xfbf1c7), // grovbox fg0
        });
        cu_state.default_font = default_font;

        //- return

        const window = try gpa.create(Window);
        window.* = .{
            .wl_window = wl_window,
            .title = title,
            .renderer = renderer,
            .cu_callbacks = cu_callbacks,
            .cu_state = cu_state,
            .default_font = default_font,
            .mono_font = mono_font,
        };
        return window;
    }

    pub fn deinit(window: *Window, gpa: Allocator) void {
        window.cu_state.deinit();
        window.cu_callbacks.deinit();
        window.renderer.deinit(gpa);
        window.wl_window.deinit(gpa);
        gpa.destroy(window);
    }
};

const WindowList = struct {
    map: std.AutoArrayHashMapUnmanaged(wl.Window.WindowId, *Window),

    pub const empty = WindowList{ .map = .empty };

    pub fn deinit(self: *WindowList, gpa: Allocator) void {
        self.map.deinit(gpa);
    }

    pub fn pushWindow(self: *WindowList, gpa: Allocator, window: *Window) !void {
        try self.map.put(gpa, window.wl_window.id, window);
    }

    pub fn getWindow(self: WindowList, window_id: wl.Window.WindowId) *Window {
        return self.map.get(window_id) orelse @panic("invalid key");
    }

    pub fn slice(self: WindowList) []*Window {
        return self.map.values();
    }
};
