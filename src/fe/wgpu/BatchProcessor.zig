const BatchProcessor = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const log = std.log.scoped(.@"wgpu.BatchProcessor");

const FontFace = @import("FontFace.zig");
const FontManager = @import("FontManager.zig");
const TextShaper = @import("TextShaper.zig");
const RectInstance = @import("WgpuRenderer.zig").RectInstance;

const cu = @import("cu");
const mt = cu.math;

const tracy = @import("tracy");

font_manager: *const FontManager,
shaper: TextShaper,

surface_size: mt.Size(u32),
scissor_rect: mt.Rect(u32),
rect_list: std.ArrayListUnmanaged(RectInstance) = .empty,
text_lists: std.AutoHashMapUnmanaged(
    *const FontFace,
    std.ArrayListUnmanaged(RectInstance),
) = .empty,

batches: std.ArrayListUnmanaged(BatchData) = .empty,

pub fn init(
    font_manager: *const FontManager,
    surface_size: mt.Size(u32),
) !BatchProcessor {
    const shaper = try TextShaper.init();
    return .{
        .font_manager = font_manager,
        .shaper = shaper,
        .surface_size = surface_size,
        .scissor_rect = .fromBounds(.bounds(.zero, surface_size)),
    };
}

pub fn deinit(self: *BatchProcessor) void {
    self.shaper.deinit();
}

fn reset(
    self: *BatchProcessor,
) void {
    self.scissor_rect = .fromBounds(.bounds(.zero, self.surface_size));
    self.rect_list = .empty;
    self.text_lists = .empty;
}

pub fn process(
    self: *BatchProcessor,
    arena: Allocator,
    surface_size: mt.Size(u32),
) ![]const BatchData {
    if (!cu.state.ui_built) return &[_]BatchData{};

    const trace =
        tracy.beginZone(@src(), .{ .name = "BatchProcessor.process" });
    defer trace.end();

    self.surface_size = surface_size;
    self.batches = .empty;
    self.reset();

    try self.processRoot(arena, cu.state.ui_root);
    try self.processRoot(arena, cu.state.ui_tooltip_root);

    return self.batches.items;
}

fn processRoot(
    self: *BatchProcessor,
    arena: Allocator,
    root: *cu.Atom,
) !void {
    try self.processAtom(arena, root);
    try self.flushBatches(arena);
}

fn flushBatches(self: *BatchProcessor, arena: Allocator) !void {
    try self.batches.ensureUnusedCapacity(arena, self.text_lists.size + 1);

    if (self.rect_list.items.len != 0)
        self.batches.appendAssumeCapacity(.{
            .scissor_rect = self.scissor_rect,
            .font_face = null,
            .rects = self.rect_list.items,
        });

    var iter = self.text_lists.iterator();
    while (iter.next()) |entry| {
        if (entry.value_ptr.items.len == 0) continue;
        self.batches.appendAssumeCapacity(.{
            .scissor_rect = self.scissor_rect,
            .font_face = entry.key_ptr.*,
            .rects = entry.value_ptr.items,
        });
    }

    self.reset();
}

fn processAtom(
    self: *BatchProcessor,
    arena: Allocator,
    atom: *cu.Atom,
) !void {
    if (std.math.isNan(atom.rect.p0.x) or
        std.math.isNan(atom.rect.p0.y) or
        std.math.isNan(atom.rect.p1.x) or
        std.math.isNan(atom.rect.p1.y))
    {
        return;
    }

    const trace =
        tracy.beginZone(@src(), .{ .name = "BatchProcessor.processAtom" });
    defer trace.end();

    const rect = atom.rect;

    if (atom.flags.contains(.clip_rect)) {
        try self.flushBatches(arena);

        self.scissor_rect = rect.round().intFromFloat(u32);
    }
    defer if (atom.flags.contains(.clip_rect)) {
        self.flushBatches(arena) catch {
            // @FIXME: maybe we should just put this at the end with a try?
            log.err("failed to flush batches for cliped rect", .{});
        };
    };

    if (atom.flags.contains(.draw_background)) {
        const color = atom.palette.get(.background).toRgbaF32();
        try self.rect_list.append(arena, .{
            .dst = rect,
            .color = color,
            .corner_radius = atom.corner_radius,
        });
    }

    if (atom.flags.contains(.draw_border)) {
        const color = atom.palette.get(.border).toRgbaF32();
        try self.rect_list.append(arena, .{
            .dst = rect,
            .color = color,
            .corner_radius = atom.corner_radius,
            .border_thickness = atom.border_width,
        });
    }

    if (atom.flags.contains(.draw_side_top)) {
        const topleft = rect.topLeft();
        const topright = rect.topRight();

        const border_rect = mt.Rect(f32).rect(
            topleft,
            .point(topright.x, topright.y + atom.border_width),
        );

        const color = atom.palette.get(.border).toRgbaF32();
        try self.rect_list.append(arena, .{
            .dst = border_rect,
            .color = color,
        });
    }

    if (atom.flags.contains(.draw_side_bottom)) {
        const bottomleft = rect.bottomLeft();
        const bottomright = rect.bottomRight();

        const border_rect = mt.Rect(f32).rect(
            .point(bottomleft.x, bottomleft.y - atom.border_width),
            bottomright,
        );

        const color = atom.palette.get(.border).toRgbaF32();
        try self.rect_list.append(arena, .{
            .dst = border_rect,
            .color = color,
        });
    }

    if (atom.flags.contains(.draw_side_left)) {
        const topleft = rect.topLeft();
        const bottomleft = rect.bottomLeft();

        const border_rect = mt.Rect(f32).rect(
            topleft,
            .point(bottomleft.x + atom.border_width, bottomleft.y),
        );

        const color = atom.palette.get(.border).toRgbaF32();
        try self.rect_list.append(arena, .{
            .dst = border_rect,
            .color = color,
        });
    }

    if (atom.flags.contains(.draw_side_right)) {
        const topright = rect.topRight();
        const bottomright = rect.bottomRight();

        const border_rect = mt.Rect(f32).rect(
            .point(topright.x - atom.border_width, topright.y),
            bottomright,
        );

        const color = atom.palette.get(.border).toRgbaF32();
        try self.rect_list.append(arena, .{
            .dst = border_rect,
            .color = color,
        });
    }

    if (atom.flags.contains(.draw_text) or
        atom.flags.contains(.draw_text_weak))
    {
        const font_ptr = cu.state.getFont(atom.font);
        const font_face: *const FontFace = @ptrCast(@alignCast(font_ptr));

        const entry =
            try self.text_lists.getOrPutValue(arena, font_face, .empty);

        const font_atlas = self.font_manager.getAtlas(font_face);

        const shaped_text = try self.shaper
            .shape(font_face, font_atlas, atom.display_string);

        const color = if (atom.flags.contains(.draw_text_weak))
            atom.palette.get(.text_weak).toRgbaF32()
        else if (atom.flags.contains(.draw_text))
            atom.palette.get(.text).toRgbaF32()
        else
            unreachable;

        try shaped_text.generateRects(
            arena,
            entry.value_ptr,
            atom.text_rect.p0,
            color,
        );
    }

    if (atom.children) |children| {
        var maybe_child: ?*cu.Atom = children.first;
        while (maybe_child) |child| : (maybe_child = child.siblings.next) {
            try self.processAtom(arena, child);
        }
    }
}

pub const BatchData = struct {
    scissor_rect: mt.Rect(u32),
    font_face: ?*const FontFace,
    rects: []const RectInstance,
};
