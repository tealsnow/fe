const std = @import("std");

const cu = @import("cu.zig");

pub const FontHandle = *anyopaque;
pub const FontId = enum(u32) { _ };

pub const FontManager = struct {
    list: std.ArrayListUnmanaged(FontHandle) = .empty,

    pub const empty = FontManager{};

    pub fn registerFont(self: *FontManager, font: FontHandle) FontId {
        const id: FontId = @enumFromInt(self.list.items.len);
        self.list.append(cu.state.gpa, font) catch @panic("oom");
        return id;
    }

    pub fn getFont(self: *const FontManager, id: FontId) FontHandle {
        return self.list.items[@intFromEnum(id)];
    }

    pub fn deinit(self: *FontManager) void {
        self.list.deinit(cu.state.gpa);
    }
};
