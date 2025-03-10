const Renderer = @This();

const std = @import("std");

const sdl = @import("sdl/sdl.zig");
const cu = @import("cu/cu.zig");

sdl_rend: *sdl.Renderer,
bg_color_stack: std.ArrayListUnmanaged(cu.Color) = .empty,
viewport_offset: cu.Vec2(f32) = .zero,

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
    // std.log.debug("rendering: {}", .{atom});

    if (std.math.isNan(atom.rect.p0.x) or
        std.math.isNan(atom.rect.p0.y) or
        std.math.isNan(atom.rect.p1.x) or
        std.math.isNan(atom.rect.p1.y))
    {
        return;
    }

    const rect = sdl.FRect{
        .x = atom.rect.p0.x - self.viewport_offset.x,
        .y = atom.rect.p0.y - self.viewport_offset.y,
        .w = atom.rect.p1.x - self.viewport_offset.x - atom.rect.p0.x,
        .h = atom.rect.p1.y - self.viewport_offset.y - atom.rect.p0.y,
    };

    // std.log.debug("-- rect: x: {}, y: {}, w: {}, h: {}", .{ rect.x, rect.y, rect.w, rect.h });

    if (atom.flags.clip_rect) {
        const view_bounds = sdl.Rect{
            .x = @intFromFloat(rect.x),
            .y = @intFromFloat(rect.y),
            .w = @intFromFloat(rect.w),
            .h = @intFromFloat(rect.h),
        };
        try self.sdl_rend.setViewport(&view_bounds);
        self.viewport_offset = self.viewport_offset.add(atom.rect.p0);
        try self.sdl_rend.setClipRect(&.{
            .x = 0,
            .y = 0,
            .w = view_bounds.w,
            .h = view_bounds.h,
        });
    }
    defer if (atom.flags.clip_rect) {
        self.sdl_rend.setViewport(null) catch @panic("unset viewport");
        self.viewport_offset = self.viewport_offset.sub(atom.rect.p0);
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

    try self.renderText(rect, atom);

    if (atom.flags.draw_border) {
        try self.setDrawColor(atom.palette.border);
        try self.drawRect(rect);
    }

    // try self.setDrawColor(@bitCast(@as(u32, 0xff0000ff)));
    // try self.drawRect(rect);

    if (atom.flags.draw_side_top) {
        try self.setDrawColor(atom.palette.border);
        // try self.sdl_rend.drawLineF(atom.rect.p0.x, atom.rect.p0.y, atom.rect.p1.x, atom.rect.p0.y);
        try self.drawLine(atom.rect.topLeft(), atom.rect.topRight());
    }

    if (atom.flags.draw_side_bottom) {
        try self.setDrawColor(atom.palette.border);
        // try self.sdl_rend.drawLineF(atom.rect.p0.x, atom.rect.p1.y, atom.rect.p1.x, atom.rect.p1.y);
        try self.drawLine(atom.rect.bottomLeft(), atom.rect.bottomRight());
    }

    if (atom.flags.draw_side_left) {
        try self.setDrawColor(atom.palette.border);
        // try self.sdl_rend.drawLineF(atom.rect.p0.x, atom.rect.p0.y, atom.rect.p0.x, atom.rect.p1.y);
        try self.drawLine(atom.rect.topLeft(), atom.rect.bottomLeft());
    }

    if (atom.flags.draw_side_right) {
        try self.setDrawColor(atom.palette.border);
        // try self.sdl_rend.drawLineF(atom.rect.p1.x, atom.rect.p0.y, atom.rect.p1.x, atom.rect.p1.y);
        try self.drawLine(atom.rect.topRight(), atom.rect.bottomRight());
    }

    if (atom.children) |children| {
        var maybe_child: ?*cu.Atom = children.first;
        while (maybe_child) |child| : (maybe_child = child.siblings.next) {
            try self.renderAtom(child);
        }
    }
}

fn renderText(self: *Renderer, rect: sdl.FRect, atom: *cu.Atom) !void {
    if (!(atom.flags.draw_text or atom.flags.draw_text_weak))
        return;

    const color =
        if (atom.flags.draw_text_weak)
            atom.palette.text_weak
        else if (atom.flags.draw_text)
            atom.palette.text
        else
            unreachable;

    const text_data = atom.text_data.?;
    const fonthandle = cu.state.font_manager.getFont(atom.font);
    const font: *FontHandle = @alignCast(@ptrCast(fonthandle));

    const surface = try font.ttf_font.renderTextLCD(
        text_data.zstring,
        sdlColorFromCuColor(color),
        sdlColorFromCuColor(self.bg_color_stack.getLast()),
    );
    defer surface.deinit();

    const texture = try self.sdl_rend.createTextureFromSurface(surface);
    defer texture.deinit();

    var dst_rect = switch (atom.text_align) {
        .left => sdl.FRect{
            .x = rect.x,
            .y = rect.y,
            .w = text_data.size.w,
            .h = text_data.size.h,
        },
        .center => sdl.FRect{
            .x = @floor(rect.x + (rect.w - text_data.size.w) / 2),
            .y = @floor(rect.y + (rect.h - text_data.size.h) / 2),
            .w = text_data.size.w,
            .h = text_data.size.h,
        },
        .right => sdl.FRect{
            .x = @floor(rect.x + rect.w - text_data.size.w),
            .y = @floor(rect.y + (rect.h - text_data.size.h) / 2),
            .w = text_data.size.w,
            .h = text_data.size.h,
        },
    };
    dst_rect.y += TextHeightPadding / 2;
    dst_rect.h -= TextHeightPadding;
    dst_rect.x += TextWidthPadding / 2;
    dst_rect.w -= TextWidthPadding;

    try self.sdl_rend.renderCopyF(texture, null, &dst_rect);
}

fn sdlColorFromCuColor(color: cu.Color) sdl.Color {
    return @bitCast(color);
}

const TextWidthPadding = 2;
const TextHeightPadding = 6;

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

    pub fn setSize(self: *FontHandle, ptsize: c_int) !void {
        self.ptsize = ptsize;
        try self.ttf_font.setSize(ptsize);
    }
};

pub const Callbacks = struct {
    fn measureText(context: *anyopaque, text: [:0]const u8, font_handle: cu.FontHandle) cu.Axis2(f32) {
        _ = context;
        const font: *FontHandle = @alignCast(@ptrCast(font_handle));
        const w, const h = font.ttf_font.sizeTextTuple(text) catch @panic("failed to measure text");
        return .axis(@floatFromInt(w + TextWidthPadding), @floatFromInt(h + TextHeightPadding));
    }

    pub const vtable = cu.State.Callbacks.VTable{
        .measureText = &measureText,
    };

    pub const callbacks = cu.State.Callbacks{
        .context = undefined,
        .vtable = vtable,
    };
};
