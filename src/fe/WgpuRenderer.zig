const Renderer = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

const log = std.log.scoped(.@"wgpu renderer");

const Size = @import("math.zig").Size;

const wgpu = @import("wgpu");

surface: *wgpu.Surface,
surface_format: wgpu.TextureFormat,
device: *wgpu.Device,
queue: *wgpu.Queue,
pipeline: *wgpu.RenderPipeline,

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
    const adapter, const surface = try createAdapaterAndSurface(
        surface_descriptor_chain,
    );
    defer {
        log.debug("releasing adapter", .{});
        adapter.release();
    }

    //- inspect adapter
    if (inspect.adapter) |alloc| {
        log.debug("inspecting adapter", .{});
        try inspectAdapter(alloc, adapter);
    }

    //- device request
    log.debug("requesting device", .{});

    const device_response = adapter.requestDeviceSync(&.{
        .label = "fe device",
        .required_feature_count = 0,
        .required_limits = null,
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

    if (inspect.surface)
        inspectSurface(surface_caps);

    const surface_format = surface_caps.formats[0];
    log.debug("preffered surface format: {s}", .{@tagName(surface_format)});

    configureSurfaceBare(initial_size, device, surface, surface_format);

    const pipeline = try createPipeline(device, surface_format);

    return .{
        .surface = surface,
        .surface_format = surface_format,
        .device = device,
        .queue = queue,
        .pipeline = pipeline,
    };
}

pub fn deinit(renderer: Renderer) void {
    defer renderer.surface.unconfigure();
    defer renderer.queue.release();
    defer renderer.device.release();
    defer renderer.pipeline.release();
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

fn createPipeline(
    device: *wgpu.Device,
    surface_format: wgpu.TextureFormat,
) !*wgpu.RenderPipeline {
    //- create shader module
    log.debug("creating shader module", .{});

    const shader_code_desc = wgpu.ShaderModuleWGSLDescriptor{
        .code = @embedFile("triangle.wgsl"),
    };
    const shader_module =
        device.createShaderModule(&.{
            .next_in_chain = &shader_code_desc.chain,
        }) orelse {
            log.err("failed to create shader module", .{});
            return error.wgpu;
        };

    //- create pipline
    log.debug("creating pipeline", .{});

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

    const render_pipline_desc = wgpu.RenderPipelineDescriptor{
        .vertex = .{
            .module = shader_module,
            .entry_point = "vsMain",
        },
        .primitive = .{
            .topology = .triangle_list, // every 3 vertices are a tri
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
        .layout = null,
    };

    const pipeline =
        device.createRenderPipeline(&render_pipline_desc) orelse {
            log.debug("failed to create render pipeline", .{});
            return error.wgpu;
        };
    return pipeline;
}

pub fn reconfigure(renderer: Renderer, size: Size(u32)) void {
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
