pub const c = @cImport({
    @cInclude("SDL3/SDL.h");
    @cInclude("SDL3_ttf/SDL_ttf.h");
});

pub const Error = error{sdl};

// Categories following: https://wiki.libsdl.org/SDL3/APIByCategory

//- Basics
// main
const init = @import("init.zig");
pub usingnamespace init;
// hints
// properies
const err = @import("err.zig");
pub usingnamespace err;
// log
// assert
// version

//- Video
const video = @import("video.zig");
pub usingnamespace video;
const render = @import("render.zig");
pub usingnamespace render;
const pixels = @import("pixels.zig");
pub usingnamespace pixels;
// blendmode
const rect = @import("rect.zig");
pub usingnamespace rect;
const surface = @import("surface.zig");
pub usingnamespace surface;
// clipboard
// vulkan
// metal
// camera

//- Input Events
const event = @import("event.zig");
pub usingnamespace event;
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
const stdinc = @import("stdinc.zig");
pub usingnamespace stdinc;
// guid
// misc

pub const ttf = @import("ttf.zig");
