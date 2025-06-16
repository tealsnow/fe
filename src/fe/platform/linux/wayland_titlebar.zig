const log = @import("std").log.scoped(.@"fe.app.titlebar");

const wl = @import("wayland/wayland.zig");
const MenuBar = @import("../MenuBar.zig");

const cu = @import("cu");
const b = cu.builder;

pub fn buildTitlebar(
    window: *wl.Window,
    rounding: f32,
    menu_bar: MenuBar,
) void {
    const tiling = window.tiling;

    b.stacks.font.pushForMany(.button);
    defer _ = b.stacks.font.pop();

    const height = b.em(1.5);

    b.stacks.flags.push(.draw_side_bottom);
    b.stacks.layout_axis.push(.x);
    b.stacks.pref_size.push(.size(.fill, .px_strict(height)));
    const topbar = b.open("###titlebar");
    defer b.close(topbar);

    if (!tiling.isTiled()) {
        b.stacks.pref_size
            .push(.size(.px_strict(rounding), .grow));
        _ = b.spacer();
    }

    for (menu_bar.root) |menu_button| {
        b.stacks.flags
            .push(.init(&.{ .clickable, .draw_text }));
        b.stacks.pref_size.push(.size(.text_pad(8), .px_strict(height)));
        b.stacks.hover_cursor_shape.push(.pointer);
        const item = b.build(menu_button.name);

        const inter = item.interaction();
        if (inter.hovering()) {
            item.flags.insert(.draw_border);
        }

        if (inter.clicked() or (cu.state.ctx_menu_open and inter.hovering())) {
            b.ctx_menu.openMenu(
                item.key,
                item.key,
                .point(0, height),
            );
        }

        if (b.ctx_menu.begin(item.key)) |ctx_menu| {
            defer b.ctx_menu.end(ctx_menu);

            b.stacks.flags.push(.init(&.{ .draw_background, .draw_border }));
            b.stacks.layout_axis.push(.y);
            b.stacks.pref_size.push(.square(.fit));
            const menu = b.open("###ctx menu");
            defer b.close(menu);

            b.stacks.pref_size.pushForMany(.square(.text_pad(8)));
            defer _ = b.stacks.pref_size.pop();

            for (menu_button.items) |menu_item| {
                switch (menu_item) {
                    .button => |btn| {
                        if (b.button(btn.name).clicked()) {
                            btn.action(menu_bar.context);
                            b.ctx_menu.closeMenu();
                        }
                    },
                    .list => {
                        _ = b.button("todo: list");
                    },
                }
            }
        }
    }

    //- spacer
    {
        b.stacks.flags.push(.clickable);
        b.stacks.pref_size.push(.size(.grow, .px_strict(height)));
        const topbar_space = b.build("###spacer");

        const inter = topbar_space.interaction();
        if (inter.doubleClicked())
            window.toggleMaximized();
        if (inter.f.contains(.right_pressed))
            window.showWindowMenu(.point(
                @intFromFloat(cu.state.pointer_pos.x),
                @intFromFloat(cu.state.pointer_pos.y),
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
        b.stacks.flags.push(.init(&.{ .clickable, .draw_border }));
        b.stacks.pref_size.push(.square(.px_strict(height)));
        b.stacks.hover_cursor_shape.push(.pointer);
        const button = b.openf("###top bar button {d}", .{i});
        defer b.close(button);

        const inter = button.interaction();
        if (inter.hovering())
            button.palette.set(.border, .hexRgb(0xFF0000));

        if (inter.clicked()) {
            switch (i) {
                0 => window.minimize(),
                1 => window.toggleMaximized(),
                2 => window.conn.event_queue.queue(.{ .kind = .{
                    .toplevel_close = .{ .window_id = window.id },
                } }),
                else => unreachable,
            }
        }
    }

    if (!tiling.isTiled()) {
        b.stacks.pref_size.push(.size(.px_strict(rounding), .grow));
        _ = b.spacer();
    }
}
