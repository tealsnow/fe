pub const c = @cImport({
    @cInclude("wayland-client.h");
    // @cInclude("wayland-client-core.h");
    // @cInclude("wayland-client-protocol.h");

    @cInclude("xdg-shell-client-protocal.h");
});

pub usingnamespace c;
