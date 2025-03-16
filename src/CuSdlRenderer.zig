const Renderer = @This();

const std = @import("std");
const fc = @import("fontconfig.zig");

const sdl = @import("sdl/sdl.zig");
const cu = @import("cu/cu.zig");

sdl_rend: *sdl.Renderer,
bg_color_stack: std.ArrayListUnmanaged(cu.Color) = .empty,

pub fn render(self: *Renderer) !void {
    defer self.bg_color_stack.clearAndFree(cu.state.alloc_temp);

    const color = cu.Color.hexRgb(0x000000);
    try self.bg_color_stack.append(cu.state.alloc_temp, color);
    defer _ = self.bg_color_stack.pop().?;

    try self.setDrawColor(color);
    try self.sdl_rend.clear();

    try self.renderAtom(cu.state.ui_root);

    self.sdl_rend.present();
}

fn setDrawColor(self: *Renderer, color: cu.Color) !void {
    try self.sdl_rend.setDrawColorT(sdlColorFromCuColor(color));
}

fn fillRect(self: *Renderer, rect: sdl.FRect) !void {
    try self.sdl_rend.fillRectF(&rect);
}

fn drawRect(self: *Renderer, rect: sdl.FRect) !void {
    try self.sdl_rend.drawRectF(&rect);
}

fn drawLine(self: *Renderer, p0: cu.Vec2(f32), p1: cu.Vec2(f32)) !void {
    try self.sdl_rend.drawLineF(p0.x, p0.y, p1.x, p1.y);
}

fn renderAtom(self: *Renderer, atom: *cu.Atom) !void {
    if (std.math.isNan(atom.rect.p0.x) or
        std.math.isNan(atom.rect.p0.y) or
        std.math.isNan(atom.rect.p1.x) or
        std.math.isNan(atom.rect.p1.y))
    {
        return;
    }

    const rect = sdlRectFromCuRect(atom.rect);

    if (atom.flags.clip_rect) {
        const view_bounds = sdl.Rect{
            .x = @intFromFloat(rect.x),
            .y = @intFromFloat(rect.y),
            .w = @intFromFloat(rect.w),
            .h = @intFromFloat(rect.h),
        };
        try self.sdl_rend.setClipRect(&view_bounds);
    }
    defer if (atom.flags.clip_rect) {
        self.sdl_rend.setClipRect(null) catch @panic("unset clip");
    };

    if (atom.flags.draw_background) {
        try self.bg_color_stack.append(cu.state.alloc_temp, atom.palette.background);

        try self.setDrawColor(atom.palette.background);
        try self.fillRect(rect);
    }
    defer if (atom.flags.draw_background) {
        _ = self.bg_color_stack.pop().?;
    };

    if (atom.flags.draw_text or atom.flags.draw_text_weak)
        try self.renderText(atom);

    if (atom.flags.draw_border) {
        try self.setDrawColor(atom.palette.border);
        try self.drawRect(rect);
    }

    if (atom.flags.draw_side_top) {
        try self.setDrawColor(atom.palette.border);
        try self.drawLine(atom.rect.topLeft(), atom.rect.topRight());
    }

    if (atom.flags.draw_side_bottom) {
        try self.setDrawColor(atom.palette.border);
        try self.drawLine(atom.rect.bottomLeft(), atom.rect.bottomRight());
    }

    if (atom.flags.draw_side_left) {
        try self.setDrawColor(atom.palette.border);
        try self.drawLine(atom.rect.topLeft(), atom.rect.bottomLeft());
    }

    if (atom.flags.draw_side_right) {
        try self.setDrawColor(atom.palette.border);
        try self.drawLine(atom.rect.topRight(), atom.rect.bottomRight());
    }

    if (atom.children) |children| {
        var maybe_child: ?*cu.Atom = children.first;
        while (maybe_child) |child| : (maybe_child = child.siblings.next) {
            try self.renderAtom(child);
        }
    }
}

fn renderText(self: *Renderer, atom: *cu.Atom) !void {
    const color =
        if (atom.flags.draw_text_weak)
            atom.palette.text_weak
        else if (atom.flags.draw_text)
            atom.palette.text
        else
            unreachable;

    const fonthandle = cu.state.font_manager.getFont(atom.font);
    const font: *FontHandle = @alignCast(@ptrCast(fonthandle));

    const zstring = try cu.state.alloc_temp.dupeZ(u8, atom.display_string);

    const surface = try font.ttf_font.renderTextLCD(
        zstring,
        sdlColorFromCuColor(color),
        sdlColorFromCuColor(self.bg_color_stack.getLast()),
    );
    defer surface.deinit();

    const texture = try self.sdl_rend.createTextureFromSurface(surface);
    defer texture.deinit();

    const dst_rect = sdlRectFromCuRect(atom.text_rect);

    try self.sdl_rend.renderCopyF(texture, null, &dst_rect);
}

fn sdlColorFromCuColor(color: cu.Color) sdl.Color {
    return @bitCast(color);
}

fn sdlRectFromCuRect(rect: cu.Range2(f32)) sdl.FRect {
    return sdl.FRect{
        .x = rect.p0.x,
        .y = rect.p0.y,
        .w = rect.p1.x - rect.p0.x,
        .h = rect.p1.y - rect.p0.y,
    };
}

pub const FontHandle = struct {
    ttf_font: *sdl.ttf.Font,
    ptsize: c_int,

    pub fn init(file: [*c]u8, ptsize: c_int) !FontHandle {
        return .{
            .ttf_font = try sdl.ttf.Font.open(file, ptsize),
            .ptsize = ptsize,
        };
    }

    pub fn deinit(self: *const FontHandle) void {
        self.ttf_font.close();
    }

    /// ensure fonconfig is initialized
    pub fn createFromFamilyName(allocator: std.mem.Allocator, family: [:0]const u8, ptsize: c_int) !*FontHandle {
        const path = try getFontPathFromFamilyName(allocator, family);
        defer allocator.free(path);

        const ptr = try allocator.create(FontHandle);
        ptr.* = try init(path, ptsize);
        return ptr;
    }

    pub fn destroy(self: *FontHandle, allocator: std.mem.Allocator) void {
        self.ttf_font.close();
        allocator.destroy(self);
    }

    pub fn setSize(self: *FontHandle, ptsize: c_int) !void {
        self.ptsize = ptsize;
        try self.ttf_font.setSize(ptsize);
    }

    /// Caller owns memory
    /// Returns the font for a generic family name such as sans, monospace or arial
    /// ensure fonconfig is initialized
    pub fn getFontPathFromFamilyName(allocator: std.mem.Allocator, family: [:0]const u8) ![:0]u8 {
        const pattern = try fc.Pattern.create();
        defer pattern.destroy();
        try pattern.addString(.family, family);
        try pattern.addBool(.outline, .true);

        const config = try fc.Config.getCurrent();
        try config.substitute(pattern, .pattern);
        fc.defaultSubsitute(pattern);

        const match = try fc.fontMatch(config, pattern);
        defer match.destroy();

        const path = try match.getString(.file, 0);
        return try allocator.dupeZ(u8, path);
    }
};

pub const Callbacks = struct {
    fn measureText(context: *anyopaque, text: []const u8, font_handle: cu.FontHandle) cu.Axis2(f32) {
        _ = context;
        const zstring = cu.state.alloc_temp.dupeZ(u8, text) catch @panic("oom");
        const font: *FontHandle = @alignCast(@ptrCast(font_handle));
        const w, const h = font.ttf_font.sizeTextTuple(zstring) catch @panic("failed to measure text");
        return .axis(@floatFromInt(w), @floatFromInt(h));
    }

    fn fontSize(context: *anyopaque, font_handle: cu.FontHandle) f32 {
        _ = context;
        const font: *FontHandle = @alignCast(@ptrCast(font_handle));
        return @floatFromInt(font.ptsize);
    }

    pub const vtable = cu.State.Callbacks.VTable{
        .measureText = &measureText,
        .fontSize = &fontSize,
    };

    pub const callbacks = cu.State.Callbacks{
        .context = undefined,
        .vtable = vtable,
    };
};
