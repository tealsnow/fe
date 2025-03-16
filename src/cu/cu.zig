//! # Attribution
//!
//! Much of the design of this it taken from a series of blogs on UI by
//! Ryan Fleury (https://rfleury.com/i/146446067/ui-programming-series)
//! with some parts taken from the implementation of the ui layer of raddebugger
//! (https://github.com/EpicGamesExt/raddebugger) (Copyright (c) 2024 Epic Games Tools)

const builtin = @import("builtin");
const std = @import("std");
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const assert = std.debug.assert;

pub const Atom = @import("Atom.zig");
pub const AtomFlags = Atom.Flags;
pub const Color = @import("color.zig").Color;
pub const layout = @import("layout.zig").layout;

const math = @import("math.zig");
pub usingnamespace math;
const builder = @import("builder.zig");
pub usingnamespace builder;
const input = @import("input.zig");
pub usingnamespace input;
const scope_locals = @import("scope_locals.zig");
pub usingnamespace scope_locals;
const font = @import("font.zig");
pub usingnamespace font;

pub const State = @import("State.zig");
pub var state: State = undefined;

pub fn debugAssert(ok: bool, comptime fmt: []const u8, args: anytype) void {
    if (builtin.mode == .Debug) {
        if (!ok) {
            std.log.err("assertion failure", .{});
            std.log.err(fmt, args);
            @panic("assertion failure");
        }
    }
}
