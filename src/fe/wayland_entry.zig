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
        .{ .width = 200, .height = 200 },
    );
    defer window.deinit(gpa);
    window.inset = 15;

    // -------------------------------------------------------------------------
    // - wgpu

    const surface, const surface_format, const device, const queue = blk: {
        const adapter, const surface = adapter_surface: {
            //- instance creation
            log.debug("creating instance", .{});

            const instance_desc = wgpu.InstanceDescriptor{
                .next_in_chain = null,
            };
            const instance = wgpu.Instance.create(&instance_desc) orelse {
                log.err("failed to create wgpu instance", .{});
                return error.wgpu;
            };
            defer {
                log.debug("releasing instance", .{});
                instance.release();
            }

            //- create window surface
            log.debug("creating wgpu surface", .{});
            const from_wl_surface = wgpu.SurfaceDescriptorFromWaylandSurface{
                .display = conn.wl_display,
                .surface = window.wl_surface,
            };
            const surface_desc = wgpu.SurfaceDescriptor{
                .next_in_chain = &from_wl_surface.chain,
                .label = "wayland surface",
            };
            const surface = instance.createSurface(&surface_desc) orelse {
                log.err("failed to create wgpu surface in wayland", .{});
                return error.wgpu;
            };

            //- adapter request
            log.debug("requesting adapter", .{});

            const request_adapter_options = wgpu.RequestAdapterOptions{
                .next_in_chain = null,
                .compatible_surface = surface,
            };
            const adapter_response =
                instance.requestAdapterSync(&request_adapter_options);
            const adapter = adapter_response.adapter orelse {
                log.err("failed to request wgpu adapter", .{});
                return error.wgpu;
            };

            //- inspect adapter
            log.debug("inspecting adapter", .{});
            try inspectAdapter(gpa, adapter);

            break :adapter_surface .{ adapter, surface };
        };
        defer {
            log.debug("releasing adapter", .{});
            adapter.release();
        }

        //- device request
        log.debug("requesting device", .{});

        const device_desc = wgpu.DeviceDescriptor{
            .next_in_chain = null,
            .label = "fe device",
            .required_feature_count = 0,
            .required_limits = null,
            .default_queue = .{
                .next_in_chain = null,
                .label = "default queue",
            },
            .device_lost_callback = &deviceLostCallback,
        };
        const device_response = adapter.requestDeviceSync(&device_desc);
        const device = device_response.device orelse {
            log.err("failed to request wgpu device", .{});
            return error.wgpu;
        };

        //- inspect device
        log.debug("inspecting device", .{});
        try inspectDevice(gpa, device);

        //- command queue
        log.debug("getting command queue", .{});
        const queue = device.getQueue() orelse {
            log.err("failed to get wgpu queue", .{});
            return error.wgpu;
        };

        //- configure surface
        log.debug("configuring surface", .{});

        var surface_caps: wgpu.SurfaceCapabilities = undefined;
        defer surface_caps.freeMembers();
        surface.getCapabilities(adapter, &surface_caps);
        assert(surface_caps.format_count >= 1);

        {
            //- Inspect surface
            log.debug("inspecting surface", .{});

            log.debug("Available surface texture formats:", .{});
            for (surface_caps.formats[0..surface_caps.format_count]) |format| {
                log.debug("- {s}", .{@tagName(format)});
            }

            log.debug("Available surface present modes:", .{});
            for ( //
                surface_caps.present_modes //
                [0..surface_caps.present_mode_count] //
            ) |present_mode| {
                log.debug("- {s}", .{@tagName(present_mode)});
            }

            log.debug("Available surface alpha modes:", .{});
            for ( //
                surface_caps.alpha_modes[0..surface_caps.alpha_mode_count] //
            ) |alpha_mode| {
                log.debug("- {s}", .{@tagName(alpha_mode)});
            }
        }

        const surface_format = surface_caps.formats[0];
        log.debug("preffered surface format: {s}", .{@tagName(surface_format)});

        configureSurfaceBare(window.size, device, surface, surface_format);

        break :blk .{ surface, surface_format, device, queue };
    };

    defer surface.unconfigure();
    defer queue.release();
    defer device.release();

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
                    window.tiling = conf.state;

                    const new_size_inner = conf.size orelse window.size;
                    const new_size = wl.Window.computeOuterSize(
                        window.inset,
                        new_size_inner,
                        window.tiling,
                    );

                    if (new_size.width != window.size.width or
                        new_size.height != window.size.height)
                    {
                        window.size = new_size;
                        // try surface.reconfigure();
                        configureSurfaceBare(
                            new_size,
                            device,
                            surface,
                            surface_format,
                        );
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

        if (do_render) {
            const render_log = std.log.scoped(.@"wgpu renderer");
            {
                //- next surface texture
                render_log.debug(
                    "getting next target surface texture view",
                    .{},
                );

                const target_view = target_view: {
                    var surface_texture: wgpu.SurfaceTexture = undefined;
                    surface.getCurrentTexture(&surface_texture);
                    // defer surface_texture.texture.release(); // not with wgpu-native

                    if (surface_texture.status != .success)
                        break :target_view null;

                    const view_desc = wgpu.TextureViewDescriptor{
                        .next_in_chain = null,
                        .label = "fe texture view",
                        .format = surface_texture.texture.getFormat(),
                        .dimension = .@"2d",
                        .base_mip_level = 0,
                        .mip_level_count = 1,
                        .base_array_layer = 0,
                        .array_layer_count = 1,
                        .aspect = .all,
                        // .usage = wgpu.TextureUsage.render_attachment |
                        //     wgpu.TextureUsage.texture_binding,
                    };
                    const target_view =
                        surface_texture.texture.createView(&view_desc) orelse
                        break :target_view null;

                    break :target_view target_view;
                } orelse {
                    render_log.warn(
                        "failed to get next surface texture view",
                        .{},
                    );
                    return;
                };
                defer {
                    render_log.debug(
                        "releasing target surface texture view",
                        .{},
                    );
                    target_view.release();
                }

                const command_buffer = command_buffer: {
                    //- command encoder
                    render_log.debug("creating command encoder", .{});

                    const encoder_desc = wgpu.CommandEncoderDescriptor{
                        .next_in_chain = null,
                        .label = "fe command encoder",
                    };
                    const encoder =
                        device.createCommandEncoder(&encoder_desc) orelse {
                            render_log.err(
                                "failed to create command encoder",
                                .{},
                            );
                            return;
                        };
                    defer {
                        render_log.debug("releasing command encoder", .{});
                        encoder.release();
                    }

                    encoder.insertDebugMarker("test debug marker");

                    {
                        //- render pass
                        render_log.debug("creating render pass", .{});

                        const render_pass_desc = wgpu.RenderPassDescriptor{
                            .next_in_chain = null,
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
                                    .depth_slice = //
                                    wgpu.WGPU_DEPTH_SLICE_UNDEFINED,
                                },
                            },
                            .depth_stencil_attachment = null,
                            .timestamp_writes = null,
                        };
                        const render_pass =
                            encoder.beginRenderPass(&render_pass_desc) orelse {
                                render_log.err(
                                    "failed to begin render pass",
                                    .{},
                                );
                                return;
                            };
                        defer {
                            render_log.debug("releasing render pass", .{});
                            render_pass.release();
                        }

                        render_pass.end();
                    }

                    //- command
                    render_log.debug("creating command buffer", .{});

                    const command_buffer_desc = wgpu.CommandBufferDescriptor{
                        .next_in_chain = null,
                        .label = "fe command buffer",
                    };
                    const command_buffer =
                        encoder.finish(&command_buffer_desc) orelse {
                            render_log.err("failed to finish encoding", .{});
                            return;
                        };

                    break :command_buffer command_buffer;
                };
                defer {
                    render_log.debug("releasing command buffer", .{});
                    command_buffer.release();
                }

                //- submit command
                render_log.debug("submitting command", .{});

                queue.submit(&.{command_buffer});
            }

            //- presenting surface
            render_log.debug("presenting surface", .{});

            surface.present();
            // not sure if this is needed
            // theres a good chance that the present call does this already
            window.commit();
        }
    }
}

fn configureSurfaceBare(
    size: Size(u32),
    device: *wgpu.Device,
    surface: *wgpu.Surface,
    format: wgpu.TextureFormat,
) void {
    const surface_config = wgpu.SurfaceConfiguration{
        .next_in_chain = null,
        .device = device,
        .usage = wgpu.TextureUsage.render_attachment,
        .format = format,
        .view_format_count = 0,
        .alpha_mode = .auto,
        .width = size.width,
        .height = size.height,
        .present_mode = .fifo,
    };
    surface.configure(&surface_config);
}

fn inspectAdapter(gpa: Allocator, adapter: *wgpu.Adapter) !void {
    //- limit listing
    log.debug("getting adapter limits", .{});

    var supported_limits = wgpu.SupportedLimits{
        .next_in_chain = null,
        .limits = .{},
    };
    _ = adapter.getLimits(&supported_limits) or return error.wgpu;
    const limits = supported_limits.limits;

    log.debug("Adapter limits:", .{});
    log.debug(
        "- maxTextureDimension1D: {d}",
        .{limits.max_texture_dimension_1d},
    );
    log.debug(
        "- maxTextureDimension2D: {d}",
        .{limits.max_texture_dimension_2d},
    );
    log.debug(
        "- maxTextureDimension3D: {d}",
        .{limits.max_texture_dimension_3d},
    );
    log.debug(
        "- maxTextureArrayLayers: {d}",
        .{limits.max_texture_array_layers},
    );

    //- feature listing
    log.debug("getting adapter features", .{});

    const feature_count = adapter.enumerateFeatures(null);
    log.debug("adapter feature count: {d}", .{feature_count});
    const feature_list = try gpa.alloc(wgpu.FeatureName, feature_count);
    defer gpa.free(feature_list);
    _ = adapter.enumerateFeatures(feature_list.ptr);

    log.debug("Adapter features:", .{});
    for (feature_list) |feature| {
        log.debug("- {s}", .{@tagName(feature)});
    }
}

fn inspectDevice(gpa: Allocator, device: *wgpu.Device) !void {
    //- limits
    log.debug("getting device limits", .{});

    var supported_limits = wgpu.SupportedLimits{
        .next_in_chain = null,
        .limits = .{},
    };
    if (device.getLimits(&supported_limits) == 0) return error.wgpu;
    const limits = supported_limits.limits;

    log.debug("Device limits:", .{});
    log.debug(
        "- maxTextureDimension1D: {d}",
        .{limits.max_texture_dimension_1d},
    );
    log.debug(
        "- maxTextureDimension2D: {d}",
        .{limits.max_texture_dimension_2d},
    );
    log.debug(
        "- maxTextureDimension3D: {d}",
        .{limits.max_texture_dimension_3d},
    );
    log.debug(
        "- maxTextureArrayLayers: {d}",
        .{limits.max_texture_array_layers},
    );

    //- features
    log.debug("getting device features", .{});

    const feature_count = device.enumerateFeatures(null);
    log.debug("device feature count: {d}", .{feature_count});
    const feature_list = try gpa.alloc(wgpu.FeatureName, feature_count);
    defer gpa.free(feature_list);
    _ = device.enumerateFeatures(feature_list.ptr);

    log.debug("Device features:", .{});
    for (feature_list) |feature| {
        log.debug("- {s}", .{@tagName(feature)});
    }
}

fn deviceLostCallback(
    reason: wgpu.DeviceLostReason,
    message: ?[*:0]const u8,
    userdata: ?*anyopaque,
) callconv(.c) void {
    _ = userdata;
    log.err("Device lost reason: {}", .{reason});
    if (message) |str| {
        log.err("message: {s}", .{str});
    }
}

fn queueWorkDoneCallback(
    status: wgpu.WorkDoneStatus,
    userdata: ?*anyopaque,
) callconv(.c) void {
    _ = userdata;
    log.debug("Queue work finished with status: {}", .{status});
}
