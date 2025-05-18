const Renderer = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

const log_scope = .@"wgpu renderer";
const log = std.log.scoped(log_scope);

pub const wgpu = @import("wgpu");
const ft = @import("freetype");
const pretty = @import("pretty");

const cu = @import("cu");
const mt = cu.math;

pub const FontAtlas = @import("FontAtlas.zig");
pub const FontFace = @import("FontFace.zig");
pub const TextShaper = @import("TextShaper.zig");

const shader_code = @embedFile("rect.wgsl");

//= fields

surface: *wgpu.Surface,
surface_format: wgpu.TextureFormat,
device: *wgpu.Device,
queue: *wgpu.Queue,

shader_module: *wgpu.ShaderModule,
pipeline_layout: *wgpu.PipelineLayout,
pipeline: *wgpu.RenderPipeline,

uniform: UniformData,
uniform_buffer: *wgpu.Buffer,

uniform_bind_group_layout: *wgpu.BindGroupLayout,
uniform_bind_group: *wgpu.BindGroup,

texture_bind_group_layout: *wgpu.BindGroupLayout,

font_atlas_manager: *FontAtlasManager,
batch_processor: *BatchProcessor,

//= methods

pub const InspectOptions = struct {
    instance: ?Allocator = null,
    adapter: ?Allocator = null,
    device: ?Allocator = null,
    surface: bool = false,
};

pub const InitParams = struct {
    surface_descriptor: wgpu.SurfaceDescriptor,
    initial_surface_size: mt.Size(u32),
    inspect: InspectOptions,
};

pub fn init(gpa: Allocator, params: InitParams) !Renderer {
    const adapter, const surface = try createAdapaterAndSurface(
        params.surface_descriptor,
        params.inspect.instance,
    );
    defer {
        log.debug("releasing adapter", .{});
        adapter.release();
    }

    //- inspect adapter
    if (params.inspect.adapter) |alloc| {
        log.debug("inspecting adapter", .{});
        try inspectAdapter(alloc, adapter);
    }

    //- request device
    log.debug("requesting device", .{});

    const required_limits = getRequiredLimits(adapter);

    const device_response = adapter.requestDeviceSync(&.{
        .required_feature_count = 0,
        .required_limits = &required_limits,
        .default_queue = .{},
        .device_lost_callback = &deviceLostCallback,
    });
    const device = device_response.device orelse {
        log.err("failed to request device", .{});
        return error.wgpu;
    };

    //- inspect device
    if (params.inspect.device) |alloc| {
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

    if (params.inspect.surface) {
        inspectSurface(surface_caps);
    }

    const surface_format = surface_caps.formats[0];
    log.info("using surface format: {s}", .{@tagName(surface_format)});

    configureSurfaceBare(
        params.initial_surface_size,
        device,
        surface,
        surface_format,
    );

    //- pipeline

    const shader_module, //
    const uniform_bind_group_layout, //
    const texture_bind_group_layout, //
    const pipeline_layout, //
    const pipeline =
        try createPipeline(device, surface_format);

    //- uniform

    const uniform = UniformData{
        .surface_size_px = params.initial_surface_size.floatFromInt(f32),
    };

    const uniform_buffer = device.createBuffer(&.{
        .label = "uniform buffer",
        .size = @sizeOf(UniformData),
        .usage = wgpu.BufferUsage.copy_dst | wgpu.BufferUsage.uniform,
        .mapped_at_creation = @intFromBool(false),
    }) orelse {
        log.err("failed to create rect uniform buffer", .{});
        return error.wgpu;
    };

    uniform.write(uniform_buffer, queue);

    //- uniform bind group

    const uniform_bind_group_entry = wgpu.BindGroupEntry{
        .binding = 0,
        .buffer = uniform_buffer,
        .offset = 0,
        .size = @sizeOf(UniformData),
    };

    const uniform_bind_group_entries = [_]wgpu.BindGroupEntry{
        uniform_bind_group_entry,
    };

    const uniform_bind_group = device.createBindGroup(&.{
        .label = "uniform bind group",
        .layout = uniform_bind_group_layout,
        .entry_count = uniform_bind_group_entries.len,
        .entries = &uniform_bind_group_entries,
    }) orelse {
        log.err("failed to create rect instance bind group", .{});
        return error.wgpu;
    };

    //- return

    const font_atlas_manager = try gpa.create(FontAtlasManager);
    font_atlas_manager.* = try .init();

    const batch_processor = try gpa.create(BatchProcessor);
    batch_processor.* = try .init(font_atlas_manager);

    return .{
        .surface = surface,
        .surface_format = surface_format,
        .device = device,
        .queue = queue,

        .shader_module = shader_module,
        .pipeline_layout = pipeline_layout,
        .pipeline = pipeline,

        .uniform = uniform,
        .uniform_buffer = uniform_buffer,

        .uniform_bind_group_layout = uniform_bind_group_layout,
        .uniform_bind_group = uniform_bind_group,

        .texture_bind_group_layout = texture_bind_group_layout,

        .font_atlas_manager = font_atlas_manager,
        .batch_processor = batch_processor,
    };
}

pub fn deinit(renderer: Renderer, gpa: Allocator) void {
    defer renderer.surface.release();
    defer renderer.surface.unconfigure();
    defer renderer.queue.release();
    defer renderer.device.release();

    defer renderer.shader_module.release();
    defer renderer.pipeline_layout.release();
    defer renderer.pipeline.release();

    defer renderer.uniform_buffer.release();

    defer renderer.uniform_bind_group_layout.release();
    defer renderer.uniform_bind_group.release();

    defer renderer.texture_bind_group_layout.release();

    defer gpa.destroy(renderer.font_atlas_manager);
    defer renderer.font_atlas_manager.deinit(gpa);

    defer gpa.destroy(renderer.batch_processor);
    defer renderer.batch_processor.deinit();
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
            .{
                @tagName(adapter_response.status),
                adapter_response.message,
            },
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

pub fn reconfigure(renderer: *Renderer, size: mt.Size(u32)) void {
    renderer.uniform.surface_size_px = size.floatFromInt(f32);
    renderer.uniform.write(renderer.uniform_buffer, renderer.queue);

    configureSurfaceBare(
        size,
        renderer.device,
        renderer.surface,
        renderer.surface_format,
    );
}

fn createShaderModule(device: *wgpu.Device) !*wgpu.ShaderModule {
    const shader_code_desc =
        wgpu.ShaderModuleWGSLDescriptor{ .code = shader_code };
    return device.createShaderModule(&.{
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
    *wgpu.ShaderModule,
    *wgpu.BindGroupLayout, // uniform
    *wgpu.BindGroupLayout, // texture
    *wgpu.PipelineLayout,
    *wgpu.RenderPipeline,
} {
    const shader_module = try createShaderModule(device);

    const blend_state = wgpu.BlendState{
        .color = .{
            .src_factor = .src_alpha,
            .dst_factor = .one_minus_src_alpha,
            .operation = .add,
        },
        .alpha = wgpu.BlendComponent.over,
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

    //- uniform bind group
    const uniform_bind_group_entry_layout = wgpu.BindGroupLayoutEntry{
        .binding = 0,
        .visibility = wgpu.ShaderStage.vertex | wgpu.ShaderStage.fragment,
        .buffer = .{
            .type = .uniform,
            .min_binding_size = @sizeOf(UniformData),
        },
        .sampler = .{},
        .texture = .{},
        .storage_texture = .{},
    };

    const uniform_bind_group_layout_entries = [_]wgpu.BindGroupLayoutEntry{
        uniform_bind_group_entry_layout,
    };

    const uniform_bind_group_layout = device.createBindGroupLayout(&.{
        .label = "uniform bind group layout",
        .entry_count = uniform_bind_group_layout_entries.len,
        .entries = &uniform_bind_group_layout_entries,
    }) orelse {
        log.err("failed to create bind group layout", .{});
        return error.wgpu;
    };

    //- texture bind group
    const texture_bind_group_entry_layout = wgpu.BindGroupLayoutEntry{
        .binding = 0,
        .visibility = wgpu.ShaderStage.vertex | wgpu.ShaderStage.fragment,
        .texture = .{
            .multisampled = @intFromBool(false),
            .view_dimension = .@"2d",
            .sample_type = .float,
        },
        .buffer = .{},
        .sampler = .{},
        .storage_texture = .{},
    };

    const sampler_bind_group_entry_layout = wgpu.BindGroupLayoutEntry{
        .binding = 1,
        .visibility = wgpu.ShaderStage.fragment,
        .sampler = .{ .type = .filtering },
        .buffer = .{},
        .texture = .{},
        .storage_texture = .{},
    };

    const texture_bind_group_layout_entries = [_]wgpu.BindGroupLayoutEntry{
        texture_bind_group_entry_layout,
        sampler_bind_group_entry_layout,
    };

    const texture_bind_group_layout = device.createBindGroupLayout(&.{
        .label = "texture bind group layout",
        .entry_count = texture_bind_group_layout_entries.len,
        .entries = &texture_bind_group_layout_entries,
    }) orelse {
        log.err("failed to create bind group layout", .{});
        return error.wgpu;
    };

    //- bind groups

    const bind_group_layouts = [_]*wgpu.BindGroupLayout{
        uniform_bind_group_layout,
        texture_bind_group_layout,
    };

    //- pipeline layout
    const pipeline_layout = device.createPipelineLayout(&.{
        .bind_group_layout_count = bind_group_layouts.len,
        .bind_group_layouts = &bind_group_layouts,
    }) orelse {
        log.err("failed to create pipeline layout", .{});
        return error.wgpu;
    };

    //- vertex layout

    const rect_instance_layout_attributes = [_]wgpu.VertexAttribute{
        .{ // dst_p0
            .shader_location = 0,
            .format = .float32x2,
            .offset = 0,
        },
        .{ // dst_p1
            .shader_location = 1,
            .format = .float32x2,
            .offset = 2 * @sizeOf(f32),
        },
        .{ // tex_p0
            .shader_location = 2,
            .format = .float32x2,
            .offset = 4 * @sizeOf(f32),
        },
        .{ // tex_p0
            .shader_location = 3,
            .format = .float32x2,
            .offset = 6 * @sizeOf(f32),
        },
        .{ // color
            .shader_location = 4,
            .format = .float32x4,
            .offset = 8 * @sizeOf(f32),
        },
        .{ // corner_radius
            .shader_location = 5,
            .format = .float32,
            .offset = 12 * @sizeOf(f32),
        },
        .{ // edge_softness
            .shader_location = 6,
            .format = .float32,
            .offset = 13 * @sizeOf(f32),
        },
        .{ // border_thickness
            .shader_location = 7,
            .format = .float32,
            .offset = 14 * @sizeOf(f32),
        },
    };

    const rect_instance_layout = wgpu.VertexBufferLayout{
        .array_stride = @sizeOf(RectInstance),
        .step_mode = .instance,
        .attribute_count = rect_instance_layout_attributes.len,
        .attributes = &rect_instance_layout_attributes,
    };

    const vertex_buffer_layouts = [_]wgpu.VertexBufferLayout{
        rect_instance_layout,
    };

    //- pipeline desc
    const pipline_desc = wgpu.RenderPipelineDescriptor{
        .vertex = .{
            .module = shader_module,
            .entry_point = "vsMain",

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
        shader_module,
        uniform_bind_group_layout,
        texture_bind_group_layout,
        pipeline_layout,
        pipeline,
    };
}

//= Helpers

fn configureSurfaceBare(
    size: mt.Size(u32),
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
        log.err("Device lost message: {s}", .{str});
    }
}

//= rendering

// renderer log - only use for err/warn unless testing
const rlog = std.log.scoped(.@"wgpu render");

pub fn render(renderer: Renderer, arena: Allocator) !void {
    const batch_data = try renderer.batch_processor.process(arena);
    defer renderer.batch_processor.reset();

    var render_pass_data =
        try arena.alloc(RenderPassData, batch_data.len);

    for (batch_data, 0..) |data, i| {
        render_pass_data[i] =
            try renderer.batchToRenderPass(renderer.font_atlas_manager, data);
    }

    renderer.renderPassData(render_pass_data);

    for (render_pass_data) |data| {
        data.deinit();
    }
}

pub fn renderPassData(
    renderer: Renderer,
    render_pass_data: []const RenderPassData,
) void {
    //- get next surface texture
    const target_view =
        getTargetTextureView(renderer.surface) catch |err| {
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
    const command_buffer =
        renderer.encodeCommands(target_view, render_pass_data) catch |err| {
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
            .label = "atlas texture view",
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
    render_pass_data: []const RenderPassData,
) EncodeCommandsError!*wgpu.CommandBuffer {
    //- command encoder
    const encoder =
        renderer.device.createCommandEncoder(&.{}) orelse
        return error.CreateCommandEncoderFailed;
    defer encoder.release();

    //- render pass
    renderer.doRenderPass(encoder, target_view, render_pass_data);

    //- command
    const command_buffer =
        encoder.finish(&.{}) orelse
        return error.FinishEncoderFailed;

    return command_buffer;
}

fn doRenderPass(
    renderer: *const Renderer,
    encoder: *wgpu.CommandEncoder,
    target_view: *wgpu.TextureView,
    pass_data: []const RenderPassData,
) void {
    const pass =
        encoder.beginRenderPass(&.{
            .label = "render pass",
            .color_attachment_count = 1,
            .color_attachments = &.{
                .{
                    .view = target_view,
                    .resolve_target = null,
                    .load_op = .clear,
                    .store_op = .discard,
                    .clear_value = .{
                        // .r = 0.9,
                        // .g = 0.1,
                        // .b = 0.2,
                        // .a = 1.0
                        .r = 0.0,
                        .g = 0.0,
                        .b = 0.0,
                        .a = 0.0,
                    },
                    // .depth_slice = wgpu.WGPU_DEPTH_SLICE_UNDEFINED,
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
    defer pass.release();

    pass.setPipeline(renderer.pipeline);

    pass.setBindGroup(
        0,
        renderer.uniform_bind_group,
        0,
        null,
    );

    for (pass_data) |data| {
        pass.setBindGroup(
            1,
            data.atlas_texture_bind_group,
            0,
            null,
        );

        pass.setVertexBuffer(
            0,
            data.rect_buffer,
            0,
            data.rect_buffer.getSize(),
        );

        pass.draw(4, data.rect_buffer_count, 0, 0);
    }

    pass.end();
}

//= gpu types

pub const RectInstance = extern struct {
    dst: mt.Rect(f32),
    tex: mt.Rect(f32) = .zero,
    color: mt.RgbaF32,
    corner_radius: f32 = 0,
    edge_softness: f32 = 0,
    border_thickness: f32 = 0,
};

// fields should be 16 bit aligned
const UniformData = extern struct {
    surface_size_px: mt.Size(f32), // 8
    _padding: [2]u32 = @splat(0), // 8

    pub fn write(
        uniform: UniformData,
        buffer: *wgpu.Buffer,
        queue: *wgpu.Queue,
    ) void {
        queue.writeBuffer(buffer, 0, &uniform, buffer.getSize());
    }
};

//= CuCallbacks

pub const CuCallbacks = struct {
    renderer: *const Renderer,
    gpa: Allocator,

    pub fn init(renderer: *const Renderer, gpa: Allocator) !CuCallbacks {
        return .{ .renderer = renderer, .gpa = gpa };
    }

    pub fn deinit(cb: CuCallbacks) void {
        _ = cb;
        // cb.shaper.deinit();
    }

    pub fn callbacks(cb: *CuCallbacks) cu.State.Callbacks {
        return .{
            .context = @ptrCast(@alignCast(cb)),
            .vtable = .{
                .measureText = &measureText,
                .fontSize = &fontSize,
                .getGraphicsInfo = &getGraphicsInfo,
            },
        };
    }

    fn measureText(
        context: *anyopaque,
        text: []const u8,
        font_handle: cu.State.FontHandle,
    ) mt.Size(f32) {
        const cb: *CuCallbacks = @ptrCast(@alignCast(context));

        const font_face: *FontFace = @alignCast(@ptrCast(font_handle));

        // @TODO: It might be work caching this for later use in rendering

        const font_atlas = cb.renderer.font_atlas_manager.getAtlas(font_face);

        const shaped = cb.renderer.batch_processor.shaper
            .shape(font_face, font_atlas, text) catch
            @panic("failed to shape text");

        const size = shaped.calculateSize(cb.gpa) catch @panic("oom");
        return .size(size.width, size.height);
    }

    fn fontSize(context: *anyopaque, font_handle: cu.State.FontHandle) f32 {
        _ = context;
        const font_face: *FontFace = @alignCast(@ptrCast(font_handle));
        return font_face.line_height;
    }

    fn getGraphicsInfo(context: *anyopaque) cu.State.GraphicsInfo {
        _ = context;

        const builtin = @import("builtin");
        return switch (builtin.os.tag) {
            .linux => .{
                // linux does not supply a cohesive api for a double click time
                // there is something in dbus/gnome, but its not widely used
                .double_click_time_us = 500 * std.time.us_per_ms,
            },
            .windows => {
                @compileError("TODO: use windows apis to get info");
                // see: https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-getdoubleclicktime
            },
            .macos => {
                @compileError("TODO: use macos apis to get info");
                // see: https://stackoverflow.com/questions/21935842/os-x-double-click-speed
            },
            else => @compileError("platform unsupported at present"),
        };
    }
};

//= render pass data

pub const RenderPassData = struct {
    atlas_texture: *wgpu.Texture,
    atlas_texture_view: *wgpu.TextureView,
    atlas_texture_sampler: *wgpu.Sampler,
    atlas_texture_bind_group: *wgpu.BindGroup,

    rect_buffer: *wgpu.Buffer,
    rect_buffer_count: u32,

    pub fn init(
        device: *wgpu.Device,
        queue: *wgpu.Queue,
        texture_bind_group_layout: *wgpu.BindGroupLayout,
        font_atlas_texture: FontAtlas.TextureDataRef,
        rect_buffer_data: []const RectInstance,
    ) !RenderPassData {
        //- create texture
        const atlas_texture_size = wgpu.Extent3D{
            .width = font_atlas_texture.size.width,
            .height = font_atlas_texture.size.height,
            .depth_or_array_layers = 1,
        };

        const atlas_texture_desc = wgpu.TextureDescriptor{
            .label = "font atlas",
            .usage = wgpu.TextureUsage.texture_binding |
                wgpu.TextureUsage.copy_dst,
            .dimension = .@"2d",
            .size = atlas_texture_size,
            .format = .r8_unorm,
        };
        const atlas_texture =
            device.createTexture(&atlas_texture_desc) orelse {
                log.err("Failed to create atlas texture", .{});
                return error.wgpu;
            };

        const atlas_texture_view = atlas_texture.createView(&.{
            .label = "atlas texture view",
        }) orelse {
            log.err("failed to create atlas texture view", .{});
            return error.wgpu;
        };
        const atlas_texture_sampler = device.createSampler(&.{
            .label = "atlas texture sampler",
            .mag_filter = .linear,
            .min_filter = .linear,
        }) orelse {
            log.err("failed to create atlas texture sampler", .{});
            return error.wgpu;
        };

        //- write texture
        queue.writeTexture(
            &.{
                .texture = atlas_texture,
                .origin = .{},
            },
            font_atlas_texture.bytes,
            font_atlas_texture.size.width *
                font_atlas_texture.size.height,
            &.{
                .offset = 0,
                .bytes_per_row = font_atlas_texture.size.width,
                .rows_per_image = font_atlas_texture.size.height,
            },
            &atlas_texture_size,
        );

        //- bind group
        const texture_bind_group_entry = wgpu.BindGroupEntry{
            .binding = 0,
            .texture_view = atlas_texture_view,
        };
        const sampler_bind_group_entry = wgpu.BindGroupEntry{
            .binding = 1,
            .sampler = atlas_texture_sampler,
        };

        const texture_bind_group_entries = [_]wgpu.BindGroupEntry{
            texture_bind_group_entry,
            sampler_bind_group_entry,
        };

        const atlas_texture_bind_group = device.createBindGroup(&.{
            .label = "atlas texture bind group",
            .layout = texture_bind_group_layout,
            .entry_count = texture_bind_group_entries.len,
            .entries = &texture_bind_group_entries,
        }) orelse {
            log.err("failed to create rect instance bind group", .{});
            return error.wgpu;
        };

        //- create rect buffer
        const rect_buffer = device.createBuffer(&.{
            .label = "rect instance buffer",
            .size = rect_buffer_data.len * @sizeOf(RectInstance),
            .usage = wgpu.BufferUsage.copy_dst |
                wgpu.BufferUsage.vertex,
            .mapped_at_creation = @intFromBool(false),
        }) orelse {
            log.err("failed to create rect instance buffer", .{});
            return error.wgpu;
        };

        //- write rect buffer
        queue.writeBuffer(
            rect_buffer,
            0,
            rect_buffer_data.ptr,
            rect_buffer.getSize(),
        );

        //- return

        return .{
            .atlas_texture = atlas_texture,
            .atlas_texture_view = atlas_texture_view,
            .atlas_texture_sampler = atlas_texture_sampler,
            .atlas_texture_bind_group = atlas_texture_bind_group,

            .rect_buffer = rect_buffer,
            .rect_buffer_count = @intCast(rect_buffer_data.len),
        };
    }

    pub fn deinit(data: RenderPassData) void {
        defer data.atlas_texture.release();
        defer data.atlas_texture_view.release();
        defer data.atlas_texture_sampler.release();
        defer data.atlas_texture_bind_group.release();

        defer data.rect_buffer.release();
    }
};

//= atlas manager

pub const FontAtlasManager = struct {
    ft_lib: *ft.Library,
    atlas_map: std.AutoHashMapUnmanaged(*FontFace, *FontAtlas) = .empty,

    pub fn init() !FontAtlasManager {
        const ft_lib = try ft.Library.init();
        return .{ .ft_lib = ft_lib };
    }

    pub fn deinit(self: *FontAtlasManager, gpa: Allocator) void {
        var iter = self.atlas_map.iterator();
        while (iter.next()) |entry| {
            const font_face = entry.key_ptr.*;
            font_face.deinit();
            gpa.destroy(font_face);

            const atlas = entry.value_ptr.*;
            atlas.deinit(gpa);
            gpa.destroy(atlas);
        }

        self.atlas_map.deinit(gpa);

        self.ft_lib.deinit();
    }

    pub fn initFontFace(
        self: *FontAtlasManager,
        gpa: Allocator,
        path: [:0]const u8,
        index: i32,
        pt_size: i32,
        dpi: mt.Point(u16),
    ) !*FontFace {
        const face = try gpa.create(FontFace);
        face.* = try FontFace.fromPath(self.ft_lib, path, index, pt_size, dpi);

        const atlas = try gpa.create(FontAtlas);
        atlas.* = try FontAtlas.init(face);

        // create a small white square at 0,0 for texture-less rects
        _ = try atlas.blit(gpa, .square(2), 0, &(.{255} ** (3 * 2 * 2)), 0);

        try atlas.cacheAscii(gpa);

        try self.atlas_map.put(gpa, face, atlas);

        return face;
    }

    pub fn getAtlas(
        self: *const FontAtlasManager,
        font_face: *const FontFace,
    ) *FontAtlas {
        // const cast since we don't actually modify it
        return self.atlas_map.get(@constCast(font_face)) orelse
            @panic("given font face not owned by this atlas manager");
    }
};

//= batch data

pub const BatchData = struct {
    font_face: *const FontFace,
    rects: []const RectInstance,
};

pub fn batchToRenderPass(
    renderer: *const Renderer,
    font_atlas_manager: *const FontAtlasManager,
    batch_data: BatchData,
) !RenderPassData {
    const font_atlas =
        font_atlas_manager.getAtlas(batch_data.font_face);

    const render_pass_data = try RenderPassData.init(
        renderer.device,
        renderer.queue,
        renderer.texture_bind_group_layout,
        font_atlas.textureDataRef(),
        batch_data.rects,
    );

    return render_pass_data;
}

// @TODO:
//  put non text rects all in one buffer
//  then put text rects into own buffer based on font used
//  this means we need an empty texture
pub const BatchProcessor = struct {
    font_atlas_manager: *const FontAtlasManager,
    batches: std.ArrayListUnmanaged(BatchData) = .empty,
    shaper: TextShaper,

    list: std.ArrayListUnmanaged(RectInstance) = .empty,
    font: ?*const FontFace = null,

    pub fn init(
        font_atlas_manager: *const FontAtlasManager,
    ) !BatchProcessor {
        const shaper = try TextShaper.init();
        return .{
            .font_atlas_manager = font_atlas_manager,
            .shaper = shaper,
        };
    }

    pub fn deinit(self: *BatchProcessor) void {
        self.shaper.deinit();
    }

    pub fn reset(self: *BatchProcessor) void {
        self.batches = .empty;
        self.list = .empty;
    }

    pub fn process(
        self: *BatchProcessor,
        arena: Allocator,
    ) ![]const BatchData {
        if (!cu.state.ui_built) return &[_]BatchData{};

        try self.processAtom(arena, cu.state.ui_root);

        const rects = try self.list.toOwnedSlice(arena);
        const batch = BatchData{
            .font_face = self.font orelse @panic(""),
            .rects = rects,
        };
        try self.batches.append(arena, batch);

        return self.batches.items;
    }

    pub fn processAtom(
        self: *BatchProcessor,
        arena: Allocator,
        atom: *cu.Atom,
    ) !void {
        if (std.math.isNan(atom.rect.p0.x) or
            std.math.isNan(atom.rect.p0.y) or
            std.math.isNan(atom.rect.p1.x) or
            std.math.isNan(atom.rect.p1.y))
        {
            return;
        }

        const rect = atom.rect;

        if (atom.flags.clip_rect) {
            // @TODO
        }

        if (atom.flags.draw_background) {
            const color = atom.palette.get(.background).toRgbaF32();
            try self.list.append(arena, .{
                .dst = rect,
                .color = color,
                .corner_radius = atom.corner_radius,
            });
        }

        if (atom.flags.draw_border) {
            const color = atom.palette.get(.border).toRgbaF32();
            try self.list.append(arena, .{
                .dst = rect,
                .color = color,
                .corner_radius = atom.corner_radius,
                .border_thickness = atom.border_width,
            });
        }

        if (atom.flags.draw_side_top) {
            const topleft = rect.topLeft();
            const topright = rect.topRight();

            const border_rect = mt.Rect(f32).rect(
                topleft,
                .point(topright.x, topright.y + atom.border_width),
            );

            const color = atom.palette.get(.border).toRgbaF32();
            try self.list.append(arena, .{
                .dst = border_rect,
                .color = color,
            });
        }

        if (atom.flags.draw_side_bottom) {
            const bottomleft = rect.bottomLeft();
            const bottomright = rect.bottomRight();

            const border_rect = mt.Rect(f32).rect(
                .point(bottomleft.x, bottomleft.y - atom.border_width),
                bottomright,
            );

            const color = atom.palette.get(.border).toRgbaF32();
            try self.list.append(arena, .{
                .dst = border_rect,
                .color = color,
            });
        }

        if (atom.flags.draw_side_left) {
            const topleft = rect.topLeft();
            const bottomleft = rect.bottomLeft();

            const border_rect = mt.Rect(f32).rect(
                topleft,
                .point(bottomleft.x + atom.border_width, bottomleft.y),
            );

            const color = atom.palette.get(.border).toRgbaF32();
            try self.list.append(arena, .{
                .dst = border_rect,
                .color = color,
            });
        }

        if (atom.flags.draw_side_right) {
            const topright = rect.topRight();
            const bottomright = rect.bottomRight();

            const border_rect = mt.Rect(f32).rect(
                .point(topright.x - atom.border_width, topright.y),
                bottomright,
            );

            const color = atom.palette.get(.border).toRgbaF32();
            try self.list.append(arena, .{
                .dst = border_rect,
                .color = color,
            });
        }

        const font_ptr = cu.state.getFont(atom.font);
        const font_face: *const FontFace = @ptrCast(@alignCast(font_ptr));

        self.font = font_face;

        if (atom.flags.draw_text or atom.flags.draw_text_weak) {
            const font_atlas = self.font_atlas_manager.getAtlas(font_face);

            const shaped_text = try self.shaper
                .shape(font_face, font_atlas, atom.display_string);

            const color = if (atom.flags.draw_text)
                atom.palette.get(.text).toRgbaF32()
            else if (atom.flags.draw_text_weak)
                atom.palette.get(.text_weak).toRgbaF32()
            else
                unreachable;

            try shaped_text.generateRects(
                arena,
                &self.list,
                atom.text_rect.p0,
                color,
            );
        }

        if (atom.children) |children| {
            var maybe_child: ?*cu.Atom = children.first;
            while (maybe_child) |child| : (maybe_child = child.siblings.next) {
                try self.processAtom(arena, child);
            }
        }
    }
};
