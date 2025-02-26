const std = @import("std");

const sdl = @import("sdl/sdl.zig");
const fontconfig = @import("fontconfig.zig");

const cu = @import("cu/cu.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    gpa.backing_allocator = std.heap.c_allocator;
    defer {
        const result = gpa.deinit();
        if (result == .leak) {
            std.debug.print("Memory leak detected\n", .{});
        }
    }
    const alloc = gpa.allocator();

    try sdl.init(sdl.InitFlags.All);
    defer sdl.quit();

    try sdl.ttf.init();
    defer sdl.ttf.deinit();

    const window = try sdl.Window.init(.{
        .title = "fe",
        .position = .{},
        .size = .{ .w = 800, .h = 600 },
        .flags = sdl.Window.Flag.allow_highdpi | sdl.Window.Flag.resizable,
    });
    defer window.deinit();

    const renderer = try sdl.Renderer.init(.{
        .window = window,
        .flags = .{ .accelerated = true },
    });
    defer renderer.deinit();

    try fontconfig.init();
    defer fontconfig.deinit();

    const font_path = try fontconfig.getFontForFamilyName(alloc, "sans");
    defer alloc.free(font_path);

    std.log.info("font_path: '{s}'", .{font_path});

    const font = try sdl.ttf.Font.open(font_path, 24);
    defer font.deinit();

    // const font_color = sdl.Color{ .r = 255, .g = 255, .b = 255, .a = 255 };
    // const surface = try font.renderTextSolid("Hello, World!", font_color);
    // defer surface.deinit();

    // const texture = try renderer.createTextureFromSurface(surface);
    // defer texture.deinit();

    // var tex_w: c_int = 0;
    // var tex_h: c_int = 0;
    // try texture.query(null, null, &tex_w, &tex_h);
    // const dst_rect = sdl.Rect{ .x = 0, .y = 0, .w = tex_w, .h = tex_h };

    try cu.init(alloc, renderer, font);
    defer cu.deinit();

    var running = true;
    while (running) {
        while (sdl.Event.poll()) |event| {
            switch (event.type) {
                .quit => running = false,
                .key => |key| key_blk: {
                    if (key.state != .pressed) break :key_blk;

                    switch (key.keysym.scancode) {
                        .escape => {
                            running = false;
                        },
                        .h => {
                            std.debug.print("Hello!\n", .{});
                        },
                        else => {},
                    }
                    if (key.keysym.scancode == .escape) running = false;
                },
                else => {},
            }
        }

        cu.startFrame();
        defer cu.endFrame();

        try renderer.setDrawColor(18, 18, 18, 255);
        try renderer.clear();

        // try renderer.renderCopy(texture, null, &dst_rect);

        cu.startBuild(window);

        { // root
            const root = cu.ui(.{}, "root");
            defer root.end();
            root.layout_axis = .x;
            root.size.sz = .{ .w = .full, .h = .full };

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
                }

                {
                    const content = cu.ui(.{}, "left content");
                    defer content.end();
                    content.size.sz = .{ .w = .grow, .h = .grow };
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
                    header.flags.text_centered = true;
                }

                {
                    const content = cu.ui(.{}, "right content");
                    defer content.end();
                    content.size.sz = .{ .w = .grow, .h = .grow };
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
                    bar.layout_axis = .y;
                    inner.size.sz = .{ .w = .full, .h = .sum };

                    for (0..2) |i| {
                        const icon = cu.uif(.{}, "right bar icon {d}", .{i});
                        defer icon.end();
                        icon.size.sz = .{ .w = .px(16), .h = .px(16) };
                    }
                }
            }
        }

        cu.endBuild();
        try render(cu.state.ui_root, renderer);

        renderer.present();
    }
}

fn render(atom: *cu.Atom, renderer: *sdl.Renderer) !void {
    try renderer.setDrawColorT(atom.color);
    const rect = sdl.FRect{
        .x = atom.rect.vec.x0,
        .y = atom.rect.vec.y0,
        .w = atom.rect.vec.x1 - atom.rect.vec.x0,
        .h = atom.rect.vec.y1 - atom.rect.vec.y0,
    };
    try renderer.drawRectF(&rect);

    if (atom.flags.draw_text) {
        const text_data = atom.text_data.?;

        // const font_color = sdl.Color{ .r = 255, .g = 255, .b = 255, .a = 255 };
        // const surface = try cu.gs.font.renderTextSolid(text_data.zstring, font_color);
        // defer surface.deinit();

        // const texture = try renderer.createTextureFromSurface(surface);
        // defer texture.deinit();

        const dst_rect = sdl.Rect{
            .x = @intFromFloat(rect.x),
            .y = @intFromFloat(rect.y),
            .w = text_data.size.sz.w,
            .h = text_data.size.sz.h,
        };

        // try renderer.renderCopy(texture, null, &dst_rect);

        try renderer.setDrawColorT(sdl.Color{ .r = 255, .g = 0, .b = 0, .a = 255 });
        try renderer.drawRect(&dst_rect);
    }

    if (atom.children) |children| {
        var maybe_child: ?*cu.Atom = children.first;
        while (maybe_child) |child| : (maybe_child = child.siblings.next) {
            try render(child, renderer);
        }
    }
}
