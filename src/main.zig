const std = @import("std");
const assert = std.debug.assert;

const sdl = @import("sdl/sdl.zig");
const fontconfig = @import("fontconfig.zig");

const cu = @import("cu/cu.zig");

const one_frame = false;

// @TODO:
//   @[ ]: migrate to a panicing allocator
//   @[ ]: overflow and cliping
//   @[ ]: better rendering
//     @[x]: text alignment
//     @[x]: backgrounds
//     @[x]: borders
//     @[ ]: clipping -- the way sdl does clipping is not working for us, ignoring this for now
//   @[ ]: tooltips/dropdowns - general popups
//   @[ ]: scrolling
//   @[ ]: floating

pub fn main() !void {
    try sdl.init(sdl.InitFlags.All);
    defer sdl.quit();

    try sdl.ttf.init();
    defer sdl.ttf.quit();

    run() catch |err| {
        const ttf_err = sdl.ttf.getError() orelse "[none]";
        const sdl_err = sdl.getError() orelse "[none]";
        std.log.err("[SDL_TTF]: {s}", .{ttf_err});
        std.log.err("[SDL]: {s}", .{sdl_err});

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

    const default_font, const monospace_font = blk: {
        const default_path = try fontconfig.getFontForFamilyName(alloc, "sans");
        defer alloc.free(default_path);
        std.log.info("default font path: '{s}'", .{default_path});

        const monospace_path = try fontconfig.getFontForFamilyName(alloc, "monospace");
        defer alloc.free(monospace_path);
        std.log.info("monospace font path: '{s}'", .{monospace_path});

        const default = try sdl.ttf.Font.open(default_path, 16);
        std.log.info("default font name: '{s}'", .{try default.faceFamilyName()});

        const monospace = try sdl.ttf.Font.open(monospace_path, 16);
        std.log.info("monospace font name: '{s}'", .{try monospace.faceFamilyName()});

        break :blk .{ default, monospace };
    };
    defer default_font.deinit();
    defer monospace_font.deinit();

    try cu.state.init(alloc, SdlCallbacks.callbacks);
    defer cu.state.deinit();

    cu.state.default_font = cu.state.font_manager.registerFont(@alignCast(@ptrCast(default_font)));
    const monospace_font_id = cu.state.font_manager.registerFont(@alignCast(@ptrCast(monospace_font)));

    // @TODO: base these values on display refresh rate
    const event_timeout_ms = 16 / 2;
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
                    cu.state.pushEvent(.{
                        .kind = .key_press,
                        .key = key.keysym,
                        .state = @enumFromInt(@intFromEnum(key.state)),
                    });

                    if (key.state != .pressed) break :key_blk;

                    switch (key.keysym.scancode) {
                        .escape => {
                            running = false;
                        },
                        else => {},
                    }
                },
                .motion => |motion| {
                    cu.state.pushEvent(.{
                        .kind = .mouse_move,
                        .pos = .vec(@floatFromInt(motion.x), @floatFromInt(motion.y)),
                    });
                },
                .button => |button| {
                    cu.state.pushEvent(.{
                        .kind = .mouse_press,
                        .button = button.button,
                        .button_clicks = button.clicks,
                        .state = @enumFromInt(@intFromEnum(button.state)),
                        .pos = .vec(@floatFromInt(button.x), @floatFromInt(button.y)),
                    });
                },

                .wheel => |wheel| {
                    cu.state.pushEvent(.{
                        .kind = .scroll,
                        .scroll = .vec(wheel.preciseX, wheel.preciseY),
                    });
                },

                .text => |text| {
                    const slice = std.mem.sliceTo(text.text[0..], 0);
                    cu.state.pushEvent(.{
                        .kind = .text_input,
                        .text = slice,
                    });
                },

                .window => |wind| switch (wind.event) {
                    .resized => {
                        cu.state.window_size = .axis(@floatFromInt(wind.data1), @floatFromInt(wind.data2));
                    },

                    else => {},
                },

                else => {},
            }
        }

        // while (update_lag >= ns_per_update) : (update_lag -= ns_per_update) {
        {
            cu.startBuild(window.getID());
            defer cu.endBuild();
            cu.state.ui_root.layout_axis = .y;
            cu.state.ui_root.flags.draw_background = true;

            { // topbar
                const topbar = cu.ui(.{ .draw_side_bottom = true }, "topbar");
                defer topbar.end();
                topbar.layout_axis = .x;
                topbar.pref_size = .{ .w = .full, .h = .px(24) };

                _ = cu.growSpacer();

                for (0..3) |i| {
                    const button = cu.uif(
                        cu.Atom.Flags.clickable.combine(.{
                            .draw_border = true,
                        }),
                        "top bar button {d}",
                        .{i},
                    );
                    defer button.end();
                    button.pref_size = .{ .w = .px(24), .h = .px(24) };

                    const int = button.interation();
                    // button.color =
                    //     cu.Color.hexRgb(if (int.f.hovering) 0xFF0000 else 0xFFFFFF);

                    if (int.f.isClicked()) {
                        std.debug.print("top bar button {d} clicked\n", .{i});
                        switch (i) {
                            0 => {},
                            1 => {},
                            2 => running = false,
                            else => unreachable,
                        }
                    }
                }
            }

            { // main pane
                const main_pane = cu.ui(.{}, "main pain");
                defer main_pane.end();
                main_pane.layout_axis = .x;
                main_pane.pref_size = .{ .w = .grow, .h = .grow };

                { // left pane
                    const pane = cu.ui(.{ .draw_side_right = true }, "left pane");
                    defer pane.end();
                    pane.layout_axis = .y;
                    pane.pref_size = .{ .w = .percent(0.4), .h = .full };

                    {
                        const header = cu.ui(.{ .draw_side_bottom = true }, "left header");
                        defer header.end();
                        header.equipDisplayString();
                        header.pref_size.w = .grow;
                        header.display_string = "Left Header gylp";
                        header.text_align = .right;
                    }

                    {
                        const content = cu.ui(.{}, "left content");
                        defer content.end();
                        content.layout_axis = .y;
                        content.pref_size = .{ .w = .grow, .h = .grow };
                        content.flags.clip = true;

                        const old_def = cu.state.default_font;
                        defer cu.state.default_font = old_def;
                        cu.state.default_font = monospace_font_id;

                        cu.withTextColor(.hexRgb(0xff0000))({
                            _ = cu.labelf("fps: {d}", .{fps});
                            _ = cu.labelf("build count: {d}", .{cu.state.current_build_index});
                            _ = cu.labelf("render count: {d}", .{render_count});
                            _ = cu.labelf("atom build count: {d}", .{cu.state.build_atom_count});
                        });

                        _ = cu.labelf("current atom count: {d}", .{cu.state.atom_map.count()});
                        _ = cu.labelf("event count: {d}", .{cu.state.event_list.len});
                        const active = cu.state.atom_map.get(cu.state.active_atom_key);
                        _ = cu.labelf("active atom: {?}", .{active});
                        const hot = cu.state.atom_map.get(cu.state.hot_atom_key);
                        const hot_lbl = cu.labelf("hot atom: {?}", .{hot});
                        hot_lbl.flags.draw_text_weak = true;
                    }
                }

                { // right pane
                    const pane = cu.ui(.{}, "right pane");
                    defer pane.end();
                    pane.layout_axis = .y;
                    pane.pref_size = .{ .w = .grow, .h = .full };

                    {
                        const header = cu.ui(.{ .draw_side_bottom = true }, "right header");
                        defer header.end();
                        header.equipDisplayString();
                        header.pref_size.w = .grow;
                        header.text_align = .center;
                    }

                    {
                        const content = cu.ui(.{}, "right content");
                        defer content.end();
                        content.layout_axis = .y;
                        content.pref_size = .{ .w = .grow, .h = .grow };
                    }
                }

                { // right bar
                    const bar = cu.ui(.{ .draw_side_left = true }, "right bar");
                    defer bar.end();
                    bar.layout_axis = .y;

                    const icon_size = cu.Atom.PrefSize.px(24);
                    bar.pref_size = .{ .w = icon_size, .h = .grow };

                    {
                        const inner = cu.ui(.{}, "right bar inner");
                        defer inner.end();
                        inner.layout_axis = .y;
                        inner.pref_size = .{ .w = icon_size, .h = .fit };

                        for (0..5) |i| {
                            {
                                const icon = cu.uif(.{ .draw_border = true }, "right bar icon {d}", .{i});
                                defer icon.end();
                                // icon.pref_size = .{ .w = .px(16), .h = .px(16) };
                                icon.pref_size = .square(icon_size);

                                // const inter = icon.interation();
                                // icon.color =
                                //     cu.Color.hexRgb(if (inter.f.hovering) 0xFF0000 else 0xFFFFFF);
                            }

                            {
                                const pad = cu.ui(.{}, "");
                                defer pad.end();
                                pad.pref_size = .{ .w = .px(16), .h = .px(4) };
                            }
                        }
                    }
                }
            }
        }

        // try render(renderer);
        var rend = Renderer{ .sdl_rend = renderer };
        try rend.render();

        fps_count += 1;
        render_count += 1;

        if (current_time.since(prev_fps_calc) >= 1e9) {
            fps = fps_count;
            fps_count = 0;
            prev_fps_calc = current_time;
        }

        if (one_frame and cu.state.current_build_index == 1) running = false;
    }
}

pub const Renderer = struct {
    sdl_rend: *sdl.Renderer,
    bg_color_stack: std.ArrayListUnmanaged(cu.Color) = .empty,

    pub fn setDrawColor(self: *Renderer, color: cu.Color) !void {
        try self.sdl_rend.setDrawColorT(sdlColorFromCuColor(color));
    }

    pub fn fillRect(self: *Renderer, rect: sdl.FRect) !void {
        try self.sdl_rend.fillRectF(&rect);
    }

    pub fn drawRect(self: *Renderer, rect: sdl.FRect) !void {
        try self.sdl_rend.drawRectF(&rect);
    }

    pub fn render(self: *Renderer) !void {
        const color = cu.Color.hexRgb(0x000000);
        try self.bg_color_stack.append(cu.state.alloc_temp, color);
        defer _ = self.bg_color_stack.pop().?;

        try self.setDrawColor(color);
        try self.sdl_rend.clear();

        try self.renderAtom(cu.state.ui_root);

        self.sdl_rend.present();
    }

    pub fn renderAtom(self: *Renderer, atom: *cu.Atom) !void {
        // std.log.debug("rendering: {}", .{atom});

        const rect = sdl.FRect{
            .x = atom.rect.p0.x,
            .y = atom.rect.p0.y,
            .w = atom.rect.p1.x - atom.rect.p0.x,
            .h = atom.rect.p1.y - atom.rect.p0.y,
        };

        // std.log.debug("-- rect: x: {}, y: {}, w: {}, h: {}", .{ rect.x, rect.y, rect.w, rect.h });

        // if (atom.flags.clip) {
        //     if (!std.math.isNan(rect.x) and
        //         !std.math.isNan(rect.y) and
        //         !std.math.isNan(rect.w) and
        //         !std.math.isNan(rect.h))
        //     {
        //         try self.sdl_rend.setClipRect(&.{
        //             .x = @intFromFloat(rect.x),
        //             .y = @intFromFloat(rect.y),
        //             .w = @intFromFloat(rect.w),
        //             .h = @intFromFloat(rect.h),
        //         });
        //     }
        // }
        // defer self.sdl_rend.setClipRect(null) catch @panic("unset clip");

        if (atom.flags.draw_background) {
            try self.bg_color_stack.append(cu.state.alloc_temp, atom.palette.background);

            try self.setDrawColor(atom.palette.background);
            try self.fillRect(rect);
        }
        defer if (atom.flags.draw_background) {
            _ = self.bg_color_stack.pop().?;
        };

        if (atom.flags.draw_border) {
            try self.setDrawColor(atom.palette.border);
            try self.drawRect(rect);
        }

        if (atom.flags.draw_side_top) {
            try self.setDrawColor(atom.palette.border);
            try self.sdl_rend.drawLineF(atom.rect.p0.x, atom.rect.p0.y, atom.rect.p1.x, atom.rect.p0.y);
        }

        if (atom.flags.draw_side_bottom) {
            try self.setDrawColor(atom.palette.border);
            try self.sdl_rend.drawLineF(atom.rect.p0.x, atom.rect.p1.y, atom.rect.p1.x, atom.rect.p1.y);
        }

        if (atom.flags.draw_side_left) {
            try self.setDrawColor(atom.palette.border);
            try self.sdl_rend.drawLineF(atom.rect.p0.x, atom.rect.p0.y, atom.rect.p0.x, atom.rect.p1.y);
        }

        if (atom.flags.draw_side_right) {
            try self.setDrawColor(atom.palette.border);
            try self.sdl_rend.drawLineF(atom.rect.p1.x, atom.rect.p0.y, atom.rect.p1.x, atom.rect.p1.y);
        }

        try self.renderText(rect, atom);

        if (atom.children) |children| {
            var maybe_child: ?*cu.Atom = children.first;
            while (maybe_child) |child| : (maybe_child = child.siblings.next) {
                try self.renderAtom(child);
            }
        }
    }

    pub fn renderText(self: *Renderer, rect: sdl.FRect, atom: *cu.Atom) !void {
        if (!(atom.flags.draw_text or atom.flags.draw_text_weak))
            return;

        const color =
            if (atom.flags.draw_text_weak)
                atom.palette.text_weak
            else if (atom.flags.draw_text)
                atom.palette.text
            else
                unreachable;

        const text_data = atom.text_data.?;
        const fonthandle = cu.state.font_manager.getFont(atom.font);
        const font: *sdl.ttf.Font = @alignCast(@ptrCast(fonthandle));

        // const surface = try font.renderTextBlended(text_data.zstring, sdlColorFromCuColor(color));
        const surface = try font.renderTextLCD(
            text_data.zstring,
            sdlColorFromCuColor(color),
            sdlColorFromCuColor(self.bg_color_stack.getLast()),
        );
        defer surface.deinit();

        const texture = try self.sdl_rend.createTextureFromSurface(surface);
        defer texture.deinit();

        var dst_rect = switch (atom.text_align) {
            .left => sdl.FRect{
                .x = rect.x,
                .y = rect.y,
                .w = text_data.size.w,
                .h = text_data.size.h,
            },
            .center => sdl.FRect{
                .x = @floor(rect.x + (rect.w - text_data.size.w) / 2),
                .y = @floor(rect.y + (rect.h - text_data.size.h) / 2),
                .w = text_data.size.w,
                .h = text_data.size.h,
            },
            .right => sdl.FRect{
                .x = @floor(rect.x + rect.w - text_data.size.w),
                .y = @floor(rect.y + (rect.h - text_data.size.h) / 2),
                .w = text_data.size.w,
                .h = text_data.size.h,
            },
        };
        dst_rect.y += SdlTextHeightPadding / 2;
        dst_rect.h -= SdlTextHeightPadding;

        try self.sdl_rend.renderCopyF(texture, null, &dst_rect);
    }

    fn sdlColorFromCuColor(color: cu.Color) sdl.Color {
        return @bitCast(color);
    }
};

pub const SdlTextHeightPadding = 8;

const SdlCallbacks = struct {
    fn measureText(context: *anyopaque, text: [:0]const u8, _font: cu.FontHandle) cu.Axis2(f32) {
        _ = context;
        const font: *sdl.ttf.Font = @alignCast(@ptrCast(_font));
        const w, const h = font.sizeTextTuple(text) catch @panic("failed to measure text");
        return .axis(@floatFromInt(w), @floatFromInt(h + SdlTextHeightPadding));
    }

    pub const vtable = cu.State.Callbacks.VTable{
        .measureText = &measureText,
    };

    pub const callbacks = cu.State.Callbacks{
        .context = undefined,
        .vtable = vtable,
    };
};
