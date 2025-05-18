pub const c = @cImport({
    @cInclude("SDL3/SDL.h");
    @cInclude("SDL3_ttf/SDL_ttf.h");
});

pub const Error = error{sdl};

// Categories following: https://wiki.libsdl.org/SDL3/APIByCategory

//- Basics
// main
pub const init = @import("init.zig");
// hints
// properies
pub const err = @import("err.zig");
// log
// assert
// version

//- Video
pub const video = @import("video.zig");
pub const render = @import("render.zig");
pub const pixels = @import("pixels.zig");
// blendmode
pub const rect = @import("rect.zig");
pub const surface = @import("surface.zig");
// clipboard
// vulkan
// metal
// camera

//- Input Events
pub const event = @import("event.zig");
// keyboard
// mouse
// joystick
// gamepad
// touch
// pen
// sensor
// hidpi

//- Force Feedback ("Haptic")
// haptic

//- Audio
// audio

//- GPU
// gpu

//- Threads
// thread
// mutex
// atomic

//- Time
// timer
// time

//- File I/O abstractions
// filesystem
// storage
// iostream
// asyncio

//- Platform and CPU Information
// platform
// cpuinfo
// intrin
// endian
// bits

//- Additional Functionality
// loadso
// process
// power
// messagebox
// dialog
// tray
// locale
// system
pub const stdinc = @import("stdinc.zig");
// guid
// misc

pub const ttf = @import("ttf.zig");
