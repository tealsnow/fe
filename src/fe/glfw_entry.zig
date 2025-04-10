const builtin = @import("builtin");

const std = @import("std");
const Allocator = std.mem.Allocator;
const log = std.log.scoped(.@"fe[glfw]");
const assert = std.debug.assert;

const glfw = @import("glfw");
const wgpu = @import("wgpu");

const cu = @import("cu");

// const xdg_decoration = @cImport({
//     @cInclude("xdg-decoration-unstable-v1-client-protocol.h");
//     // @cInclude("xdg-decoration-unstable-v1-client-protocol-code.h");
// });

const wp_viewporter = @cImport({
    @cInclude("viewporter-client-protocol.h");
    // @cInclude("viewporter-client-protocol-code.h");
});

pub const Application = struct {
    window: glfw.Window,

    surface: *wgpu.Surface,
    surface_format: wgpu.TextureFormat,
    device: *wgpu.Device,
    queue: *wgpu.Queue,

    pub fn init(gpa: Allocator) !Application {
        //- glfw init
        log.debug("initializing glfw", .{});

        const platform: glfw.PlatformType = switch (builtin.os.tag) {
            .linux => if (glfw.platformSupported(.wayland)) .wayland else .x11,
            .windows => .win32,
            .macos => .cocoa,
            else => .any,
        };

        log.info("hinting glfw to use platform: {}", .{platform});

        _ = glfw.init(.{
            .platform = platform,
        }) or {
            log.err("failed to initialize glfw", .{});
            return error.glfw;
        };
        glfw.setErrorCallback(glfwErrorCallback);

        log.info("glfw is using platform: {}", .{glfw.getPlatform()});

        //- window creation
        log.debug("creating window", .{});

        const init_window_size = cu.Axis2(u32).axis(800, 600);

        const window = glfw.Window.create(
            init_window_size.w,
            init_window_size.h,
            "fe",
            null,
            null,
            .{
                .decorated = true,
                .center_cursor = false,
                .scale_to_monitor = false,
                .resizable = true,
                .client_api = .no_api,
            },
        ) orelse {
            log.err("failed to create glfw window", .{});
            return error.glfw;
        };
        window.setKeyCallback(keyCallback);
        window.setCursorPosCallback(cursorPosCallback);

        // if (glfw.getPlatform() == .wayland) {
        //     const native = glfw.Native(.{ .wayland = true });
        //     _ = native; // autofix

        //     wp_viewporter.wp_viewporter
        // }

        const surface, const surface_format, const device, const queue = blk: {
            const adapter, const surface = adapter_surface: {
                //- instance creation
                log.debug("creating instance", .{});

                const instance_desc = wgpu.InstanceDescriptor{ .next_in_chain = null };
                const instance = wgpu.Instance.create(&instance_desc) orelse {
                    log.err("failed to create wgpu instance", .{});
                    return error.wgpu;
                };
                defer {
                    log.debug("releasing instance", .{});
                    instance.release();
                }

                //- create window surface
                log.debug("creating glfw-window wgpu-surface", .{});
                const surface = createGlfwWindowWgpuSurface(window, instance) orelse {
                    log.err("failed to create glfw-window wgpu-surface", .{});
                    return error.glfw_wgpu;
                };

                //- adapter request
                log.debug("requesting adapter", .{});

                const request_adapter_options = wgpu.RequestAdapterOptions{
                    .next_in_chain = null,
                    .compatible_surface = surface,
                };
                const adapter_response = instance.requestAdapterSync(&request_adapter_options);
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
                for (surface_caps.present_modes[0..surface_caps.present_mode_count]) |present_mode| {
                    log.debug("- {s}", .{@tagName(present_mode)});
                }

                log.debug("Available surface alpha modes:", .{});
                for (surface_caps.alpha_modes[0..surface_caps.alpha_mode_count]) |alpha_mode| {
                    log.debug("- {s}", .{@tagName(alpha_mode)});
                }
            }

            const surface_format = surface_caps.formats[0];
            log.debug("preffered surface format: {s}", .{@tagName(surface_format)});

            configureSurfaceBare(init_window_size, device, surface, surface_format);

            break :blk .{ surface, surface_format, device, queue };
        };

        return .{
            .window = window,
            .surface = surface,
            .surface_format = surface_format,
            .device = device,
            .queue = queue,
        };
    }

    pub fn deinit(app: *Application) void {
        log.debug("app deinit", .{});

        log.debug("unconfiguring surface", .{});
        app.surface.unconfigure();

        log.debug("releasing queue", .{});
        app.queue.release();

        log.debug("releasing surface", .{});
        app.surface.release();

        log.debug("releasing device", .{});
        app.device.release();

        log.debug("destrying window", .{});
        app.window.destroy();

        log.debug("terminating glfw", .{});
        glfw.terminate();
    }

    pub fn runLoop(app: *Application) !void {
        const render_log = std.log.scoped(.@"wgpu renderer");

        glfw.pollEvents();

        {
            //- configure surface
            render_log.debug("configuring surface", .{});

            // @FIXME: Not sure if it is ideal to do this every frame
            app.configureSurface();

            //- next surface texture
            render_log.debug("getting next target surface texture view", .{});

            const target_view = app.getNextSurfaceTextureView() orelse {
                render_log.warn("failed to get next surface texture view", .{});
                return;
            };
            defer {
                render_log.debug("releasing target surface texture view", .{});
                target_view.release();
            }

            const command_buffer = command_buffer: {
                //- command encoder
                render_log.debug("creating command encoder", .{});

                const encoder_desc = wgpu.CommandEncoderDescriptor{
                    .next_in_chain = null,
                    .label = "fe command encoder",
                };
                const encoder = app.device.createCommandEncoder(&encoder_desc) orelse {
                    render_log.err("failed to create command encoder", .{});
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
                                .clear_value = .{ .r = 0.9, .g = 0.1, .b = 0.2, .a = 1.0 },
                                .depth_slice = wgpu.WGPU_DEPTH_SLICE_UNDEFINED,
                            },
                        },
                        .depth_stencil_attachment = null,
                        .timestamp_writes = null,
                    };
                    const render_pass = encoder.beginRenderPass(&render_pass_desc) orelse {
                        render_log.err("failed to begin render pass", .{});
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
                const command_buffer = encoder.finish(&command_buffer_desc) orelse {
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

            app.queue.submit(&.{command_buffer});
        }

        //- presenting surface
        render_log.debug("presenting surface", .{});

        app.surface.present();
    }

    pub fn isRunning(app: *const Application) bool {
        return !app.window.shouldClose();
    }

    fn getNextSurfaceTextureView(app: *const Application) ?*wgpu.TextureView {
        var surface_texture: wgpu.SurfaceTexture = undefined;
        app.surface.getCurrentTexture(&surface_texture);
        // defer surface_texture.texture.release(); // not with wgpu-native

        if (surface_texture.status != .success)
            return null;

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
            // .usage = wgpu.TextureUsage.render_attachment | wgpu.TextureUsage.texture_binding,
        };
        const target_view = surface_texture.texture.createView(&view_desc) orelse return null;

        return target_view;
    }

    fn configureSurface(app: *const Application) void {
        const size = app.window.getSize();
        configureSurfaceBare(.axis(size.width, size.height), app.device, app.surface, app.surface_format);
    }

    fn configureSurfaceBare(
        size: cu.Axis2(u32),
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
            .width = size.w,
            .height = size.h,
            .present_mode = .fifo,
        };
        surface.configure(&surface_config);
    }
};

pub fn entry(gpa: Allocator) !void {
    //- app init
    log.debug("initializing application", .{});

    var app = try Application.init(gpa);
    defer app.deinit();

    //- main loop
    log.debug("starting main loop", .{});

    while (app.isRunning()) {
        try app.runLoop();
    }
}

fn glfwErrorCallback(code: glfw.ErrorCode, description: [:0]const u8) void {
    log.err("glfw error: code: {} -- {s}", .{ code, description });
}

fn keyCallback(window: glfw.Window, key: glfw.Key, scancode: i32, action: glfw.Action, mods: glfw.Mods) void {
    _ = scancode;
    _ = mods;
    if ((key == .escape or key == .q) and action == .press)
        window.setShouldClose(true);
}

fn cursorPosCallback(window: glfw.Window, xpos: f64, ypos: f64) void {
    _ = window;
    _ = xpos;
    _ = ypos;
}

fn inspectAdapter(gpa: Allocator, adapter: *wgpu.Adapter) !void {
    //- limit listing
    log.debug("getting adapter limits", .{});

    var supported_limits = wgpu.SupportedLimits{ .next_in_chain = null, .limits = .{} };
    _ = adapter.getLimits(&supported_limits) or return error.wgpu;
    const limits = supported_limits.limits;

    log.debug("Adapter limits:", .{});
    log.debug("- maxTextureDimension1D: {d}", .{limits.max_texture_dimension_1d});
    log.debug("- maxTextureDimension2D: {d}", .{limits.max_texture_dimension_2d});
    log.debug("- maxTextureDimension3D: {d}", .{limits.max_texture_dimension_3d});
    log.debug("- maxTextureArrayLayers: {d}", .{limits.max_texture_array_layers});

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

    var supported_limits = wgpu.SupportedLimits{ .next_in_chain = null, .limits = .{} };
    if (device.getLimits(&supported_limits) == 0) return error.wgpu;
    const limits = supported_limits.limits;

    log.debug("Device limits:", .{});
    log.debug("- maxTextureDimension1D: {d}", .{limits.max_texture_dimension_1d});
    log.debug("- maxTextureDimension2D: {d}", .{limits.max_texture_dimension_2d});
    log.debug("- maxTextureDimension3D: {d}", .{limits.max_texture_dimension_3d});
    log.debug("- maxTextureArrayLayers: {d}", .{limits.max_texture_array_layers});

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

fn deviceLostCallback(reason: wgpu.DeviceLostReason, message: ?[*:0]const u8, userdata: ?*anyopaque) callconv(.c) void {
    _ = userdata;
    log.err("Device lost reason: {}", .{reason});
    if (message) |str| {
        log.err("message: {s}", .{str});
    }
}

fn queueWorkDoneCallback(status: wgpu.WorkDoneStatus, userdata: ?*anyopaque) callconv(.c) void {
    _ = userdata;
    log.debug("Queue work finished with status: {}", .{status});
}

fn createGlfwWindowWgpuSurface(window: glfw.Window, instance: *wgpu.Instance) ?*wgpu.Surface {
    switch (builtin.os.tag) {
        .windows => {
            const native = glfw.Native(.{
                .win32 = true,
            });
            _ = native;
            @compileError("windowos support is TODO");
        },
        .macos => {
            const native = glfw.Native(.{
                .cocoa = true,
            });
            _ = native;
            @panic("apple cocoa support is TODO");
        },
        .linux => {
            const native = glfw.Native(.{
                .wayland = true,
                .x11 = true,
            });

            switch (glfw.getPlatform()) {
                .wayland => {
                    const wl_display = native.getWaylandDisplay();
                    const wl_surface = native.getWaylandWindow(window);
                    const from_wl_surface = wgpu.SurfaceDescriptorFromWaylandSurface{
                        .display = wl_display,
                        .surface = wl_surface,
                    };

                    const surface_desc = wgpu.SurfaceDescriptor{
                        .next_in_chain = &from_wl_surface.chain,
                        .label = "wayland surface",
                    };
                    return instance.createSurface(&surface_desc);
                },
                .x11 => {
                    const x11_display = native.getX11Display();
                    const x11_window = native.getX11Window(window);
                    const from_xlib_window = wgpu.SurfaceDescriptorFromXlibWindow{
                        .display = x11_display,
                        .window = @intCast(x11_window),
                    };

                    const surface_desc = wgpu.SurfaceDescriptor{
                        .next_in_chain = &from_xlib_window.chain,
                        .label = "x11 surface",
                    };
                    return instance.createSurface(&surface_desc);
                },
                else => unreachable,
            }
        },
        else => @compileError("unsupported platform"),
    }
}
