const std = @import("std");
const log = std.log.scoped(.@"cu::input");

const sdl = @import("sdl3");
const cu = @import("cu.zig");
const Atom = cu.Atom;

// @TODO: remove reliance on sdl
pub const Event = struct {
    kind: EventKind,
    timestamp_us: u64,
    consumed: bool,
};

pub const EventKind = union(enum) {
    key: KeyEvent,
    mouse_button: MouseButtonEvent,
    mouse_move: MouseMoveEvent,
    scroll: ScrollEvent,
    text: TextEvent,

    pub const KeyEvent = struct {
        scancode: sdl.Scancode,
        keycode: sdl.Keycode,
        mod: sdl.Keymod,
        state: PressState,
    };

    pub const MouseButtonEvent = struct {
        button: MouseButton,
        pos: cu.Vec2(f32),
        state: PressState,
    };

    pub const MouseMoveEvent = struct {
        pos: cu.Vec2(f32),
    };

    pub const ScrollEvent = struct {
        scroll: cu.Vec2(f32),
        pos: cu.Vec2(f32),
    };

    pub const TextEvent = struct {
        text: []const u8,
    };

    pub const PressState = enum(u8) {
        released = 0,
        pressed,
        none,
    };
};

pub const MouseButton = enum(u8) {
    none = std.math.maxInt(u8),
    left = 0,
    middle,
    right,
    forward,
    back,
    _,

    pub const array = [_]MouseButton{ .left, .middle, .right, .forward, .back };
};

pub const InteractionFlags = packed struct(u32) {
    const Self = @This();

    // mouse press -> atom pressed while hovering
    left_pressed: bool = false,
    middle_pressed: bool = false,
    right_pressed: bool = false,

    // released -> atom was pressed & released, in or out of bounds
    left_released: bool = false,
    middle_released: bool = false,
    right_released: bool = false,

    // clicked -> atom was pressed & released, in bounds
    left_clicked: bool = false,
    middle_clicked: bool = false,
    right_clicked: bool = false,

    // dragging -> atom was pressed, still holding
    left_dragging: bool = false,
    middle_dragging: bool = false,
    right_dragging: bool = false,

    // double clicked -> atom was clicked, pressed again
    left_double_clicked: bool = false,
    middle_double_clicked: bool = false,
    right_double_clicked: bool = false,

    // double dragging -> atom was double-clicked, still holding
    left_double_dragging: bool = false,
    middle_double_dragging: bool = false,
    right_double_dragging: bool = false,

    // triple clicked -> atom was double-clicked, pressed again
    left_triple_clicked: bool = false,
    middle_triple_clicked: bool = false,
    right_triple_clicked: bool = false,

    // triple dragging -> atom was triple-clicked, still holding
    left_triple_dragging: bool = false,
    middle_triple_dragging: bool = false,
    right_triple_dragging: bool = false,

    // keyboard pressed -> atom has focus, activated via keyboard
    keyboard_pressed: bool = false,

    hovering: bool = false, // hovering specifically over this atom
    mouse_over: bool = false, // mouse is over, but may be occluded

    _padding: enum(u5) { zero } = .zero,

    pub const pressed = InteractionFlags{
        .left_pressed = true,
        .keyboard_pressed = true,
    };

    pub const released = InteractionFlags{
        .left_released = true,
    };

    pub const clicked = InteractionFlags{
        .left_clicked = true,
        .keyboard_pressed = true,
    };

    pub const any_clicked = InteractionFlags{
        .left_clicked = true,
        .middle_clicked = true,
        .right_clicked = true,
        .keyboard_pressed = true,
    };

    pub const any_dragging = InteractionFlags{
        .left_dragging = true,
        .middle_dragging = true,
        .right_dragging = true,
        .keyboard_pressed = true,
    };

    inline fn asInt(self: Self) u32 {
        return @bitCast(self);
    }

    inline fn fromInt(value: u32) Self {
        return @bitCast(value);
    }

    inline fn bitOr(self: Self, other: Self) Self {
        return fromInt(self.asInt() | other.asInt());
    }

    inline fn bitAnd(self: Self, other: Self) Self {
        return fromInt(self.asInt() & other.asInt());
    }

    pub inline fn combine(self: Self, other: Self) Self {
        return bitOr(self, other);
    }

    pub inline fn containsAny(self: Self, other: Self) bool {
        return bitAnd(self, other).asInt() > 0;
    }

    pub inline fn isPressed(self: InteractionFlags) bool {
        return self.containsAny(.pressed);
    }

    pub inline fn isReleased(self: InteractionFlags) bool {
        return self.containsAny(.released);
    }

    pub inline fn isClicked(self: InteractionFlags) bool {
        return self.containsAny(.clicked);
    }

    pub inline fn isDoubleClicked(self: InteractionFlags) bool {
        return self.containsAny(.double_clicked);
    }

    pub inline fn isTripleClicked(self: InteractionFlags) bool {
        return self.containsAny(.triple_clicked);
    }

    pub inline fn isDragging(self: InteractionFlags) bool {
        return self.containsAny(.dragging);
    }

    pub inline fn buttonPressed(f: InteractionFlags, button: MouseButton) bool {
        return switch (button) {
            .left, .middle, .right => {
                const button_int: u5 = @intCast(@intFromEnum(button));
                const base_int: u32 = @bitCast(InteractionFlags{ .left_pressed = true });
                const f_int: u32 = @bitCast(f);
                return (f_int & (base_int << button_int)) != 0;
            },
            .back, .forward => false,
            else => false,
        };
    }
};

pub const Interation = struct {
    atom: *Atom,
    scroll: cu.Vec2(f32) = .zero,
    modifiers: sdl.Keymod = .{},
    f: InteractionFlags = .{},
};

fn setButtonGeneric(
    f: InteractionFlags,
    base: InteractionFlags,
    button: MouseButton,
) InteractionFlags {
    switch (button) {
        .left, .middle, .right => {
            const f_int: u32 = @bitCast(f);
            const base_int: u32 = @bitCast(base);
            const button_int: u5 = @intCast(@intFromEnum(button));
            return @bitCast(f_int | (base_int << button_int));
        },
        .back, .forward => return f, // @TODO
        else => return f,
    }
}

pub fn interactionFromAtom(atom: *Atom) Interation {
    var inter = Interation{ .atom = atom };

    var rect = atom.rect;

    // calculate possibly cliped rect
    var maybe_parent: ?*Atom = atom.parent;
    while (maybe_parent) |parent| : (maybe_parent = parent.parent) {
        if (parent.flags.clip_rect) {
            rect = rect.intersect(parent.rect);
        }
    }

    // determine if we're under the context menu or not
    maybe_parent = atom;
    const ctx_menu_is_ancestor = while (maybe_parent) |parent| : (maybe_parent = parent.parent) {
        if (parent == cu.state.ui_ctx_menu_root)
            break true;
    } else false;

    // calculate blacklist rectagele
    const blacklist_rect = if (!ctx_menu_is_ancestor and cu.state.ctx_menu_open)
        cu.state.ui_ctx_menu_root.rect
    else
        cu.Range2(f32).zero;

    var maybe_event = cu.state.event_list.first;
    while (maybe_event) |node| : (maybe_event = node.next) {
        const event = node.data;
        if (event.consumed) continue;

        const button = switch (event.kind) {
            .mouse_button => |button| button: {
                cu.state.mouse = button.pos;
                break :button button;
            },
            .mouse_move => |move| {
                cu.state.mouse = move.pos;
                continue;
            },
            else => {
                continue;
            },
        };

        const in_bounds = !blacklist_rect.contains(cu.state.mouse) and rect.contains(cu.state.mouse);
        const button_idx = @intFromEnum(button.button);

        // mouse down in box -> set box as hot/active -> press event
        if (atom.flags.mouse_clickable and
            button.state == .pressed and
            in_bounds and
            button.button != .none)
        {
            event.consumed = true;

            cu.state.hot_atom_key = atom.key;
            cu.state.active_atom_key[button_idx] = atom.key;

            cu.state.start_drag_pos = cu.state.mouse;

            inter.f = setButtonGeneric(inter.f, .{ .left_pressed = true }, button.button);

            const double_click_time_us = cu.state.graphics_info.double_click_time_us;

            const last_pressed_key =
                cu.state.press_history_key[button_idx].indexBack(0) orelse Atom.Key.nil;
            const last_pressed_timestamp_us =
                cu.state.press_history_timestamp_us[button_idx].indexBack(0) orelse std.math.maxInt(u64);

            if (Atom.Key.eql(atom.key, last_pressed_key) and
                event.timestamp_us - last_pressed_timestamp_us <= double_click_time_us)
            {
                inter.f = setButtonGeneric(inter.f, .{ .left_double_clicked = true }, button.button);
            }

            const last_last_pressed_key =
                cu.state.press_history_key[button_idx].indexBack(1) orelse Atom.Key.nil;
            const last_last_pressed_timestamp_us =
                cu.state.press_history_timestamp_us[button_idx].indexBack(1) orelse std.math.maxInt(u64);

            if (Atom.Key.eql(atom.key, last_pressed_key) and
                Atom.Key.eql(atom.key, last_last_pressed_key) and
                event.timestamp_us - last_pressed_timestamp_us <= double_click_time_us and
                last_pressed_timestamp_us - last_last_pressed_timestamp_us <= double_click_time_us)
            {
                inter.f = setButtonGeneric(inter.f, .{ .left_triple_clicked = true }, button.button);
            }

            cu.state.press_history_timestamp_us[button_idx].push(event.timestamp_us);
            cu.state.press_history_key[button_idx].push(atom.key);
        }

        // mouse in/out release in box -> unset as active -> release (and maybe click) event
        if (atom.flags.mouse_clickable and
            button.state == .released and
            button.button != .none and
            cu.state.active_atom_key[button_idx].eql(atom.key))
        {
            cu.state.active_atom_key[button_idx] = .nil;

            const click = in_bounds;
            if (click) cu.state.hot_atom_key = .nil;

            inter.f = setButtonGeneric(inter.f, .{ .left_released = true }, button.button);
            if (click)
                inter.f = setButtonGeneric(inter.f, .{ .left_clicked = true }, button.button);

            event.consumed = true;
        }
    }

    if (rect.contains(cu.state.mouse) and !blacklist_rect.contains(cu.state.mouse)) {
        inter.f.mouse_over = true;
    }

    // mouse over atom, without any other hot key -> set hot, mark hovering
    {
        if (atom.flags.mouse_clickable and
            inter.f.mouse_over and
            (cu.state.hot_atom_key.eql(.nil) or cu.state.hot_atom_key.eql(atom.key)))
        {
            var none_active_or_we_are_active = true;
            for (cu.state.active_atom_key) |key| {
                none_active_or_we_are_active = none_active_or_we_are_active and (key == .nil or key.eql(atom.key));
            }
            if (none_active_or_we_are_active) {
                cu.state.hot_atom_key = atom.key;
                inter.f.hovering = true;
            }
        }
    }

    // active -> dragging
    if (atom.flags.mouse_clickable) {
        for (MouseButton.array) |button| {
            const idx = @intFromEnum(button);
            if (Atom.Key.eql(atom.key, cu.state.active_atom_key[idx]) or
                inter.f.buttonPressed(button))
            {
                inter.f = setButtonGeneric(inter.f, .{ .left_dragging = true }, button);
            }
        }
    }

    if (!ctx_menu_is_ancestor and inter.f.containsAny(.{ .left_pressed = true, .right_pressed = true, .middle_pressed = true })) {
        cu.ctxMenuClose();
    }

    return inter;
}
