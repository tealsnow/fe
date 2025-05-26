const std = @import("std");

const wl = @import("wayland").client.wl;
const xdg = @import("wayland").client.xdg;
const xkb = @import("xkbcommon");

const Window = @import("Window.zig");
const WindowId = Window.WindowId;

const mt = @import("cu").math;

pub const EventQueue = EventQueueCircleBuffer(32, Event);

pub const Event = struct {
    kind: Kind,
    time: ?u32 = null, // ms

    pub const Kind = union(enum) {
        surface_configure: SurfaceConfigure,

        toplevel_configure: ToplevelConfigure,
        toplevel_close: ToplevelClose,

        // popup_configure: PopupConfigure,
        // popup_done: PopupDone,
        // popup_repositioned: PopupRepositioned,

        frame: Frame,

        keyboard_focus: KeyboardFocus,
        key: Key,
        modifier: Modifier,
        text: Text,

        pointer_focus: PointerFocus,
        pointer_motion: PointerMotion,
        pointer_button: PointerButton,
        pointer_scroll: PointerScroll,

        pointer_gesture_swipe: PointerGestureSwipe,
        pointer_gesture_pinch: PointerGesturePinch,
        pointer_gesture_hold: PointerGestureHold,
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
        serial: u32,
        window_id: WindowId,
    };

    pub const ToplevelConfigure = struct {
        window_id: WindowId,
        size: ?mt.Size(u32),
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
                state.tiled_left or
                state.tiled_right or
                state.tiled_top or
                state.tiled_bottom;
        }
    };

    pub const ToplevelClose = struct {
        window_id: WindowId,
    };

    // pub const PopupConfigure = struct {
    //     position: Point(u32),
    //     size: Size(u32),
    // };

    // pub const PopupDone = struct {};

    // pub const PopupRepositioned = struct {
    //     token: u32,
    // };

    pub const Frame = struct {
        window_id: WindowId,
    };

    pub const KeyboardFocus = struct {
        serial: u32,
        window_id: WindowId,
        state: FocusState,
    };

    pub const Key = struct {
        serial: u32,
        state: PressState,
        scancode: u32,
        keysym: xkb.Keysym,
        codepoint: u21, // may be 0
    };

    pub const Modifier = struct {
        serial: u32,
        state: ModifierState,
    };

    pub const Text = struct {
        codepoint: u21,
        utf8: [4:0]u8,

        pub fn sliceZ(text: Text) [:0]const u8 {
            return std.mem.sliceTo(&text.utf8, 0);
        }

        pub fn slice(text: Text) []const u8 {
            return text.sliceZ()[0..];
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
        serial: u32,
        window_id: WindowId,
        state: FocusState,
    };

    pub const PointerMotion = struct {
        point: mt.Point(f64),
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

    pub const PointerGestureSwipe = union(enum) {
        begin: Begin,
        update: Update,
        end: End,

        pub const Begin = struct {
            serial: u32,
            surface: ?*wl.Surface,
            fingers: u32,
        };

        pub const Update = struct {
            dx: f64,
            dy: f64,
        };

        pub const End = struct {
            serial: u32,
            cancelled: bool,
        };
    };

    pub const PointerGesturePinch = union(enum) {
        begin: Begin,
        update: Update,
        end: End,

        pub const Begin = struct {
            serial: u32,
            surface: ?*wl.Surface,
            fingers: u32,
        };

        pub const Update = struct {
            dx: f64,
            dy: f64,
            scale: f64,
            rotation: f64, // cw
        };

        pub const End = struct {
            serial: u32,
            cancelled: bool,
        };
    };

    pub const PointerGestureHold = union(enum) {
        begin: Begin,
        end: End,

        pub const Begin = struct {
            serial: u32,
            surface: ?*wl.Surface,
            fingers: u32,
        };

        pub const End = struct {
            serial: u32,
            cancelled: bool,
        };
    };
};

/// Will be faster (if only marginal) with a power of 2 Size
///
/// This has no checking for overwriting
pub fn EventQueueCircleBuffer(comptime size: usize, comptime T: type) type {
    return struct {
        buffer: [size]T,
        head: usize,
        tail: usize,

        const Self = @This();

        pub const empty = Self{
            .buffer = undefined,
            .head = 0,
            .tail = 0,
        };

        pub fn queue(self: *Self, item: T) void {
            self.buffer[self.head] = item;
            self.head = (self.head + 1) % size;
        }

        pub fn dequeue(self: *Self) ?T {
            if (self.tail == self.head) return null;

            const item = self.buffer[self.tail];
            self.tail = (self.tail + 1) % size;
            return item;
        }

        pub fn indexBack(self: *const Self, i: usize) ?T {
            const tail = (self.tail + i) % size;
            if (tail == self.head) return null;
            return self.buffer[tail];
        }

        pub fn count(self: *Self) usize {
            return (self.head -% self.tail +% size) % size;
        }
    };
}
