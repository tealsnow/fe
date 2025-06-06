const log = @import("std").log.scoped(.@"fe.app.titlebar");

pub const wl = @import("../platform/linux/wayland/wayland.zig");

const cu = @import("cu");
const b = cu.builder;

pub fn TitlebarButtons(comptime Context: type) type {
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

pub fn buildTitlebar(
    window: *wl.Window,
    rounding: f32,
    comptime MenuContext: type,
    menu_buttons: TitlebarButtons(MenuContext),
) void {
    const tiling = window.tiling;

    b.stacks.font.pushForMany(.button);
    defer _ = b.stacks.font.pop();

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
            .push(.init(&.{ .clickable, .draw_text }));
        b.stacks.pref_size.push(.size(.text_pad(8), .px(height)));
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
            const menu = b.open("ctx menu");
            defer b.close(menu);

            // b.stacks.pref_size.pushForMany(.square(.text_pad(8)));
            // defer _ = b.stacks.pref_size.pop();

            for (menu_button.items) |menu_item| {
                b.stacks.pref_size.push(.square(.text_pad(8)));
                if (b.button(menu_item.name).clicked()) {
                    menu_item.action(menu_buttons.context);
                    b.ctx_menu.closeMenu();
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
            .push(.init(&.{ .clickable, .draw_border }));
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
