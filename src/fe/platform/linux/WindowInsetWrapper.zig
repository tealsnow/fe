//! Insets atoms created between `begin` and `end` based on the window inset
//! with the current tiling
//!
//! Handles resizing and cursor shape
// @TODO: use cu mouse cursor api when implemented
const WindowInsetWrapper = @This();

const wl = @import("wayland/wayland.zig");

const cu = @import("cu");
const b = cu.builder;

window: *const wl.Window,
inset: f32,
vert_body: *cu.Atom,
hori_body: *cu.Atom,

pub fn begin(window: *const wl.Window) WindowInsetWrapper {
    const inset: f32 = @floatFromInt(window.inset orelse 0);
    const tiling = window.tiling;

    // Since we create atoms before where we want to add this to the tree
    // we create this as an orphan here as we want to be able to use
    // any properties on the stacks.
    cu.state.next_atom_orphan = true;
    const hori_body = b.build("###hori inset body");
    hori_body.hover_cursor_shape = .default;

    if (!tiling.tiled_top) {
        b.stacks.pref_size.push(.size(.fill, .px(inset)));
        b.stacks.layout_axis.push(.x);
        const top_inset_container = b.open("###top inset container");
        defer b.close(top_inset_container);

        b.stacks.flags.pushForMany(.clickable);
        defer _ = b.stacks.flags.pop();

        b.stacks.pref_size.push(.square(.px(inset)));
        b.stacks.hover_cursor_shape.push(.resize_nwse);
        const top_left = b.build("###top-left inset").interaction();

        b.stacks.pref_size.push(.square(.grow));
        b.stacks.hover_cursor_shape.push(.resize_ns);
        const top_middle = b.build("###top-middle inset").interaction();

        b.stacks.pref_size.push(.square(.px(inset)));
        b.stacks.hover_cursor_shape.push(.resize_nesw);
        const top_right = b.build("###top-right inset").interaction();

        if (top_left.pressed())
            window.startResize(.top_left);

        if (top_middle.pressed())
            window.startResize(.top);

        if (top_right.pressed())
            window.startResize(.top_right);
    }

    b.stacks.layout_axis.push(.x);
    b.stacks.pref_size.push(.square(.grow));
    const vert_body = b.open("###vert inset body");

    if (!tiling.tiled_left) {
        b.stacks.pref_size.push(.size(.px(inset), .fill));
        b.stacks.flags.push(.clickable);
        b.stacks.hover_cursor_shape.push(.resize_ew);
        const left = b.build("###left inset").interaction();

        if (left.pressed())
            window.startResize(.left);
    }

    // We put the atom into the tree here and as a parent
    b.addToTopParent(hori_body);
    b.pushParent(hori_body);

    hori_body.pref_size = .square(.grow);

    return .{
        .window = window,
        .inset = inset,
        .vert_body = vert_body,
        .hori_body = hori_body,
    };
}

pub fn end(win_inset: WindowInsetWrapper) void {
    const window = win_inset.window;
    const tiling = window.tiling;
    const inset = win_inset.inset;

    b.close(win_inset.hori_body);

    if (!tiling.tiled_right) {
        b.stacks.pref_size.push(.size(.px(inset), .fill));
        b.stacks.flags.push(.clickable);
        b.stacks.hover_cursor_shape.push(.resize_ew);
        const right = b.build("###right inset").interaction();

        if (right.pressed())
            window.startResize(.right);
    }

    b.close(win_inset.vert_body);

    if (!tiling.tiled_bottom) {
        b.stacks.layout_axis.push(.x);
        b.stacks.pref_size.push(.size(.fill, .px(inset)));
        const bottom_inset_container = b.open("###bottom inset container");
        defer b.close(bottom_inset_container);

        b.stacks.flags.pushForMany(.clickable);
        defer _ = b.stacks.flags.pop();

        b.stacks.pref_size.push(.square(.px(inset)));
        b.stacks.hover_cursor_shape.push(.resize_nesw);
        const bottom_left = b.build("###bottom-left inset").interaction();

        b.stacks.pref_size.push(.square(.grow));
        b.stacks.hover_cursor_shape.push(.resize_ns);
        const bottom_middle = b.build("###bottom-middle inset").interaction();

        b.stacks.pref_size.push(.square(.px(inset)));
        b.stacks.hover_cursor_shape.push(.resize_nwse);
        const bottom_right = b.build("###bottom-right inset").interaction();

        if (bottom_left.pressed())
            window.startResize(.bottom_left);

        if (bottom_middle.pressed())
            window.startResize(.bottom);

        if (bottom_right.pressed())
            window.startResize(.bottom_right);
    }
}
