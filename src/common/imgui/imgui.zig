pub const c = @cImport({
    @cDefine("CIMGUI_DEFINE_ENUMS_AND_STRUCTS", "");
    @cInclude("cimgui.h");
});

pub const impl_sdl2 = @import("impl_sdl2.zig");
pub const impl_sdlrenderer2 = @import("impl_sdlrenderer2.zig");
