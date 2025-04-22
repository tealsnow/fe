const Renderer = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

const log_scope = .@"wgpu renderer";
const log = std.log.scoped(log_scope);

const wgpu = @import("wgpu");

const pretty = @import("pretty");

const mt = @import("math.zig");
const Size = mt.Size;

const tri_shader_code = @embedFile("triangle.wgsl");

surface: *wgpu.Surface,
surface_format: wgpu.TextureFormat,
device: *wgpu.Device,
queue: *wgpu.Queue,

// bind_group_layout: *wgpu.BindGroupLayout,
// pipeline_layout: *wgpu.PipelineLayout,
// pipeline: *wgpu.RenderPipeline,
//
// shader_globals: ShaderGlobals,
// shader_globals_buffer: *wgpu.Buffer,
// shader_globals_bind_group: *wgpu.BindGroup,
//
// rect_buffer_data_len: u32,
// rect_buffer: *wgpu.Buffer,

rect_pass: RenderPassRect,

pub const InspectOptions = struct {
    instance: ?Allocator = null,
    adapter: ?Allocator = null,
    device: ?Allocator = null,
    surface: bool = false,
};

pub fn init(
    surface_descriptor: wgpu.SurfaceDescriptor,
    initial_size: Size(u32),
    inspect: InspectOptions,
) !Renderer {
    const adapter, const surface =
        try createAdapaterAndSurface(surface_descriptor, inspect.instance);
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
    log.info("using surface format: {s}", .{@tagName(surface_format)});

    configureSurfaceBare(initial_size, device, surface, surface_format);

    // //- create pipline
    // log.debug("creating render pipeline", .{});

    // const bind_group_layout, const pipeline_layout, const pipeline =
    //     try createPipeline(device, surface_format);

    //- setup shader globals

    // const shader_globals = ShaderGlobals{
    //     .res = initial_size.floatFromInt(f32),
    //     .color = .hexRgb(0xff0000),
    // };
    //
    // const shader_globals_buffer = device.createBuffer(&.{
    //     .size = @sizeOf(ShaderGlobals),
    //     .usage = wgpu.BufferUsage.copy_dst | wgpu.BufferUsage.uniform,
    //     .mapped_at_creation = @intFromBool(false),
    // }) orelse {
    //     log.err("failed to create uniform buffer", .{});
    //     return error.wgpu;
    // };
    //
    // queue.writeBuffer(
    //     shader_globals_buffer,
    //     0,
    //     &shader_globals,
    //     shader_globals_buffer.getSize(),
    // );

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

    // const binding = wgpu.BindGroupEntry{
    //     .binding = 0,
    //     .buffer = shader_globals_buffer,
    //     .offset = 0,
    //     .size = @sizeOf(ShaderGlobals),
    // };
    //
    // const shader_globals_bind_group = device.createBindGroup(&.{
    //     .label = "fe bind group",
    //     .layout = bind_group_layout,
    //     .entry_count = 1,
    //     .entries = &.{binding},
    // }) orelse {
    //     log.err("failed to create bind group", .{});
    //     return error.wgpu;
    // };

    //-

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

    // const rect_buffer_data = [_]GpuRect{
    //     .gpuRect(.rect(.point(40, 40), .point(60, 60)), .hexRgb(0xff0000)),
    //     // .gpuRect(.rect(.point(40, 40), .point(60, 60)), .hexRgb(0xff0000)),
    //     // .gpuRect(.rect(.point(40, 40), .point(60, 60)), .hexRgb(0xff0000)),
    //     // .gpuRect(.rect(.point(40, 40), .point(60, 60)), .hexRgb(0xff0000)),
    // };
    //
    // const rect_buffer = device.createBuffer(&.{
    //     .size = rect_buffer_data.len * @sizeOf(GpuRect),
    //     .usage = wgpu.BufferUsage.copy_dst | wgpu.BufferUsage.vertex,
    //     .mapped_at_creation = @intFromBool(false),
    // }) orelse {
    //     log.err("failed to create rect buffer", .{});
    //     return error.wgpu;
    // };
    //
    // queue.writeBuffer(
    //     rect_buffer,
    //     0,
    //     &rect_buffer_data,
    //     rect_buffer.getSize(),
    // );

    //-

    const rect_pass =
        try RenderPassRect.init(
            device,
            queue,
            surface_format,
            initial_size.floatFromInt(f32),
        );

    return .{
        .surface = surface,
        .surface_format = surface_format,
        .device = device,
        .queue = queue,

        // .bind_group_layout = bind_group_layout,
        // .pipeline_layout = pipeline_layout,
        // .pipeline = pipeline,
        //
        // .shader_globals = shader_globals,
        // .shader_globals_buffer = shader_globals_buffer,
        // .shader_globals_bind_group = shader_globals_bind_group,
        //
        // .rect_buffer_data_len = rect_buffer_data.len,
        // .rect_buffer = rect_buffer,

        .rect_pass = rect_pass,
    };
}

pub fn deinit(renderer: Renderer) void {
    defer renderer.surface.unconfigure();
    defer renderer.queue.release();
    defer renderer.device.release();

    defer renderer.rect_pass.deinit();

    // defer renderer.bind_group_layout.release();
    // defer renderer.pipeline_layout.release();
    // defer renderer.pipeline.release();
    // defer renderer.shader_globals_buffer.release();
    // defer renderer.shader_globals_bind_group.release();
    // defer renderer.rect_buffer.release();
}

fn createAdapaterAndSurface(
    surface_descriptor: wgpu.SurfaceDescriptor,
    instance_report_alloc: ?Allocator,
) !struct { *wgpu.Adapter, *wgpu.Surface } {
    //- instance creation
    log.debug("creating instance", .{});

    var instance_desc_extras = wgpu.InstanceExtras{
        .backends = wgpu.InstanceBackend.all,
        .flags = wgpu.InstanceFlag.debug | wgpu.InstanceFlag.validation,
        .dx12_shader_compiler = .undefined,
        .gles3_minor_version = .automatic,
    };

    const instance_desc = wgpu.InstanceDescriptor{
        .next_in_chain = &instance_desc_extras.chain,
    };

    const instance = wgpu.Instance.create(&instance_desc) orelse {
        log.err("failed to create wgpu instance", .{});
        return error.wgpu;
    };
    defer {
        log.debug("releasing instance", .{});
        instance.release();
    }

    var report: wgpu.GlobalReport = undefined;
    instance.generateReport(&report);

    if (instance_report_alloc) |alloc| debug: {
        log.info("using backend: {s}", .{@tagName(report.backend_type)});

        if (!std.log.logEnabled(.debug, log_scope)) break :debug;

        const report_dump = try pretty.dump(alloc, report, .{
            .show_type_names = true,
            // .struct_max_len = 40,
        });
        defer alloc.free(report_dump);

        log.debug("instance report: ", .{});
        std.debug.print("{s}", .{report_dump});
    }

    //- create surface
    log.debug("creating surface", .{});

    const surface = instance.createSurface(&surface_descriptor) orelse {
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

// fn createPipeline(
//     device: *wgpu.Device,
//     surface_format: wgpu.TextureFormat,
// ) !struct {
//     *wgpu.BindGroupLayout,
//     *wgpu.PipelineLayout,
//     *wgpu.RenderPipeline,
// } {
//     //- create shader module
//     log.debug("compiling shader module", .{});
//
//     const shader_code_desc = wgpu.ShaderModuleWGSLDescriptor{
//         .code = rect_shader_code,
//     };
//     const shader_module =
//         device.createShaderModule(&.{
//             .label = "fe shader",
//             .next_in_chain = &shader_code_desc.chain,
//         }) orelse {
//             log.err("failed to create shader module", .{});
//             return error.wgpu;
//         };
//
//     //- uniform binding
//     const binding_layout = wgpu.BindGroupLayoutEntry{
//         .binding = 0,
//         .visibility = wgpu.ShaderStage.vertex | wgpu.ShaderStage.fragment,
//         .buffer = .{
//             .type = .uniform,
//             .min_binding_size = @sizeOf(ShaderGlobals),
//         },
//
//         .sampler = .{},
//         .texture = .{},
//         .storage_texture = .{},
//     };
//
//     //- bind group
//     const bind_group_layout = device.createBindGroupLayout(&.{
//         .label = "fe bind group layout",
//         .entry_count = 1,
//         .entries = &.{binding_layout},
//     }) orelse {
//         log.err("failed to create bind group layout", .{});
//         return error.wgpu;
//     };
//
//     //- vertex buffer
//     const vertex_buffer_layout = wgpu.VertexBufferLayout{
//         // .attribute_count = Vertex2D.attributes.len,
//         // .attributes = &Vertex2D.attributes,
//         // .array_stride = @sizeOf(Vertex2D),
//         // .step_mode = .vertex,
//
//         .attribute_count = GpuRect.attributes.len,
//         .attributes = &GpuRect.attributes,
//         .array_stride = @sizeOf(GpuRect),
//         .step_mode = .vertex,
//         // .step_mode = .instance,
//     };
//
//     //- fragment state
//     const blend_state = wgpu.BlendState{
//         .color = .{
//             .src_factor = .src_alpha,
//             .dst_factor = .one_minus_src_alpha,
//             .operation = .add,
//         },
//         .alpha = .{
//             .src_factor = .zero,
//             .dst_factor = .one,
//             .operation = .add,
//         },
//     };
//
//     const color_target_state = wgpu.ColorTargetState{
//         .format = surface_format,
//         .blend = &blend_state,
//         .write_mask = wgpu.ColorWriteMask.all,
//     };
//
//     const fragment_state = wgpu.FragmentState{
//         .module = shader_module,
//         .entry_point = "fsMain",
//         .target_count = 1,
//         .targets = &.{color_target_state},
//     };
//
//     //- pipeline layout
//     const pipeline_layout = device.createPipelineLayout(&.{
//         .label = "fe pipeline layout",
//         .bind_group_layout_count = 1,
//         .bind_group_layouts = &.{bind_group_layout},
//     }) orelse {
//         log.err("failed to create pipeline layout", .{});
//         return error.wgpu;
//     };
//
//     //- pipeline desc
//     const pipline_desc = wgpu.RenderPipelineDescriptor{
//         .label = "fe pipeline",
//         .vertex = .{
//             .module = shader_module,
//             .entry_point = "vsMain",
//
//             .buffer_count = 1,
//             .buffers = &.{vertex_buffer_layout},
//         },
//         .primitive = .{
//             // .topology = .triangle_list,
//             .topology = .triangle_strip,
//             .strip_index_format = .undefined, // sequential
//             .front_face = .ccw, // counter-clockwise
//             .cull_mode = .none,
//         },
//         .fragment = &fragment_state,
//         .depth_stencil = null,
//         .multisample = .{
//             .count = 1,
//             .mask = 0xffffffff,
//         },
//         .layout = pipeline_layout,
//     };
//
//     const pipeline =
//         device.createRenderPipeline(&pipline_desc) orelse {
//             log.debug("failed to create render pipeline", .{});
//             return error.wgpu;
//         };
//
//     return .{ bind_group_layout, pipeline_layout, pipeline };
// }

pub fn reconfigure(renderer: *Renderer, size: Size(u32)) void {
    // renderer.shader_globals.res = size.floatFromInt(f32);
    // renderer.queue.writeBuffer(
    //     renderer.shader_globals_buffer,
    //     @offsetOf(ShaderGlobals, "res"),
    //     &renderer.shader_globals.res,
    //     @sizeOf(Size(f32)),
    // );

    renderer.rect_pass
        .updateSurfaceSize(renderer.queue, size.floatFromInt(f32));

    configureSurfaceBare(
        size,
        renderer.device,
        renderer.surface,
        renderer.surface_format,
    );
}

//= Helpers

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
        .view_format_count = 1,
        .view_formats = &.{format},
        .alpha_mode = .@"opaque",
        .width = size.width,
        .height = size.height,
        .present_mode = .fifo,
    };
    surface.configure(&surface_config);
}

fn inspectAdapter(gpa: Allocator, adapter: *wgpu.Adapter) !void {
    //- limit listing
    log.debug("getting adapter limits", .{});

    var supported_limits = wgpu.SupportedLimits{ .limits = .{} };
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

//= Types

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

//= rendering

// renderer log - only use for err/warn unless testing
const rlog = std.log.scoped(.@"wgpu render");

pub fn render(renderer: Renderer) void {
    //- get next surface texture
    const target_view = getTargetTextureView(renderer.surface) catch |err| {
        switch (err) {
            error.GetCurrentTextureFailed => //
            rlog.err("failed to get current target texture", .{}),
            error.CreateTextureViewFailed => //
            rlog.err("failed to create target texture view", .{}),
        }
        return;
    };
    defer target_view.release();

    //- encode draw commands
    const command_buffer = renderer.encodeCommands(target_view) catch |err| {
        switch (err) {
            error.CreateCommandEncoderFailed => //
            rlog.err("failed to create command encoder", .{}),
            error.FinishEncoderFailed => //
            rlog.err("failed to finish command encoding", .{}),
        }
        return;
    };
    defer command_buffer.release();

    //- submit command
    renderer.queue.submit(&.{command_buffer});
}

const GetTargetTextureViewError = error{
    GetCurrentTextureFailed,
    CreateTextureViewFailed,
};

fn getTargetTextureView(
    surface: *wgpu.Surface,
) GetTargetTextureViewError!*wgpu.TextureView {
    var surface_texture: wgpu.SurfaceTexture = undefined;
    surface.getCurrentTexture(&surface_texture);

    if (surface_texture.status != .success)
        return error.GetCurrentTextureFailed;

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
        return error.CreateTextureViewFailed;

    return target_view;
}

const EncodeCommandsError = error{
    CreateCommandEncoderFailed,
    FinishEncoderFailed,
};

fn encodeCommands(
    renderer: *const Renderer,
    target_view: *wgpu.TextureView,
) EncodeCommandsError!*wgpu.CommandBuffer {
    //- command encoder
    const encoder =
        renderer.device.createCommandEncoder(&.{
            .label = "fe command encoder",
        }) orelse
        return error.CreateCommandEncoderFailed;
    defer encoder.release();

    //- render pass
    // renderer.renderPassRect(target_view, encoder);
    renderPassRect(renderer.rect_pass, target_view, encoder);

    //- command
    const command_buffer =
        encoder.finish(&.{ .label = "fe command buffer" }) orelse
        return error.FinishEncoderFailed;

    return command_buffer;
}

//= rect rendering

pub const RectInstance = extern struct {
    rect: mt.Rect(f32),
    color: mt.RgbaF32,

    pub fn inst(rect: mt.Rect(f32), color: mt.RgbaF32) RectInstance {
        return .{ .rect = rect, .color = color };
    }

    // const attributes = [_]wgpu.VertexAttribute{
    //     .{ // p0
    //         .shader_location = 0,
    //         .format = .float32x2,
    //         .offset = 0,
    //     },
    //     .{ // p1
    //         .shader_location = 1,
    //         .format = .float32x2,
    //         .offset = 2 * @sizeOf(f32),
    //     },
    //     .{ // color
    //         .shader_location = 2,
    //         .format = .float32x4,
    //         .offset = 4 * @sizeOf(f32),
    //     },
    // };
    //
    // pub const vertex_buffer_layout = wgpu.VertexBufferLayout{
    //     .attribute_count = attributes.len,
    //     .attributes = &attributes,
    //     .array_stride = @sizeOf(RectVert),
    //     .step_mode = .instance,
    // };
};

// fields should be 16 bit aligned
const RenderPassRectUniform = extern struct {
    surface_size_px: Size(f32), // 8
    _padding: [2]u32 = @splat(0), // 8

    // const binding_layout = wgpu.BindGroupLayoutEntry{
    //     .binding = 0,
    //     .visibility = wgpu.ShaderStage.vertex,
    //     .buffer = .{
    //         .type = .uniform,
    //         .min_binding_size = @sizeOf(RenderPassRectUniform),
    //     },
    //
    //     .sampler = .{},
    //     .texture = .{},
    //     .storage_texture = .{},
    // };
    //
    // pub fn createBindGroupLayout(device: *wgpu.Device) !*wgpu.BindGroupLayout {
    //     return device.createBindGroupLayout(&.{
    //         .label = "rect uniform bind group layout",
    //         .entry_count = 1,
    //         .entries = &.{binding_layout},
    //     }) orelse {
    //         log.err("failed to create rect bind group layout", .{});
    //         return error.wgpu;
    //     };
    // }

    // fn createBinding(buffer: *wgpu.Buffer) wgpu.BindGroupEntry {
    //     return .{
    //         .binding = 0,
    //         .buffer = buffer,
    //         .offset = 0,
    //         .size = @sizeOf(RenderPassRectUniform),
    //     };
    // }
    //
    // fn createBindGroup(
    //     device: *wgpu.Device,
    //     layout: *wgpu.BindGroupLayout,
    //     buffer: *wgpu.Buffer,
    // ) !*wgpu.BindGroup {
    //     const binding = createBinding(buffer);
    //
    //     return device.createBindGroup(&.{
    //         .label = "rect uniform bind group",
    //         .layout = layout,
    //         .entry_count = 1,
    //         .entries = &.{binding},
    //     }) orelse {
    //         log.err("failed to create rect bind group", .{});
    //         return error.wgpu;
    //     };
    // }
    //
    // pub fn init(
    //     device: *wgpu.Device,
    //     bind_group_layout: *wgpu.BindGroupLayout,
    //     surface_size_px: Size(f32),
    // ) !struct {
    //     RenderPassRectUniform,
    //     *wgpu.Buffer,
    //     *wgpu.BindGroup,
    // } {
    //     const uniform = RenderPassRectUniform{
    //         .surface_size_px = surface_size_px,
    //     };
    //
    //     const buffer = device.createBuffer(&.{
    //         .size = @sizeOf(RenderPassRectUniform),
    //         .usage = wgpu.BufferUsage.copy_dst | wgpu.BufferUsage.uniform,
    //         .mapped_at_creation = @intFromBool(false),
    //     }) orelse {
    //         log.err("failed to create rect uniform buffer", .{});
    //         return error.wgpu;
    //     };
    //
    //     const bind_group =
    //         try createBindGroup(device, bind_group_layout, buffer);
    //
    //     return .{ uniform, buffer, bind_group };
    // }

    pub fn write(
        uniform: RenderPassRectUniform,
        buffer: *wgpu.Buffer,
        queue: *wgpu.Queue,
    ) void {
        queue.writeBuffer(buffer, 0, &uniform, buffer.getSize());
    }
};

const RenderPassRect = struct {
    bind_group_layout: *wgpu.BindGroupLayout,
    pipeline_layout: *wgpu.PipelineLayout,
    pipeline: *wgpu.RenderPipeline,

    uniform: RenderPassRectUniform,
    uniform_buffer: *wgpu.Buffer,

    rect_vertex_buffer_data_len: u32,
    rect_vertex_buffer: *wgpu.Buffer,

    unused_instance_buffer_data_len: u32,
    unused_instance_buffer: *wgpu.Buffer,

    bind_group: *wgpu.BindGroup,

    pub fn init(
        device: *wgpu.Device,
        queue: *wgpu.Queue,
        surface_format: wgpu.TextureFormat,
        surface_size_px: Size(f32),
    ) !RenderPassRect {
        const bind_group_layout, //
        const pipeline_layout, //
        const pipeline =
            try createPipeline(device, surface_format);

        // const uniform, const uniform_buffer, const uniform_bind_group =
        //     try RenderPassRectUniform.init(
        //         device,
        //         uniform_bind_group_layout,
        //         surface_size_px,
        //     );

        //- uniform setup

        const uniform = RenderPassRectUniform{
            .surface_size_px = surface_size_px,
        };

        const uniform_buffer = device.createBuffer(&.{
            .label = "uniform buffer",
            .size = @sizeOf(RenderPassRectUniform),
            .usage = wgpu.BufferUsage.copy_dst | wgpu.BufferUsage.uniform,
            .mapped_at_creation = @intFromBool(false),
        }) orelse {
            log.err("failed to create rect uniform buffer", .{});
            return error.wgpu;
        };

        uniform.write(uniform_buffer, queue);

        //- rect steup

        const red = mt.RgbaF32.hexRgb(0xff0000);
        const rect_vertex_buffer_data = [_]RectInstance{
            .inst(.rect(.point(40, 40), .point(60, 60)), red),
            .inst(.rect(.point(40, 40), .point(60, 60)), red),
            .inst(.rect(.point(40, 40), .point(60, 60)), red),
            .inst(.rect(.point(40, 40), .point(60, 60)), red),
        };

        const rect_vertex_buffer = device.createBuffer(&.{
            .label = "rect vertex buffer",
            .size = rect_vertex_buffer_data.len * @sizeOf(RectInstance),
            // .usage = wgpu.BufferUsage.copy_dst |
            //     wgpu.BufferUsage.vertex |
            //     wgpu.BufferUsage.storage,
            .usage = wgpu.BufferUsage.copy_dst |
                wgpu.BufferUsage.vertex,
            .mapped_at_creation = @intFromBool(false),
        }) orelse {
            log.err("failed to create rect buffer", .{});
            return error.wgpu;
        };

        queue.writeBuffer(
            rect_vertex_buffer,
            0,
            &rect_vertex_buffer_data,
            rect_vertex_buffer.getSize(),
        );

        //- unused instance data
        // This should be 4x the number of rect vertices

        const unused_instance_buffer_data: //
        [4 * rect_vertex_buffer_data.len]u32 = .{
            0, 1, 2, 3,
            0, 1, 2, 3,
            0, 1, 2, 3,
            0, 1, 2, 3,
        };

        const unused_instance_buffer = device.createBuffer(&.{
            .label = "unused instance buffer",
            .size = unused_instance_buffer_data.len * @sizeOf(u32),
            .usage = wgpu.BufferUsage.copy_dst |
                wgpu.BufferUsage.vertex,
            .mapped_at_creation = @intFromBool(false),
        }) orelse {
            log.err("failed to create ununsed instance buffer", .{});
            return error.wgpu;
        };

        queue.writeBuffer(
            unused_instance_buffer,
            0,
            &unused_instance_buffer_data,
            unused_instance_buffer.getSize(),
        );

        //- bind group

        const uniform_bind_group_entry = wgpu.BindGroupEntry{
            .binding = 0,
            .buffer = uniform_buffer,
            .offset = 0,
            .size = @sizeOf(RenderPassRectUniform),
        };

        // const rect_instance_bind_group_entry = wgpu.BindGroupEntry{
        //     .binding = 1,
        //     .buffer = rect_instance_buffer,
        //     .offset = @sizeOf(RenderPassRectUniform),
        //     // .offset = 256,
        //     .size = rect_instance_buffer.getSize(),
        // };

        const bind_group_entries = [_]wgpu.BindGroupEntry{
            uniform_bind_group_entry,
            // rect_instance_bind_group_entry,
        };

        const bind_group = device.createBindGroup(&.{
            .label = "rect bind group",
            .layout = bind_group_layout,
            .entry_count = bind_group_entries.len,
            .entries = &bind_group_entries,
        }) orelse {
            log.err("failed to create rect instance bind group", .{});
            return error.wgpu;
        };

        return RenderPassRect{
            .bind_group_layout = bind_group_layout,
            .pipeline_layout = pipeline_layout,
            .pipeline = pipeline,

            .uniform = uniform,
            .uniform_buffer = uniform_buffer,

            .rect_vertex_buffer_data_len = rect_vertex_buffer_data.len,
            .rect_vertex_buffer = rect_vertex_buffer,

            .unused_instance_buffer_data_len = unused_instance_buffer_data.len,
            .unused_instance_buffer = unused_instance_buffer,

            .bind_group = bind_group,
        };
    }

    pub fn deinit(pass: RenderPassRect) void {
        defer pass.bind_group_layout.release();
        defer pass.pipeline_layout.release();
        defer pass.pipeline.release();

        defer pass.uniform_buffer.release();
        defer pass.rect_vertex_buffer.release();
        defer pass.unused_instance_buffer.release();
        defer pass.bind_group.release();
    }

    pub fn updateSurfaceSize(
        pass: *RenderPassRect,
        queue: *wgpu.Queue,
        size: Size(f32),
    ) void {
        pass.uniform.surface_size_px = size;
        pass.uniform.write(pass.uniform_buffer, queue);
    }

    const shader_code = @embedFile("rect.wgsl");

    fn createShaderModule(device: *wgpu.Device) !*wgpu.ShaderModule {
        const shader_code_desc =
            wgpu.ShaderModuleWGSLDescriptor{ .code = shader_code };
        return device.createShaderModule(&.{
            .label = "rect shader",
            .next_in_chain = &shader_code_desc.chain,
        }) orelse {
            log.err("failed to create rect shader module", .{});
            return error.wgpu;
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
        log.debug("creating rect pipeline", .{});

        const shader_module = try createShaderModule(device);

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

        // const uniform_bind_group_layout =
        //     try RenderPassRectUniform.createBindGroupLayout(device);

        // const rect_instance_binding_layout = wgpu.BindGroupLayoutEntry{
        //     .binding = 1,
        //     .visibility = wgpu.ShaderStage.vertex,
        //     .buffer = .{
        //         .type = .read_only_storage,
        //         .min_binding_size = @sizeOf(RectInstance),
        //     },
        //
        //     .sampler = .{},
        //     .texture = .{},
        //     .storage_texture = .{},
        // };
        //
        // const rect_instance_bind_group_layout =
        //     device.createBindGroupLayout(&.{
        //         .label = "rect instance bind group layout",
        //         .entry_count = 1,
        //         .entries = &.{rect_instance_binding_layout},
        //     }) orelse {
        //         log.err("failed to create instance bind group layout", .{});
        //         return error.wgpu;
        //     };
        //
        // const bind_group_layouts = [2]*wgpu.BindGroupLayout{
        //     uniform_bind_group_layout,
        //     rect_instance_bind_group_layout,
        // };

        const uniform_bind_group_entry_layout =
            wgpu.BindGroupLayoutEntry{
                .binding = 0,
                .visibility = wgpu.ShaderStage.vertex,
                .buffer = .{
                    .type = .uniform,
                    .min_binding_size = @sizeOf(RenderPassRectUniform),
                },
                .sampler = .{},
                .texture = .{},
                .storage_texture = .{},
            };

        // const rect_instance_bind_group_entry_layout =
        //     wgpu.BindGroupLayoutEntry{
        //         .binding = 1,
        //         .visibility = wgpu.ShaderStage.vertex,
        //         .buffer = .{
        //             .type = .read_only_storage,
        //             .min_binding_size = @sizeOf(RectInstance),
        //         },
        //         .sampler = .{},
        //         .texture = .{},
        //         .storage_texture = .{},
        //     };

        const bind_group_layout_entries = [_]wgpu.BindGroupLayoutEntry{
            uniform_bind_group_entry_layout,
            // rect_instance_bind_group_entry_layout,
        };

        const bind_group_layout = device.createBindGroupLayout(&.{
            .label = "bind group layout",
            .entry_count = bind_group_layout_entries.len,
            .entries = &bind_group_layout_entries,
        }) orelse {
            log.err("failed to create bind group layout", .{});
            return error.wgpu;
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

        //- vertex layout

        const rect_vertex_attributes = [_]wgpu.VertexAttribute{
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
                .offset = 2 * 2 * @sizeOf(f32),
            },
        };

        const rect_vertex_buffer_layout = wgpu.VertexBufferLayout{
            .array_stride = @sizeOf(RectInstance),
            .step_mode = .vertex,
            .attribute_count = rect_vertex_attributes.len,
            .attributes = &rect_vertex_attributes,
        };

        const unused_instance_attributes = [_]wgpu.VertexAttribute{
            .{ // _unsued
                .shader_location = 3,
                .format = .uint32,
                .offset = 0,
            },
        };

        const unused_instance_buffer_layout = wgpu.VertexBufferLayout{
            .array_stride = @sizeOf(u32),
            .step_mode = .instance,
            .attribute_count = unused_instance_attributes.len,
            .attributes = &unused_instance_attributes,
        };

        const vertex_buffer_layouts = [_]wgpu.VertexBufferLayout{
            rect_vertex_buffer_layout,
            unused_instance_buffer_layout,
        };

        //- pipeline desc
        const pipline_desc = wgpu.RenderPipelineDescriptor{
            .label = "fe pipeline",
            .vertex = .{
                .module = shader_module,
                .entry_point = "vsMain",

                // .buffer_count = 1,
                // .buffers = &.{RectVert.vertex_buffer_layout},

                // .buffer_count = 0,

                .buffer_count = vertex_buffer_layouts.len,
                .buffers = &vertex_buffer_layouts,
            },
            .primitive = .{
                .topology = .triangle_strip,
                .strip_index_format = .undefined, // sequential
                .front_face = .ccw, // counter-clockwise
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

        return .{
            bind_group_layout,
            pipeline_layout,
            pipeline,
        };
    }
};

fn renderPassRect(
    rect_pass: RenderPassRect,
    target_view: *wgpu.TextureView,
    encoder: *wgpu.CommandEncoder,
) void {
    const render_pass =
        encoder.beginRenderPass(&.{
            .label = "rect render pass",
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

    render_pass.setPipeline(rect_pass.pipeline);

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

    // render_pass.setVertexBuffer(
    //     0,
    //     rect_pass.rect_buffer,
    //     0,
    //     rect_pass.rect_buffer.getSize(),
    // );

    render_pass.setBindGroup(
        0,
        rect_pass.bind_group,
        0,
        null,
    );

    render_pass.setVertexBuffer(
        0,
        rect_pass.rect_vertex_buffer,
        0,
        rect_pass.rect_vertex_buffer.getSize(),
    );

    render_pass.setVertexBuffer(
        1,
        rect_pass.unused_instance_buffer,
        0,
        rect_pass.unused_instance_buffer.getSize(),
    );

    // render_pass.setVertexBuffer

    // render_pass.drawIndexed(index_buffer_data.len, 1, 0, 0, 0);
    // render_pass.draw(renderer.rect_buffer_data_len, 1, 0, 0);
    // render_pass.draw(renderer.rect_buffer_data_len, 1, 0, 0);
    // render_pass.draw(1, 4, 0, 0);

    // // unoptimized duplicated draw
    // render_pass.draw(4, 1, 0, 0);

    render_pass.draw(
        4,
        4,
        0,
        0,
    );

    render_pass.end();
}
