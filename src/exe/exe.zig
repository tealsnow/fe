const options = @import("options");

const builtin = @import("builtin");
const std = @import("std");
const Allocator = std.mem.Allocator;

const log = common.log.Scoped("exe");

const debug_mode = builtin.mode == .Debug;
const debugger_attached = options.debugger_attached;

const common = @import("common");
const out = common.out;
const tracy = common.tracy;
const sdl = common.sdl;
const fc = common.fc;
const ft = common.ft;
const hb = common.hb;
const wgpu = common.wgpu;
const wgpu_sdl = common.wgpu_sdl;
const imgui = common.imgui;

// const enable_vsync = true;
const enable_vsync = false;

const limit_framerate = true;
// const limit_framerate = false;

// FIXME: Keep all global state in one place
var dynlib_recompiled = false;
var dynlib_recompiling = false;

const sdlmem = @import("sdlmem.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{
        // .never_unmap = true,
        // .retain_metadata = true,

        // .verbose_log = true,
    }){};
    gpa.backing_allocator = std.heap.c_allocator;
    // const allocator = gpa.allocator();
    var tracing_allocator = tracy.TracingAllocator.initNamed("main", gpa.allocator());
    const allocator = tracing_allocator.allocator();
    defer {
        const status = gpa.deinit();
        if (status == .leak) {
            log.fatal(@src(), "Exited with memory leak");
        }
    }

    const level_filter = common.log.LevelFilter.trace;
    var console_logger = common.log.ConsoleLogger.new(level_filter);
    common.log.setup(.{
        .allocator = allocator,
        .level_filter = level_filter,
        .logger = console_logger.logger(),
    });

    const exit_code: ExitCode = run(allocator) catch |err| switch (err) {
        error.Sdl => blk: {
            log.fatalkv(
                @src(),
                "Fatal SDL error",
                .{ .err = sdl.getError() orelse "null" },
            );
            if (debug_mode)
                return err;
            break :blk .sdl;
        },
        else => blk: {
            log.fatalkv(
                @src(),
                "Fatal error",
                .{ .err = err },
            );
            if (debug_mode)
                return err;
            break :blk .general;
        },
    };

    exit_code.exit();
}

const ExitCode = enum(u8) {
    successful = 0,
    general = 1,
    sdl = 2,

    pub fn exit(self: ExitCode) noreturn {
        if (self == .successful)
            std.process.cleanExit();
        std.process.exit(@intFromEnum(self));
    }
};

fn run(allocator: Allocator) !ExitCode {
    const init_span = common.log.Span.start(@src(), .{
        .name = "init",
        .log = .{
            .level = .debug,
            .target = "exe",
        },
        .tracy = .{},
    });

    log.info(@src(), "starting application");
    defer log.info(@src(), "exiting application");

    if (debug_mode)
        log.info(@src(), "running in debug mode");

    if (std.valgrind.runningOnValgrind() > 0)
        log.info(@src(), "running under valgrind");

    if (debugger_attached)
        log.warn(
            @src(),
            "running with the assumption that a debugger will be attached",
        );

    log.debug(@src(), "installing signal handlers");
    try installSigaction();

    // const font_path = try fc.getFontForFamilyName(allocator, "arial");
    // // const font_path = try fc.getFontForFamilyName(allocator, "monospace");
    // // defer allocator.free(font_path);

    // log.tracekv(@src(), "got font", .{ .path = font_path });

    // var ft_lib: ft.FT_Library = undefined;
    // if (ft.FT_Init_FreeType(&ft_lib) != 0) return error.FtInit;
    // defer _ = ft.FT_Done_FreeType(ft_lib);
    // log.trace(@src(), "loaded truetype");

    // var ft_face: ft.FT_Face = undefined;
    // if (ft.FT_New_Face(ft_lib, font_path, 0, &ft_face) != 0)
    //     return error.FtNewFace;
    // defer _ = ft.FT_Done_Face(ft_face);
    // log.trace(@src(), "loaded truetype face");

    // allocator.free(font_path);

    // _ = ft.FT_Set_Pixel_Sizes(ft_face, 0, 24);

    // const hb_font = hb.hb_ft_font_create(@ptrCast(ft_face), null);
    // defer hb.hb_font_destroy(hb_font);
    // const hb_buffer = hb.hb_buffer_create();
    // defer hb.hb_buffer_destroy(hb_buffer);
    // log.trace(@src(), "setup hb");

    // NOTE(ketanr): I'm not sure if theres much need for this. The only
    //  usecase I can think of is just trying to so see and minimize
    //  allocations in our use of sdl. Time will tell
    //  Or using the arena allocator for sdl during the loop?
    // var sdl_tracing_allocator = tracy.TracingAllocator.initNamed("sdl", allocator);
    if (options.tracy_enable) {
        var sdl_tracing_allocator = tracy.TracingAllocator.initNamed(
            "sdl",
            std.heap.raw_c_allocator,
        );
        sdlmem.init(allocator);
        sdlmem.setAllocator(sdl_tracing_allocator.allocator());
    }

    log.debug(@src(), "initalizing sdl");
    try sdl.init(.{ .video = true, .events = true });
    defer sdl.quit();

    log.debug(@src(), "creating main window (starting hidden)");
    const main_window = try sdl.Window.init(.{
        .title = "fe",
        .position = .{
            .x = .centered,
            .y = .centered,
        },
        .size = .{ .w = 800, .h = 600 },
        .flags = sdl.Window.Flag.hidden | sdl.Window.Flag.allow_highdpi | sdl.Window.Flag.resizable,
    });
    defer main_window.deinit();

    log.debug(@src(), "creating test window (starting hidden)");
    const test_window = try sdl.Window.init(.{
        .title = "fe - aux window",
        .position = .{},
        .size = .{ .w = 800, .h = 600 },
        .flags = sdl.Window.Flag.hidden | sdl.Window.Flag.allow_highdpi | sdl.Window.Flag.resizable,
    });
    defer test_window.deinit();

    log.debug(@src(), "creating test window renderer");
    const test_renderer = try sdl.Renderer.init(.{
        .window = test_window,
        .flags = .{
            .present_vsync = false,
            .accelerated = true,
        },
    });
    defer test_renderer.deinit();

    log.debug(@src(), "initializing imgui");
    const imgui_context = imgui.c.igCreateContext(null);
    defer imgui.c.igDestroyContext(imgui_context);
    const io = imgui.c.igGetIO();
    io.*.ConfigFlags |= imgui.c.ImGuiConfigFlags_NavEnableKeyboard;
    io.*.ConfigFlags |= imgui.c.ImGuiConfigFlags_NavEnableGamepad;
    io.*.ConfigFlags |= imgui.c.ImGuiConfigFlags_DockingEnable;

    imgui.c.igStyleColorsDark(null);

    if (!imgui.impl_sdl2.c.ImGui_ImplSDL2_InitForSDLRenderer(@ptrCast(test_window), @ptrCast(test_renderer)))
        return error.imgui_sdl;
    defer imgui.impl_sdl2.c.ImGui_ImplSDL2_Shutdown();
    if (!imgui.impl_sdlrenderer2.c.ImGui_ImplSDLRenderer2_Init(@ptrCast(test_renderer)))
        return error.imgui_sdlrenderer;
    defer imgui.impl_sdlrenderer2.c.ImGui_ImplSDLRenderer2_Shutdown();

    // start wgpu setup

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
    const surface = try wgpu_sdl.createSurface(instance, main_window) orelse return error.sdlwgpu;
    defer surface.release();

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
    defer device.release();

    log.debug(@src(), "obtaining queue");
    const queue = device.getQueue() orelse return error.wgpu;
    defer queue.release();

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
    defer render_pipeline.release();

    log.debug(@src(), "configuring surface");
    var config = wgpu.SurfaceConfiguration{
        .device = device,
        .usage = wgpu.TextureUsage.render_attachment,
        .format = surface_capabilities.formats[0],

        // .present_mode = .fifo, // vsync
        // .present_mode = .immediate,
        // TODO: test to see if .fifo_relaxed may work better for vsync
        .present_mode = if (enable_vsync) .fifo else .immediate,

        .alpha_mode = surface_capabilities.alpha_modes[0],

        .width = 0,
        .height = 0,
    };

    {
        const window_size = main_window.size();
        config.width = @intCast(window_size.w);
        config.height = @intCast(window_size.h);
    }

    surface.configure(&config);
    log.debug(@src(), "finished wgpu setup");

    // end wgpu setup

    log.debug(@src(), "initializing dynlib");
    var dynlib = try Dynlib.load(allocator);
    defer dynlib.unload(allocator);
    dynlib.api.init(allocator);
    defer dynlib.api.deinit(allocator);

    var arena = std.heap.ArenaAllocator.init(std.heap.raw_c_allocator);
    // var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    var tracing_arena_allocator = tracy.TracingAllocator.initNamed("arena", arena.allocator());
    defer tracing_arena_allocator.discard();
    const arena_allocator = tracing_arena_allocator.allocator();

    // HACK: workaround for the memory tracing not getting the right timing
    //  information. Without it allocations are reported as being a long time
    //  before actuality
    //  probably a bug with the in-dev version of tracy I'm using
    _ = arena_allocator.alloc(u8, 1) catch {};

    const event_timeout_ms: u64 = if (limit_framerate) 16 else 0;

    const ns_60_fps: u64 = 16 * 1_000_000; // ns
    const ns_per_update = ns_60_fps;
    const ns_per_render =
        if (enable_vsync or !limit_framerate) 0 else ns_60_fps;

    var timer = try std.time.Timer.start();
    var update_lag: u64 = ns_per_update;
    var render_lag: u64 = ns_per_render;

    // the maxmimum amount of time a frame/update can be behind before we reset it
    const max_lag_multiple = 4;

    var fps_last_time = try std.time.Instant.now();
    var fps_frame_count: u32 = 0;

    var shown_arena_failed_reset = false;
    var shown_texture_suboptimal = false;
    var should_reload_dynlib = false;

    var running = true;

    var update_tick_count: u32 = 0;
    var render_frame_count: u32 = 0;

    var fps: f64 = 0;

    const old_log_alloc = common.log.global_state.allocator;
    common.log.global_state.allocator = arena_allocator;
    defer common.log.global_state.allocator = old_log_alloc;

    const deinit_span_options = common.log.Span.Options{
        .name = "deinit",
        .log = .{
            .level = .debug,
            .target = "exe",
        },
    };
    var deinit_span: ?common.log.Span = null;
    defer {
        if (deinit_span) |span| {
            _ = span.end(@src());
        }
    }

    main_window.show();
    test_window.show();

    _ = init_span.end(@src());
    log.debug(@src(), "initialization done");
    while (running) {
        tracy.frameMark();

        const elapsed = timer.lap();
        update_lag += elapsed;
        // wrapping add to avoid the cost of an if in the case that ns_per_render == 0
        render_lag +%= elapsed;

        // elapsed is measured in nano-seconds where sdl wants miliseconds
        const elapsed_ms = elapsed / 1_000_000;
        const timeout = @as(c_int, @intCast(event_timeout_ms -| elapsed_ms));
        if (sdl.Event.waitTimeout(timeout)) |ev| events_block: {
            const events_zone = tracy.initZone(@src(), .{ .name = "events" });
            defer events_zone.deinit();

            if (imgui.impl_sdl2.c.ImGui_ImplSDL2_ProcessEvent(@ptrCast(ev.original)))
                break :events_block;

            switch (ev.type) {
                .quit => {
                    log.debug(@src(), "quit event recived, quiting...");

                    running = false;
                    std.debug.assert(deinit_span == null);
                    deinit_span = common.log.Span.start(@src(), deinit_span_options);
                },

                .key => |key| key_block: {
                    if (key.state != .pressed)
                        break :key_block;
                    switch (key.keysym.sym) {
                        .q => {
                            log.info(@src(), "q pressed - quiting...");

                            sdl.Event.push(.quit);
                        },

                        .r => {
                            should_reload_dynlib = true;

                            shown_texture_suboptimal = false;
                            shown_arena_failed_reset = false;
                        },

                        .h => {
                            dynlib.api.greet("World");
                        },

                        .p => {
                            const counter = dynlib.api.getCounter();
                            log.tracef(@src(), "counter: {d}", .{counter});
                        },

                        else => {},
                    }
                },

                .window => |win| switch (win.event) {
                    .resized => {
                        if (win.windowID == main_window.getID()) {
                            const width = win.data1;
                            const height = win.data2;
                            config.width = @intCast(width);
                            config.height = @intCast(height);

                            surface.configure(&config);
                        }
                    },

                    .close => {
                        log.debugkv(
                            @src(),
                            "close request recieved",
                            .{ .window = win.windowID },
                        );

                        sdl.Event.push(.quit);
                    },

                    else => {},
                },

                else => {},
            }
        }

        while (update_lag >= ns_per_update) : (update_lag -|= ns_per_update) {
            const update_zone = tracy.initZone(@src(), .{ .name = "update" });
            defer update_zone.deinit();
            update_tick_count +%= 1;

            if (update_lag > ns_per_update * max_lag_multiple) {
                log.warnkv(
                    @src(),
                    "update loop too far behind, setting lag value to zero",
                    .{ .ns_per_update = ns_per_update, .was = update_lag },
                );
                update_lag = 0;
            }

            const delta_time_ns = elapsed;
            _ = delta_time_ns;

            if (should_reload_dynlib or dynlib_recompiled) {
                should_reload_dynlib = false;
                dynlib_recompiled = false;
                dynlib_recompiling = false;

                log.trace(@src(), "reloading dynlib...");
                defer log.trace(@src(), "reloading dynlib done");

                try dynlib.reload(allocator);
            }

            // TODO: Figure out if this is good place to put it
            //  or if it should be at the end of the loop
            //   (don't realy want it running as fast a possible)
            //  or if it should be in its own timestep
            //  or just stay here
            //
            // FIXME: Limit this accordingly!
            //  we should first figure out a good limit
            const area_reset_success = arena.reset(.retain_capacity);
            tracing_arena_allocator.discard();
            if (debug_mode and !area_reset_success and !shown_arena_failed_reset) {
                shown_arena_failed_reset = true;
                log.err(
                    @src(),
                    "arena reset failed. This is likely to happen again " ++
                        "so this message will not repeat. To reset this flag press r",
                );
            }
        }

        // FIXME: still using ~20% cpu at idle
        //  is there really that much overhead in wgpu?
        //  stays at ~0-1% if rendering is disabled
        while (render_lag >= ns_per_render) : (render_lag -|= ns_per_render) {
            const render_zone = tracy.initZone(@src(), .{ .name = "render" });
            defer render_zone.deinit();
            render_frame_count +%= 1;

            if (ns_per_render != 0 and render_lag >= ns_per_render * max_lag_multiple) {
                log.warnkv(
                    @src(),
                    "render loop too far behind, setting lag value to zero",
                    .{ .ns_per_update = ns_per_render, .was = render_lag },
                );
                render_lag = 0;
            }

            fps_frame_count += 1;
            const current_time = try std.time.Instant.now();
            const delta_time = current_time.since(fps_last_time);

            if (delta_time >= 1_000_000_000) {
                const delta_seconds = @as(f64, @floatFromInt(delta_time)) / 1_000_000_000;
                fps = @as(f64, @floatFromInt(fps_frame_count)) / delta_seconds;
                fps_frame_count = 0;
                fps_last_time = current_time;
            }

            { // imgui test window
                const imgui_zone = tracy.initZone(@src(), .{ .name = "imgui" });
                defer imgui_zone.deinit();

                imgui.impl_sdlrenderer2.c.ImGui_ImplSDLRenderer2_NewFrame();
                imgui.impl_sdl2.c.ImGui_ImplSDL2_NewFrame();
                imgui.c.igNewFrame();

                defer {
                    imgui.c.igRender();
                    _ = sdl.c.SDL_RenderSetScale(
                        @ptrCast(test_renderer),
                        io.*.DisplayFramebufferScale.x,
                        io.*.DisplayFramebufferScale.y,
                    );
                    test_renderer.setDrawColor(255, 255, 255, 255) catch {};
                    test_renderer.clear() catch {};
                    imgui.impl_sdlrenderer2.c.ImGui_ImplSDLRenderer2_RenderDrawData(
                        @ptrCast(imgui.c.igGetDrawData()),
                        @ptrCast(test_renderer),
                    );
                    test_renderer.present();
                }

                imgui.c.igShowDemoWindow(null);

                if (imgui.c.igBegin("my window", null, 0)) {
                    imgui.c.igText("fps: %.2f", fps);

                    const counter = dynlib.api.getCounter();
                    imgui.c.igText("counter: %d", counter);
                }
                imgui.c.igEnd();

                dynlib.api.doImgui();
            }

            var surface_texture: wgpu.SurfaceTexture = undefined;
            surface.getCurrentTexture(&surface_texture);
            defer surface_texture.texture.?.release();

            switch (surface_texture.status) {
                .success => {
                    // TODO: check surface_texture.suboptimal
                    if (!shown_texture_suboptimal and surface_texture.suboptimal != 0) {
                        // FIXME: triggers when using x11 backend for sdl
                        shown_texture_suboptimal = true;
                        log.warn(@src(), "surface texture is suboptimal");
                    }
                },
                .timeout, .outdated, .lost => {
                    log.infokv(
                        @src(),
                        "Recreating surface texture",
                        .{ .status = surface_texture.status },
                    );

                    if (surface_texture.texture) |texture|
                        texture.release();

                    const size = main_window.size();
                    if (size.w != 0 and size.h != 0) {
                        config.width = @intCast(size.w);
                        config.height = @intCast(size.h);
                        surface.configure(&config);
                    }
                    continue;
                },
                .out_of_memory, .device_lost => {
                    log.fatalkv(
                        @src(),
                        "fatal texture error",
                        .{ .status = surface_texture.status },
                    );
                    return error.wgpu;
                },
            }
            if (surface_texture.texture == null)
                return error.wgpu;

            const frame = surface_texture.texture.?
                .createView(&.{}) orelse return error.wgpu;
            defer frame.release();

            const command_encoder = device.createCommandEncoder(&.{
                .label = "Command encoder",
            }) orelse return error.wgpu;
            defer command_encoder.release();

            command_encoder.insertDebugMarker("my debug marker");

            const color = dynlib.api.getColor();
            const render_pass_encoder = command_encoder.beginRenderPass(&.{
                .label = "Render pass encoder",
                .color_attachment_count = 1,
                .color_attachments = &[_]wgpu.ColorAttachment{
                    wgpu.ColorAttachment{
                        .view = frame,
                        .load_op = .clear,
                        .store_op = .store,
                        .clear_value = .{
                            .r = @as(f64, @floatFromInt(color.r)) / 256,
                            .g = @as(f64, @floatFromInt(color.g)) / 256,
                            .b = @as(f64, @floatFromInt(color.b)) / 256,
                            .a = 1.0,
                        },
                    },
                },
            }) orelse return error.wgpu;

            render_pass_encoder.setPipeline(render_pipeline);
            render_pass_encoder.draw(3, 1, 0, 0);
            render_pass_encoder.end();
            render_pass_encoder.release();

            const command_buffer = command_encoder.finish(&.{
                .label = "Command buffer",
            }) orelse return error.wgpu;
            defer command_buffer.release();

            queue.submit(&[_]*const wgpu.CommandBuffer{command_buffer});
            surface.present();

            // =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-= //
            // ------------------------------- //
            // =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-= //

            // const color = dynlib.api.getColor();
            // renderer.setDrawColor(color.r, color.g, color.b, 255) catch {};
            // // renderer.setDrawColor(30, 30, 30, 255) catch {};
            // renderer.clear() catch {};

            // const x: c_uint = 20;
            // const y: c_uint = 20;
            // // const text = "Hello, (fe) World!";
            // const text = if (dynlib_recompiling)
            //     "reloading..."
            // else
            //     try std.fmt.allocPrint(
            //         arena_allocator,
            //         "{d}",
            //         .{render_frame_count},
            //     );

            // { // shaping
            //     hb.hb_buffer_reset(hb_buffer);
            //     hb.hb_buffer_add_utf8(
            //         hb_buffer,
            //         text.ptr,
            //         @intCast(text.len),
            //         0,
            //         -1,
            //     );
            //     hb.hb_buffer_guess_segment_properties(hb_buffer);

            //     hb.hb_shape(hb_font, hb_buffer, null, 0);
            // }

            // var glyph_count: c_uint = 0;
            // const glyph_info =
            //     hb.hb_buffer_get_glyph_infos(hb_buffer, &glyph_count);
            // const glyph_pos =
            //     hb.hb_buffer_get_glyph_positions(hb_buffer, &glyph_count);

            // const metrics = ft_face.*.size.*.metrics;
            // // Convert from 26.6 fixed point
            // // FIXME: I think this is a times 64?
            // const baseline = y + (metrics.ascender >> 6);

            // var pen_x = x;

            // var i: c_uint = 0;
            // while (i < glyph_count) : (i += 1) {
            //     _ = ft.FT_Load_Glyph(
            //         ft_face,
            //         glyph_info[i].codepoint,
            //         ft.FT_LOAD_RENDER,
            //     );
            //     const slot = ft_face.*.glyph;

            //     const glyph_surface = sdl.c.SDL_CreateRGBSurfaceFrom(
            //         slot.*.bitmap.buffer,
            //         @intCast(slot.*.bitmap.width),
            //         @intCast(slot.*.bitmap.rows),
            //         8,
            //         slot.*.bitmap.pitch,
            //         0,
            //         0,
            //         0,
            //         0,
            //     );
            //     defer sdl.c.SDL_FreeSurface(glyph_surface);

            //     var colors: [256]sdl.c.SDL_Color = undefined;
            //     var j: usize = 0;
            //     while (j < 256) : (j += 1) {
            //         colors[j].r = @intCast(j);
            //         colors[j].g = @intCast(j);
            //         colors[j].b = @intCast(j);
            //         colors[j].a = @intCast(j);
            //     }
            //     _ = sdl.c.SDL_SetPaletteColors(
            //         glyph_surface.*.format.*.palette,
            //         &colors,
            //         0,
            //         256,
            //     );

            //     const glyph_texture = sdl.c.SDL_CreateTextureFromSurface(
            //         @ptrCast(renderer),
            //         glyph_surface,
            //     );
            //     defer sdl.c.SDL_DestroyTexture(glyph_texture);

            //     // not too sure of this values sigificance
            //     const magic_scale = 64;

            //     const glyph_x: c_int = @as(c_int, @intCast(pen_x)) + @divFloor(glyph_pos[i].x_offset, magic_scale) + slot.*.bitmap_left;
            //     const glyph_y: c_int = @as(c_int, @intCast(baseline)) - slot.*.bitmap_top;

            //     const dest_rect = sdl.c.SDL_Rect{
            //         .x = glyph_x,
            //         .y = glyph_y,
            //         .w = @intCast(slot.*.bitmap.width),
            //         .h = @intCast(slot.*.bitmap.rows),
            //     };

            //     _ = sdl.c.SDL_RenderCopy(
            //         @ptrCast(renderer),
            //         glyph_texture,
            //         null,
            //         &dest_rect,
            //     );

            //     pen_x += @intCast(@divFloor(glyph_pos[i].x_advance, magic_scale));
            // }

            // renderer.present();

            if (ns_per_render == 0) break;
        }
    }

    return .successful;
}

pub const Dynlib = struct {
    lib: std.DynLib,
    api: common.Api,

    const Path = "zig-out/lib/libdynlib.so";

    pub fn load(allocator: Allocator) !Dynlib {
        var dynlib: Dynlib = undefined;
        try dynlib._load(allocator);
        return dynlib;
    }

    fn _load(dynlib: *Dynlib, allocator: Allocator) !void {
        const open_path = switch (builtin.os.tag) {
            // Windows locks open files, so it is a good idea to open a temp
            // copied file as to avoid any locks
            .windows => win_blk: {
                const original_path = Path;

                const last_dot = std.mem.lastIndexOf(u8, original_path, ".");
                const last_slash = std.mem.lastIndexOf(u8, original_path, "/");

                var temp_path_buf: [std.fs.MAX_PATH_BYTES]u8 = undefined;
                const temp_path = if (last_dot != null and (last_slash == null or last_dot.? > last_slash.?)) path_blk: {
                    const base = original_path[0..last_dot.?];
                    const ext = original_path[last_dot.?..];
                    break :path_blk try std.fmt.bufPrint(&temp_path_buf, "{s}_temp{s}", .{ base, ext });
                } else try std.fmt.bufPrint(&temp_path_buf, "{s}_temp", .{original_path});

                const source_file = try std.fs.cwd().openFile(original_path, .{});
                defer source_file.close();

                // create/overwite the tempfile
                const temp_file = try std.fs.cwd().createFile(temp_path, .{});
                defer temp_file.close();
                _ = try source_file.copyRangeAll(0, temp_file, 0, try source_file.getEndPos());

                break :win_blk temp_path;
            },
            else => Path,
        };

        dynlib.lib = try std.DynLib.open(open_path);
        errdefer dynlib.lib.close();

        try common.Api.load(&dynlib.lib, &dynlib.api);
        dynlib.api.onLoad(allocator, common.log.global_state);
    }

    pub fn unload(dynlib: *Dynlib, allocator: Allocator) void {
        dynlib.api.onUnload(allocator);
        dynlib.lib.close();
    }

    pub fn reload(dynlib: *Dynlib, allocator: Allocator) !void {
        const memory = dynlib.api.getMemory();
        dynlib.unload(allocator);
        try dynlib._load(allocator);
        dynlib.api.setMemory(memory);
    }
};

fn installSigaction() !void {
    const act = std.os.linux.Sigaction{
        .handler = .{ .handler = handleSignal },
        .mask = std.os.linux.empty_sigset,
        .flags = 0,
    };
    try trySigaction(std.os.linux.SIG.USR1, &act, null);
    try trySigaction(std.os.linux.SIG.USR2, &act, null);
}

fn trySigaction(
    sig: u6,
    noalias act: ?*const std.os.linux.Sigaction,
    noalias oact: ?*std.os.linux.Sigaction,
) !void {
    const res = std.os.linux.sigaction(sig, act, oact);
    if (res != 0) {
        const err = std.posix.errno(res);
        log.errkv(
            @src(),
            "Failed to setup sigaction",
            .{ .errno = err },
        );
        return error.Sigaction;
    }
}

fn handleSignal(sig: c_int) callconv(.C) void {
    switch (sig) {
        std.os.linux.SIG.USR1 => {
            log.info(
                @src(),
                "USR1: dynlib recompiled",
            );
            dynlib_recompiled = true;
        },
        std.os.linux.SIG.USR2 => {
            log.info(
                @src(),
                "USR2: dynlib recompiling",
            );
            dynlib_recompiling = true;
        },
        else => {
            log.warnkv(
                @src(),
                "Got unknown signal",
                .{ .sig = sig },
            );
        },
    }
}
