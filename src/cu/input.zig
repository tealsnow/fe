const std = @import("std");
const log = std.log.scoped(.@"cu.input");

const cu = @import("cu.zig");
const math = cu.math;
const Atom = cu.Atom;

pub const Event = struct {
    kind: EventKind,
    timestamp_us: u64,
    consumed: bool,
};

pub const EventKind = union(enum) {
    key: KeyEvent,
    mouse_button: MouseButtonEvent,
    mouse_move: math.Point(f32),
    scroll: math.Point(f32),
    text: []const u8,

    pub const KeyEvent = struct {
        scancode: i32,
        keycode: Keycode,
        mod: Modifiers,
        state: PressState,
    };

    pub const MouseButtonEvent = struct {
        button: MouseButton,
        state: PressState,
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

    pub const array = [_]MouseButton{ .left, .middle, .right, .forward, .back };
};

pub const InteractionFlag = enum(u8) {
    left_pressed = 0,
    middle_pressed,
    right_pressed,

    left_released,
    middle_released,
    right_released,

    left_clicked,
    middle_clicked,
    right_clicked,

    left_dragging,
    middle_dragging,
    right_dragging,

    left_double_clicked,
    middle_double_clicked,
    right_double_clicked,

    left_double_dragging,
    middle_double_dragging,
    right_double_dragging,

    left_triple_clicked,
    middle_triple_clicked,
    right_triple_clicked,

    left_triple_dragging,
    middle_triple_dragging,
    right_triple_dragging,

    keyboard_pressed,

    hovering,
    mouse_over,

    pub fn fromButton(
        base: MouseButtonKind,
        button: MouseButton,
    ) ?InteractionFlag {
        switch (button) {
            .none, .forward, .back => return null,
            else => {},
        }

        const base_int: u8 = @intFromEnum(base);
        const inter_base_int = base_int * 3;

        const button_int: u8 = @intFromEnum(button);
        const inter_int = inter_base_int + button_int;

        return @enumFromInt(inter_int);
    }

    // must be kept up to date with InterationFlag
    pub const MouseButtonKind = enum(u8) {
        pressed = 0,
        released,
        clicked,
        dragging,
        double_clicked,
        double_dragging,
        tripple_clicked,
        tripple_dragging,
    };
};

pub const InteractionFlags = struct {
    enum_set: std.EnumSet(InteractionFlag),

    pub const none = InteractionFlags{ .enum_set = .{} };

    // mouse press -> atom pressed while hovering
    pub const left_pressed = initOne(.left_pressed);
    pub const middle_pressed = initOne(.middle_pressed);
    pub const right_pressed = initOne(.right_pressed);

    // released -> atom was pressed & released, in or out of bounds
    pub const left_released = initOne(.left_released);
    pub const middle_released = initOne(.middle_released);
    pub const right_released = initOne(.right_released);

    // clicked -> atom was pressed & released, in bounds
    pub const left_clicked = initOne(.left_clicked);
    pub const middle_clicked = initOne(.middle_clicked);
    pub const right_clicked = initOne(.right_clicked);

    // dragging -> atom was pressed, still holding
    pub const left_dragging = initOne(.left_dragging);
    pub const middle_dragging = initOne(.middle_dragging);
    pub const right_dragging = initOne(.right_dragging);

    // double clicked -> atom was clicked, pressed again
    pub const left_double_clicked = initOne(.left_double_clicked);
    pub const middle_double_clicked = initOne(.middle_double_clicked);
    pub const right_double_clicked = initOne(.right_double_clicked);

    // double dragging -> atom was double-clicked, still holding
    pub const left_double_dragging = initOne(.left_double_dragging);
    pub const middle_double_dragging = initOne(.middle_double_dragging);
    pub const right_double_dragging = initOne(.right_double_dragging);

    // triple clicked -> atom was double-clicked, pressed again
    pub const left_triple_clicked = initOne(.left_triple_clicked);
    pub const middle_triple_clicked = initOne(.middle_triple_clicked);
    pub const right_triple_clicked = initOne(.right_triple_clicked);

    // triple dragging -> atom was triple-clicked, still holding
    pub const left_triple_dragging = initOne(.left_triple_dragging);
    pub const middle_triple_dragging = initOne(.middle_triple_dragging);
    pub const right_triple_dragging = initOne(.right_triple_dragging);

    // keyboard pressed -> atom has focus, activated via keyboard
    pub const keyboard_pressed = initOne(.keyboard_pressed);

    // hovering specifically over this atom
    pub const hovering = initOne(.hovering);
    // mouse is over, but may be occluded
    pub const mouse_over = initOne(.mouse_over);

    pub const pressed = initMany(&.{
        .left_pressed,
        .keyboard_pressed,
    });

    pub const any_pressed = initMany(&.{
        .left_pressed,
        .right_pressed,
        .middle_pressed,
        .keyboard_pressed,
    });

    pub const released = initMany(&.{
        .left_released,
    });

    pub const clicked = initMany(&.{
        .left_clicked,
        .keyboard_pressed,
    });

    pub const any_clicked = initMany(&.{
        .left_clicked,
        .middle_clicked,
        .right_clicked,
        .keyboard_pressed,
    });

    pub const any_dragging = initMany(&.{
        .left_dragging,
        .middle_dragging,
        .right_dragging,
    });

    const Flags = InteractionFlags;
    const Flag = InteractionFlag;

    pub fn initMany(flags: []const Flag) Flags {
        return .{ .enum_set = .initMany(flags) };
    }

    pub fn initOne(flag: Flag) Flags {
        return .{ .enum_set = .initOne(flag) };
    }

    pub fn contains(flags: Flags, flag: Flag) bool {
        return flags.enum_set.contains(flag);
    }

    pub fn containsAny(flags: Flags, set: Flags) bool {
        var iter = set.enum_set.iterator();
        while (iter.next()) |flag| {
            if (flags.contains(flag))
                return true;
        }
        return false;
    }

    pub fn insert(flags: *Flags, flag: Flag) void {
        flags.enum_set.insert(flag);
    }

    pub fn remove(flags: *Flags, flag: Flag) void {
        flags.enum_set.remove(flag);
    }

    pub fn setPresent(flags: *Flags, flag: Flag, present: bool) void {
        flags.enum_set.setPresent(flag, present);
    }

    pub fn unionWith(flags: Flags, other: Flags) Flags {
        return .{ .enum_set = .unionWith(flags.enum_set, other.enum_set) };
    }
};

pub const Interaction = struct {
    atom: *Atom,
    scroll: math.Point(f32) = .zero,
    modifiers: Modifiers = .{},
    f: InteractionFlags = .none,

    pub fn pressed(self: Interaction) bool {
        return self.f.containsAny(.pressed);
    }

    pub fn anyPressed(self: Interaction) bool {
        return self.f.containsAny(.any_pressed);
    }

    pub fn released(self: Interaction) bool {
        return self.f.containsAny(.released);
    }

    pub fn clicked(self: Interaction) bool {
        return self.f.containsAny(.clicked);
    }

    pub fn anyClicked(self: Interaction) bool {
        return self.f.containsAny(.any_clicked);
    }

    pub fn doubleClicked(self: Interaction) bool {
        return self.f.containsAny(.left_double_clicked);
    }

    pub fn tripleClicked(self: Interaction) bool {
        return self.f.containsAny(.left_triple_clicked);
    }

    pub fn dragging(self: Interaction) bool {
        return self.f.containsAny(.left_dragging);
    }

    pub fn hovering(self: Interaction) bool {
        return self.f.contains(.hovering);
    }

    pub fn buttonPressed(self: Interaction, button: MouseButton) bool {
        const flag =
            InteractionFlag.fromButton(.pressed, button) orelse
            return false;
        return self.f.contains(flag);
    }
};

fn setButtonGeneric(
    f: *InteractionFlags,
    base: InteractionFlag.MouseButtonKind,
    button: MouseButton,
) void {
    const flag = InteractionFlag.fromButton(base, button) orelse return;
    f.insert(flag);
}

pub fn interactionFromAtom(atom: *Atom) Interaction {
    var inter = Interaction{ .atom = atom };

    // calculate possibly cliped rect
    const rect = blk: {
        var rect = atom.rect;
        var maybe_parent: ?*Atom = atom.parent;
        while (maybe_parent) |parent| : (maybe_parent = parent.parent) {
            if (parent.flags.contains(.clip_rect)) {
                rect = rect.intersect(parent.rect);
            }
        }
        break :blk rect;
    };

    // determine if we're under the context menu or not
    const ctx_menu_is_ancestor = blk: {
        var maybe_parent: ?*Atom = atom;
        break :blk while (maybe_parent) |parent| : (maybe_parent = parent.parent) {
            if (parent == cu.state.ui_ctx_menu_root)
                break true;
        } else false;
    };

    // calculate blacklist rectagele
    const blacklist_rect = if (!ctx_menu_is_ancestor and cu.state.ctx_menu_open)
        cu.state.ui_ctx_menu_root.rect
    else
        math.Rect(f32).zero;

    const in_bounds = !blacklist_rect.contains(cu.state.mouse) and
        rect.contains(cu.state.mouse);

    var i: usize = 0;
    while (i < cu.state.event_list.len) : (i += 1) {
        const event = &cu.state.event_list.buffer[i];
        if (event.consumed) continue;

        switch (event.kind) {
            .mouse_button => |button| {
                // mouse down in box -> set box as hot/active -> press event
                if (atom.flags.contains(.mouse_clickable) and
                    button.state == .pressed and
                    in_bounds and
                    button.button != .none)
                {
                    event.consumed = true;

                    cu.state.hot_atom_key = atom.key;
                    cu.state.active_atom_key.set(button.button, atom.key);

                    cu.state.start_drag_pos = cu.state.mouse;

                    setButtonGeneric(&inter.f, .pressed, button.button);

                    const double_click_time_us =
                        cu.state.graphics_info.double_click_time_us;

                    const last_pressed_key = cu.state.press_history_key
                        .get(button.button).indexBack(0) orelse
                        Atom.Key.nil;
                    const last_pressed_timestamp_us = cu.state.press_history_timestamp_us
                        .get(button.button).indexBack(0) orelse
                        std.math.maxInt(u64);

                    if (Atom.Key.eql(atom.key, last_pressed_key) and
                        event.timestamp_us -
                            last_pressed_timestamp_us <= double_click_time_us)
                    {
                        setButtonGeneric(&inter.f, .double_clicked, button.button);
                    }

                    const last_last_pressed_key = cu.state.press_history_key
                        .get(button.button).indexBack(1) orelse
                        Atom.Key.nil;
                    const last_last_pressed_timestamp_us =
                        cu.state.press_history_timestamp_us
                            .get(button.button)
                            .indexBack(1) orelse std.math.maxInt(u64);

                    if (Atom.Key.eql(atom.key, last_pressed_key) and
                        Atom.Key.eql(atom.key, last_last_pressed_key) and
                        event.timestamp_us - last_pressed_timestamp_us <=
                            double_click_time_us and
                        last_pressed_timestamp_us - last_last_pressed_timestamp_us <=
                            double_click_time_us)
                    {
                        setButtonGeneric(&inter.f, .tripple_clicked, button.button);
                    }

                    cu.state.press_history_timestamp_us
                        .getPtr(button.button)
                        .push(event.timestamp_us);
                    cu.state.press_history_key
                        .getPtr(button.button)
                        .push(atom.key);
                }

                // mouse in/out release in box -> unset as active -> release (and maybe click) event
                if (atom.flags.contains(.mouse_clickable) and
                    button.state == .released and
                    button.button != .none and
                    cu.state.active_atom_key.get(button.button).eql(atom.key))
                {
                    cu.state.active_atom_key.set(button.button, .nil);

                    const click = in_bounds;
                    if (click) cu.state.hot_atom_key = .nil;

                    setButtonGeneric(&inter.f, .released, button.button);
                    if (click)
                        setButtonGeneric(&inter.f, .clicked, button.button);

                    event.consumed = true;
                }
            },
            .mouse_move => |pos| {
                cu.state.mouse = pos;
            },
            .scroll => |pt| {
                if (in_bounds and atom.flags.contains(.view_scroll)) {
                    inter.scroll.x += pt.x;
                    inter.scroll.y += pt.y;
                    event.consumed = true;
                }
            },
            else => {},
        }
    }

    if (rect.contains(cu.state.mouse) and
        !blacklist_rect.contains(cu.state.mouse))
    {
        inter.f.insert(.mouse_over);
    }

    // mouse over atom, without any other hot key -> set hot, mark hovering
    {
        if (atom.flags.contains(.mouse_clickable) and
            inter.f.contains(.mouse_over) and
            (cu.state.hot_atom_key.eql(.nil) or
                cu.state.hot_atom_key.eql(atom.key)))
        {
            var none_active_or_we_are_active = true;
            for (cu.state.active_atom_key.values) |key| {
                none_active_or_we_are_active =
                    none_active_or_we_are_active and
                    (key == .nil or key.eql(atom.key));
            }
            if (none_active_or_we_are_active) {
                cu.state.hot_atom_key = atom.key;
                inter.f.insert(.hovering);
            }
        }
    }

    // active -> dragging
    if (atom.flags.contains(.mouse_clickable)) {
        for (MouseButton.array) |button| {
            if (Atom.Key.eql(atom.key, cu.state.active_atom_key.get(button)) or
                inter.buttonPressed(button))
            {
                setButtonGeneric(&inter.f, .dragging, button);
            }
        }
    }

    // close context menu if clicked out side of
    if (!ctx_menu_is_ancestor and inter.anyClicked()) {
        cu.builder.ctx_menu.closeMenu();
    }

    return inter;
}

// @TODO
pub const Keycode = enum(u32) {
    unknown,
    _,
};

pub const Modifiers = packed struct {
    shift: bool = false,
    ctrl: bool = false,
    alt: bool = false,
};
