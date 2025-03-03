const std = @import("std");
const assert = std.debug.assert;

const sdl = @import("sdl/sdl.zig");
const fontconfig = @import("fontconfig.zig");

const cu = @import("cu/cu.zig");

const one_frame = false;

pub fn main() !void {
    try sdl.init(sdl.InitFlags.All);
    defer sdl.quit();

    try sdl.ttf.init();
    defer sdl.ttf.quit();

    run() catch |err| {
        const sdl_err = sdl.getError() orelse "[none]";
        const ttf_err = sdl.ttf.getError() orelse "[none]";
        std.log.err("[SDL]: {s}", .{sdl_err});
        std.log.err("[SDL_TTF]: {s}", .{ttf_err});

        return err;
    };
}

pub fn run() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    gpa.backing_allocator = std.heap.c_allocator;
    defer {
        const result = gpa.deinit();
        if (result == .leak) {
            std.debug.print("Memory leak detected\n", .{});
        }
    }
    const alloc = gpa.allocator();

    const window = try sdl.Window.init(.{
        .title = "fe",
        .position = .{},
        .size = .{ .w = 800, .h = 600 },
        .flags = sdl.Window.Flag.allow_highdpi | sdl.Window.Flag.resizable,
    });
    defer window.deinit();

    const renderer = try sdl.Renderer.init(.{
        .window = window,
        .flags = .{
            .accelerated = true,
            .present_vsync = false,
        },
    });
    defer renderer.deinit();

    try fontconfig.init();
    defer fontconfig.deinit();

    const font_path = try fontconfig.getFontForFamilyName(alloc, "sans");
    defer alloc.free(font_path);

    std.log.info("font_path: '{s}'", .{font_path});

    const font = try sdl.ttf.Font.open(font_path, 16);
    defer font.deinit();

    try cu.init(alloc, renderer, font);
    defer cu.deinit();

    const event_timeout_ms = 10;
    const ns_per_update = 1_000_000_000 / 60; // 16 ms in ns
    var update_lag: u64 = ns_per_update;

    var fps_count: u32 = 0; // accumulator of frame count
    var fps: u32 = 0; // set once per second to fps_count

    var prev_fps_calc = try std.time.Instant.now(); // counts to one second, before reset
    var previous_time = try std.time.Instant.now(); // used to measure elapsed time between frames

    var render_count: usize = 0;

    var running = true;
    while (running) {
        const current_time = try std.time.Instant.now();
        const elapsed = current_time.since(previous_time);
        previous_time = current_time;
        update_lag += elapsed;

        // process input
        if (sdl.Event.waitTimeout(event_timeout_ms)) |event| {
            // while (sdl.Event.poll()) |event| {
            switch (event.type) {
                .quit => running = false,
                .key => |key| key_blk: {
                    if (key.state != .pressed) break :key_blk;

                    switch (key.keysym.scancode) {
                        .escape => {
                            running = false;
                        },
                        else => {},
                    }
                },
                .motion => |motion| {
                    cu.state.input.mouse_position.xy = .{
                        .x = @floatFromInt(motion.x),
                        .y = @floatFromInt(motion.y),
                    };
                },
                .button => |button| {
                    const index = @intFromEnum(button.button) - 1;
                    cu.state.input.mouse_buttons[index] = button.state;
                },

                else => {},
            }
        }

        // while (update_lag >= ns_per_update) : (update_lag -= ns_per_update) {
        {
            cu.startBuild(window);
            defer cu.endBuild();
            cu.state.ui_root.layout_axis = .y;

            { // topbar
                const topbar = cu.ui(.{}, "topbar");
                defer topbar.end();
                topbar.layout_axis = .x;
                topbar.size.sz = .{ .w = .full, .h = .px(24) };

                {
                    const spacer = cu.ui(.{}, "");
                    defer spacer.end();
                    spacer.size.sz = .{ .w = .grow, .h = .grow };
                }

                for (0..3) |i| {
                    const button = cu.uif(.{}, "top bar button {d}", .{i});
                    defer button.end();
                    button.size.sz = .{ .w = .px(24), .h = .px(24) };

                    const inter = button.interation();
                    button.color =
                        cu.colorHexRgb(if (inter.f.hovering) 0xFF0000 else 0xFFFFFF);
                }

                const inter = topbar.interation();
                topbar.color = cu.colorHexRgb(if (inter.f.hovering) 0xFF0000 else 0xFFFFFF);
            }

            { // main pane
                const main_pane = cu.ui(.{}, "main pain");
                defer main_pane.end();
                main_pane.layout_axis = .x;
                main_pane.size.sz = .{ .w = .grow, .h = .grow };

                { // left pane
                    const pane = cu.ui(.{}, "left pane");
                    defer pane.end();
                    pane.layout_axis = .y;
                    pane.size.sz = .{ .w = .percent(0.3), .h = .full };

                    {
                        const header = cu.ui(.{}, "left header");
                        defer header.end();
                        header.equipDisplayString();
                        header.size.sz.w = .grow;
                        header.displayString = "Left Header gylp";
                    }

                    {
                        const content = cu.ui(.{}, "left content");
                        defer content.end();
                        content.layout_axis = .y;
                        content.size.sz = .{ .w = .grow, .h = .grow };

                        _ = cu.labelf("fps: {d}", .{fps});
                        _ = cu.labelf("build count: {d}", .{cu.state.current_build_index});
                        _ = cu.labelf("render count: {d}", .{render_count});
                        _ = cu.labelf("atom build count: {d}", .{cu.state.build_atom_count});
                        _ = cu.labelf("current atom count: {d}", .{cu.state.atom_map.count()});
                    }
                }

                { // right pane
                    const pane = cu.ui(.{}, "right pane");
                    defer pane.end();
                    pane.layout_axis = .y;
                    pane.size.sz = .{ .w = .grow, .h = .full };

                    {
                        const header = cu.ui(.{}, "right header");
                        defer header.end();
                        header.equipDisplayString();
                        header.size.sz.w = .grow;
                        // header.text_align = .center;
                    }

                    {
                        const content = cu.ui(.{}, "right content");
                        defer content.end();
                        content.layout_axis = .y;
                        content.size.sz = .{ .w = .grow, .h = .grow };

                        inline for (cu.state.input.mouse_buttons, 0..) |button, i| {
                            const mbtn = cu.uif(
                                .{},
                                "{s}: {s}",
                                .{
                                    std.meta.fields(sdl.MouseButton)[i + 1].name,
                                    @tagName(button),
                                },
                            );
                            defer mbtn.end();
                            mbtn.equipDisplayString();
                        }
                    }
                }

                { // right bar
                    const bar = cu.ui(.{}, "right bar");
                    defer bar.end();
                    bar.layout_axis = .y;
                    bar.size.sz = .{ .w = .px(16), .h = .grow };

                    {
                        const inner = cu.ui(.{}, "right bar inner");
                        defer inner.end();
                        inner.layout_axis = .y;
                        inner.size.sz = .{ .w = .px(16), .h = .fit };

                        for (0..5) |i| {
                            {
                                const icon = cu.uif(.{}, "right bar icon {d}", .{i});
                                defer icon.end();
                                icon.size.sz = .{ .w = .px(16), .h = .px(16) };

                                const inter = icon.interation();
                                icon.color =
                                    cu.colorHexRgb(if (inter.f.hovering) 0xFF0000 else 0xFFFFFF);
                            }

                            {
                                const pad = cu.ui(.{}, "");
                                defer pad.end();
                                pad.size.sz = .{ .w = .px(16), .h = .px(4) };
                            }
                        }
                    }
                }
            }
        }

        try render(renderer);

        if (current_time.since(prev_fps_calc) >= 1e9) {
            fps = fps_count;
            fps_count = 0;
            prev_fps_calc = current_time;
        }

        fps_count += 1;
        render_count += 1;

        if (one_frame and cu.state.current_build_index == 1) running = false;
    }
}

fn render(renderer: *sdl.Renderer) !void {
    try renderer.setDrawColor(18, 18, 18, 255);
    try renderer.clear();

    try renderAtom(cu.state.ui_root, renderer);

    renderer.present();
}

fn renderAtom(atom: *cu.Atom, renderer: *sdl.Renderer) !void {
    try renderer.setDrawColorT(atom.color);
    const rect = sdl.FRect{
        .x = atom.rect.xy.x0,
        .y = atom.rect.xy.y0,
        .w = atom.rect.xy.x1 - atom.rect.xy.x0,
        .h = atom.rect.xy.y1 - atom.rect.xy.y0,
    };
    if (!atom.key.eql(cu.Key.Zero))
        try renderer.drawRectF(&rect);

    if (atom.flags.draw_text) {
        // @TODO: text alignment
        const text_data = atom.text_data.?;

        const font_color = sdl.Color{ .r = 255, .g = 255, .b = 255, .a = 255 };
        const surface = try cu.state.font.renderTextBlended(text_data.zstring, font_color);
        defer surface.deinit();

        const texture = try renderer.createTextureFromSurface(surface);
        defer texture.deinit();

        const dst_rect = sdl.FRect{
            .x = rect.x,
            .y = rect.y,
            .w = @floatFromInt(text_data.size.sz.w),
            .h = @floatFromInt(text_data.size.sz.h),
        };

        try renderer.renderCopyF(texture, null, &dst_rect);
    }

    if (atom.children) |children| {
        var maybe_child: ?*cu.Atom = children.first;
        while (maybe_child) |child| : (maybe_child = child.siblings.next) {
            try renderAtom(child, renderer);
        }
    }
}
