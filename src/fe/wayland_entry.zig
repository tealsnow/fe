// @TODO:
//   @[ ]: window shadows - cu?

const std = @import("std");
const assert = std.debug.assert;
const mem = std.mem;
const Allocator = mem.Allocator;
const log = std.log.scoped(.@"fe[wl]");

const wl = @import("platform/linux/wayland/wayland.zig");

const WgpuRenderer = @import("wgpu/WgpuRenderer.zig");

const cu = @import("cu");
const mt = cu.math;
const AtomFlags = cu.AtomFlags;
const b = cu.builder;

const xkb = @import("xkbcommon");

// @TODO: Migrate to use ghostty/pkg/fontconfig
const fc = @import("fontconfig.zig");

const pretty = @import("pretty");

pub fn entry(gpa: Allocator) !void {
    try run(gpa);

    std.process.cleanExit();
}

fn run(gpa: Allocator) !void {
    //- window
    const conn = try wl.Connection.init(gpa);
    defer conn.deinit(gpa);

    const window = try wl.Window.init(
        gpa,
        conn,
        .{ .width = 1024, .height = 576 },
    );
    defer window.deinit(gpa);
    window.inset = 15;
    window.minimium_size = .{ .width = 200, .height = 100 };

    //- font loading
    const def_font_path = def_font_path: {
        const font_family = "sans";

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
        break :def_font_path try gpa.dupeZ(u8, path);
    };
    defer gpa.free(def_font_path);

    log.debug("default font path (sans): {s}", .{def_font_path});

    //- wpgu

    var renderer = try WgpuRenderer.init(gpa, .{
        .surface_descriptor = //
        WgpuRenderer.wgpu.surfaceDescriptorFromWaylandSurface(.{
            .label = "wayland surface",
            .display = conn.wl_display,
            .surface = window.wl_surface,
        }),
        .initial_surface_size = window.size,
        .inspect = .{
            // .instance = gpa,
            // .adapter = gpa,
            // .device = gpa,
            // .surface = true,
        },
    });
    defer renderer.deinit(gpa);

    // log.debug("dpi: {d}x{d}", .{ conn.hdpi, conn.vdpi });
    const dpi = mt.Point(u16).point(
        @intFromFloat(@round(conn.hdpi)),
        @intFromFloat(@round(conn.vdpi)),
    );

    const font_face =
        try renderer
            .font_atlas_manager
            .initFontFace(gpa, def_font_path, 0, 11, dpi);

    //- cu

    var cu_callbacks = try WgpuRenderer.CuCallbacks.init(&renderer, gpa);
    defer cu_callbacks.deinit();

    const ui_state = try cu.State.init(gpa, cu_callbacks.callbacks());
    defer ui_state.deinit();

    cu.state = ui_state;

    const default_font =
        ui_state.registerFont(@alignCast(@ptrCast(font_face)));

    ui_state.default_palette = .init(.{
        .background = .hexRgb(0x1d2021), // gruvbox bg0
        .text = .hexRgb(0xebdbb2), // gruvbox fg1
        .text_weak = .hexRgb(0xbdae93), // gruvbox fg3
        .border = .hexRgb(0x3c3836), // gruvbox bg1
        .hot = .hexRgb(0x665c54), // grovbox bg3
        .active = .hexRgb(0xfbf1c7), // grovbox fg0
    });
    ui_state.default_font = default_font;

    //- arena

    var arena_alloc = std.heap.ArenaAllocator.init(gpa);
    defer arena_alloc.deinit();
    const arena = arena_alloc.allocator();

    //- main loop

    var test_toggle = false;

    log.info("starting main loop", .{});
    window.commit();

    main_loop: while (true) {
        defer {
            _ = arena_alloc.reset(.retain_capacity);
        }

        try conn.dispatch();

        var do_render = false;

        while (conn.event_queue.dequeue()) |event| switch (event.kind) {
            .surface_configure => |configure| {
                window.handleSurfaceConfigureEvent(configure);
                do_render = true;
            },

            .toplevel_configure => |conf| conf: {
                do_render = true;

                const size =
                    window.handleToplevelConfigureEvent(conf) orelse
                    // null means no resize
                    break :conf;

                renderer.reconfigure(size);

                cu.state.window_size = .size(
                    @floatFromInt(size.width),
                    @floatFromInt(size.height),
                );
            },

            .toplevel_close => {
                log.debug("close request", .{});
                std.process.exit(0);
                // break :main_loop;
            },

            .frame => {
                // the compositor has told us this is a good time to render
                // useful for animations or just rendering every time

                do_render = true;
            },

            .keyboard_focus => |focus| {
                _ = focus;
            },

            .key => |key| key: {
                cu.state.pushEvent(.{ .key = .{
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
                cu.state.pushEvent(.{ .key = .{
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
                cu.state.pushEvent(.{ .text = .{
                    .text = text.slice(),
                } });
            },

            .pointer_focus => |focus| {
                _ = focus;
            },
            .pointer_motion => |motion| {
                cu.state.pushEvent(.{ .mouse_move = .{
                    .pos = motion.point.floatCast(f32),
                } });
            },
            .pointer_button => |button| {
                cu.state.pushEvent(.{ .mouse_button = .{
                    .button = switch (button.button) {
                        .left => .left,
                        .middle => .middle,
                        .right => .right,
                        .forward => .forward,
                        .back => .back,
                    },
                    .pos = cu.state.mouse,
                    .state = if (button.state == .pressed)
                        .pressed
                    else
                        .released,
                } });
            },
            .pointer_scroll => |scroll| scroll: {
                const value = scroll.value orelse break :scroll;
                cu.state.pushEvent(.{ .scroll = .{
                    .scroll = if (scroll.axis == .vertical)
                        .size(@floatCast(value), 0)
                    else
                        .size(0, @floatCast(value)),
                    .pos = cu.state.mouse,
                } });
            },
        };

        if (!do_render) continue :main_loop;

        b.startFrame();
        defer b.endFrame();

        b.startBuild(0); // @TODO: use proper window id
        cu.state.ui_root.layout_axis = .y;
        cu.state.ui_root.flags.draw_background = true;
        cu.state.ui_root.palette.set(.background, .hexRgba(0xffffff00));

        //- window inset
        {
            const window_rounding = 10;

            const tiling = window.tiling;
            b.stacks.flags.push(flags: {
                var flags = AtomFlags.none.drawBackground();

                if (!tiling.isTiled()) {
                    flags.draw_border = true;
                    b.stacks.corner_radius.push(window_rounding);
                } else {
                    flags.draw_side_top = !tiling.tiled_top;
                    flags.draw_side_bottom = !tiling.tiled_bottom;
                    flags.draw_side_left = !tiling.tiled_left;
                    flags.draw_side_right = !tiling.tiled_right;
                }

                break :flags flags;
            });
            b.stacks.layout_axis.push(.y);
            const window_inset_wrapper = WindowInsetWrapper.begin(window);
            defer window_inset_wrapper.end();

            //- top bar
            {
                b.stacks.flags.push(AtomFlags.none.drawSideBottom());
                b.stacks.layout_axis.push(.x);
                b.stacks.pref_size.push(.size(.fill, .fit));
                const topbar = b.open("topbar");
                defer b.close(topbar);

                if (!tiling.isTiled()) {
                    b.stacks.pref_size
                        .push(.size(.px(window_rounding), .grow));
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
                        .push(AtomFlags.none.clickable().drawText());
                    b.stacks.pref_size.push(.square(.text_pad(8)));
                    const item = b.build(item_str);

                    const inter = item.interaction();
                    if (inter.f.hovering) {
                        item.flags.draw_border = true;
                    }

                    if (inter.f.isClicked()) {
                        std.debug.print("clicked {s}\n", .{item_str});
                        // dropdown_open = true;
                    }
                }

                //- spacer
                {
                    b.stacks.flags.push(AtomFlags.none.clickable());
                    b.stacks.pref_size.push(.square(.grow));
                    const topbar_space = b.build("topbar spacer");

                    const inter = topbar_space.interaction();
                    if (inter.f.left_double_clicked)
                        window.toggleMaximized();
                    if (inter.f.right_pressed)
                        window.showWindowMenu(.point(
                            @intFromFloat(cu.state.mouse.x),
                            @intFromFloat(cu.state.mouse.y),
                        ));
                    if (inter.f.left_dragging) {
                        window.startMove();

                        // @HACK:
                        //  since we loose window focus after the we start
                        //  a move/drag we never get a mouse button release
                        //  event. So we push a synthetic one.
                        conn.event_queue.queue(
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
                        .push(AtomFlags.none.clickable().drawBorder());
                    b.stacks.pref_size
                        .push(.square(.px(topbar.rect.height())));
                    const button = b.openf("top bar button {d}", .{i});
                    defer b.close(button);

                    const int = button.interaction();
                    if (int.f.hovering)
                        button.palette.set(.border, .hexRgb(0xFF0000));

                    if (int.f.isClicked()) {
                        switch (i) {
                            0 => window.minimize(),
                            1 => window.toggleMaximized(),
                            2 => conn.event_queue.queue(
                                .{ .kind = .{ .toplevel_close = void{} } },
                            ),
                            else => unreachable,
                        }
                    }
                }

                if (!tiling.isTiled()) {
                    b.stacks.pref_size.push(.size(.px(window_rounding), .grow));
                    _ = b.spacer();
                }
            }

            //- main pane
            {
                b.stacks.layout_axis.push(.x);
                b.stacks.pref_size.push(.square(.grow));
                const main_pane = b.open("main pain");
                defer b.close(main_pane);

                //- left pane
                {
                    b.stacks.flags.push(AtomFlags.none.drawSideRight());
                    b.stacks.layout_axis.push(.y);
                    b.stacks.pref_size.push(.size(.percent(0.4), .fill));
                    const pane = b.open("left pane");
                    defer b.close(pane);

                    //- header
                    {
                        b.stacks.flags
                            .push(AtomFlags.none.drawSideBottom().drawText());
                        b.stacks.text_align.push(.size(.end, .center));
                        b.stacks.pref_size.push(.size(.grow, .text));
                        const header = b.build("left header");
                        header.display_string = "Left Header gylp";
                    }

                    //- content
                    {
                        b.stacks.flags
                            .push(AtomFlags.none.clipRect().allowOverflow());
                        b.stacks.layout_axis.push(.y);
                        b.stacks.pref_size.push(.square(.grow));
                        const content = b.open("left content");
                        defer b.close(content);

                        // cu.stacks.font.pushForMany(monospace_font);
                        // defer _ = cu.stacks.font.pop();

                        _ = b.label("Hello, World!");

                        _ = b.lineSpacer();
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
                            .push(AtomFlags.none.drawSideBottom().drawText());
                        b.stacks.layout_axis.push(.x);
                        b.stacks.text_align.push(.square(.center));
                        b.stacks.pref_size.push(.size(.grow, .text));
                        const header = b.open("right header");
                        defer b.close(header);
                        header.display_string = "Right Header";

                        if (header.interaction().f.mouse_over) {
                            b.stacks.palette.pushForMany(.init(
                                .{ .background = .hexRgb(0x001800) },
                            ));
                            defer _ = b.stacks.palette.pop();

                            b.stacks.flags.push(
                                AtomFlags.none.floating().drawBackground(),
                            );
                            b.stacks.layout_axis.push(.y);
                            b.stacks.pref_size.push(.square(.fit));
                            const float = b.open("floating");
                            defer b.close(float);
                            float.rel_position = cu.state.mouse
                                .sub(header.rect.p0)
                                .add(.splat(10));

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

                        b.stacks.pref_size.push(.square(.text_pad(8)));
                        if (b.button("foo bar").f.isClicked()) {
                            log.debug("foo bar clicked", .{});
                        }

                        _ = b.lineSpacer();

                        b.stacks.pref_size.push(.size(.px(40), .px(20)));
                        _ = b.toggleSwitch(&test_toggle);
                    }
                }

                //- right bar
                {
                    const icon_size = cu.Atom.PrefSize.px(24);

                    b.stacks.flags.push(AtomFlags.none.drawSideLeft());
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
                                    .push(AtomFlags.none.drawBorder());
                                b.stacks.pref_size.push(.square(icon_size));
                                _ = b.buildf("right bar icon {d}", .{i});
                            }

                            b.stacks.pref_size.push(.size(icon_size, .px(4)));
                            _ = b.spacer();
                        }
                    }
                }
            }
        }

        b.endBuild();

        try renderer.render(arena);
        renderer.surface.present();
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

            b.stacks.flags.pushForMany(AtomFlags.none.clickable());
            defer _ = b.stacks.flags.pop();

            b.stacks.pref_size.push(.square(.px(inset)));
            const top_left = b.build("top-left inset").interaction();

            b.stacks.pref_size.push(.square(.grow));
            const top_middle = b.build("top-middle inset").interaction();

            b.stacks.pref_size.push(.square(.px(inset)));
            const top_right = b.build("top-right inset").interaction();

            if (top_left.f.mouse_over)
                window.conn.setCursor(.resize_nwse) catch {};
            if (top_left.f.isPressed())
                window.startResize(.top_left);

            if (top_middle.f.mouse_over)
                window.conn.setCursor(.resize_ns) catch {};
            if (top_middle.f.isPressed())
                window.startResize(.top);

            if (top_right.f.mouse_over)
                window.conn.setCursor(.resize_nesw) catch {};
            if (top_right.f.isPressed())
                window.startResize(.top_right);
        }

        b.stacks.layout_axis.push(.x);
        b.stacks.pref_size.push(.square(.grow));
        const vert_body = b.open("vert inset body");

        if (!tiling.tiled_left) {
            b.stacks.pref_size.push(.size(.px(inset), .fill));
            b.stacks.flags.push(AtomFlags.none.clickable());
            const left = b.build("left inset").interaction();

            if (left.f.mouse_over)
                window.conn.setCursor(.resize_ew) catch {};
            if (left.f.isPressed())
                window.startResize(.left);
        }

        // We put the atom into the tree here and as a parent
        b.addToTopParent(hori_body);
        b.pushParent(hori_body);

        hori_body.pref_size = .square(.grow);

        const hori_inter = hori_body.interaction();
        if (hori_inter.f.mouse_over)
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
            b.stacks.flags.push(AtomFlags.none.clickable());
            const right = b.build("right inset").interaction();

            if (right.f.mouse_over)
                window.conn.setCursor(.resize_ew) catch {};
            if (right.f.isPressed())
                window.startResize(.right);
        }

        b.close(win_inset.vert_body);

        if (!tiling.tiled_bottom) {
            b.stacks.layout_axis.push(.x);
            b.stacks.pref_size.push(.size(.fill, .px(inset)));
            const bottom_inset_container = b.open("bottom inset container");
            defer b.close(bottom_inset_container);

            b.stacks.flags.pushForMany(AtomFlags.none.clickable());
            defer _ = b.stacks.flags.pop();

            b.stacks.pref_size.push(.square(.px(inset)));
            const bottom_left = b.build("bottom-left inset").interaction();

            b.stacks.pref_size.push(.square(.grow));
            const bottom_middle = b.build("bottom-middle inset").interaction();

            b.stacks.pref_size.push(.square(.px(inset)));
            const bottom_right = b.build("bottom-right inset").interaction();

            if (bottom_left.f.mouse_over)
                window.conn.setCursor(.resize_nesw) catch {};
            if (bottom_left.f.isPressed())
                window.startResize(.bottom_left);

            if (bottom_middle.f.mouse_over)
                window.conn.setCursor(.resize_ns) catch {};
            if (bottom_middle.f.isPressed())
                window.startResize(.bottom);

            if (bottom_right.f.mouse_over)
                window.conn.setCursor(.resize_nwse) catch {};
            if (bottom_right.f.isPressed())
                window.startResize(.bottom_right);
        }
    }
};
