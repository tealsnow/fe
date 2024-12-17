const options = @import("options");

const std = @import("std");

const common = @import("common");
const Api = common.Api;

const log = common.log.Scoped("dynlib");

const imgui = common.imgui.c;

const wgpu = common.wgpu;
const wgpu_sdl = common.wgpu_sdl;
const sdl = common.sdl;

comptime {
    Api.exportGetApi(getApi);
}

fn getApi(out_api: *Api) callconv(.C) void {
    out_api.* = .{
        .onLoad = &onLoad,
        .onUnload = &onUnload,

        .init = &init,
        .deinit = &deinit,

        .getMemory = &getMemory,
        .setMemory = &setMemory,

        .greet = &greet,

        .getCounter = &getCounter,

        .doImgui = &doImgui,

        .onUpdate = &onUpdate,
        .onRender = &onRender,

        .onResize = &onResize,
    };
}

const Memory = struct {
    counter: u32,

    window: *sdl.Window,
    render_state: RenderState,
};

var g_memory: *Memory = undefined;

fn onLoad(allocator: std.mem.Allocator, log_state: common.log.State) void {
    _ = allocator;

    common.log.setup(log_state);
    // log.debug(@src(), "onLoad");
}

fn onUnload(allocator: std.mem.Allocator) void {
    _ = allocator;

    // log.debug(@src(), "onUnload");
}

fn init(allocator: std.mem.Allocator, window: *sdl.Window) void {
    // log.debug(@src(), "init");
    g_memory = allocator.create(Memory) catch @panic("oom");
    g_memory.* = undefined;

    g_memory.counter = 0;
    g_memory.window = window;
    g_memory.render_state = RenderState.init(window) catch @panic("failed to init wgpu");
}

fn deinit(allocator: std.mem.Allocator) void {
    // log.debug(@src(), "deinit");
    allocator.destroy(g_memory);

    g_memory.render_state.deinit();
}

fn getMemory() *anyopaque {
    return @alignCast(@ptrCast(g_memory));
}

fn setMemory(memory: *anyopaque) void {
    g_memory = @alignCast(@ptrCast(memory));
}

fn greet(name: []const u8) void {
    log.tracef(@src(), "{d}: Hello, {s}!", .{ g_memory.counter, name });

    g_memory.counter += 1;
}

fn getCounter() u32 {
    return g_memory.counter;
}

fn doImgui() void {
    if (imgui.igBegin("dynlib window", null, 0)) {
        imgui.igText("This is window from dynlib -- dynamic (can change at runtime)");
        imgui.igText("count: %d", g_memory.counter);

        if (imgui.igSmallButton("incremnt counter")) {
            g_memory.counter += 1;
        }
    }
    imgui.igEnd();
}

fn onResize() void {
    const size = g_memory.window.size();
    g_memory.render_state.resize(@intCast(size.w), @intCast(size.h));
}

fn onUpdate() void {
    //
}

fn onRender() void {
    wgpuRender(&g_memory.render_state) catch |err| {
        log.fatalkv(@src(), "Fatal rendering error", .{ .err = err });
    };
}

pub const RenderState = struct {
    device: *wgpu.Device,
    surface: *wgpu.Surface,
    config: wgpu.SurfaceConfiguration,
    pipeline: *wgpu.RenderPipeline,
    queue: *wgpu.Queue,

    pub fn init(window: *sdl.Window) !RenderState {
        log.debug(@src(), "initializing wgpu");

        log.debug(@src(), "obtaining instance");
        const instance_desc = wgpu.InstanceDescriptor{
            .next_in_chain = null,
        };
        var instance_desc_extra = wgpu.InstanceExtras{
            .backends = wgpu.InstanceBackend.primary,
            .flags = 0,
            .dx12_shader_compiler = .undefined,
            .gles3_minor_version = .automatic,
        };
        const instance = wgpu.Instance.create(&instance_desc.withNativeExtras(&instance_desc_extra)) orelse return error.wgpu;
        defer instance.release();

        log.debug(@src(), "obtaining surface");
        const surface = try wgpu_sdl.createSurface(instance, window) orelse return error.sdlwgpu;

        log.debug(@src(), "obtaining adapter");
        const adapter_res = instance.requestAdapterSync(
            &.{ .power_preference = .low_power },
        );
        if (adapter_res.status != .success) return error.wgpu;
        const adapter = adapter_res.adapter.?;
        defer adapter.release();

        log.debug(@src(), "obtaining device");
        const device_res = adapter.requestDeviceSync(&.{
            .next_in_chain = null,
            .label = "My Device",
            .required_feature_count = 0,
            .required_features = null,
            .required_limits = null,
            .default_queue = .{
                .next_in_chain = null,
                .label = "Default Queue",
            },
        });
        if (device_res.status != .success) return error.wgpu;
        const device = device_res.device.?;

        log.debug(@src(), "obtaining queue");
        const queue = device.getQueue() orelse return error.wgpu;

        const shader_src =
            \\@vertex
            \\fn vs_main(@builtin(vertex_index) in_vertex_index: u32) -> @builtin(position) vec4<f32> {
            \\    let x = f32(i32(in_vertex_index) - 1);
            \\    let y = f32(i32(in_vertex_index & 1u) * 2 - 1);
            \\    return vec4<f32>(x, y, 0.0, 1.0);
            \\}
            \\
            \\@fragment
            \\fn fs_main() -> @location(0) vec4<f32> {
            \\    return vec4<f32>(1.0, 1.0, 1.0, 1.0);
            \\}
        ;

        log.debug(@src(), "creating shader");
        const shader_module = device.createShaderModule(&.{
            .label = "shader",
            .next_in_chain = @ptrCast(
                &wgpu.ShaderModuleWGSLDescriptor{
                    .chain = .{
                        .s_type = .shader_module_wgsl_descriptor,
                    },
                    .code = shader_src,
                },
            ),
        }) orelse return error.wgpu;
        defer shader_module.release();

        log.debug(@src(), "creating pipline layout");
        const pipeline_layout = device.createPipelineLayout(&.{
            .label = "Pipeline layout",
            .bind_group_layout_count = 0,
            .bind_group_layouts = &[_]*const wgpu.BindGroupLayout{},
        }) orelse return error.wgpu;
        defer pipeline_layout.release();

        const surface_capabilities = blk: {
            var caps: wgpu.SurfaceCapabilities = undefined;
            surface.getCapabilities(adapter, &caps);
            break :blk caps;
        };

        log.debug(@src(), "creating render pipline");
        const render_pipeline = device.createRenderPipeline(&.{
            .label = "Render pipeline",
            .layout = pipeline_layout,
            .vertex = .{
                .module = shader_module,
                .entry_point = "vs_main",
            },
            .fragment = &wgpu.FragmentState{
                .module = shader_module,
                .entry_point = "fs_main",
                .target_count = 1,
                .targets = &[_]wgpu.ColorTargetState{
                    wgpu.ColorTargetState{
                        .format = surface_capabilities.formats[0],
                        .write_mask = wgpu.ColorWriteMask.all,
                    },
                },
            },
            .primitive = .{
                .topology = .triangle_list,
            },
            .multisample = .{
                .count = 1,
                .mask = 0xFFFFFFFF,
            },
        }) orelse return error.wgpu;

        log.debug(@src(), "configuring surface");
        var config = wgpu.SurfaceConfiguration{
            .device = device,
            .usage = wgpu.TextureUsage.render_attachment,
            .format = surface_capabilities.formats[0],

            // .present_mode = .fifo, // vsync
            // .present_mode = .immediate,
            // TODO: test to see if .fifo_relaxed may work better for vsync
            .present_mode = if (options.enable_vsync) .fifo else .immediate,

            .alpha_mode = surface_capabilities.alpha_modes[0],

            .width = 0,
            .height = 0,
        };

        {
            const window_size = window.size();
            config.width = @intCast(window_size.w);
            config.height = @intCast(window_size.h);
        }

        surface.configure(&config);
        log.debug(@src(), "finished wgpu setup");

        return RenderState{
            .device = device,
            .surface = surface,
            .config = config,
            .pipeline = render_pipeline,
            .queue = queue,
        };
    }

    pub fn deinit(self: *const RenderState) void {
        self.surface.release();
        self.device.release();
        self.pipeline.release();
        self.queue.release();
    }

    pub fn resize(self: *RenderState, width: u32, height: u32) void {
        self.config.width = width;
        self.config.height = height;
        self.surface.configure(&self.config);
    }
};

fn wgpuRender(render_state: *RenderState) !void {
    var surface_texture: wgpu.SurfaceTexture = undefined;
    render_state.surface.getCurrentTexture(&surface_texture);
    defer surface_texture.texture.?.release();

    switch (surface_texture.status) {
        .success => {
            // TODO: check surface_texture.suboptimal
            // if (!shown_texture_suboptimal and surface_texture.suboptimal != 0) {
            //     // FIXME: triggers when using x11 backend for sdl
            //     shown_texture_suboptimal = true;
            //     log.warn(@src(), "surface texture is suboptimal");
            // }
        },
        .timeout, .outdated, .lost => {
            log.infokv(
                @src(),
                "Recreating surface texture",
                .{ .status = surface_texture.status },
            );

            if (surface_texture.texture) |texture|
                texture.release();

            const size = g_memory.window.size();
            if (size.w != 0 and size.h != 0) {
                render_state.resize(@intCast(size.w), @intCast(size.h));
            }
            return;
        },
        .out_of_memory, .device_lost => {
            log.fatalkv(
                @src(),
                "fatal texture error",
                .{ .status = surface_texture.status },
            );
            return error.out_of_memory_or_device_lost;
        },
    }
    if (surface_texture.texture == null)
        return error.surface_texture_is_null;

    const frame = surface_texture.texture.?
        .createView(&.{}) orelse return error.create_view;
    defer frame.release();

    const command_encoder = render_state.device.createCommandEncoder(&.{
        .label = "Command encoder",
    }) orelse return error.command_encoder;
    defer command_encoder.release();

    command_encoder.insertDebugMarker("my debug marker");

    const render_pass_encoder = command_encoder.beginRenderPass(&.{
        .label = "Render pass encoder",
        .color_attachment_count = 1,
        .color_attachments = &[_]wgpu.ColorAttachment{
            wgpu.ColorAttachment{
                .view = frame,
                .load_op = .clear,
                .store_op = .store,
                .clear_value = .{
                    .r = 0.1,
                    .g = 0.2,
                    .b = 0.2,
                    .a = 1.0,
                },
            },
        },
    }) orelse return error.render_pass_encoder;

    render_pass_encoder.setPipeline(render_state.pipeline);
    render_pass_encoder.draw(3, 1, 0, 0);
    render_pass_encoder.end();
    render_pass_encoder.release();

    const command_buffer = command_encoder.finish(&.{
        .label = "Command buffer",
    }) orelse return error.command_buffer;
    defer command_buffer.release();

    render_state.queue.submit(&[_]*const wgpu.CommandBuffer{command_buffer});
    render_state.surface.present();
}
