const State = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const log = std.log.scoped(.@"fe.app.State");

const xkb = @import("xkbcommon");
const tracy = @import("tracy");

// @TODO: Migrate to use ghostty/pkg/fontconfig
const fc = @import("../fontconfig.zig");

const wl = @import("../platform/linux/wayland/wayland.zig");
const EventQueueCircleBuffer = wl.EventQueueCircleBuffer;

const WgpuRenderer = @import("../wgpu/WgpuRenderer.zig");
const FontManager = WgpuRenderer.FontManager;

const cu = @import("cu");
const mt = cu.math;
const b = cu.builder;

pub const APP_ID = "me.ketanr.fe";

const PanelWindow = @import("PanelWindow.zig");

//= params

running: bool = true,

action_queue: ActionQueue = .empty,
gpa: Allocator,
arena: Allocator,

window_list: WindowList,
window_rounding: f32,

font_manager: *FontManager,
font_face_map: FontManager.FontFaceMap,

focus_window_keyboard: ?*Window = null,
focus_window_pointer: ?*Window = null,

//= methods

pub fn init(gpa: Allocator, arena: Allocator) !State {
    const window_list = try WindowList.init(gpa);

    //- fonts
    var font_manager = try FontManager.init(gpa);

    const def_font_path = try getFontFromFamilyName(gpa, "sans");
    defer gpa.free(def_font_path);
    const mono_font_path = try getFontFromFamilyName(gpa, "mono");
    defer gpa.free(mono_font_path);

    const dpi = mt.Size(u16).size(
        @intFromFloat(@round(window_list.conn.hdpi)),
        @intFromFloat(@round(window_list.conn.vdpi)),
    );

    const font_face_map = try font_manager.makeFontFaceMap(
        gpa,
        .init(.{
            .body = .{ .path = def_font_path, .pt = 8 },
            .label = .{ .path = def_font_path, .pt = 10 },
            .button = .{ .path = def_font_path, .pt = 10 },
            .mono = .{ .path = mono_font_path, .pt = 10 },
        }),
        dpi,
    );

    return .{
        .gpa = gpa,
        .arena = arena,

        .window_list = window_list,
        .window_rounding = 10,

        .font_manager = font_manager,
        .font_face_map = font_face_map,
    };
}

pub fn deinit(state: *State) void {
    state.font_manager.deinit(state.gpa);
    state.window_list.deinit();
}

pub const NewWindowParams = struct {
    title: [:0]const u8,
    initial_size: mt.Size(u32),
    interface: Window.Interface,
};

pub fn newWindow(state: *State, params: NewWindowParams) !*Window {
    return Window.init(&state.window_list, .{
        .title = params.title,
        .app_id = APP_ID,
        .initial_size = params.initial_size,
        .interface = params.interface,
        .font_manager = state.font_manager,
        .font_face_map = state.font_face_map,
    });
}

pub fn runUpdate(state: *State) !void {
    cu.state = undefined;

    try state.window_list.conn.dispatch();

    while (state.window_list.conn.event_queue.dequeue()) //
    |event| switch (event.kind) {
        .surface_configure => |configure| {
            const win = state.window_list.getWindow(configure.window_id);
            win.wl_window.handleSurfaceConfigureEvent(configure);

            win.present_frame = true;
        },
        .toplevel_configure => |conf| conf: {
            const win = state.window_list.getWindow(conf.window_id);
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
            state.action_queue.queue(.{ .close_window = close.window_id });
        },
        .frame => |frame| frame: {
            const win = state.window_list.maybeGetWindow(frame.window_id) orelse
                break :frame;

            // re-setup a callback, every callback is only valid once
            win.wl_window.setupFrameCallback();

            win.present_frame = true;
        },

        .keyboard_focus => |focus| {
            switch (focus.state) {
                .enter => state.focus_window_keyboard =
                    state.window_list.getWindow(focus.window_id),
                .leave => state.focus_window_keyboard = null,
            }
        },
        .key => |key| key: {
            const win = state.focus_window_keyboard orelse break :key;
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
                xkb.Keysym.Escape => state.action_queue.queue(.quit),

                else => {},
            }
        },
        .modifier => |mods| mods: {
            const win = state.focus_window_keyboard orelse break :mods;
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
        .text => |text| text: {
            const win = state.focus_window_keyboard orelse break :text;
            win.cu_state.pushEvent(.{
                .text = text.slice(),
            });
        },

        .pointer_focus => |focus| {
            switch (focus.state) {
                .enter => state.focus_window_pointer =
                    state.window_list.getWindow(focus.window_id),
                .leave => {
                    if (state.focus_window_pointer) |win|
                        win.cu_state.pushEvent(.{ .mouse_move = .inf });

                    state.focus_window_pointer = null;
                },
            }
        },
        .pointer_motion => |motion| motion: {
            const win = state.focus_window_pointer orelse break :motion;
            win.cu_state.pushEvent(.{
                .mouse_move = motion.point.floatCast(f32),
            });
        },
        .pointer_button => |button| button: {
            const win = state.focus_window_pointer orelse break :button;
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
            const win = state.focus_window_pointer orelse break :scroll;
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

    while (state.action_queue.dequeue()) |action| switch (action) {
        .quit => {
            // skip defers on release
            // on debug it is a noop
            std.process.cleanExit();

            state.running = false;
        },
        .close_window => |id| {
            const window = state.window_list.getWindow(id);
            if (state.focus_window_pointer == window)
                state.focus_window_pointer = null;
            if (state.focus_window_keyboard == window)
                state.focus_window_keyboard = null;

            state.window_list.closeWindow(id);
        },
    };

    {
        const frame_trace = tracy.startDiscontinuousFrame("present");
        defer frame_trace.end();

        for (state.window_list.slice()) |window| {
            if (!window.present_frame) continue;

            const trace_window =
                tracy.beginZone(@src(), .{ .name = "window" });
            defer trace_window.end();
            trace_window.name("window: {s}", .{window.title});
            trace_window.text("{*}", .{window});

            window.present_frame = false;

            window.build();

            if (state.focus_window_pointer == window) {
                const pointer_kind = if (window.cu_state.pointer_kind) |kind|
                    cuPointerKindToWlCursorKind(kind)
                else
                    .default;
                try state.window_list.conn.setCursor(pointer_kind);
            }

            try window.renderer.render(state.arena, state.font_manager);
            window.renderer.surface.present();
        }
    }

    if (state.window_list.slice().len == 0)
        state.action_queue.queue(.quit);
}

//= actions

pub const Action = union(enum) {
    quit,
    close_window: wl.WindowId,
};

pub const ActionQueue = EventQueueCircleBuffer(32, Action);

//= window

pub const WindowList = struct {
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

pub const Window = struct {
    wl_window: *wl.Window,
    title: [:0]const u8,
    renderer: *WgpuRenderer,
    cu_callbacks: *WgpuRenderer.CuCallbacks,
    cu_state: *cu.State,
    interface: Interface,

    present_frame: bool = true,

    pub const Interface = struct {
        context: *anyopaque,
        vtable: *const VTable,

        pub const VTable = struct {
            build: *const fn (*anyopaque, *Window) void,
            close: *const fn (*anyopaque, *Window) void,
        };

        pub fn build(inter: Interface, window: *Window) void {
            inter.vtable.build(inter.context, window);
        }

        pub fn close(inter: Interface, window: *Window) void {
            inter.vtable.close(inter.context, window);
        }
    };

    pub const InitParams = struct {
        title: [:0]const u8,
        app_id: ?[:0]const u8 = null,
        inset: ?u32 = 15,
        initial_size: mt.Size(u32),
        min_size: ?mt.Size(u32) = .square(200),
        interface: Interface,
        font_manager: *const WgpuRenderer.FontManager,
        font_face_map: WgpuRenderer.FontManager.FontFaceMap,
    };

    pub fn init(
        list: *WindowList,
        params: InitParams,
    ) !*Window {
        const wl_window = try wl.Window.init(
            list.gpa,
            list.conn,
            params.initial_size,
        );
        wl_window.setTitle(params.title);
        if (params.app_id) |id| wl_window.setAppId(id);
        wl_window.inset = params.inset;
        wl_window.setMinSize(if (params.min_size) |s| s else .square(0));

        const gpa = list.gpa;
        const conn = list.conn;

        //- renderer

        const renderer = try WgpuRenderer.init(gpa, .{
            .surface_descriptor = //
            WgpuRenderer.wgpu.surfaceDescriptorFromWaylandSurface(.{
                .label = "wayland surface",
                .display = conn.wl_display,
                .surface = wl_window.wl_surface,
            }),
            .initial_surface_size = wl_window.size,
            .font_manager = params.font_manager,
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
            params.font_manager,
            @floatFromInt(conn.cursor_size),
        );

        var font_kind_map = cu.FontKindMap.initUndefined();
        {
            var map = params.font_face_map;
            var iter = map.iterator();
            while (iter.next()) |entry| {
                font_kind_map
                    .set(entry.key, @alignCast(@ptrCast(entry.value.*)));
            }
        }

        const cu_state = try cu.State.init(gpa, .{
            .callbacks = cu_callbacks.callbacks(),
            .font_kind_map = font_kind_map,
        });

        cu_state.default_palette = .init(.{
            .background = .hexRgb(0x1d2021), // gruvbox bg0
            .text = .hexRgb(0xebdbb2), // gruvbox fg1
            .text_weak = .hexRgb(0xbdae93), // gruvbox fg3
            .border = .hexRgb(0x3c3836), // gruvbox bg1
            .hot = .hexRgb(0x665c54), // grovbox bg3
            .active = .hexRgb(0xfbf1c7), // grovbox fg0
        });

        //- return

        wl_window.commit();

        const window = try gpa.create(Window);
        window.* = .{
            .wl_window = wl_window,
            .title = params.title,
            .renderer = renderer,
            .cu_callbacks = cu_callbacks,
            .cu_state = cu_state,
            .interface = params.interface,
        };

        try list.pushWindow(window);

        return window;
    }

    pub fn deinit(window: *Window, gpa: Allocator) void {
        window.interface.close(window);

        window.cu_state.deinit();
        window.cu_callbacks.deinit();
        window.renderer.deinit();
        window.wl_window.deinit(gpa);
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

//= cu pointer kind to wl cursor kind

pub fn cuPointerKindToWlCursorKind(
    pointer_kind: cu.PointerKind,
) wl.CursorKind {
    return switch (pointer_kind) {
        .default => .default,
        .context_menu => .context_menu,
        .help => .help,
        .clickable => .pointer,
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
