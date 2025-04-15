const std = @import("std");

const wl = @import("wayland").client.wl;
const xdg = @import("wayland").client.xdg;
const xkb = @import("xkbcommon");

const Size = @import("../../../math.zig").Size;
const Point = @import("../../../math.zig").Point;

/// Will be faster (if only marginal) with a power of 2 Size
///
/// This has no checking for overwriting
pub fn CircleBufferQueue(comptime size: usize, comptime T: type) type {
    return struct {
        buffer: [size]T,
        head: usize,
        tail: usize,

        const Queue = @This();

        pub const empty = Queue{
            .buffer = undefined,
            .head = 0,
            .tail = 0,
        };

        pub fn queue(self: *Queue, item: T) void {
            self.buffer[self.head] = item;
            self.head = (self.head + 1) % size;
        }

        pub fn dequeue(self: *Queue) ?T {
            if (self.tail == self.head) return null;

            const item = self.buffer[self.tail];
            self.tail = (self.tail + 1) % size;
            return item;
        }

        pub fn count(self: *Queue) usize {
            return (self.head -% self.tail +% size) % size;
        }
    };
}

// set to 8 max as a conservative measure, I have not seen more than 3 in my
// testing, but different compositors could act different
pub const EventQueue = CircleBufferQueue(8, Event);

pub const Event = struct {
    kind: Kind,
    time: ?u32 = null, // ms

    pub const Kind = union(enum) {
        surface_configure: SurfaceConfigure,

        toplevel_configure: ToplevelConfigure,
        toplevel_close: void,

        frame: void,

        keyboard_focus: KeyboardFocus,
        key: Key,
        modifier: Modifier,
        text: Text,

        pointer_focus: PointerFocus,
        pointer_motion: PointerMotion,
        pointer_button: PointerButton,
        pointer_scroll: PointerScroll,
    };

    pub const PressState = enum {
        pressed,
        released,
    };

    pub const FocusState = enum {
        enter,
        leave,
    };

    pub const Ping = struct {
        xdg_wm_base: *xdg.WmBase,
        serial: u32,
    };

    pub const SurfaceConfigure = struct {
        wl_surface: *wl.Surface,
        xdg_surface: *xdg.Surface,
        serial: u32,
    };

    pub const ToplevelConfigure = struct {
        size: ?Size(u32),
        state: ToplevelConfigureState,
    };

    pub const ToplevelConfigureState = packed struct {
        maximized: bool = false,
        fullscreen: bool = false,
        resizing: bool = false,
        activated: bool = false,
        tiled_left: bool = false,
        tiled_right: bool = false,
        tiled_top: bool = false,
        tiled_bottom: bool = false,
        suspended: bool = false,

        pub fn isTiled(state: ToplevelConfigureState) bool {
            return state.maximized or
                state.fullscreen or
                (state.tiled_left and
                    state.tiled_right and
                    state.tiled_top and
                    state.tiled_bottom);
        }
    };

    pub const KeyboardFocus = struct {
        state: FocusState,
        serial: u32,
        wl_surface: ?*wl.Surface,
    };

    pub const Key = struct {
        state: PressState,
        scancode: u32,
        keysym: xkb.Keysym,
        codepoint: u21, // may be 0
        serial: u32,
    };

    pub const Modifier = struct {
        state: ModifierState,
        serial: u32,
    };

    pub const Text = struct {
        codepoint: u21,
        utf8: [4:0]u8,

        pub fn sliceZ(text: Text) [:0]const u8 {
            return std.mem.sliceTo(&text.utf8, 0);
        }

        pub fn slice(text: Text) []const u8 {
            const z = text.sliceZ();
            z[0..z.len];
        }
    };

    pub const ModifierState = packed struct(u8) {
        shift: bool = false,
        caps_lock: bool = false,
        ctrl: bool = false,
        alt: bool = false,
        logo: bool = false, // super
        _padding: u3 = 0,
    };

    pub const PointerFocus = struct {
        state: FocusState,
        serial: u32,
        wl_surface: ?*wl.Surface,
    };

    pub const PointerMotion = struct {
        point: Point(f64),
    };

    pub const PointerButton = struct {
        state: PressState,
        button: PointerButtonKind,
        serial: u32,
    };

    pub const PointerButtonKind = enum {
        left,
        right,
        middle,
        forward,
        back,
    };

    pub const PointerScroll = struct {
        axis: PointerScrollAxis,
        source: PointerScrollSource,
        /// null means stop event, see `PointerScrollSource`
        value: ?f64,
    };

    pub const PointerScrollAxis = enum {
        vertical,
        horizontal,
    };

    /// A stop event is always garenteed for finger,
    /// but not for any other type
    pub const PointerScrollSource = enum {
        unknown,
        wheel,
        finger,
        continuous,
        wheel_tilt,
    };
};
