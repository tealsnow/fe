const std = @import("std");

const sdl = @import("sdl/sdl.zig");
const fontconfig = @import("fontconfig.zig");

const ui = @import("ui/ui.zig");

const alloca = @import("alloca.zig");

pub fn main() !void {
    // try alloca.chainingAllocatorTest();
    // if (true) std.process.exit(0);

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    // gpa.backing_allocator = std.heap.c_allocator;
    // defer {
    //     const result = gpa.deinit();
    //     if (result == .leak) {
    //         std.debug.print("Memory leak detected\n", .{});
    //     }
    // }
    const alloc = gpa.allocator();

    try sdl.init(sdl.InitFlags.All);
    // defer sdl.quit();

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
    // defer renderer.deinit();

    try fontconfig.init();
    defer fontconfig.deinit();

    const font_path = try fontconfig.getFontForFamilyName(alloc, "sans");
    defer alloc.free(font_path);

    std.log.info("font_path: '{s}'", .{font_path});

    const font = try sdl.ttf.Font.open(font_path, 24);
    defer font.deinit();

    const font_color = sdl.Color{ .r = 255, .g = 255, .b = 255, .a = 255 };
    const surface = try font.renderTextSolid("Hello, World!", font_color);
    defer surface.deinit();

    const texture = try renderer.createTextureFromSurface(surface);
    defer texture.deinit();

    var tex_w: c_int = 0;
    var tex_h: c_int = 0;
    try texture.query(null, null, &tex_w, &tex_h);
    const dst_rect = sdl.Rect{ .x = 0, .y = 0, .w = tex_w, .h = tex_h };

    // ui.gs = try ui.GlobalState.init(alloc, renderer, font);
    // defer ui.gs.deinit();

    var temp_alloc = std.heap.ArenaAllocator.init(alloc);
    defer temp_alloc.deinit();

    var widget_pool =
        try ui.GlobalState.WidgetPool
        .initPreheated(alloc, ui.GlobalState.MaxWidgets);
    defer widget_pool.deinit();

    ui.gs = .{
        .renderer = renderer,
        .font = font,

        .alloc_temp = temp_alloc.allocator(),
        // .widget_alloc = alloc,
        .alloc_persistent = alloc,

        .widget_pool = widget_pool,
    };
    // defer ui.gs.deinit();

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

        try renderer.setDrawColor(18, 18, 18, 255);
        try renderer.clear();

        try renderer.renderCopy(texture, null, &dst_rect);

        ui.start(window);

        ui.ui("my_root")(.{
            .layout_axis = .x,
            .size = .{ .sz = .{
                .w = ui.Size.grow,
                .h = ui.Size.grow,
            } },
        })({
            ui.ui("left pane")(.{
                .layout_axis = .y,
                .size = .{ .sz = .{
                    .w = ui.Size.percent(0.3),
                    .h = ui.Size.percent(1.0),
                } },
            })({
                //
            });

            ui.ui("right pane")(.{
                .layout_axis = .y,
                .size = .{ .sz = .{
                    .w = ui.Size.grow,
                    .h = ui.Size.percent(1),
                } },
            })({
                //
            });
        });

        // if (ui.open("my_root", .{
        //     .layout_axis = .x,
        //     .size = .{ .sz = .{
        //         .w = ui.Size.px(@floatFromInt(window_size.w)),
        //         .h = ui.Size.px(@floatFromInt(window_size.h)),
        //     } },
        // })) |my_root| {
        //     defer my_root.close();

        //     if (ui.open("left pane", .{
        //         .layout_axis = .y,
        //         .size = .{ .sz = .{
        //             .w = ui.Size.percent(0.3),
        //             .h = ui.Size.percent(1.0),
        //         } },
        //     })) |left_pane| {
        //         defer left_pane.close();

        //         if (ui.open("left header", .{
        //             .size = .{ .sz = .{
        //                 .w = ui.Size.grow,
        //                 .h = ui.Size.text,
        //             } },
        //         })) |left_header| {
        //             defer left_header.close();
        //         }

        //         if (ui.open("left content", .{
        //             .size = .{ .sz = .{
        //                 .w = ui.Size.grow,
        //                 .h = ui.Size.grow,
        //             } },
        //         })) |left_content| {
        //             defer left_content.close();
        //         }
        //     }

        //     if (ui.open("right pane", .{
        //         .layout_axis = .y,
        //         .size = .{ .sz = .{
        //             .w = ui.Size.grow,
        //             .h = ui.Size.percent(1),
        //         } },
        //     })) |right_pane| {
        //         defer right_pane.close();

        //         if (ui.open("right header", .{
        //             .size = .{ .sz = .{
        //                 .w = ui.Size.grow,
        //                 .h = ui.Size.text,
        //             } },
        //         })) |right_header| {
        //             defer right_header.close();
        //         }

        //         if (ui.open("right content", .{
        //             .size = .{ .sz = .{
        //                 .w = ui.Size.grow,
        //                 .h = ui.Size.grow,
        //             } },
        //         })) |right_content| {
        //             defer right_content.close();
        //         }
        //     }

        //     if (ui.open("right bar", .{
        //         .layout_axis = .y,
        //         .size = .{ .sz = .{
        //             .w = ui.Size.px(16),
        //             .h = ui.Size.grow,
        //         } },
        //     })) |right_bar| {
        //         defer right_bar.close();

        //         if (ui.open("right bar inner", .{
        //             .layout_axis = .y,
        //             .size = .{ .sz = .{
        //                 .w = ui.Size.percent(1),
        //                 .h = ui.Size.sum,
        //             } },
        //         })) |right_bar_inner| {
        //             defer right_bar_inner.close();

        //             if (ui.open("right bar icon 1", .{
        //                 .size = .{ .sz = .{
        //                     .w = ui.Size.px(16),
        //                     .h = ui.Size.px(16),
        //                 } },
        //             })) |icon_1| {
        //                 defer icon_1.close();
        //             }

        //             if (ui.open("right bar icon 2", .{
        //                 .size = .{ .sz = .{
        //                     .w = ui.Size.px(16),
        //                     .h = ui.Size.px(16),
        //                 } },
        //             })) |icon_2| {
        //                 defer icon_2.close();
        //             }
        //         }
        //     }
        // }

        const root = try ui.end();
        try render(root, renderer);

        renderer.present();

        _ = temp_alloc.reset(.retain_capacity);
        // _ = ui.gs.widget_pool.reset(.retain_capacity);

        // if (ui.gs.current_frame_index > 10) {
        //     running = false;
        // }
        // std.debug.print("frame_index: {d}\n", .{ui.gs.current_frame_index});
    }
}

fn render(root: *ui.Widget, renderer: *sdl.Renderer) !void {
    try renderer.setDrawColorT(root.color);
    try renderer.drawRectF(&.{
        .x = root.rect.vec.x0,
        .y = root.rect.vec.y0,
        .w = root.rect.vec.x1 - root.rect.vec.x0,
        .h = root.rect.vec.y1 - root.rect.vec.y0,
    });

    if (root.children) |children| {
        var maybe_child: ?*ui.Widget = children.first;
        while (maybe_child) |child| : (maybe_child = child.siblings.next) {
            try render(child, renderer);
        }
    }
}
