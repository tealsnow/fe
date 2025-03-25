const c = @cImport({
    @cInclude("SDL3/SDL_events.h");
});
const sdl = @import("sdl3.zig");
const Error = sdl.Error;
const WindowID = sdl.WindowID;
const DisplayID = sdl.DisplayID;

pub const Scancode = @import("scancode.zig").Scancode;
pub const Keycode = @import("keycode.zig").Keycode;

pub const EventType = enum(u32) {
    quit = c.SDL_EVENT_QUIT,
    terminating = c.SDL_EVENT_TERMINATING,
    low_memory = c.SDL_EVENT_LOW_MEMORY,
    will_enter_background = c.SDL_EVENT_WILL_ENTER_BACKGROUND,
    did_enter_background = c.SDL_EVENT_DID_ENTER_BACKGROUND,
    will_enter_foreground = c.SDL_EVENT_WILL_ENTER_FOREGROUND,
    did_enter_foreground = c.SDL_EVENT_DID_ENTER_FOREGROUND,
    locale_changed = c.SDL_EVENT_LOCALE_CHANGED,
    system_theme_changed = c.SDL_EVENT_SYSTEM_THEME_CHANGED,
    display_orientation = c.SDL_EVENT_DISPLAY_ORIENTATION,
    display_added = c.SDL_EVENT_DISPLAY_ADDED,
    display_removed = c.SDL_EVENT_DISPLAY_REMOVED,
    display_moved = c.SDL_EVENT_DISPLAY_MOVED,
    display_desktop_mode_changed = c.SDL_EVENT_DISPLAY_DESKTOP_MODE_CHANGED,
    display_current_mode_changed = c.SDL_EVENT_DISPLAY_CURRENT_MODE_CHANGED,
    display_content_scale_changed = c.SDL_EVENT_DISPLAY_CONTENT_SCALE_CHANGED,
    window_shown = c.SDL_EVENT_WINDOW_SHOWN,
    window_hidden = c.SDL_EVENT_WINDOW_HIDDEN,
    window_exposed = c.SDL_EVENT_WINDOW_EXPOSED,
    window_moved = c.SDL_EVENT_WINDOW_MOVED,
    window_resized = c.SDL_EVENT_WINDOW_RESIZED,
    window_pixel_size_changed = c.SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED,
    window_metal_view_resized = c.SDL_EVENT_WINDOW_METAL_VIEW_RESIZED,
    window_minimized = c.SDL_EVENT_WINDOW_MINIMIZED,
    window_maximized = c.SDL_EVENT_WINDOW_MAXIMIZED,
    window_restored = c.SDL_EVENT_WINDOW_RESTORED,
    window_mouse_enter = c.SDL_EVENT_WINDOW_MOUSE_ENTER,
    window_mouse_leave = c.SDL_EVENT_WINDOW_MOUSE_LEAVE,
    window_focus_gained = c.SDL_EVENT_WINDOW_FOCUS_GAINED,
    window_focus_lost = c.SDL_EVENT_WINDOW_FOCUS_LOST,
    window_close_requested = c.SDL_EVENT_WINDOW_CLOSE_REQUESTED,
    window_hit_test = c.SDL_EVENT_WINDOW_HIT_TEST,
    window_iccprof_changed = c.SDL_EVENT_WINDOW_ICCPROF_CHANGED,
    window_display_changed = c.SDL_EVENT_WINDOW_DISPLAY_CHANGED,
    window_display_scale_changed = c.SDL_EVENT_WINDOW_DISPLAY_SCALE_CHANGED,
    window_safe_area_changed = c.SDL_EVENT_WINDOW_SAFE_AREA_CHANGED,
    window_occluded = c.SDL_EVENT_WINDOW_OCCLUDED,
    window_enter_fullscreen = c.SDL_EVENT_WINDOW_ENTER_FULLSCREEN,
    window_leave_fullscreen = c.SDL_EVENT_WINDOW_LEAVE_FULLSCREEN,
    window_destroyed = c.SDL_EVENT_WINDOW_DESTROYED,
    window_hdr_state_changed = c.SDL_EVENT_WINDOW_HDR_STATE_CHANGED,
    key_down = c.SDL_EVENT_KEY_DOWN,
    key_up = c.SDL_EVENT_KEY_UP,
    text_editing = c.SDL_EVENT_TEXT_EDITING,
    text_input = c.SDL_EVENT_TEXT_INPUT,
    keymap_changed = c.SDL_EVENT_KEYMAP_CHANGED,
    keyboard_added = c.SDL_EVENT_KEYBOARD_ADDED,
    keyboard_removed = c.SDL_EVENT_KEYBOARD_REMOVED,
    text_editing_candidates = c.SDL_EVENT_TEXT_EDITING_CANDIDATES,
    mouse_motion = c.SDL_EVENT_MOUSE_MOTION,
    mouse_button_down = c.SDL_EVENT_MOUSE_BUTTON_DOWN,
    mouse_button_up = c.SDL_EVENT_MOUSE_BUTTON_UP,
    mouse_wheel = c.SDL_EVENT_MOUSE_WHEEL,
    mouse_added = c.SDL_EVENT_MOUSE_ADDED,
    mouse_removed = c.SDL_EVENT_MOUSE_REMOVED,
    joystick_axis_motion = c.SDL_EVENT_JOYSTICK_AXIS_MOTION,
    joystick_ball_motion = c.SDL_EVENT_JOYSTICK_BALL_MOTION,
    joystick_hat_motion = c.SDL_EVENT_JOYSTICK_HAT_MOTION,
    joystick_button_down = c.SDL_EVENT_JOYSTICK_BUTTON_DOWN,
    joystick_button_up = c.SDL_EVENT_JOYSTICK_BUTTON_UP,
    joystick_added = c.SDL_EVENT_JOYSTICK_ADDED,
    joystick_removed = c.SDL_EVENT_JOYSTICK_REMOVED,
    joystick_battery_updated = c.SDL_EVENT_JOYSTICK_BATTERY_UPDATED,
    joystick_update_complete = c.SDL_EVENT_JOYSTICK_UPDATE_COMPLETE,
    gamepad_axis_motion = c.SDL_EVENT_GAMEPAD_AXIS_MOTION,
    gamepad_button_down = c.SDL_EVENT_GAMEPAD_BUTTON_DOWN,
    gamepad_button_up = c.SDL_EVENT_GAMEPAD_BUTTON_UP,
    gamepad_added = c.SDL_EVENT_GAMEPAD_ADDED,
    gamepad_removed = c.SDL_EVENT_GAMEPAD_REMOVED,
    gamepad_remapped = c.SDL_EVENT_GAMEPAD_REMAPPED,
    gamepad_touchpad_down = c.SDL_EVENT_GAMEPAD_TOUCHPAD_DOWN,
    gamepad_touchpad_motion = c.SDL_EVENT_GAMEPAD_TOUCHPAD_MOTION,
    gamepad_touchpad_up = c.SDL_EVENT_GAMEPAD_TOUCHPAD_UP,
    gamepad_sensor_update = c.SDL_EVENT_GAMEPAD_SENSOR_UPDATE,
    gamepad_update_complete = c.SDL_EVENT_GAMEPAD_UPDATE_COMPLETE,
    gamepad_steam_handle_updated = c.SDL_EVENT_GAMEPAD_STEAM_HANDLE_UPDATED,
    finger_down = c.SDL_EVENT_FINGER_DOWN,
    finger_up = c.SDL_EVENT_FINGER_UP,
    finger_motion = c.SDL_EVENT_FINGER_MOTION,
    finger_canceled = c.SDL_EVENT_FINGER_CANCELED,
    clipboard_update = c.SDL_EVENT_CLIPBOARD_UPDATE,
    drop_file = c.SDL_EVENT_DROP_FILE,
    drop_text = c.SDL_EVENT_DROP_TEXT,
    drop_begin = c.SDL_EVENT_DROP_BEGIN,
    drop_complete = c.SDL_EVENT_DROP_COMPLETE,
    drop_position = c.SDL_EVENT_DROP_POSITION,
    audio_device_added = c.SDL_EVENT_AUDIO_DEVICE_ADDED,
    audio_device_removed = c.SDL_EVENT_AUDIO_DEVICE_REMOVED,
    audio_device_format_changed = c.SDL_EVENT_AUDIO_DEVICE_FORMAT_CHANGED,
    sensor_update = c.SDL_EVENT_SENSOR_UPDATE,
    pen_proximity_in = c.SDL_EVENT_PEN_PROXIMITY_IN,
    pen_proximity_out = c.SDL_EVENT_PEN_PROXIMITY_OUT,
    pen_down = c.SDL_EVENT_PEN_DOWN,
    pen_up = c.SDL_EVENT_PEN_UP,
    pen_button_down = c.SDL_EVENT_PEN_BUTTON_DOWN,
    pen_button_up = c.SDL_EVENT_PEN_BUTTON_UP,
    pen_motion = c.SDL_EVENT_PEN_MOTION,
    pen_axis = c.SDL_EVENT_PEN_AXIS,
    camera_device_added = c.SDL_EVENT_CAMERA_DEVICE_ADDED,
    camera_device_removed = c.SDL_EVENT_CAMERA_DEVICE_REMOVED,
    camera_device_approved = c.SDL_EVENT_CAMERA_DEVICE_APPROVED,
    camera_device_denied = c.SDL_EVENT_CAMERA_DEVICE_DENIED,
    render_targets_reset = c.SDL_EVENT_RENDER_TARGETS_RESET,
    render_device_reset = c.SDL_EVENT_RENDER_DEVICE_RESET,
    render_device_lost = c.SDL_EVENT_RENDER_DEVICE_LOST,
    private0 = c.SDL_EVENT_PRIVATE0,
    private1 = c.SDL_EVENT_PRIVATE1,
    private2 = c.SDL_EVENT_PRIVATE2,
    private3 = c.SDL_EVENT_PRIVATE3,
    poll_sentinel = c.SDL_EVENT_POLL_SENTINEL,
    user = c.SDL_EVENT_USER,
};

pub const Event = extern union {
    type: EventType,
    common: CommonEvent,
    display: DisplayEvent,
    window: WindowEvent,
    kdevice: KeyboardDeviceEvent,
    key: KeyboardEvent,
    edit: TextEditingEvent,
    edit_candidates: TextEditingCandidatesEvent,
    text: TextInputEvent,
    mdevice: MouseDeviceEvent,
    motion: MouseMotionEvent,
    button: MouseButtonEvent,
    wheel: MouseWheelEvent,
    jdevice: JoyDeviceEvent,
    jaxis: JoyAxisEvent,
    jball: JoyBallEvent,
    jhat: JoyHatEvent,
    jbutton: JoyButtonEvent,
    jbattery: JoyBatteryEvent,
    gdevice: GamepadDeviceEvent,
    gaxis: GamepadAxisEvent,
    gbutton: GamepadButtonEvent,
    gtouchpad: GamepadTouchpadEvent,
    gsensor: GamepadSensorEvent,
    adevice: AudioDeviceEvent,
    cdevice: CameraDeviceEvent,
    sensor: SensorEvent,
    quit: QuitEvent,
    user: UserEvent,
    tfinger: TouchFingerEvent,
    pproximity: PenProximityEvent,
    ptouch: PenTouchEvent,
    pmotion: PenMotionEvent,
    pbutton: PenButtonEvent,
    paxis: PenAxisEvent,
    render: RenderEvent,
    drop: DropEvent,
    clipboard: ClipboardEvent,
    padding: [128]u8,

    pub fn poll() ?Event {
        var event: c.SDL_Event = undefined;
        return if (c.SDL_PollEvent(&event))
            return @bitCast(event)
        else
            return null;
    }

    pub fn wait() ?Event {
        var event: c.SDL_Event = undefined;
        return if (c.SDL_WaitEvent(&event))
            return @bitCast(event)
        else
            return null;
    }

    pub fn waitTimeout(timeout_ms: i32) ?Event {
        var event: c.SDL_Event = undefined;
        return if (c.SDL_WaitEventTimeout(&event, timeout_ms))
            return @bitCast(event)
        else
            return null;
    }

    pub fn push(event: Event) Error!void {
        if (!c.SDL_PushEvent(@constCast(@ptrCast(&event)))) return error.sdl;
    }

    pub fn mkCommon() Event {
        return .{ .common = .{
            .type = undefined,
            .reserved = 0,
            .timestamp = 0,
        } };
    }

    pub fn mkQuit() Event {
        var ev = mkCommon();
        ev.type = .quit;
        return ev;
    }

    pub fn mkWindow(ty: EventType, id: WindowID, data1: i32, data2: i32) Event {
        var ev = mkCommon();
        ev.type = ty;
        ev.window.window_id = id;
        ev.window.data1 = data1;
        ev.window.data2 = data2;
        return ev;
    }
};

pub const KeyboardID = enum(u32) { _ };

pub const Keymod = packed struct(u16) {
    lshift: bool = false,
    rshift: bool = false,
    lctrl: bool = false,
    rctrl: bool = false,
    lalt: bool = false,
    ralt: bool = false,
    lgui: bool = false,
    rgui: bool = false,
    num: bool = false,
    caps: bool = false,
    mode: bool = false,
    scroll: bool = false,
    _reserved: enum(u4) { zero } = .zero,

    pub fn ctrl(self: Keymod) bool {
        return self.lctrl or self.rctrl;
    }

    pub fn shift(self: Keymod) bool {
        return self.lshift or self.rshift;
    }

    pub fn alt(self: Keymod) bool {
        return self.lalt or self.ralt;
    }

    pub fn gui(self: Keymod) bool {
        return self.lgui or self.rgui;
    }
};

pub const MouseID = enum(u32) { _ };

pub const MouseButton = enum(u8) {
    left = c.SDL_BUTTON_LEFT,
    middle = c.SDL_BUTTON_MIDDLE,
    right = c.SDL_BUTTON_RIGHT,
    x1 = c.SDL_BUTTON_X1,
    x2 = c.SDL_BUTTON_X2,
    _,
};

pub const MouseButtonFlag = struct {
    pub const lmask = @as(MouseButtonFlags, c.SDL_BUTTON_LMASK);
    pub const mmask = @as(MouseButtonFlags, c.SDL_BUTTON_MMASK);
    pub const rmask = @as(MouseButtonFlags, c.SDL_BUTTON_RMASK);
    pub const x1mask = @as(MouseButtonFlags, c.SDL_BUTTON_X1MASK);
    pub const x2mask = @as(MouseButtonFlags, c.SDL_BUTTON_X2MASK);
};

// see `MouseButtonFlag`
pub const MouseButtonFlags = u32;

pub const MouseWheelDirection = enum(c_uint) {
    normal = c.SDL_MOUSEWHEEL_NORMAL,
    flipped = c.SDL_MOUSEWHEEL_FLIPPED,
};

pub const JoystickID = enum(u32) { _ };

pub const PowerState = enum(c_int) {
    @"error" = c.SDL_POWERSTATE_ERROR,
    unknown = c.SDL_POWERSTATE_UNKNOWN,
    on_battery = c.SDL_POWERSTATE_ON_BATTERY,
    no_battery = c.SDL_POWERSTATE_NO_BATTERY,
    charging = c.SDL_POWERSTATE_CHARGING,
    charged = c.SDL_POWERSTATE_CHARGED,
};

pub const HatFlag = struct {
    pub const centered = c.SDL_HAT_CENTERED;
    pub const up = c.SDL_HAT_UP;
    pub const right = c.SDL_HAT_RIGHT;
    pub const down = c.SDL_HAT_DOWN;
    pub const left = c.SDL_HAT_LEFT;
    pub const rightup = .right | .up;
    pub const rightdown = .right | .down;
    pub const leftup = .left | .up;
    pub const leftdown = .left | .down;
};

// see `HatFlag`
pub const HatFlags = u8;

pub const GamepadAxis = enum(i8) {
    invalid = c.SDL_GAMEPAD_AXIS_INVALID,
    leftx = c.SDL_GAMEPAD_AXIS_LEFTX,
    lefty = c.SDL_GAMEPAD_AXIS_LEFTY,
    rightx = c.SDL_GAMEPAD_AXIS_RIGHTX,
    righty = c.SDL_GAMEPAD_AXIS_RIGHTY,
    left_trigger = c.SDL_GAMEPAD_AXIS_LEFT_TRIGGER,
    right_trigger = c.SDL_GAMEPAD_AXIS_RIGHT_TRIGGER,
};

pub const GamepadButton = enum(i8) {
    invalid = c.SDL_GAMEPAD_BUTTON_INVALID,
    south = c.SDL_GAMEPAD_BUTTON_SOUTH,
    east = c.SDL_GAMEPAD_BUTTON_EAST,
    west = c.SDL_GAMEPAD_BUTTON_WEST,
    north = c.SDL_GAMEPAD_BUTTON_NORTH,
    back = c.SDL_GAMEPAD_BUTTON_BACK,
    guide = c.SDL_GAMEPAD_BUTTON_GUIDE,
    start = c.SDL_GAMEPAD_BUTTON_START,
    left_stick = c.SDL_GAMEPAD_BUTTON_LEFT_STICK,
    right_stick = c.SDL_GAMEPAD_BUTTON_RIGHT_STICK,
    left_shoulder = c.SDL_GAMEPAD_BUTTON_LEFT_SHOULDER,
    right_shoulder = c.SDL_GAMEPAD_BUTTON_RIGHT_SHOULDER,
    dpad_up = c.SDL_GAMEPAD_BUTTON_DPAD_UP,
    dpad_down = c.SDL_GAMEPAD_BUTTON_DPAD_DOWN,
    dpad_left = c.SDL_GAMEPAD_BUTTON_DPAD_LEFT,
    dpad_right = c.SDL_GAMEPAD_BUTTON_DPAD_RIGHT,
    right_paddle1 = c.SDL_GAMEPAD_BUTTON_RIGHT_PADDLE1,
    left_paddle1 = c.SDL_GAMEPAD_BUTTON_LEFT_PADDLE1,
    right_paddle2 = c.SDL_GAMEPAD_BUTTON_RIGHT_PADDLE2,
    left_paddle2 = c.SDL_GAMEPAD_BUTTON_LEFT_PADDLE2,
    touchpad = c.SDL_GAMEPAD_BUTTON_TOUCHPAD,
    misc1 = c.SDL_GAMEPAD_BUTTON_MISC1,
    misc2 = c.SDL_GAMEPAD_BUTTON_MISC2,
    misc3 = c.SDL_GAMEPAD_BUTTON_MISC3,
    misc4 = c.SDL_GAMEPAD_BUTTON_MISC4,
    misc5 = c.SDL_GAMEPAD_BUTTON_MISC5,
    misc6 = c.SDL_GAMEPAD_BUTTON_MISC6,
};

pub const SensorType = enum(i32) {
    invalid = c.SDL_SENSOR_INVALID,
    unknown = c.SDL_SENSOR_UNKNOWN,
    accel = c.SDL_SENSOR_ACCEL,
    gyro = c.SDL_SENSOR_GYRO,
    accel_l = c.SDL_SENSOR_ACCEL_L,
    gyro_l = c.SDL_SENSOR_GYRO_L,
    accel_r = c.SDL_SENSOR_ACCEL_R,
    gyro_r = c.SDL_SENSOR_GYRO_R,
};

pub const AudioDeviceID = enum(u32) { _ };

pub const CameraID = enum(u32) { _ };

pub const TouchID = enum(u32) { _ };

pub const FingerID = enum(u32) { _ };

pub const PenID = enum(u32) { _ };

pub const PenInputFlag = struct {
    pub const button_1 = @as(PenInputFlags, c.SDL_PEN_INPUT_BUTTON_1);
    pub const button_2 = @as(PenInputFlags, c.SDL_PEN_INPUT_BUTTON_2);
    pub const button_3 = @as(PenInputFlags, c.SDL_PEN_INPUT_BUTTON_3);
    pub const button_4 = @as(PenInputFlags, c.SDL_PEN_INPUT_BUTTON_4);
    pub const button_5 = @as(PenInputFlags, c.SDL_PEN_INPUT_BUTTON_5);
    pub const eraser_tip = @as(PenInputFlags, c.SDL_PEN_INPUT_ERASER_TIP);
};

// See `PenInputFlag`
pub const PenInputFlags = u32;

pub const PenAxis = enum(c_uint) {
    pressure = c.SDL_PEN_AXIS_PRESSURE,
    xtilt = c.SDL_PEN_AXIS_XTILT,
    ytilt = c.SDL_PEN_AXIS_YTILT,
    distance = c.SDL_PEN_AXIS_DISTANCE,
    rotation = c.SDL_PEN_AXIS_ROTATION,
    slider = c.SDL_PEN_AXIS_SLIDER,
    tangential_pressure = c.SDL_PEN_AXIS_TANGENTIAL_PRESSURE,
};

pub const SensorID = enum(u32) { _ };

pub const CommonEvent = extern struct {
    type: EventType,
    reserved: u32,
    timestamp: u64,
};

pub const DisplayEvent = extern struct {
    type: EventType,
    reserved: u32,
    timestamp: u64,
    display_id: DisplayID,
    data1: i32,
    data2: i32,
};

pub const WindowEvent = extern struct {
    type: EventType,
    reserved: u32,
    timestamp: u64,
    window_id: WindowID,
    data1: i32,
    data2: i32,
};

pub const KeyboardDeviceEvent = extern struct {
    type: EventType,
    reserved: u32,
    timestamp: u64,
    which: KeyboardID,
};

pub const KeyboardEvent = extern struct {
    type: EventType,
    reserved: u32,
    timestamp: u64,
    window_id: WindowID,
    which: KeyboardID,
    scancode: Scancode,
    key: Keycode,
    mod: Keymod,
    raw: u16,
    down: bool,
    repeat: bool,
};

pub const TextEditingEvent = extern struct {
    type: EventType,
    reserved: u32,
    timestamp: u64,
    window_id: WindowID,
    text: [*:0]const u8,
    start: i32,
    length: i32,
};

pub const TextEditingCandidatesEvent = extern struct {
    type: EventType,
    reserved: u32,
    timestamp: u64,
    window_id: WindowID,
    candidates: [*]const [*:0]const u8,
    num_candidates: i32,
    selected_candidate: i32,
    horizontal: bool,
    padding1: u8,
    padding2: u8,
    padding3: u8,
};

pub const TextInputEvent = extern struct {
    type: EventType,
    reserved: u32,
    timestamp: u64,
    window_id: WindowID,
    text: [*:0]const u8,
};

pub const MouseDeviceEvent = extern struct {
    type: EventType,
    reserved: u32,
    timestamp: u64,
    which: MouseID,
};

pub const MouseMotionEvent = extern struct {
    type: EventType,
    reserved: u32,
    timestamp: u64,
    window_id: WindowID,
    which: MouseID,
    state: MouseButtonFlags,
    x: f32,
    y: f32,
    xrel: f32,
    yrel: f32,
};

pub const MouseButtonEvent = extern struct {
    type: EventType,
    reserved: u32,
    timestamp: u64,
    window_id: WindowID,
    which: MouseID,
    button: MouseButton,
    down: bool,
    clicks: u8,
    padding: u8,
    x: f32,
    y: f32,
};

pub const MouseWheelEvent = extern struct {
    type: EventType,
    reserved: u32,
    timestamp: u64,
    window_id: WindowID,
    which: MouseID,
    x: f32,
    y: f32,
    direction: MouseWheelDirection,
    mouse_x: f32,
    mouse_y: f32,
};

pub const JoyAxisEvent = extern struct {
    type: EventType,
    reserved: u32,
    timestamp: u64,
    which: JoystickID,
    axis: u8,
    padding1: u8,
    padding2: u8,
    padding3: u8,
    value: i16,
    padding4: u16,
};

pub const JoyBallEvent = extern struct {
    type: EventType,
    reserved: u32,
    timestamp: u64,
    which: JoystickID,
    ball: u8,
    padding1: u8,
    padding2: u8,
    padding3: u8,
    xrel: i16,
    yrel: i16,
};

pub const JoyHatEvent = extern struct {
    type: EventType,
    reserved: u32,
    timestamp: u64,
    which: JoystickID,
    hat: HatFlags,
    value: u8,
    padding1: u8,
    padding2: u8,
};

pub const JoyButtonEvent = extern struct {
    type: EventType,
    reserved: u32,
    timestamp: u64,
    which: JoystickID,
    button: u8,
    down: bool,
    padding1: u8,
    padding2: u8,
};

pub const JoyDeviceEvent = extern struct {
    type: EventType,
    reserved: u32,
    timestamp: u64,
    which: JoystickID,
};

pub const JoyBatteryEvent = extern struct {
    type: EventType,
    reserved: u32,
    timestamp: u64,
    which: JoystickID,
    state: PowerState,
    percent: c_int,
};

pub const GamepadAxisEvent = extern struct {
    type: EventType,
    reserved: u32,
    timestamp: u64,
    which: JoystickID,
    axis: GamepadAxis,
    padding1: u8,
    padding2: u8,
    padding3: u8,
    value: i16,
    padding4: u16,
};

pub const GamepadButtonEvent = extern struct {
    type: EventType,
    reserved: u32,
    timestamp: u64,
    which: JoystickID,
    button: GamepadButton,
    down: bool,
    padding1: u8,
    padding2: u8,
};

pub const GamepadDeviceEvent = extern struct {
    type: EventType,
    reserved: u32,
    timestamp: u64,
    which: JoystickID,
};

pub const GamepadTouchpadEvent = extern struct {
    type: EventType,
    reserved: u32,
    timestamp: u64,
    which: JoystickID,
    touchpad: i32,
    finger: i32,
    x: f32,
    y: f32,
    pressure: f32,
};

pub const GamepadSensorEvent = extern struct {
    type: EventType,
    reserved: u32,
    timestamp: u64,
    which: JoystickID,
    sensor: SensorType,
    data: [3]f32,
    sensor_timestamp: u64,
};

pub const AudioDeviceEvent = extern struct {
    type: EventType,
    reserved: u32,
    timestamp: u64,
    which: AudioDeviceID,
    recording: bool,
    padding1: u8,
    padding2: u8,
    padding3: u8,
};

pub const CameraDeviceEvent = extern struct {
    type: EventType,
    reserved: u32,
    timestamp: u64,
    which: CameraID,
};

pub const RenderEvent = extern struct {
    type: EventType,
    reserved: u32,
    timestamp: u64,
    window_id: WindowID,
};

pub const TouchFingerEvent = extern struct {
    type: EventType,
    reserved: u32,
    timestamp: u64,
    touch_id: TouchID,
    finger_id: FingerID,
    x: f32,
    y: f32,
    dx: f32,
    dy: f32,
    pressure: f32,
    window_id: WindowID,
};

pub const PenProximityEvent = extern struct {
    type: EventType,
    reserved: u32,
    timestamp: u64,
    windowID: WindowID,
    which: PenID,
};

pub const PenMotionEvent = extern struct {
    type: EventType,
    reserved: u32,
    timestamp: u64,
    windowID: WindowID,
    which: PenID,
    pen_state: PenInputFlags,
    x: f32,
    y: f32,
};

pub const PenTouchEvent = extern struct {
    type: EventType,
    reserved: u32,
    timestamp: u64,
    window_id: WindowID,
    which: PenID,
    pen_state: PenInputFlags,
    x: f32,
    y: f32,
    eraser: bool,
    down: bool,
};

pub const PenButtonEvent = extern struct {
    type: EventType,
    reserved: u32,
    timestamp: u64,
    window_id: WindowID,
    which: PenID,
    pen_state: PenInputFlags,
    x: f32,
    y: f32,
    button: u8,
    down: bool,
};

pub const PenAxisEvent = extern struct {
    type: EventType,
    reserved: u32,
    timestamp: u64,
    window_id: WindowID,
    which: PenID,
    pen_state: PenInputFlags,
    x: f32,
    y: f32,
    axis: PenAxis,
    value: f32,
};

pub const DropEvent = extern struct {
    type: EventType,
    reserved: u32,
    timestamp: u64,
    window_id: WindowID,
    x: f32,
    y: f32,
    source: [*:0]const u8,
    data: [*:0]const u8,
};

pub const ClipboardEvent = extern struct {
    type: EventType,
    reserved: u32,
    timestamp: u64,
    owner: bool,
    num_mime_types: i32,
    mime_types: [*][*:0]const u8,
};

pub const SensorEvent = extern struct {
    type: EventType,
    reserved: u32,
    timestamp: u64,
    which: SensorID,
    data: [6]f32,
    sensor_timestamp: u64,
};

pub const QuitEvent = extern struct {
    type: EventType,
    reserved: u32,
    timestamp: u64,
};

pub const UserEvent = extern struct {
    type: EventType,
    reserved: u32,
    timestamp: u64,
    window_id: WindowID,
    code: i32,
    data1: ?*anyopaque,
    data2: ?*anyopaque,
};
