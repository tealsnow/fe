// @TODO:
//   @[ ]: pointer gestures
//     https://wayland.app/protocols/pointer-gestures-unstable-v1
//     gonna wait until support has been around for a little longer
//
//   @[ ]: xdg-desktop-portal
//     @[x]: cursor theme and size
//     @[ ]: desktop theme / appearance
//     @[ ]: listen to changes

pub const Connection = @import("Connection.zig");
pub const Window = @import("Window.zig");

pub const CursorKind = @import("cursor_manager.zig").CursorKind;

pub const Event = @import("events.zig").Event;
pub const EventQueue = @import("events.zig").EventQueue;
