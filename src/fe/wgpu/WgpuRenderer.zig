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

const mt = @import("../math.zig");

pub const FontAtlas = @import("FontAtlas.zig");
pub const ShapedText = @import("ShapedText.zig");
pub const FontFace = @import("FontFace.zig");

const shader_code = @embedFile("rect.wgsl");

//= fields

surface: *wgpu.Surface,
surface_format: wgpu.TextureFormat,
device: *wgpu.Device,
queue: *wgpu.Queue,

pipeline_layout: *wgpu.PipelineLayout,
pipeline: *wgpu.RenderPipeline,

uniform: UniformData,
uniform_buffer: *wgpu.Buffer,

uniform_bind_group_layout: *wgpu.BindGroupLayout,
uniform_bind_group: *wgpu.BindGroup,

texture_bind_group_layout: *wgpu.BindGroupLayout,

//= methods

pub const InspectOptions = struct {
    instance: ?Allocator = null,
    adapter: ?Allocator = null,
    device: ?Allocator = null,
    surface: bool = false,
};

pub fn init(
    surface_descriptor: wgpu.SurfaceDescriptor,
    initial_surface_size: mt.Size(u32),
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

    configureSurfaceBare(
        initial_surface_size,
        device,
        surface,
        surface_format,
    );

    //- pipeline

    const uniform_bind_group_layout, //
    const texture_bind_group_layout, //
    const pipeline_layout, //
    const pipeline =
        try createPipeline(device, surface_format);

    //- uniform

    const uniform = UniformData{
        .surface_size_px = initial_surface_size.floatFromInt(f32),
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

    return .{
        .surface = surface,
        .surface_format = surface_format,
        .device = device,
        .queue = queue,

        .pipeline_layout = pipeline_layout,
        .pipeline = pipeline,

        .uniform = uniform,
        .uniform_buffer = uniform_buffer,

        .uniform_bind_group_layout = uniform_bind_group_layout,
        .uniform_bind_group = uniform_bind_group,

        .texture_bind_group_layout = texture_bind_group_layout,
    };
}

pub fn deinit(renderer: Renderer) void {
    defer renderer.surface.unconfigure();
    defer renderer.queue.release();
    defer renderer.device.release();

    defer renderer.pipeline_layout.release();
    defer renderer.pipeline.release();

    defer renderer.uniform_buffer.release();

    defer renderer.uniform_bind_group_layout.release();
    defer renderer.uniform_bind_group.release();

    defer renderer.texture_bind_group_layout.release();
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
            // .src_factor = .one,
            // .dst_factor = .one_minus_src_alpha,
            // .operation = .add,
        },
        .alpha = .{
            .src_factor = .zero,
            .dst_factor = .one,
            .operation = .add,
            // .src_factor = .one,
            // .dst_factor = .one_minus_src_alpha,
            // .operation = .add,
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

pub fn render(
    renderer: Renderer,
    render_pass_data: *const RenderPassData,
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
    render_pass_data: *const RenderPassData,
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
    pass_data: *const RenderPassData,
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
    defer pass.release();

    pass.setPipeline(renderer.pipeline);

    pass.setBindGroup(
        0,
        renderer.uniform_bind_group,
        0,
        null,
    );

    pass.setBindGroup(
        1,
        pass_data.atlas_texture_bind_group,
        0,
        null,
    );

    pass.setVertexBuffer(
        0,
        pass_data.rect_buffer,
        0,
        pass_data.rect_buffer.getSize(),
    );

    pass.draw(4, pass_data.rect_buffer_count, 0, 0);

    pass.end();
}

//= gpu types

pub const RectInstance = extern struct {
    dst: mt.Rect(f32),
    tex: mt.Rect(f32),
    color: mt.RgbaF32,
    corner_radius: f32,
    edge_softness: f32,
    border_thickness: f32,

    pub fn recti(
        dst: mt.Rect(f32),
        tex: mt.Rect(f32),
        color: mt.RgbaF32,
        corner_radius: f32,
        edge_softness: f32,
        border_thickness: f32,
    ) RectInstance {
        return .{
            .dst = dst,
            .tex = tex,
            .color = color,
            .corner_radius = corner_radius,
            .edge_softness = edge_softness,
            .border_thickness = border_thickness,
        };
    }
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
    fn measureText(
        context: *anyopaque,
        text: []const u8,
        font_handle: cu.State.FontHandle,
    ) cu.Axis2(f32) {
        _ = context;
        const font_face: *FontFace = @alignCast(@ptrCast(font_handle));

        // @TODO: It might be work caching this for later use in rendering
        const shaped = ShapedText.init(font_face, text) catch
            @panic("failed to shape text");
        defer shaped.deinit();

        const size = shaped.calculateSize().floatFromInt(f32);
        return .axis(size.width, size.height);
    }

    fn fontSize(context: *anyopaque, font_handle: cu.State.FontHandle) f32 {
        _ = context;
        const font_face: *FontFace = @alignCast(@ptrCast(font_handle));
        return @floatFromInt(font_face.lineHeight());
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

    pub const callbacks = cu.State.Callbacks{
        .context = undefined,
        .vtable = .{
            .measureText = &measureText,
            .fontSize = &fontSize,
            .getGraphicsInfo = &getGraphicsInfo,
        },
    };
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
            .format = .rgba8_unorm,
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
            .mag_filter = .nearest,
            .min_filter = .nearest,
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
                font_atlas_texture.size.height *
                4,
            &.{
                .offset = 0,
                .bytes_per_row = font_atlas_texture.size.width * 4,
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

pub const FontAtlasManager = struct {};

//=
// pub const BatchData = struct {
//     font_face: *FontFace,
//     rects: []const RectInstance,
// };
