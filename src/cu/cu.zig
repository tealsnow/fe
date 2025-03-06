//! # Attribution
//!
//! Much of the design of this it taken from a series of blogs on UI by
//! Ryan Fleury (https://rfleury.com/i/146446067/ui-programming-series)
//! with some parts taken from the implementation of the ui layer of raddebugger
//! (https://github.com/EpicGamesExt/raddebugger) (Copyright (c) 2024 Epic Games Tools)

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const assert = std.debug.assert;

pub const Atom = @import("Atom.zig");
pub const Color = @import("color.zig").Color;
pub const layout = @import("layout.zig").layout;

pub const math = @import("math.zig");
pub usingnamespace math;
pub const builder = @import("builder.zig");
pub usingnamespace builder;
pub const input = @import("input.zig");
pub usingnamespace input;
pub const scope_locals = @import("scope_locals.zig");
pub usingnamespace scope_locals;

pub const State = @import("State.zig");

pub var state: State = undefined;
