const wgpu = @import("wgpu");
const sdl = @import("sdl.zig");

const log = @import("log.zig").Scoped("wgpu_sdl");

pub fn createSurface(instance: *wgpu.Instance, window: *sdl.Window) !?*wgpu.Surface {
    var info: sdl.c.SDL_SysWMinfo = undefined;
    sdl.c.SDL_GetVersion(&info.version);
    _ = sdl.c.SDL_GetWindowWMInfo(@ptrCast(window), &info);

    switch (info.subsystem) {
        sdl.c.SDL_SYSWM_X11 => {
            log.debug(@src(), "using x11 backend");

            const desc_x11 = wgpu.SurfaceDescriptorFromXlibWindow{
                .chain = .{
                    .next = null,
                    .s_type = .surface_descriptor_from_xlib_window,
                },
                .window = info.info.x11.window,
                .display = @ptrCast(info.info.x11.display),
            };

            const desc = wgpu.SurfaceDescriptor{
                .label = "X11 Surface Descriptor",
                .next_in_chain = @ptrCast(&desc_x11),
            };

            return instance.createSurface(&desc);
        },
        sdl.c.SDL_SYSWM_WAYLAND => {
            log.debug(@src(), "using wayland backend");

            const desc_wl = wgpu.SurfaceDescriptorFromWaylandSurface{
                .chain = .{
                    .next = null,
                    .s_type = .surface_descriptor_from_wayland_surface,
                },
                .display = @ptrCast(info.info.wl.display),
                .surface = @ptrCast(info.info.wl.surface),
            };

            const desc = wgpu.SurfaceDescriptor{
                .label = "Wayland Surface Descriptor",
                .next_in_chain = @ptrCast(&desc_wl),
            };

            return instance.createSurface(&desc);
        },
        else => {
            log.err(@src(), "using unsupported backend");
            return error.unsupported;
        },
    }
}
