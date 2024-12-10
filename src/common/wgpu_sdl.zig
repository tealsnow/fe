const builtin = @import("builtin");

const wgpu = @import("wgpu");
const sdl = @import("sdl.zig");

const log = @import("log.zig").Scoped("wgpu_sdl");

pub fn createSurface(instance: *wgpu.Instance, window: *sdl.Window) !?*wgpu.Surface {
    var info: sdl.c.SDL_SysWMinfo = undefined;
    sdl.c.SDL_GetVersion(&info.version);
    _ = sdl.c.SDL_GetWindowWMInfo(@ptrCast(window), &info);

    switch (info.subsystem) {
        sdl.c.SDL_SYSWM_X11 => if (builtin.target.os.tag == .linux) {
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
        } else @panic("got X11 as sdl subsystem on non Linux platform"),
        sdl.c.SDL_SYSWM_WAYLAND => if (builtin.target.os.tag == .linux) {
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
        } else @panic("got Wayland as sdl subsystem on non Linux platform"),
        sdl.c.SDL_SYSWM_WINDOWS => if (builtin.target.os.tag == .windows) {
            const desc_win = wgpu.SurfaceDescriptorFromWindowsHWND{
                .chain = .{
                    .next = null,
                    .s_type = .surface_descriptor_from_wayland_surface,
                },
                .hwnd = info.info.win.window,
                .hinstance = info.info.win.hinstance,
            };

            const desc = wgpu.SurfaceDescriptor{
                .label = "Windows Surface Descriptor",
                .next_in_chain = @ptrCast(&desc_win),
            };

            return instance.createSurface(&desc);
        } else @panic("got Windows as sdl subsystem on non Windows platform"),
        sdl.c.SDL_SYSWM_COCOA => if (builtin.target.os.tag == .macos) {
            log.err(@src(), "TODO: implement cocoa support");
            return error.todo;

            // TODO: implment cocoa/macos support
            //  I mean just look at the code below, I don't even know if I can
            //  do this obj-c bullshit in zig, let alone debug it

            // NSWindow * nsWindow = info.info.cocoa.window;
            // [nsWindow.contentView setWantsLayer : YES];
            // id metalLayer = [CAMetalLayer layer];
            // [nsWindow.contentView setLayer : metalLayer];

            // WGPUSurfaceDescriptorFromMetalLayer surfaceDescriptorFromMetalLayer;
            // surfaceDescriptorFromMetalLayer.chain.next = 0;
            // surfaceDescriptorFromMetalLayer.chain.sType = WGPUSType_SurfaceDescriptorFromMetalLayer;
            // surfaceDescriptorFromMetalLayer.layer = metalLayer;

            // WGPUSurfaceDescriptor surfaceDescriptor;
            // surfaceDescriptor.label = 0;
            // surfaceDescriptor.nextInChain = (const WGPUChainedStruct*)&surfaceDescriptorFromMetalLayer;

            // return wgpuInstanceCreateSurface(instance, &surfaceDescriptor);
        } else @panic("got Cocoa as sdl subsystem on non OSX platform"),
        else => {
            log.err(@src(), "using unsupported sdl backend/platform");
            return error.unsupported;
        },
    }
}
