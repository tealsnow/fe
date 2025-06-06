//! # Attribution
//!
//! Much of the design of this it taken from a series of blogs on UI by
//! Ryan Fleury (https://rfleury.com/i/146446067/ui-programming-series)
//! with some parts taken from the implementation of the ui layer of raddebugger
//! (https://github.com/EpicGamesExt/raddebugger) (Copyright (c) 2024 Epic Games Tools)

const builtin = @import("builtin");
const std = @import("std");
const assert = std.debug.assert;

pub const Atom = @import("Atom.zig");
pub const AtomFlags = Atom.Flags;
pub const layout = @import("layout.zig").layout;
pub const State = @import("State.zig");
pub const FontHandle = State.FontHandle;
pub const FontKind = State.FontKind;
pub const FontKindMap = State.FontKindMap;
pub const PointerKind = State.PointerKind;
pub const math = @import("math.zig");
pub const builder = @import("builder.zig");
pub const input = @import("input.zig");
pub const Interaction = input.Interaction;
pub const CircleBuffer = @import("circle_buffer.zig").CircleBuffer;
pub const TreeMixin = @import("tree_mixin.zig").TreeMixin;

// const scope_locals = @import("scope_locals.zig");

pub var state: *State = undefined;

// @TODO: remove in favor of `if (builtin.mode == .Debug) {}`
pub fn debugAssert(ok: bool, comptime fmt: []const u8, args: anytype) void {
    if (builtin.mode == .Debug) {
        if (!ok) {
            std.log.err("assertion failure", .{});
            std.log.err(fmt, args);
            @panic("assertion failure");
        }
    }
}
