const Renderer = @This();

const builtin = @import("builtin");
const std = @import("std");

const fc = @import("fontconfig.zig");
const sdl = @import("sdl3");

const cu = @import("cu");
const math = cu.math;

const tracy = @import("tracy");

sdl_rend: *sdl.render.Renderer,
bg_color_stack: std.ArrayListUnmanaged(cu.math.RgbaU8) = .empty,

pub fn render(self: *Renderer) !void {
    if (!cu.state.ui_built) return;

    const trace = tracy.beginZone(@src(), .{ .name = "render" });
    defer trace.end();

    defer self.bg_color_stack.clearAndFree(cu.state.arena);

    const color = math.RgbaU8.hexRgb(0x000000);
    try self.bg_color_stack.append(cu.state.arena, color);
    defer _ = self.bg_color_stack.pop().?;

    try self.setDrawColor(color);
    try self.sdl_rend.clear();

    try self.renderAtom(cu.state.ui_root);

    try self.sdl_rend.present();
}

fn setDrawColor(self: *Renderer, color: math.RgbaU8) !void {
    try self.sdl_rend.setDrawColorT(sdlColorFromCuColor(color));
}

fn fillRect(self: *Renderer, rect: sdl.rect.FRect) !void {
    try self.sdl_rend.fillRect(&rect);
}

fn drawRect(self: *Renderer, rect: sdl.rect.FRect) !void {
    try self.sdl_rend.renderRect(&rect);
}

fn drawLine(self: *Renderer, p0: math.Point(f32), p1: math.Point(f32)) !void {
    try self.sdl_rend.renderLine(p0.x, p0.y, p1.x, p1.y);
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
        const view_bounds = sdl.rect.Rect{
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
        const background = atom.palette.get(.background);

        try self.bg_color_stack.append(cu.state.arena, background);

        try self.setDrawColor(background);
        try self.fillRect(rect);
    }
    defer if (atom.flags.draw_background) {
        _ = self.bg_color_stack.pop().?;
    };

    if (atom.flags.draw_text or atom.flags.draw_text_weak)
        try self.renderText(atom);

    if (atom.flags.draw_border) {
        try self.setDrawColor(atom.palette.get(.border));
        try self.drawRect(rect);
    }

    if (atom.flags.draw_side_top) {
        try self.setDrawColor(atom.palette.get(.border));
        try self.drawLine(atom.rect.topLeft(), atom.rect.topRight());
    }

    if (atom.flags.draw_side_bottom) {
        try self.setDrawColor(atom.palette.get(.border));
        try self.drawLine(atom.rect.bottomLeft(), atom.rect.bottomRight());
    }

    if (atom.flags.draw_side_left) {
        try self.setDrawColor(atom.palette.get(.border));
        try self.drawLine(atom.rect.topLeft(), atom.rect.bottomLeft());
    }

    if (atom.flags.draw_side_right) {
        try self.setDrawColor(atom.palette.get(.border));
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
            atom.palette.get(.text_weak)
        else if (atom.flags.draw_text)
            atom.palette.get(.text)
        else
            unreachable;

    const fonthandle = cu.state.getFont(atom.font);
    const font: *sdl.ttf.Font = @alignCast(@ptrCast(fonthandle));

    const surface = try font.renderTextLCD(
        atom.display_string,
        sdlColorFromCuColor(color),
        sdlColorFromCuColor(self.bg_color_stack.getLast()),
    );
    defer surface.deinit();

    const texture = try self.sdl_rend.createTextureFromSurface(surface);
    defer texture.deinit();

    const dst_rect = sdlRectFromCuRect(atom.text_rect);

    try self.sdl_rend.renderTexture(texture, null, &dst_rect);
}

fn sdlColorFromCuColor(color: math.RgbaU8) sdl.pixels.Color {
    return @bitCast(color);
}

fn sdlRectFromCuRect(rect: math.Rect(f32)) sdl.rect.FRect {
    return .{
        .x = rect.p0.x,
        .y = rect.p0.y,
        .w = rect.p1.x - rect.p0.x,
        .h = rect.p1.y - rect.p0.y,
    };
}

/// ensure fonconfig is initialized
pub fn createFontFromFamilyName(
    gpa: std.mem.Allocator,
    family: [:0]const u8,
    ptsize: f32,
) !*sdl.ttf.Font {
    const path = try getFontPathFromFamilyName(gpa, family);
    defer gpa.free(path);
    return try sdl.ttf.Font.open(path, ptsize);
}

/// Caller owns memory
/// Returns the font for a generic family name such as sans, monospace or arial
/// ensure fonconfig is initialized
pub fn getFontPathFromFamilyName(
    allocator: std.mem.Allocator,
    family: [:0]const u8,
) ![:0]u8 {
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

pub const Callbacks = struct {
    fn measureText(
        context: *anyopaque,
        text: []const u8,
        font_handle: cu.State.FontHandle,
    ) math.Size(f32) {
        _ = context;
        const font: *sdl.ttf.Font = @alignCast(@ptrCast(font_handle));
        const w, const h = font.getStringSize(text) catch
            @panic("failed to measure text");
        return .size(@floatFromInt(w), @floatFromInt(h));
    }

    fn fontSize(context: *anyopaque, font_handle: cu.State.FontHandle) f32 {
        _ = context;
        const font: *sdl.ttf.Font = @alignCast(@ptrCast(font_handle));
        return font.getSize() catch @panic("failed to get font size");
    }

    fn getGraphicsInfo(context: *anyopaque) cu.State.GraphicsInfo {
        _ = context;
        return switch (builtin.os.tag) {
            .linux => .{
                // linux does not supply a cohesive api for a double click time
                // there is something in dbus/gnome, but its not widely used
                .double_click_time_us = 500 * std.time.us_per_ms,
            },
            .windows => {
                @compileError("TODO: use windows apis to get info");
                // see: https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-getdoubleclicktime
            },
            .macos => {
                @compileError("TODO: use macos apis to get info");
                // see: https://stackoverflow.com/questions/21935842/os-x-double-click-speed
            },
            else => @compileError("platform unsupported at present"),
        };
    }

    pub const callbacks = cu.State.Callbacks{
        .context = undefined,
        .vtable = .{
            .measureText = &measureText,
            .fontSize = &fontSize,
            .getGraphicsInfo = &getGraphicsInfo,
        },
    };
};
