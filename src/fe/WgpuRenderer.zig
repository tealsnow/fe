const Renderer = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

const log = std.log.scoped(.@"wgpu renderer");

const wgpu = @import("wgpu");

const pretty = @import("pretty");

const mt = @import("math.zig");
const Size = mt.Size;

const tri_shader_code = @embedFile("triangle.wgsl");
const rect_shader_code = @embedFile("rect.wgsl");

surface: *wgpu.Surface,
surface_format: wgpu.TextureFormat,
device: *wgpu.Device,
queue: *wgpu.Queue,

bind_group_layout: *wgpu.BindGroupLayout,
pipeline_layout: *wgpu.PipelineLayout,
pipeline: *wgpu.RenderPipeline,

shader_globals: ShaderGlobals,
shader_globals_buffer: *wgpu.Buffer,
shader_globals_bind_group: *wgpu.BindGroup,

rect_buffer_data_len: u32,
rect_buffer: *wgpu.Buffer,

pub const InspectOptions = struct {
    adapter: ?Allocator = null,
    device: ?Allocator = null,
    surface: bool = false,
};

pub fn init(
    surface_descriptor_chain: *const wgpu.ChainedStruct,
    initial_size: Size(u32),
    inspect: InspectOptions,
) !Renderer {
    const adapter, const surface =
        try createAdapaterAndSurface(surface_descriptor_chain);
    defer {
        log.debug("releasing adapter", .{});
        adapter.release();
    }

    //- inspect adapter
    if (inspect.adapter) |alloc| {
        log.debug("inspecting adapter", .{});
        try inspectAdapter(alloc, adapter);
    }

    //- request device
    log.debug("requesting device", .{});

    const required_limits = getRequiredLimits(adapter);

    const device_response = adapter.requestDeviceSync(&.{
        .label = "fe device",
        .required_feature_count = 0,
        .required_limits = &required_limits,
        .default_queue = .{ .label = "default queue" },
        .device_lost_callback = &deviceLostCallback,
    });
    const device = device_response.device orelse {
        log.err("failed to request device", .{});
        return error.wgpu;
    };

    //- inspect device
    if (inspect.device) |alloc| {
        log.debug("inspecting device", .{});
        try inspectDevice(alloc, device);
    }

    //- command queue
    log.debug("getting command queue", .{});
    const queue = device.getQueue() orelse {
        log.err("failed to get queue", .{});
        return error.wgpu;
    };

    //- configure surface
    log.debug("configuring surface", .{});

    var surface_caps: wgpu.SurfaceCapabilities = undefined;
    defer surface_caps.freeMembers();
    surface.getCapabilities(adapter, &surface_caps);
    assert(surface_caps.format_count >= 1);

    if (inspect.surface) {
        inspectSurface(surface_caps);
    }

    const surface_format = surface_caps.formats[0];
    log.debug("preffered surface format: {s}", .{@tagName(surface_format)});

    configureSurfaceBare(initial_size, device, surface, surface_format);

    //- create pipline
    log.debug("creating render pipeline", .{});

    const bind_group_layout, const pipeline_layout, const pipeline =
        try createPipeline(device, surface_format);

    //- setup shader globals

    const shader_globals = ShaderGlobals{
        .res = initial_size.floatFromInt(f32),
        .color = .hexRgb(0xff0000),
    };

    const shader_globals_buffer = device.createBuffer(&.{
        .size = @sizeOf(ShaderGlobals),
        .usage = wgpu.BufferUsage.copy_dst | wgpu.BufferUsage.uniform,
        .mapped_at_creation = @intFromBool(false),
    }) orelse {
        log.err("failed to create uniform buffer", .{});
        return error.wgpu;
    };

    queue.writeBuffer(
        shader_globals_buffer,
        0,
        &shader_globals,
        shader_globals_buffer.getSize(),
    );

    // queue.writeBuffer(
    //     shader_globals_buffer,
    //     @offsetOf(ShaderGlobals, "color"),
    //     &shader_globals.color,
    //     @sizeOf(mt.RgbaF32),
    // );

    // queue.writeBuffer(
    //     shader_globals_buffer,
    //     @offsetOf(ShaderGlobals, "res"),
    //     &shader_globals.res,
    //     @sizeOf(Size(f32)),
    // );

    const binding = wgpu.BindGroupEntry{
        .binding = 0,
        .buffer = shader_globals_buffer,
        .offset = 0,
        .size = @sizeOf(ShaderGlobals),
    };

    const shader_globals_bind_group = device.createBindGroup(&.{
        .label = "fe bind group",
        .layout = bind_group_layout,
        .entry_count = 1,
        .entries = &.{binding},
    }) orelse {
        log.err("failed to create bind group", .{});
        return error.wgpu;
    };

    // -------------------------------------------------------------------------

    //- vertex/index buffers

    // const vertex_buffer_data = [_]WgpuRenderer.Vertex2D{
    //     .vert(.point(-0.5, -0.5), .hexRgb(0xff0000)),
    //     .vert(.point(0.5, -0.5), .hexRgb(0x00ff00)),
    //     .vert(.point(0.5, 0.5), .hexRgb(0x0000ff)),
    //     .vert(.point(-0.5, 0.5), .hexRgba(0xffff00)),
    // };

    // const index_buffer_data = [_]u16{
    //     0, 1, 2, //
    //     0, 2, 3,
    // };

    // const vertex_buffer = renderer.device.createBuffer(&.{
    //     .size = vertex_buffer_data.len * @sizeOf(WgpuRenderer.Vertex2D),
    //     .usage = wgpu.BufferUsage.copy_dst | wgpu.BufferUsage.vertex,
    //     .mapped_at_creation = @intFromBool(false),
    // }) orelse {
    //     log.err("failed to create vertex buffer", .{});
    //     return error.wgpu;
    // };
    // defer vertex_buffer.release();

    // const index_buffer = renderer.device.createBuffer(&.{
    //     .size = index_buffer_data.len * @sizeOf(u16),
    //     .usage = wgpu.BufferUsage.copy_dst | wgpu.BufferUsage.index,
    //     .mapped_at_creation = @intFromBool(false),
    // }) orelse {
    //     log.err("failed to create index buffer", .{});
    //     return error.wgpu;
    // };
    // defer index_buffer.release();

    // renderer.queue.writeBuffer(
    //     vertex_buffer,
    //     0,
    //     &vertex_buffer_data,
    //     vertex_buffer.getSize(),
    // );
    // renderer.queue.writeBuffer(
    //     index_buffer,
    //     0,
    //     &index_buffer_data,
    //     index_buffer.getSize(),
    // );

    //- rect test

    const rect_buffer_data = [_]GpuRect{
        .gpuRect(.rect(.point(40, 40), .point(100, 100)), .hexRgb(0xff0000)),
        // .gpuRect(.rect(.point(-0.5, -0.5), .point(0.5, 0.5)), .hexRgb(0xff0000)),
    };

    const rect_buffer = device.createBuffer(&.{
        .size = rect_buffer_data.len * @sizeOf(GpuRect),
        .usage = wgpu.BufferUsage.copy_dst | wgpu.BufferUsage.vertex,
        .mapped_at_creation = @intFromBool(false),
    }) orelse {
        log.err("failed to create rect buffer", .{});
        return error.wgpu;
    };

    queue.writeBuffer(
        rect_buffer,
        0,
        &rect_buffer_data,
        rect_buffer.getSize(),
    );

    // -------------------------------------------------------------------------

    return .{
        .surface = surface,
        .surface_format = surface_format,
        .device = device,
        .queue = queue,

        .bind_group_layout = bind_group_layout,
        .pipeline_layout = pipeline_layout,
        .pipeline = pipeline,

        .shader_globals = shader_globals,
        .shader_globals_buffer = shader_globals_buffer,
        .shader_globals_bind_group = shader_globals_bind_group,

        .rect_buffer_data_len = rect_buffer_data.len,
        .rect_buffer = rect_buffer,
    };
}

pub fn deinit(renderer: Renderer) void {
    defer renderer.surface.unconfigure();
    defer renderer.queue.release();
    defer renderer.device.release();
    defer renderer.bind_group_layout.release();
    defer renderer.pipeline_layout.release();
    defer renderer.pipeline.release();
    defer renderer.shader_globals_buffer.release();
    defer renderer.shader_globals_bind_group.release();
    defer renderer.rect_buffer.release();
}

fn createAdapaterAndSurface(
    surface_descriptor_chain: *const wgpu.ChainedStruct,
) !struct { *wgpu.Adapter, *wgpu.Surface } {
    //- instance creation
    log.debug("creating instance", .{});

    const instance = wgpu.Instance.create(&.{}) orelse {
        log.err("failed to create wgpu instance", .{});
        return error.wgpu;
    };
    defer {
        log.debug("releasing instance", .{});
        instance.release();
    }

    //- create surface
    log.debug("creating surface", .{});

    const surface = instance.createSurface(&.{
        .next_in_chain = surface_descriptor_chain,
        .label = "fe surface",
    }) orelse {
        log.err("failed to create wgpu surface", .{});
        return error.wgpu;
    };

    //- adapter request
    log.debug("requesting adapter", .{});

    const adapter_response =
        instance.requestAdapterSync(&.{ .compatible_surface = surface });

    const adapter = adapter_response.adapter orelse {
        log.err(
            "failed to request wgpu adapter: status: {s}: {?s}",
            .{ @tagName(adapter_response.status), adapter_response.message },
        );
        return error.wgpu;
    };

    return .{ adapter, surface };
}

fn getRequiredLimits(adapter: *wgpu.Adapter) wgpu.RequiredLimits {
    _ = adapter;
    // const supported_limits: wgpu.SupportedLimits = undefined;
    // if (!adapter.getLimits(&supported_limits)) return error.wgpu;

    return wgpu.RequiredLimits{
        .limits = .{
            // .max_vertex_attributes = 2,
            // .max_vertex_buffers = 1,
            // .max_buffer_size = 4 * @sizeOf(Vertex2D),
            // .max_vertex_buffer_array_stride = @sizeOf(Vertex2D),
            // .max_inter_stage_shader_components = 4,

            // .max_bind_groups = 1,
            // .max_uniform_buffers_per_shader_stage = 1,
            // .max_uniform_buffer_binding_size = @sizeOf(ShaderGlobals),
        },
    };
}

fn createPipeline(
    device: *wgpu.Device,
    surface_format: wgpu.TextureFormat,
) !struct {
    *wgpu.BindGroupLayout,
    *wgpu.PipelineLayout,
    *wgpu.RenderPipeline,
} {
    //- create shader module
    log.debug("compiling shader module", .{});

    const shader_code_desc = wgpu.ShaderModuleWGSLDescriptor{
        .code = rect_shader_code,
    };
    const shader_module =
        device.createShaderModule(&.{
            .label = "fe shader",
            .next_in_chain = &shader_code_desc.chain,
        }) orelse {
            log.err("failed to create shader module", .{});
            return error.wgpu;
        };

    //- uniform binding
    const binding_layout = wgpu.BindGroupLayoutEntry{
        .binding = 0,
        .visibility = wgpu.ShaderStage.vertex | wgpu.ShaderStage.fragment,
        .buffer = .{
            .type = .uniform,
            .min_binding_size = @sizeOf(ShaderGlobals),
        },

        .sampler = .{},
        .texture = .{},
        .storage_texture = .{},
    };

    //- bind group
    const bind_group_layout = device.createBindGroupLayout(&.{
        .label = "fe bind group layout",
        .entry_count = 1,
        .entries = &.{binding_layout},
    }) orelse {
        log.err("failed to create bind group layout", .{});
        return error.wgpu;
    };

    //- vertex buffer
    const vertex_buffer_layout = wgpu.VertexBufferLayout{
        // .attribute_count = Vertex2D.attributes.len,
        // .attributes = &Vertex2D.attributes,
        // .array_stride = @sizeOf(Vertex2D),
        // .step_mode = .vertex,

        .attribute_count = GpuRect.attributes.len,
        .attributes = &GpuRect.attributes,
        .array_stride = @sizeOf(GpuRect),
        .step_mode = .vertex,
        // .step_mode = .instance,
    };

    //- fragment state
    const blend_state = wgpu.BlendState{
        .color = .{
            .src_factor = .src_alpha,
            .dst_factor = .one_minus_src_alpha,
            .operation = .add,
        },
        .alpha = .{
            .src_factor = .zero,
            .dst_factor = .one,
            .operation = .add,
        },
    };

    const color_target_state = wgpu.ColorTargetState{
        .format = surface_format,
        .blend = &blend_state,
        .write_mask = wgpu.ColorWriteMask.all,
    };

    const fragment_state = wgpu.FragmentState{
        .module = shader_module,
        .entry_point = "fsMain",
        .target_count = 1,
        .targets = &.{color_target_state},
    };

    //- pipeline layout
    const pipeline_layout = device.createPipelineLayout(&.{
        .label = "fe pipeline layout",
        .bind_group_layout_count = 1,
        .bind_group_layouts = &.{bind_group_layout},
    }) orelse {
        log.err("failed to create pipeline layout", .{});
        return error.wgpu;
    };

    //- pipeline desc
    const pipline_desc = wgpu.RenderPipelineDescriptor{
        .label = "fe pipeline",
        .vertex = .{
            .module = shader_module,
            .entry_point = "vsMain",

            .buffer_count = 1,
            .buffers = &.{vertex_buffer_layout},
        },
        .primitive = .{
            // .topology = .triangle_list,
            .topology = .triangle_strip,
            .strip_index_format = .undefined, // sequential
            .front_face = .cw, // counter-clockwise
            .cull_mode = .none,
        },
        .fragment = &fragment_state,
        .depth_stencil = null,
        .multisample = .{
            .count = 1,
            .mask = 0xffffffff,
        },
        .layout = pipeline_layout,
    };

    const pipeline =
        device.createRenderPipeline(&pipline_desc) orelse {
            log.debug("failed to create render pipeline", .{});
            return error.wgpu;
        };

    return .{ bind_group_layout, pipeline_layout, pipeline };
}

pub fn reconfigure(renderer: *Renderer, size: Size(u32)) void {
    renderer.shader_globals.res = size.floatFromInt(f32);
    renderer.queue.writeBuffer(
        renderer.shader_globals_buffer,
        @offsetOf(ShaderGlobals, "res"),
        &renderer.shader_globals.res,
        @sizeOf(Size(f32)),
    );

    configureSurfaceBare(
        size,
        renderer.device,
        renderer.surface,
        renderer.surface_format,
    );
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
    try printLimits(gpa, limits);

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
    try printLimits(gpa, limits);

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

fn printLimits(gpa: Allocator, limits: wgpu.Limits) !void {
    const limits_str = try pretty.dump(gpa, limits, .{
        .show_type_names = true,
        .struct_max_len = 40, // limits has 31
    });
    defer gpa.free(limits_str);

    log.debug("{s}", .{limits_str});
}

fn inspectSurface(surface_caps: wgpu.SurfaceCapabilities) void {
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

// fields should be 16 bit aligned
pub const ShaderGlobals = extern struct {
    color: mt.RgbaF32, // 16
    res: Size(f32), // 8

    _padding: [2]u32 = @splat(0), // 8
};

pub const Vertex2D = extern struct {
    point: mt.Point(f32),
    color: mt.RgbaF32,

    pub fn vert(point: mt.Point(f32), color: mt.RgbaF32) Vertex2D {
        return .{ .point = point, .color = color };
    }

    pub const attributes = [_]wgpu.VertexAttribute{
        .{
            .shader_location = 0,
            .format = .float32x2,
            .offset = 0,
        },
        .{
            .shader_location = 1,
            .format = .float32x4,
            .offset = @sizeOf(mt.Point(f32)),
        },
    };
};

pub const GpuRect = extern struct {
    rect: mt.Rect(f32),
    color: mt.RgbaF32,

    pub fn gpuRect(rect: mt.Rect(f32), color: mt.RgbaF32) GpuRect {
        return .{ .rect = rect, .color = color };
    }

    pub const attributes = [_]wgpu.VertexAttribute{
        .{ // p0
            .shader_location = 0,
            .format = .float32x2,
            .offset = 0,
        },
        .{ // p1
            .shader_location = 1,
            .format = .float32x2,
            .offset = 2 * @sizeOf(f32),
        },
        .{ // color
            .shader_location = 2,
            .format = .float32x4,
            .offset = 4 * @sizeOf(f32),
        },
    };
};

pub fn draw(renderer: Renderer) void {
    // renderer log only use for err/warn unless testing
    const rlog = std.log.scoped(.@"wgpu render");

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
                    .label = "rect? render pass",
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

            // render_pass.setVertexBuffer(
            //     0,
            //     vertex_buffer,
            //     0,
            //     vertex_buffer.getSize(),
            // );
            // render_pass.setIndexBuffer(
            //     index_buffer,
            //     .uint16,
            //     0,
            //     index_buffer.getSize(),
            // );

            render_pass.setVertexBuffer(
                0,
                renderer.rect_buffer,
                0,
                renderer.rect_buffer.getSize(),
            );

            render_pass.setBindGroup(
                0,
                renderer.shader_globals_bind_group,
                0,
                null,
            );

            // render_pass.setViewport(
            //     0,
            //     0,
            //     renderer.shader_globals.res.width,
            //     renderer.shader_globals.res.height,
            //     0,
            //     1,
            // );

            // render_pass.drawIndexed(index_buffer_data.len, 1, 0, 0, 0);
            render_pass.draw(renderer.rect_buffer_data_len, 4, 0, 0);

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
