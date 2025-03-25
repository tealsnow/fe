const std = @import("std");
const sdl = @import("sdl3");
const cu = @import("cu.zig");
const Atom = cu.Atom;

pub const Event = struct {
    kind: Kind,
    key: struct {
        scancode: sdl.Scancode,
        keycode: sdl.Keycode,
        mod: sdl.Keymod,
    } = .{
        .scancode = .unknown,
        .keycode = .unknown,
        .mod = .{},
    },
    button: MouseButton = .none,
    button_clicks: u8 = 0,
    state: PressState = .none,
    pos: cu.Vec2(f32) = .zero,
    scroll: cu.Vec2(f32) = .zero,
    text: []const u8 = "",

    consumed: bool = false,

    pub const Kind = enum {
        key_press, // key, state
        mouse_press, // button, button_clicks, state, pos
        mouse_move, // pos
        scroll, // scroll, pos
        text_input, // text
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

    pub const double_clicked = InteractionFlags{
        .left_double_clicked = true,
    };

    pub const triple_clicked = InteractionFlags{
        .left_triple_clicked = true,
    };

    pub const dragging = InteractionFlags{
        .left_dragging = true,
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
};

pub const Interation = struct {
    atom: *Atom,
    scroll: cu.Vec2(f32) = .zero,
    modifiers: sdl.Keymod = .{},
    f: InteractionFlags = .{},
};

pub fn interationFromAtom(atom: *Atom) Interation {
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

        switch (event.kind) {
            .mouse_press, .mouse_move => {
                cu.state.mouse = event.pos;
            },
            else => {},
        }

        const in_bounds = !blacklist_rect.contains(event.pos) and rect.contains(event.pos);

        // mouse down in box -> set box as 'active' -> press event
        if (atom.flags.mouse_clickable and
            event.state == .pressed and
            in_bounds and
            event.button != .none)
        {
            cu.state.hot_atom_key = atom.key;
            cu.state.active_atom_key = atom.key;

            switch (event.button) {
                .left => inter.f.left_pressed = true,
                .middle => inter.f.middle_pressed = true,
                .right => inter.f.right_pressed = true,
                .back => {},
                .forward => {},
                else => {},
            }

            // drag_start_pos = event.pos

            event.consumed = true;
        }

        // mouse in/out release in box -> unset as 'active' -> release (and maybe click) event
        if (atom.flags.mouse_clickable and
            event.state == .released and
            cu.state.active_atom_key.eql(atom.key) and
            event.button != .none)
        {
            cu.state.active_atom_key = .nil;

            const click = in_bounds;
            if (click)
                cu.state.hot_atom_key = .nil;

            switch (event.button) {
                .left => inter.f = inter.f.combine(.{ .left_released = true, .left_clicked = click }),
                .middle => inter.f = inter.f.combine(.{ .middle_released = true, .middle_clicked = click }),
                .right => inter.f = inter.f.combine(.{ .right_released = true, .right_clicked = click }),
                .back => {},
                .forward => {},
                else => {},
            }

            event.consumed = true;
        }
    }

    if (rect.contains(cu.state.mouse) and !blacklist_rect.contains(cu.state.mouse)) {
        inter.f.mouse_over = true;
    }

    // mouse over atom, without any other hot key -> set hot, mark hovering
    if (atom.flags.mouse_clickable and
        inter.f.mouse_over and
        (cu.state.hot_atom_key.eql(.nil) or cu.state.hot_atom_key.eql(atom.key)) and
        (cu.state.active_atom_key.eql(.nil) or cu.state.active_atom_key.eql(atom.key)))
    {
        cu.state.hot_atom_key = atom.key;
        inter.f.hovering = true;
    }

    if (!ctx_menu_is_ancestor and inter.f.containsAny(.{ .left_pressed = true, .right_pressed = true, .middle_pressed = true })) {
        cu.ctxMenuClose();
    }

    return inter;
}
