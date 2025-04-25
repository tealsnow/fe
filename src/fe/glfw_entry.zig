const builtin = @import("builtin");

const std = @import("std");
const Allocator = std.mem.Allocator;
const log = std.log.scoped(.@"fe[glfw]");
const assert = std.debug.assert;

const glfw = @import("glfw");
const wgpu = @import("wgpu");

// const cu = @import("cu");

const mt = @import("math.zig");

const WgpuRenderer = @import("wgpu/WgpuRenderer.zig");

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

pub const Application = struct {
    window: glfw.Window,

    renderer: WgpuRenderer,

    pub fn init(gpa: Allocator) !Application {
        //- glfw init
        log.debug("initializing glfw", .{});

        const platform: glfw.PlatformType = switch (builtin.os.tag) {
            // .linux => if (glfw.platformSupported(.wayland)) .wayland else .x11,
            // .linux => .x11,
            .linux => .wayland,
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

        const init_window_size = mt.Size(u32).size(800, 600);

        const window = glfw.Window.create(
            init_window_size.width,
            init_window_size.height,
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

        const wgpu_linux_surface = blk: switch (glfw.getPlatform()) {
            .wayland => {
                const native = glfw.Native(.{ .wayland = true });

                const wl_display = native.getWaylandDisplay();
                const wl_surface = native.getWaylandWindow(window);
                const from_wl = wgpu.SurfaceDescriptorFromWaylandSurface{
                    .display = wl_display,
                    .surface = wl_surface,
                };

                break :blk wgpu.SurfaceDescriptor{
                    .next_in_chain = &from_wl.chain,
                    .label = "wayland surface",
                };
            },
            .x11 => {
                const native = glfw.Native(.{ .x11 = true });

                const x11_display = native.getX11Display();
                const x11_window = native.getX11Window(window);
                const from_xlib = wgpu.SurfaceDescriptorFromXlibWindow{
                    .display = x11_display,
                    .window = @intCast(x11_window),
                };

                break :blk wgpu.SurfaceDescriptor{
                    .next_in_chain = &from_xlib.chain,
                    .label = "x11 surface",
                };
            },
            else => @panic("unsupported platform"),
        };

        const renderer = try WgpuRenderer.init(
            wgpu_linux_surface,
            init_window_size,
            .{
                .adapter = gpa,
                .device = gpa,
                .surface = true,
            },
        );

        return .{
            .window = window,
            .renderer = renderer,
        };
    }

    pub fn deinit(app: *Application) void {
        app.renderer.deinit();
        app.window.destroy();
        glfw.terminate();
    }

    pub fn runLoop(app: *Application) !void {
        app.renderer.render();

        app.renderer.surface.present();
    }

    pub fn isRunning(app: *const Application) bool {
        return !app.window.shouldClose();
    }

    fn configureSurface(app: *const Application) void {
        const size = app.window.getSize();
        app.renderer.reconfigure(.size(size.width, size.height));
    }
};

fn glfwErrorCallback(code: glfw.ErrorCode, description: [:0]const u8) void {
    log.err("glfw error: code: {} -- {s}", .{ code, description });
}

fn keyCallback(
    window: glfw.Window,
    key: glfw.Key,
    scancode: i32,
    action: glfw.Action,
    mods: glfw.Mods,
) void {
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
