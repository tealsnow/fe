const std = @import("std");
const Allocator = std.mem.Allocator;

const wl = @import("wayland/wayland.zig");
const WgpuRenderer = @import("../../wgpu/WgpuRenderer.zig");
const FontManager = WgpuRenderer.FontManager;

const cu = @import("cu");
const b = cu.builder;
const mt = cu.math;

const platform = @import("../platform.zig");

pub const WaylandBackend = struct {
    const log = std.log.scoped(.@"platform.WaylandBackend");

    pub const Window = WaylandWindow;
    pub const WindowId = wl.WindowId;

    gpa: Allocator,

    conn: *wl.Connection,
    window_inset: ?u32 = 15, // @FIXME: make a param
    window_rounding: ?f32 = 15, // @FIXME: make a param

    next_window_id: u32 = 1,
    windows: std.AutoArrayHashMapUnmanaged(wl.WindowId, *WaylandWindow) = .empty,

    font_manager: *FontManager,
    font_face_map: FontManager.FontFaceMap,

    pub fn init(gpa: Allocator) !*WaylandBackend {
        const conn = try wl.Connection.init(gpa);

        const font_manager = try WgpuRenderer.FontManager.init(gpa);
        const def_font_path = try getFontFromFamilyName(gpa, "sans");
        defer gpa.free(def_font_path);
        const mono_font_path = try getFontFromFamilyName(gpa, "mono");
        defer gpa.free(mono_font_path);

        const font_face_map = try font_manager.makeFontFaceMap(
            gpa,
            .init(.{
                .body = .{ .path = def_font_path, .pt = 8 },
                .label = .{ .path = def_font_path, .pt = 10 },
                .button = .{ .path = def_font_path, .pt = 10 },
                .mono = .{ .path = mono_font_path, .pt = 10 },
            }),
            .square(96),
        );

        const plat = try gpa.create(WaylandBackend);
        plat.* = .{
            .gpa = gpa,

            .conn = conn,

            .font_manager = font_manager,
            .font_face_map = font_face_map,
        };
        return plat;
    }

    pub fn deinit(self: *WaylandBackend) void {
        const gpa = self.gpa;

        for (self.windows.values()) |window|
            self.closeWindow(window.wl_window.id);
        self.windows.deinit(gpa);

        self.font_manager.deinit(gpa);
        self.conn.deinit(gpa);

        gpa.destroy(self);
    }

    pub fn createWindow(
        self: *WaylandBackend,
        params: platform.WindowInitParams,
    ) !*WaylandWindow {
        //- window
        const wl_window = try wl.Window.init(
            self.gpa,
            self.conn,
            params.initial_size,
        );
        wl_window.setTitle(params.title);
        if (params.app_id) |id| wl_window.setAppId(id);
        if (params.min_size) |s| wl_window.setMinSize(s);
        wl_window.inset = self.window_inset;

        //- renderer
        const renderer = try WgpuRenderer.init(self.gpa, .{
            .surface_descriptor = //
            WgpuRenderer.wgpu.surfaceDescriptorFromWaylandSurface(.{
                .label = "wayland surface",
                .display = self.conn.wl_display,
                .surface = wl_window.wl_surface,
            }),
            .initial_surface_size = wl_window.size,
            .font_manager = self.font_manager,
            .inspect = .{
                // .instance = gpa,
                // .adapter = gpa,
                // .device = gpa,
                // .surface = true,
            },
        });

        var font_kind_map = cu.FontKindMap.initUndefined();
        {
            var map = self.font_face_map;
            var iter = map.iterator();
            while (iter.next()) |entry| {
                font_kind_map
                    .set(entry.key, @alignCast(@ptrCast(entry.value.*)));
            }
        }

        const cu_callbacks = try WgpuRenderer.CuCallbacks.init(
            renderer,
            self.font_manager,
            @floatFromInt(self.conn.cursor_size),
        );

        //- return

        wl_window.commit();

        const window = try self.gpa.create(WaylandWindow);
        try self.windows.put(self.gpa, wl_window.id, window);
        window.* = .{
            .title = params.title,
            .backend = self,

            .wl_window = wl_window,
            .renderer = renderer,

            .font_kind_map = font_kind_map,
            .cu_callbacks = cu_callbacks,
        };

        return window;
    }

    pub fn closeWindow(self: *WaylandBackend, window_id: WindowId) void {
        const window =
            (self.windows.fetchSwapRemove(window_id) orelse return).value;

        window.cu_callbacks.deinit();
        window.renderer.deinit();
        window.wl_window.deinit(self.gpa);
        self.gpa.destroy(window);
    }

    pub fn getWindow(self: *WaylandBackend, window_id: WindowId) ?*Window {
        return self.windows.get(window_id);
    }

    pub fn getEvents(
        self: *WaylandBackend,
        arena: Allocator,
    ) ![]const platform.BackendEvent {
        try self.conn.dispatch();

        var events = std.ArrayList(platform.BackendEvent).init(arena);

        while (self.conn.event_queue.dequeue()) |event| switch (event.kind) {
            .output_available => {},
            .output_unavailable => {},

            .surface_configure => |configure| conf: {
                const win =
                    self.windows.get(configure.window_id) orelse break :conf;
                win.wl_window.handleSurfaceConfigureEvent(configure);

                // events.append(.{ .window_present = configure.window_id });
            },
            .toplevel_configure => |conf| conf: {
                const win = self.windows.get(conf.window_id) orelse
                    break :conf;
                const size =
                    win.wl_window.handleToplevelConfigureEvent(conf) orelse
                    // null means no resize
                    break :conf;

                win.renderer.reconfigure(size);

                try events.append(.{ .window_resize = .{
                    .window = conf.window_id,
                    .size = size,
                } });

                // events.append(.{ .window_present = conf.window_id });
            },
            .toplevel_close => |close| {
                try events.append(.{ .window_close = close.window_id });
            },

            .toplevel_output_change => {},

            .frame => |frame| frame: {
                const window = self.windows.get(frame.window_id) orelse
                    break :frame;
                window.wl_window.setupFrameCallback();

                try events.append(.{ .window_present = frame.window_id });
            },

            .keyboard_focus => |focus| {
                try events.append(.{ .keyboard_focus = .{
                    .window = focus.window_id,
                    .focused = focus.state == .enter,
                } });
            },

            .key => |key| {
                try events.append(.{ .key = .{
                    .scancode = @intCast(key.scancode),
                    .keycode = .unknown,
                    .mod = .{},
                    .state = if (key.state == .pressed)
                        .pressed
                    else
                        .released,
                } });
            },
            .modifier => |mods| {
                try events.append(.{ .key = .{
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
                try events.append(.{ .text = text.sliceZ() });
            },

            .pointer_focus => |focus| {
                try events.append(.{ .pointer_focus = .{
                    .window = focus.window_id,
                    .focused = focus.state == .enter,
                } });
            },
            .pointer_motion => |motion| {
                try events.append(.{
                    .pointer_move = motion.point.floatCast(f32),
                });
            },
            .pointer_button => |button| {
                try events.append(.{ .pointer_button = .{
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
                const value = scroll.value orelse break :scroll;
                try events.append(.{
                    .pointer_scroll = if (scroll.axis == .vertical)
                        .point(0, @floatCast(value))
                    else
                        .point(@floatCast(value), 0),
                });
            },

            .pointer_gesture_swipe => |swipe| switch (swipe) {
                .begin => |begin| _ = begin,
                .update => |update| _ = update,
                .end => |end| _ = end,
            },
            .pointer_gesture_pinch => |pinch| switch (pinch) {
                .begin => |begin| _ = begin,
                .update => |update| _ = update,
                .end => |end| _ = end,
            },
            .pointer_gesture_hold => |hold| switch (hold) {
                .begin => |begin| _ = begin,
                .end => |end| _ = end,
            },
        };

        return events.items;
    }
};

pub const WaylandWindow = struct {
    const WindowInsetWrapper = @import("WindowInsetWrapper.zig");
    const titlebar = @import("wayland_titlebar.zig");

    title: [:0]const u8,
    backend: *WaylandBackend,

    wl_window: *wl.Window,
    renderer: *WgpuRenderer,

    font_kind_map: cu.FontKindMap,
    cu_callbacks: *WgpuRenderer.CuCallbacks,

    window_inset: ?WindowInsetWrapper = null,

    pub fn getId(self: *WaylandWindow) WaylandBackend.WindowId {
        return self.wl_window.id;
    }

    pub fn getTitle(self: *WaylandWindow) [:0]const u8 {
        return self.title;
    }

    pub fn callbacks(self: *WaylandWindow) cu.State.Callbacks {
        return self.cu_callbacks.callbacks();
    }

    pub fn startBuild(self: *WaylandWindow, menu_bar: platform.MenuBar) void {
        cu.state.ui_root.layout_axis = .y;
        cu.state.ui_root.flags.insert(.draw_background);
        cu.state.ui_root.palette.set(.background, .hexRgba(0xffffff00));

        const tiling = self.wl_window.tiling;
        b.stacks.flags.push(flags: {
            var flags = cu.AtomFlags.draw_background;

            if (!tiling.isTiled()) {
                flags.insert(.draw_border);
                if (self.backend.window_rounding) |rounding|
                    b.stacks.corner_radius.push(rounding);
            } else {
                flags.setPresent(.draw_side_top, !tiling.tiled_top);
                flags.setPresent(.draw_side_bottom, !tiling.tiled_bottom);
                flags.setPresent(.draw_side_left, !tiling.tiled_left);
                flags.setPresent(.draw_side_right, !tiling.tiled_right);
            }

            break :flags flags;
        });
        b.stacks.layout_axis.push(.y);
        const window_inset = WindowInsetWrapper.begin(self.wl_window);

        titlebar.buildTitlebar(
            self.wl_window,
            self.backend.window_rounding orelse 0,
            menu_bar,
        );

        std.debug.assert(self.window_inset == null);
        self.window_inset = window_inset;
    }

    pub fn endBuild(self: *WaylandWindow) void {
        self.window_inset.?.end();
        self.window_inset = null;
    }

    pub fn present(
        self: *WaylandWindow,
        arena: Allocator,
        cu_state: *cu.State,
    ) !void {
        if (cu_state.cursor_shape) |shape| {
            self.backend.conn
                .setCursor(cuCursorShapeToWlCursorKind(shape)) catch {};
        }

        try self.renderer.render(arena, cu_state);
        self.renderer.surface.present();
    }
};

//= get font helper

fn getFontFromFamilyName(
    gpa: Allocator,
    font_family: [:0]const u8,
) ![:0]const u8 {
    const fc = @import("../../misc/fontconfig.zig");
    try fc.init();
    defer fc.deinit();

    const pattern = try fc.Pattern.create();
    defer pattern.destroy();
    try pattern.addString(.family, font_family);
    try pattern.addBool(.outline, .true);

    const config = try fc.Config.getCurrent();
    try config.substitute(pattern, .pattern);
    fc.defaultSubstitute(pattern);

    const match = try fc.fontMatch(config, pattern);
    defer match.destroy();

    const path = try match.getString(.file, 0);
    return try gpa.dupeZ(u8, path);
}

//= cu pointer kind to wl cursor kind

pub fn cuCursorShapeToWlCursorKind(
    cursor_shape: cu.CursorShape,
) wl.CursorKind {
    return switch (cursor_shape) {
        .default => .default,
        .context_menu => .context_menu,
        .help => .help,
        .pointer => .pointer,
        .progress => .progress,
        .wait => .wait,
        .cell => .cell,
        .crosshair => .crosshair,

        .text => .text,

        .dnd_alias => .dnd_alias,
        .dnd_copy => .dnd_copy,
        .dnd_move => .dnd_move,
        .dnd_no_drop => .dnd_no_drop,
        .dnd_not_allowed => .dnd_not_allowed,
        .dnd_grab => .dnd_grab,
        .dnd_grabbing => .dnd_grabbing,

        .resize_e => .resize_e,
        .resize_n => .resize_n,
        .resize_ne => .resize_ne,
        .resize_nw => .resize_nw,
        .resize_s => .resize_s,
        .resize_se => .resize_se,
        .resize_sw => .resize_sw,
        .resize_w => .resize_w,
        .resize_ew => .resize_ew,
        .resize_ns => .resize_ns,
        .resize_nesw => .resize_nesw,
        .resize_nwse => .resize_nwse,
        .resize_col => .resize_col,
        .resize_row => .resize_row,

        .zoom_in => .zoom_in,
        .zoom_out => .zoom_out,
    };
}
