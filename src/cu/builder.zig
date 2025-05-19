const std = @import("std");
const Allocator = std.mem.Allocator;
const log = std.log.scoped(.@"cu.builder");

const cu = @import("cu.zig");
const math = cu.math;
const debugAssert = cu.debugAssert;
const Atom = cu.Atom;
const AtomFlags = cu.AtomFlags;
const FontId = cu.FontId;

const tracy = @import("tracy");

var trace_build: tracy.ZoneContext = undefined;

pub fn startFrame() void {
    const current_time = std.time.Instant.now() catch
        @panic("no std.time.Instant support");

    const dt_ns = current_time.since(cu.state.frame_previous_time);
    cu.state.frame_previous_time = current_time;

    cu.state.dt_s =
        @as(f32, @floatFromInt(dt_ns)) / @as(f32, std.time.ns_per_s);
}

pub fn endFrame() void {
    //
}

pub fn startBuild(window_id: u32) void {
    trace_build = tracy.beginZone(@src(), .{ .name = "ui build" });
    const trace_start = tracy.beginZone(@src(), .{ .name = "ui build setup" });
    defer trace_start.end();

    // cu.state.scope_locals.clearAndFree(cu.state.arena);

    //- reset stacks
    {
        stacks = .empty;

        stacks.palette
            .pushForMany(Atom.pallete.fullToPartial(cu.state.default_palette));
        stacks.font.pushForMany(cu.state.default_font);
        stacks.pref_size.pushForMany(.square(.fill));
        stacks.layout_axis.pushForMany(.none);
        stacks.flags.pushForMany(.none);
        stacks.text_align.pushForMany(.square(.center));
        stacks.border_width.pushForMany(1);
        stacks.corner_radius.pushForMany(0);
    }

    //- setup ui roots
    {
        stacks.layout_axis.push(.x);
        stacks.pref_size.push(cu.state.window_size.intoPxPrefSize());
        const root = buildFromStringF("###root window-id:{x}", .{window_id});
        root.rect = .rect(.point(0, 0), cu.state.window_size.intoPoint());
        cu.state.ui_root = root;

        stacks.layout_axis.push(.x);
        stacks.pref_size.push(.square(.fit));
        const ctx_menu_root =
            buildFromStringF("###ctx_menu_root window-id:{x}", .{window_id});
        ctx_menu_root.rect = .zero;
        cu.state.ui_ctx_menu_root = ctx_menu_root;

        // pushLayoutAxis(.once(.x));
        // pushPrefSize(.once(.square(.fit)));
        // const tooltip_root = buildFromStringF("###tooltip_root window-id:{x}", .{window_id});
        // tooltip_root.rect = .zero;
        // cu.state.ui_tooltip_root = tooltip_root;
    }

    //- setup atom stack
    {
        cu.state.atom_parent_stack.clearAndFree(cu.state.arena);
        cu.state.atom_parent_stack.push(cu.state.arena, cu.state.ui_root);
    }

    cu.state.next_ctx_menu_open = cu.state.ctx_menu_open;
}

pub fn endBuild() void {
    defer trace_build.end();
    const trace_end = tracy.beginZone(@src(), .{ .name = "ui build end" });
    defer trace_end.end();

    //- remove stale atoms
    {
        const trace =
            tracy.beginZone(@src(), .{ .name = "remove stale atoms" });
        defer trace.end();

        var to_remove = std.ArrayList(Atom.Key)
            // we would hope no more than a 1/4 of the total
            // atoms are removed in a given frame
            .initCapacity(cu.state.arena, cu.state.atom_map.count() / 4) catch
            @panic("oom");

        for (cu.state.atom_map.values()) |atom| {
            if (atom.build_index_touched_last < cu.state.current_build_index) {
                to_remove.append(atom.key) catch @panic("oom");
            }
        }

        for (to_remove.items) |key| {
            if (key == .nil) continue;
            const atom = cu.state.atom_map.fetchSwapRemove(key).?.value;
            cu.state.atom_pool.destroy(atom);
        }
    }

    //- check stack
    const root = root: {
        const root = cu.state.atom_parent_stack.pop().?;
        debugAssert(
            cu.state.atom_parent_stack.list.items.len == 0,
            "Parent stack not empty after build; " ++
                "likely forgot a defer -- last: {}",
            .{root},
        );
        debugAssert(
            cu.state.ui_root.key.eql(root.key),
            "Last item on parent stack was not ui root; instead found: {}",
            .{root},
        );
        break :root root;
    };

    //- layout
    {
        const trace = tracy.beginZone(@src(), .{ .name = "layout" });
        defer trace.end();

        cu.layout(root) catch @panic("oom");
        cu.layout(cu.state.ui_ctx_menu_root) catch @panic("oom");
        // cu.layout(cu.state.ui_tooltip_root) catch @panic("oom");
    }

    //- reset and cleanup state
    {
        cu.state.hot_atom_key = .nil;
        cu.state.ctx_menu_open = cu.state.next_ctx_menu_open;
        cu.state.current_build_index += 1;
        cu.state.ui_built = true;
        cu.state.event_list.len = 0;

        _ = cu.state.arena_allocator.reset(.retain_capacity);
    }
}

pub fn tryAtomFromKey(key: Atom.Key) ?*Atom {
    var result: ?*Atom = null;
    if (!key.eql(.nil)) {
        if (cu.state.atom_map.get(key)) |atom| {
            result = atom;
        }
    }
    return result;
}

pub fn buildFromKeyOrphan(key: Atom.Key) *Atom {
    cu.state.build_atom_count += 1;

    const atom, //
    const is_first_frame // if it was created this frame
    = if (Atom.Key.eql(key, .nil)) blk: {
        const atom = cu.state.arena.create(Atom) catch @panic("oom");
        break :blk .{ atom, true };
    } else if (tryAtomFromKey(key)) |atom| blk: {
        atom.key = key;
        break :blk .{ atom, false };
    } else blk: {
        const atom = cu.state.atom_pool.create() catch @panic("oom");
        const bad_atom =
            cu.state.atom_map.fetchPut(cu.state.gpa, key, atom) catch
                @panic("oom");
        debugAssert(
            bad_atom == null,
            "got an atom for a key that was thought to not have a value" ++
                " - keying/hashing is broken",
            .{},
        );

        break :blk .{ atom, true };
    };

    if (is_first_frame) {
        atom.* = .{
            .key = key,
            .build_index_touched_first = cu.state.current_build_index,
            .build_index_touched_last = cu.state.current_build_index,

            .hot_t = 0,
            .active_t = 0,
        };
    } else {
        atom.build_index_touched_last = cu.state.current_build_index;
    }

    // zero out per build info
    atom.children = null;
    atom.siblings.next = null;
    atom.siblings.prev = null;
    atom.parent = null;

    atom.string = "";
    atom.display_string = "";

    // per build info
    atom.font = stacks.font.topVolatile().?;
    atom.pref_size = stacks.pref_size.topVolatile().?;
    atom.layout_axis = stacks.layout_axis.topVolatile().?;
    atom.flags = stacks.flags.topVolatile().?;
    atom.text_align = stacks.text_align.topVolatile().?;
    atom.border_width = stacks.border_width.topVolatile().?;
    atom.corner_radius = stacks.corner_radius.topVolatile().?;

    {
        var partial = stacks.palette.topVolatile().?;
        var i: usize = 0;
        while (!Atom.pallete.partialIsFull(partial)) : (i += 1) {
            const next = stacks.palette.peek(i) orelse break;
            partial = Atom.pallete.mergePartials(partial, next);
        }
        atom.palette = Atom.pallete.partialToFull(partial) orelse
            @panic("could not contruct a full pallete from stack");
    }

    return atom;
}

pub fn buildFromKey(key: Atom.Key) *Atom {
    const atom = buildFromKeyOrphan(key);

    if (cu.state.next_atom_orphan) {
        cu.state.next_atom_orphan = false;
    } else {
        addToTopParent(atom);
    }

    return atom;
}

pub fn addToTopParent(atom: *Atom) void {
    const parent = cu.state.atom_parent_stack.top() orelse return;

    atom.parent = parent;

    if (parent.children) |*children| {
        const last = children.last;
        last.siblings.next = atom;
        atom.siblings.prev = last;
        children.last = atom;

        children.count += 1;
    } else {
        parent.children = .{
            .first = atom,
            .last = atom,
            .count = 1,
        };
    }
}

pub fn buildFromString(string: []const u8) *Atom {
    const seed =
        if (cu.state.atom_parent_stack.top()) |parent|
            @intFromEnum(parent.key)
        else
            0;
    const display_string, const key = Atom.Key.processString(seed, string);

    const atom = buildFromKey(key);
    atom.string = string;
    atom.display_string = display_string;

    return atom;
}

pub fn buildFromStringF(comptime fmt: []const u8, args: anytype) *Atom {
    const string = std.fmt.allocPrint(cu.state.arena, fmt, args) catch
        @panic("oom");
    return buildFromString(string);
}

//= build shorthand

pub fn build(string: []const u8) *Atom {
    return buildFromString(string);
}

pub fn buildf(comptime fmt: []const u8, args: anytype) *Atom {
    return buildFromStringF(fmt, args);
}

//= context menu

pub fn ctxMenuOpen(
    key: Atom.Key,
    anchor_box_key: Atom.Key,
    anchor_off: cu.Vec2(f32),
) void {
    _ = key;
    _ = anchor_box_key;
    _ = anchor_off;

    cu.state.next_ctx_menu_open = true;
    // ctx_menu_changed = true
    // ctx_menu_open_t = 0
    // ctx_menu_key = key
    // next_ctx_menu_anchor_key = anchor_box_key
    // ctx_menu_anchor_off = anchor_off
    // ctx_menu_touched_this_frame = true
    // ctx_menu_anchor_atom_last_pos = .zero
}

pub fn ctxMenuClose() void {
    cu.state.next_ctx_menu_open = false;
}

pub fn beginCtxMenu(key: Atom.Key) bool {
    _ = key;
    // const is_open = key.eql(ctx_menu_key) and cu.state.ctx_menu_open;
    // is_in_ctx_menu = is_open;
    //
}

pub fn endCtxMenu() void {
    // if (is_in_ctx_menu) {
    //     is_in_ctx_menu = false;
    // }
    //
}

//= hierarchy management

pub fn pushParent(atom: *Atom) void {
    cu.state.atom_parent_stack.push(cu.state.arena, atom);
}

pub fn open(string: []const u8) *Atom {
    const atom = build(string);
    pushParent(atom);
    return atom;
}

pub fn openf(comptime fmt: []const u8, args: anytype) *Atom {
    const atom = buildf(fmt, args);
    cu.state.atom_parent_stack.push(cu.state.arena, atom);
    return atom;
}

pub fn close(atom: *Atom) void {
    const top = cu.state.atom_parent_stack.pop().?;
    debugAssert(
        Atom.Key.eql(atom.key, top.key),
        "mismatched open/close; likely forgot a defer: expected {} but got {}",
        .{ atom, top },
    );
}

//= basic widgets

pub fn label(string: []const u8) *Atom {
    const atom = buildFromKey(.nil);
    // should this stay? or let the user decide with pushPrefSize
    atom.pref_size = .square(.text);
    atom.display_string = string;
    atom.flags.insert(.draw_text);
    return atom;
}

pub fn labelf(comptime fmt: []const u8, args: anytype) *Atom {
    const string = std.fmt.allocPrint(cu.state.arena, fmt, args) catch
        @panic("oom");
    return label(string);
}

pub fn spacer() *Atom {
    return buildFromKey(.nil);
}

pub fn lineSpacer() *Atom {
    stacks.pref_size.push(.size(.grow, .text));
    const line_spacer = spacer();
    line_spacer.display_string = " ";
    return line_spacer;
}

pub fn baseClickableInteractionStyles(inter: cu.Interaction) void {
    // @FIXME: the tranitions to and from no interation and hovering work,
    //  and from hovering to clicking, but not from clicking back to hovering

    const atom = inter.atom;

    const is_hot = cu.state.hot_atom_key.eql(atom.key);
    const is_active = for (cu.state.active_atom_key) |key| {
        if (key.eql(atom.key)) break true;
    } else false;

    atom.hot_t =
        math.expSmooth(atom.hot_t, @as(f32, if (is_hot) 1 else 0));
    atom.active_t =
        math.expSmooth(atom.active_t, @as(f32, if (is_active) 1 else 0));

    const palette = atom.palette;
    const from, const to, const lerp_t =
        if (is_active)
            .{ palette.get(.hot), palette.get(.active), atom.active_t }
        else
            .{ palette.get(.border), palette.get(.hot), atom.hot_t };

    atom.palette.set(.border, from.lerp(to, lerp_t));
}

pub fn button(string: []const u8) cu.Interaction {
    const atom = build(string);
    atom.flags = .unionOf(&.{ .clickable, .draw_text, .draw_border });

    const interaction = atom.interaction();
    baseClickableInteractionStyles(interaction);

    return interaction;
}

pub fn buttonf(comptime fmt: []const u8, args: anytype) *Atom {
    const string = std.fmt.allocPrint(cu.state.arena, fmt, args) catch
        @panic("oom");
    return button(string);
}

pub fn toggleSwitch(toggled: *bool) cu.Interaction {
    stacks.flags.push(.unionWith(.draw_border, .clickable));
    stacks.layout_axis.push(.y);
    const toggle = open("toggle box");
    defer close(toggle);

    const size = toggle.fixed_size;
    const padding: f32 = size.height / 5;
    const middle_size: f32 = size.height - (2 * padding);

    stacks.pref_size.push(.size(.grow, .px(padding)));
    _ = spacer();

    {
        stacks.layout_axis.push(.x);
        stacks.pref_size.push(.square(.grow));
        const track = open("track");
        defer close(track);

        track.active_t = math.expSmooth(
            track.active_t,
            if (toggled.*) size.width - middle_size - padding else padding,
        );

        stacks.pref_size.push(.size(.px(track.active_t), .grow));
        _ = spacer();

        stacks.flags.push(.draw_background);
        stacks.palette.push(.init(.{
            .background = stacks.palette.topStable().?.get(.text),
        }));
        stacks.pref_size.push(.square(.px(middle_size)));
        _ = build("toggle middle");
    }

    const inter = toggle.interaction();
    baseClickableInteractionStyles(inter);

    if (inter.clicked())
        toggled.* = !toggled.*;

    return inter;
}

//= stacks

pub const Stacks = struct {
    palette: VolatileStack(Atom.pallete.PalletePartial),
    font: VolatileStack(FontId),
    pref_size: VolatileStack(math.Size(Atom.PrefSize)),
    layout_axis: VolatileStack(Atom.LayoutAxis),
    flags: VolatileStack(Atom.Flags),
    text_align: VolatileStack(math.Size(Atom.TextAlignment)),
    border_width: VolatileStack(f32),
    corner_radius: VolatileStack(f32),

    const empty = Stacks{
        .palette = .empty,
        .pref_size = .empty,
        .font = .empty,
        .layout_axis = .empty,
        .flags = .empty,
        .text_align = .empty,
        .border_width = .empty,
        .corner_radius = .empty,
    };

    pub fn VolatileStack(comptime T: type) type {
        return struct {
            const Self = @This();

            pub const StackItem = struct {
                item: T,
                once: bool,
            };

            stack: std.MultiArrayList(StackItem),

            pub const empty = Self{ .stack = .empty };

            /// Push an item that will be removed when read next
            pub fn push(self: *Self, item: T) void {
                self.pushRaw(.{ .item = item, .once = true });
            }

            /// Push an item that can be read multiple times.
            /// Reqires a pop to remove.
            pub fn pushForMany(self: *Self, item: T) void {
                self.pushRaw(.{ .item = item, .once = false });
            }

            pub fn pushRaw(self: *Self, item: StackItem) void {
                self.stack.append(cu.state.arena, item) catch @panic("oom");
            }

            /// Read the top item - possibly removing it from the stack
            pub fn topVolatile(self: *Self) ?T {
                const elem = self.topRaw() orelse return null;
                if (elem.once)
                    self.stack.len -= 1;
                return elem.item;
            }

            /// Read the top item - without possibly removing it from the stack
            pub fn topStable(self: Self) ?T {
                const elem = self.topRaw() orelse return null;
                return elem.item;
            }

            inline fn topRaw(self: Self) ?StackItem {
                if (self.stack.len == 0) {
                    @branchHint(.unlikely);
                    return null;
                }
                return self.stack.get(self.stack.len - 1);
            }

            pub fn peek(self: Self, i: usize) ?T {
                if (self.stack.len == 0) {
                    @branchHint(.unlikely);
                    return null;
                }
                if (self.stack.len <= i) return null;

                return self.stack.get(self.stack.len - 1 - i).item;
            }

            /// Remove the top item from the stack,
            /// irrespective of if its volatile or not
            pub fn pop(self: *Self) ?T {
                if (self.stack.pop()) |elem| {
                    @branchHint(.likely);
                    return elem.item;
                } else {
                    @branchHint(.unlikely);
                    return null;
                }
            }
        };
    }
};

pub var stacks: Stacks = .empty;
