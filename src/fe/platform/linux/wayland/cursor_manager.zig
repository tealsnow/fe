const std = @import("std");
const Allocator = std.mem.Allocator;
const log = std.log.scoped(.@"wl[CursorManager]");

const wl = @import("wayland").client.wl;
const wp = @import("wayland").client.wp;

const Point = @import("../../../math.zig").Point;
const Size = @import("../../../math.zig").Size;

const Event = @import("events.zig").Event;

pub const CursorManager = union(enum) {
    pointer: PointerManager,
    cursor_shape: CursorShapeManager,

    pub fn initPointerManager(
        gpa: Allocator,
        wl_compositor: *wl.Compositor,
        wl_pointer: *wl.Pointer,
        theme_name: [*:0]const u8,
        theme_size: i32,
        wl_shm: *wl.Shm,
    ) !CursorManager {
        return .{
            .pointer = try .init(
                gpa,
                wl_compositor,
                wl_pointer,
                theme_name,
                theme_size,
                wl_shm,
            ),
        };
    }

    pub fn initCursorShapeManager(
        wl_pointer: *wl.Pointer,
        wp_cursor_shape_manager: *wp.CursorShapeManagerV1,
    ) !CursorManager {
        const device = try wp_cursor_shape_manager.getPointer(wl_pointer);
        return .{
            .cursor_shape = .{
                .wp_cursor_shape_device = device,
            },
        };
    }

    pub fn deinit(manager: CursorManager) void {
        switch (manager) {
            .pointer => |pointer| pointer.deinit(),
            .cursor_shape => {},
        }
    }

    pub fn setCursor(
        manager: CursorManager,
        enter_event_serial: u32,
        kind: CursorKind,
    ) !void {
        switch (manager) {
            .pointer => |*pointer| try pointer.setCursor(enter_event_serial, kind),
            .cursor_shape => |shape| shape.setCursor(enter_event_serial, kind),
        }
    }

    const PointerManager = struct {
        wl_compositor: *wl.Compositor,
        wl_pointer: *wl.Pointer,
        wl_cursor_theme: *wl.CursorTheme,
        cursor_cache: *CursorMap,

        pub fn init(
            gpa: Allocator,
            wl_compositor: *wl.Compositor,
            wl_pointer: *wl.Pointer,
            theme_name: [*:0]const u8,
            theme_size: i32,
            wl_shm: *wl.Shm,
        ) !PointerManager {
            const wl_cursor_theme = try wl.CursorTheme.load(
                theme_name,
                theme_size,
                wl_shm,
            );

            const cache = try gpa.create(CursorMap);
            cache.* = .init(gpa);

            return .{
                .wl_compositor = wl_compositor,
                .wl_pointer = wl_pointer,
                .wl_cursor_theme = wl_cursor_theme,
                .cursor_cache = cache,
            };
        }

        pub fn deinit(manager: PointerManager) void {
            for (manager.cursor_cache.values()) |val| {
                val.surface.destroy();
            }

            manager.wl_cursor_theme.destroy();

            const gpa = manager.cursor_cache.allocator;
            manager.cursor_cache.deinit();
            gpa.destroy(manager.cursor_cache);
        }

        pub fn setCursor(
            manager: PointerManager,
            enter_event_serial: u32,
            kind: CursorKind,
        ) !void {
            const storage = if (manager.cursor_cache.get(kind)) |storage|
                storage
            else blk: {
                const name = switch (kind) {
                    .default => "default",

                    .context_menu => "context-menu",
                    .help => "help",
                    .pointer => "pointer",
                    .progress => "progress",
                    .wait => "wait",
                    .cell => "cell",
                    .crosshair => "crosshair",

                    .text => "text",
                    .text_vertical => "vertical-text",

                    .dnd_alias => "alias",
                    .dnd_copy => "copy",
                    .dnd_move => "move",
                    .dnd_no_drop => "no-drop",
                    .dnd_not_allowed => "not-allowed",
                    .dnd_grab => "grab",
                    .dnd_grabbing => "grabbing",
                    .dnd_ask => return,

                    .resize_e => "e-resize",
                    .resize_n => "n-resize",
                    .resize_ne => "ne-resize",
                    .resize_nw => "nw-resize",
                    .resize_s => "s-resize",
                    .resize_se => "se-resize",
                    .resize_sw => "sw-resize",
                    .resize_w => "w-resize",
                    .resize_ew => "ew-resize",
                    .resize_ns => "ns-resize",
                    .resize_nesw => "nesw-resize",
                    .resize_nwse => "nwse-resize",
                    .resize_col => "col-resize",
                    .resize_row => "row-resize",
                    .resize_all => return,

                    .all_scroll => "all-scroll",

                    .zoom_in => "zoom-in",
                    .zoom_out => "zoom-out",
                };

                const cursor =
                    manager.wl_cursor_theme.getCursor(name) orelse {
                        log.err("failed to get cursor '{s}'", .{name});
                        return;
                    };

                const images = cursor.images[0..cursor.image_count];
                if (images.len > 1)
                    log.warn(
                        "more than one cursor image ({d}): TODO",
                        .{images.len},
                    );

                const image = images[0];

                const buffer = try image.getBuffer();

                const surface = try manager.wl_compositor.createSurface();
                errdefer surface.destroy();

                const storage = CursorStorage{
                    .image = image,
                    .buffer = buffer,
                    .surface = surface,
                };

                try manager.cursor_cache.put(kind, storage);

                break :blk storage;
            };

            storage.surface.attach(storage.buffer, 0, 0);
            storage.surface.commit();
            manager.wl_pointer.setCursor(
                enter_event_serial,
                storage.surface,
                @intCast(storage.image.hotspot_x),
                @intCast(storage.image.hotspot_y),
            );
        }

        const CursorMap = std.AutoArrayHashMap(CursorKind, CursorStorage);

        const CursorStorage = struct {
            image: *wl.CursorImage,
            buffer: *wl.Buffer,
            surface: *wl.Surface,
        };
    };

    const CursorShapeManager = struct {
        wp_cursor_shape_device: *wp.CursorShapeDeviceV1,

        pub fn setCursor(
            manager: CursorShapeManager,
            enter_event_serial: u32,
            kind: CursorKind,
        ) void {
            const shape: wp.CursorShapeDeviceV1.Shape = switch (kind) {
                .default => .default,
                .context_menu => .context_menu,
                .help => .help,
                .pointer => .pointer,
                .progress => .progress,
                .wait => .wait,
                .cell => .cell,
                .crosshair => .crosshair,

                .text => .text,
                .text_vertical => .vertical_text,

                .dnd_alias => .alias,
                .dnd_copy => .copy,
                .dnd_move => .move,
                .dnd_no_drop => .no_drop,
                .dnd_not_allowed => .not_allowed,
                .dnd_grab => .grab,
                .dnd_grabbing => .grabbing,
                // .dnd_ask => .dnd_ask,

                .resize_e => .e_resize,
                .resize_n => .n_resize,
                .resize_ne => .ne_resize,
                .resize_nw => .nw_resize,
                .resize_s => .s_resize,
                .resize_se => .se_resize,
                .resize_sw => .sw_resize,
                .resize_w => .w_resize,
                .resize_ew => .ew_resize,
                .resize_ns => .ns_resize,
                .resize_nesw => .nesw_resize,
                .resize_nwse => .nwse_resize,
                .resize_col => .col_resize,
                .resize_row => .row_resize,
                // .resize_all => .all_resize,

                .all_scroll => .all_scroll,

                .zoom_in => .zoom_in,
                .zoom_out => .zoom_out,

                else => return,
            };

            manager.wp_cursor_shape_device.setShape(enter_event_serial, shape);
        }
    };
};

pub const CursorKind = enum {
    default,
    context_menu,
    help,
    pointer,
    progress,
    wait,
    cell,
    crosshair,

    text,
    text_vertical,

    dnd_alias,
    dnd_copy,
    dnd_move,
    dnd_no_drop,
    dnd_not_allowed,
    dnd_grab,
    dnd_grabbing,
    dnd_ask, // v2

    resize_e,
    resize_n,
    resize_ne,
    resize_nw,
    resize_s,
    resize_se,
    resize_sw,
    resize_w,
    resize_ew,
    resize_ns,
    resize_nesw,
    resize_nwse,
    resize_col,
    resize_row,
    resize_all, // v2

    all_scroll,

    zoom_in,
    zoom_out,
};
