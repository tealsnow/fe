const std = @import("std");
const assert = std.debug.assert;
const mem = std.mem;
const Allocator = mem.Allocator;

const log = std.log.scoped(.@"fe[wl]");

const xkb = @import("xkbcommon");

const Point = @import("math.zig").Point;
const Size = @import("math.zig").Size;

const wl = @import("platform/linux/wayland/wayland.zig");

const wgpu = @import("wgpu");

const WgpuRenderer = @import("WgpuRenderer.zig");

// renderer log only use for err/warn unless testing
const rlog = std.log.scoped(.@"wgpu render");

// @TODO:
//   @[ ]: setup cu
//
//   @[ ]: pointer gestures
//     https://wayland.app/protocols/pointer-gestures-unstable-v1
//     gonna wait until support has been around for a little longer
//
//   @[ ]: xdg-desktop-portal
//     @[x]: cursor theme and size
//     @[ ]: desktop theme / appearance
//     @[ ]: listen to changes
//
//   @[ ]: window rounding - cu?
//
//   @[ ]: window shadows - cu?
//
//   @[ ]: cu: window border
//
//   @[x]: cursor shape
//     https://wayland.app/protocols/cursor-shape-v1
//
//   @[x]: out of window resizing
//
//   @[x]: wgpu intergration

pub fn entry(gpa: Allocator) !void {
    try run(gpa);

    std.process.cleanExit();
}

fn run(gpa: Allocator) !void {
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

    // -------------------------------------------------------------------------
    // - wgpu

    const wgpu_wl_surface = wgpu.SurfaceDescriptorFromWaylandSurface{
        .display = window.conn.wl_display,
        .surface = window.wl_surface,
    };

    const renderer = try WgpuRenderer.init(
        &wgpu_wl_surface.chain,
        window.size,
        .{
            .adapter = gpa,
            .device = gpa,
            .surface = true,
        },
    );
    defer renderer.deinit();

    // -------------------------------------------------------------------------
    // - main loop

    // var surface = try window.createSurface();
    // defer surface.deinit();

    var pointer_pos = Point(f64){ .x = -1, .y = -1 };
    var pointer_enter_serial: u32 = 0;

    log.info("starting main loop", .{});

    window.commit();

    main_loop: while (true) {
        try conn.dispatch();

        var do_render = false;

        while (conn.event_queue.dequeue()) |event| {
            switch (event.kind) {
                .surface_configure => |configure| {
                    window.handleSurfaceConfigureEvent(configure);
                    do_render = true;
                },

                .toplevel_configure => |conf| {
                    if (window.handleToplevelConfigureEvent(conf)) |size| {
                        renderer.reconfigure(size);
                    }

                    do_render = true;
                },

                .toplevel_close => {
                    log.debug("close request", .{});
                    break :main_loop;
                },

                .frame => {
                    // the compositor has told us this is a good time to render
                    // useful for animations or just rendering every time

                    do_render = true;
                },

                .keyboard_focus => |focus| {
                    log.debug(
                        "keyboard_focus: state: {s}, serial: {d}",
                        .{ @tagName(focus.state), focus.serial },
                    );
                },

                .key => |key| key: {
                    log.debug(
                        "key: state: {s}, scancode: {d}, keysym: {}," ++
                            " codepoint: 0x{x}",
                        .{
                            @tagName(key.state),
                            key.scancode,
                            key.keysym,
                            key.codepoint,
                        },
                    );

                    if (key.state != .pressed) break :key;

                    switch (@intFromEnum(key.keysym)) {
                        xkb.Keysym.q => break :main_loop,

                        xkb.Keysym.w => {
                            std.Thread.sleep(std.time.ns_per_s * 2);
                        },

                        else => {},
                    }
                },

                .modifier => |mods| {
                    log.debug(
                        "mods: shift: {}, caps_lock: {}, ctrl: {}, alt: {}," ++
                            " gui: {}, serial: {d}",
                        .{
                            mods.state.shift,
                            mods.state.caps_lock,
                            mods.state.ctrl,
                            mods.state.alt,
                            mods.state.logo,
                            mods.serial,
                        },
                    );
                },

                .text => |text| {
                    const utf8 = text.sliceZ();
                    log.debug(
                        "text: codepoint: 0x{x}, text: '{s}'",
                        .{
                            text.codepoint,
                            std.fmt.fmtSliceEscapeLower(utf8),
                        },
                    );
                },

                .pointer_focus => |focus| {
                    log.debug(
                        "pointer_focus: state: {s}, serial: {d}",
                        .{ @tagName(focus.state), focus.serial },
                    );

                    switch (focus.state) {
                        .enter => {
                            pointer_enter_serial = focus.serial;
                        },
                        .leave => {},
                    }
                },
                .pointer_motion => |motion| {
                    // log.debug(
                    //     "pointer_motion: {d}x{d}",
                    //     .{ motion.x, motion.y },
                    // );

                    pointer_pos = motion.point;

                    const cursor: wl.CursorKind =
                        if (window.getEdge(pointer_pos)) |edge|
                            switch (edge) {
                                .top_left, .bottom_right => .resize_nwse,
                                .top_right, .bottom_left => .resize_nesw,
                                .left, .right => .resize_ew,
                                .top, .bottom => .resize_ns,
                            }
                        else
                            .default;

                    try conn.cursor_manager.setCursor(
                        pointer_enter_serial,
                        cursor,
                    );
                },
                .pointer_button => |button| button: {
                    log.debug(
                        "pointer_button: state: {s}, button: {s}, serial: {d}",
                        .{
                            @tagName(button.state),
                            @tagName(button.button),
                            button.serial,
                        },
                    );

                    if (button.state != .pressed) break :button;

                    if (button.button == .left) {
                        if (window.getEdge(pointer_pos)) |edge| {
                            window.startResize(button.serial, edge);
                        } else {
                            window.startMove(button.serial);
                        }
                    }
                },
                .pointer_scroll => |scroll| {
                    log.debug(
                        "pointer_scroll: axis: {s}, source: {s}, value: {?d}",
                        .{
                            @tagName(scroll.axis),
                            @tagName(scroll.source),
                            scroll.value,
                        },
                    );
                },
            }
        }

        if (!do_render) continue :main_loop;

        {
            //- get next surface texture
            const target_view = target_view: {
                var surface_texture: wgpu.SurfaceTexture = undefined;
                renderer.surface.getCurrentTexture(&surface_texture);

                if (surface_texture.status != .success)
                    break :target_view null;

                const target_view =
                    surface_texture.texture.createView(&.{
                        .label = "fe texture view",
                        .format = surface_texture.texture.getFormat(),
                        .dimension = .@"2d",
                        .base_mip_level = 0,
                        .mip_level_count = 1,
                        .base_array_layer = 0,
                        .array_layer_count = 1,
                        .aspect = .all,
                    }) orelse
                    break :target_view null;

                break :target_view target_view;
            } orelse {
                rlog.err(
                    "failed to get next surface texture view",
                    .{},
                );
                return;
            };
            defer target_view.release();

            const command_buffer = command_buffer: {
                //- command encoder
                const encoder =
                    renderer.device.createCommandEncoder(&.{
                        .label = "fe command encoder",
                    }) orelse {
                        rlog.err(
                            "failed to create command encoder",
                            .{},
                        );
                        return;
                    };
                defer encoder.release();

                {
                    //- render pass
                    const render_pass =
                        encoder.beginRenderPass(&.{
                            .label = "fe render pass",
                            .color_attachment_count = 1,
                            .color_attachments = &.{
                                .{
                                    .view = target_view,
                                    .resolve_target = null,
                                    .load_op = .clear,
                                    .store_op = .store,
                                    .clear_value = .{
                                        .r = 0.9,
                                        .g = 0.1,
                                        .b = 0.2,
                                        .a = 1.0,
                                    },
                                    .depth_slice = wgpu.WGPU_DEPTH_SLICE_UNDEFINED,
                                },
                            },
                            .depth_stencil_attachment = null,
                            .timestamp_writes = null,
                        }) orelse {
                            rlog.err(
                                "failed to begin render pass",
                                .{},
                            );
                            return;
                        };
                    defer render_pass.release();

                    render_pass.setPipeline(renderer.pipeline);

                    render_pass.draw(3, 1, 0, 0);

                    render_pass.end();
                }

                //- command
                const command_buffer =
                    encoder.finish(&.{ .label = "fe command buffer" }) orelse {
                        rlog.err("failed to finish encoding", .{});
                        return;
                    };

                break :command_buffer command_buffer;
            };
            defer command_buffer.release();

            //- submit command
            renderer.queue.submit(&.{command_buffer});
        }

        //- present surface
        renderer.surface.present();
    }
}
