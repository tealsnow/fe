const std = @import("std");
const log = std.log;

const c = @cImport({
    @cInclude("SDL2/SDL.h");
});

pub const Error = error{Sdl};

pub const InitFlags = packed struct {
    timer: bool = false,
    audio: bool = false,
    video: bool = false,
    joystick: bool = false,
    haptic: bool = false,
    gamecontroller: bool = false,
    events: bool = false,
    sensor: bool = false,
    _padding: u24 = 0,

    pub fn fromInt(value: u32) InitFlags {
        return @bitCast(value);
    }

    pub fn toInt(self: InitFlags) u32 {
        return @bitCast(self);
    }

    comptime {
        std.debug.assert(@sizeOf(InitFlags) == @sizeOf(u32));
    }
};

pub fn init(flags: InitFlags) Error!void {
    if (c.SDL_Init(flags.toInt()) != 0)
        return error.Sdl;
}

pub fn quit() void {
    c.SDL_Quit();
}

pub fn getError() ?[]const u8 {
    if (c.SDL_GetError()) |err| {
        return std.mem.sliceTo(err, 0);
    } else {
        return null;
    }
}

pub const Window = opaque {
    pub const Position = struct {
        x: Axis = .undefined,
        y: Axis = .undefined,

        pub const Axis = union(enum) {
            centered: void,
            undefined: void,
            absolute: c_int,

            fn resolve(self: Axis) c_int {
                return switch (self) {
                    .centered => c.SDL_WINDOWPOS_CENTERED,
                    .undefined => c.SDL_WINDOWPOS_UNDEFINED,
                    .absolute => |pos| pos,
                };
            }
        };

        fn resolve(self: Position) struct { x: c_int, y: c_int } {
            return .{
                .x = self.x.resolve(),
                .y = self.y.resolve(),
            };
        }
    };

    pub const Size = struct {
        w: c_int,
        h: c_int,
    };

    pub const Flags = packed struct {
        fullscreen: bool = false,
        opengl: bool = false,
        shown: bool = false,
        hidden: bool = false,
        borderless: bool = false,
        resizable: bool = false,
        minimized: bool = false,
        maximized: bool = false,
        input_grabbed: bool = false,
        input_focus: bool = false,
        mouse_focus: bool = false,
        foreign: bool = false,
        fullscreen_desktop: bool = false,
        allow_highdpi: bool = false,
        mouse_capture: bool = false,
        _padding: u17 = 0,

        pub fn fromInt(value: u32) Flags {
            return @bitCast(value);
        }

        pub fn toInt(self: Flags) u32 {
            return @bitCast(self);
        }

        comptime {
            std.debug.assert(@sizeOf(Flags) == @sizeOf(u32));
        }
    };

    pub fn init(params: struct {
        title: [*c]const u8,
        position: Position = .{},
        size: Size,
        flags: Flags = .{},
    }) Error!*Window {
        const pos = params.position.resolve();
        const window = c.SDL_CreateWindow(
            params.title,
            pos.x,
            pos.y,
            params.size.w,
            params.size.h,
            params.flags.toInt(),
        ) orelse
            return error.Sdl;
        return @ptrCast(window);
    }

    pub fn deinit(self: *Window) void {
        c.SDL_DestroyWindow(@ptrCast(self));
    }

    pub fn show(self: *Window) void {
        c.SDL_ShowWindow(@ptrCast(self));
    }
};

pub const Renderer = opaque {
    pub const Flags = packed struct {
        software: bool = false,
        accelerated: bool = false,
        present_vsync: bool = false,
        target_texture: bool = false,
        _padding: u28 = 0,

        pub fn fromInt(value: u32) Flags {
            return @bitCast(value);
        }

        pub fn toInt(self: Flags) u32 {
            return @bitCast(self);
        }

        comptime {
            std.debug.assert(@sizeOf(Flags) == @sizeOf(u32));
        }
    };

    pub fn init(params: struct {
        window: *Window,
        index: c_int = -1,
        flags: Flags = .{},
    }) Error!*Renderer {
        const renderer = c.SDL_CreateRenderer(
            @ptrCast(params.window),
            params.index,
            params.flags.toInt(),
        ) orelse
            return error.Sdl;
        return @ptrCast(renderer);
    }

    pub fn deinit(self: *Renderer) void {
        c.SDL_DestroyRenderer(@ptrCast(self));
    }

    pub fn setDrawColor(self: *Renderer, r: u8, g: u8, b: u8, a: u8) Error!void {
        if (c.SDL_SetRenderDrawColor(@ptrCast(self), r, g, b, a) != 0)
            return error.Sdl;
    }

    pub fn clear(self: *Renderer) Error!void {
        if (c.SDL_RenderClear(@ptrCast(self)) != 0)
            return error.Sdl;
    }

    pub fn present(self: *Renderer) void {
        c.SDL_RenderPresent(@ptrCast(self));
    }
};

pub const Scancode = enum(c_int) {
    unknown = c.SDL_SCANCODE_UNKNOWN,
    a = c.SDL_SCANCODE_A,
    b = c.SDL_SCANCODE_B,
    c = c.SDL_SCANCODE_C,
    d = c.SDL_SCANCODE_D,
    e = c.SDL_SCANCODE_E,
    f = c.SDL_SCANCODE_F,
    g = c.SDL_SCANCODE_G,
    h = c.SDL_SCANCODE_H,
    i = c.SDL_SCANCODE_I,
    j = c.SDL_SCANCODE_J,
    k = c.SDL_SCANCODE_K,
    l = c.SDL_SCANCODE_L,
    m = c.SDL_SCANCODE_M,
    n = c.SDL_SCANCODE_N,
    o = c.SDL_SCANCODE_O,
    p = c.SDL_SCANCODE_P,
    q = c.SDL_SCANCODE_Q,
    r = c.SDL_SCANCODE_R,
    s = c.SDL_SCANCODE_S,
    t = c.SDL_SCANCODE_T,
    u = c.SDL_SCANCODE_U,
    v = c.SDL_SCANCODE_V,
    w = c.SDL_SCANCODE_W,
    x = c.SDL_SCANCODE_X,
    y = c.SDL_SCANCODE_Y,
    z = c.SDL_SCANCODE_Z,
    @"1" = c.SDL_SCANCODE_1,
    @"2" = c.SDL_SCANCODE_2,
    @"3" = c.SDL_SCANCODE_3,
    @"4" = c.SDL_SCANCODE_4,
    @"5" = c.SDL_SCANCODE_5,
    @"6" = c.SDL_SCANCODE_6,
    @"7" = c.SDL_SCANCODE_7,
    @"8" = c.SDL_SCANCODE_8,
    @"9" = c.SDL_SCANCODE_9,
    @"0" = c.SDL_SCANCODE_0,
    @"return" = c.SDL_SCANCODE_RETURN,
    escape = c.SDL_SCANCODE_ESCAPE,
    backspace = c.SDL_SCANCODE_BACKSPACE,
    tab = c.SDL_SCANCODE_TAB,
    space = c.SDL_SCANCODE_SPACE,
    minus = c.SDL_SCANCODE_MINUS,
    equals = c.SDL_SCANCODE_EQUALS,
    leftbracket = c.SDL_SCANCODE_LEFTBRACKET,
    rightbracket = c.SDL_SCANCODE_RIGHTBRACKET,
    backslash = c.SDL_SCANCODE_BACKSLASH,
    nonushash = c.SDL_SCANCODE_NONUSHASH,
    semicolon = c.SDL_SCANCODE_SEMICOLON,
    apostrophe = c.SDL_SCANCODE_APOSTROPHE,
    grave = c.SDL_SCANCODE_GRAVE,
    comma = c.SDL_SCANCODE_COMMA,
    period = c.SDL_SCANCODE_PERIOD,
    slash = c.SDL_SCANCODE_SLASH,
    capslock = c.SDL_SCANCODE_CAPSLOCK,
    f1 = c.SDL_SCANCODE_F1,
    f2 = c.SDL_SCANCODE_F2,
    f3 = c.SDL_SCANCODE_F3,
    f4 = c.SDL_SCANCODE_F4,
    f5 = c.SDL_SCANCODE_F5,
    f6 = c.SDL_SCANCODE_F6,
    f7 = c.SDL_SCANCODE_F7,
    f8 = c.SDL_SCANCODE_F8,
    f9 = c.SDL_SCANCODE_F9,
    f10 = c.SDL_SCANCODE_F10,
    f11 = c.SDL_SCANCODE_F11,
    f12 = c.SDL_SCANCODE_F12,
    printscreen = c.SDL_SCANCODE_PRINTSCREEN,
    scrolllock = c.SDL_SCANCODE_SCROLLLOCK,
    pause = c.SDL_SCANCODE_PAUSE,
    insert = c.SDL_SCANCODE_INSERT,
    home = c.SDL_SCANCODE_HOME,
    pageup = c.SDL_SCANCODE_PAGEUP,
    delete = c.SDL_SCANCODE_DELETE,
    end = c.SDL_SCANCODE_END,
    pagedown = c.SDL_SCANCODE_PAGEDOWN,
    right = c.SDL_SCANCODE_RIGHT,
    left = c.SDL_SCANCODE_LEFT,
    down = c.SDL_SCANCODE_DOWN,
    up = c.SDL_SCANCODE_UP,
    numlockclear = c.SDL_SCANCODE_NUMLOCKCLEAR,
    kp_divide = c.SDL_SCANCODE_KP_DIVIDE,
    kp_multiply = c.SDL_SCANCODE_KP_MULTIPLY,
    kp_minus = c.SDL_SCANCODE_KP_MINUS,
    kp_plus = c.SDL_SCANCODE_KP_PLUS,
    kp_enter = c.SDL_SCANCODE_KP_ENTER,
    kp_1 = c.SDL_SCANCODE_KP_1,
    kp_2 = c.SDL_SCANCODE_KP_2,
    kp_3 = c.SDL_SCANCODE_KP_3,
    kp_4 = c.SDL_SCANCODE_KP_4,
    kp_5 = c.SDL_SCANCODE_KP_5,
    kp_6 = c.SDL_SCANCODE_KP_6,
    kp_7 = c.SDL_SCANCODE_KP_7,
    kp_8 = c.SDL_SCANCODE_KP_8,
    kp_9 = c.SDL_SCANCODE_KP_9,
    kp_0 = c.SDL_SCANCODE_KP_0,
    kp_period = c.SDL_SCANCODE_KP_PERIOD,
    nonusbackslash = c.SDL_SCANCODE_NONUSBACKSLASH,
    application = c.SDL_SCANCODE_APPLICATION,
    power = c.SDL_SCANCODE_POWER,
    kp_equals = c.SDL_SCANCODE_KP_EQUALS,
    f13 = c.SDL_SCANCODE_F13,
    f14 = c.SDL_SCANCODE_F14,
    f15 = c.SDL_SCANCODE_F15,
    f16 = c.SDL_SCANCODE_F16,
    f17 = c.SDL_SCANCODE_F17,
    f18 = c.SDL_SCANCODE_F18,
    f19 = c.SDL_SCANCODE_F19,
    f20 = c.SDL_SCANCODE_F20,
    f21 = c.SDL_SCANCODE_F21,
    f22 = c.SDL_SCANCODE_F22,
    f23 = c.SDL_SCANCODE_F23,
    f24 = c.SDL_SCANCODE_F24,
    execute = c.SDL_SCANCODE_EXECUTE,
    help = c.SDL_SCANCODE_HELP,
    menu = c.SDL_SCANCODE_MENU,
    select = c.SDL_SCANCODE_SELECT,
    stop = c.SDL_SCANCODE_STOP,
    again = c.SDL_SCANCODE_AGAIN,
    undo = c.SDL_SCANCODE_UNDO,
    cut = c.SDL_SCANCODE_CUT,
    copy = c.SDL_SCANCODE_COPY,
    paste = c.SDL_SCANCODE_PASTE,
    find = c.SDL_SCANCODE_FIND,
    mute = c.SDL_SCANCODE_MUTE,
    volumeup = c.SDL_SCANCODE_VOLUMEUP,
    volumedown = c.SDL_SCANCODE_VOLUMEDOWN,
    kp_comma = c.SDL_SCANCODE_KP_COMMA,
    kp_equalsas400 = c.SDL_SCANCODE_KP_EQUALSAS400,
    international1 = c.SDL_SCANCODE_INTERNATIONAL1,
    international2 = c.SDL_SCANCODE_INTERNATIONAL2,
    international3 = c.SDL_SCANCODE_INTERNATIONAL3,
    international4 = c.SDL_SCANCODE_INTERNATIONAL4,
    international5 = c.SDL_SCANCODE_INTERNATIONAL5,
    international6 = c.SDL_SCANCODE_INTERNATIONAL6,
    international7 = c.SDL_SCANCODE_INTERNATIONAL7,
    international8 = c.SDL_SCANCODE_INTERNATIONAL8,
    international9 = c.SDL_SCANCODE_INTERNATIONAL9,
    lang1 = c.SDL_SCANCODE_LANG1,
    lang2 = c.SDL_SCANCODE_LANG2,
    lang3 = c.SDL_SCANCODE_LANG3,
    lang4 = c.SDL_SCANCODE_LANG4,
    lang5 = c.SDL_SCANCODE_LANG5,
    lang6 = c.SDL_SCANCODE_LANG6,
    lang7 = c.SDL_SCANCODE_LANG7,
    lang8 = c.SDL_SCANCODE_LANG8,
    lang9 = c.SDL_SCANCODE_LANG9,
    alterase = c.SDL_SCANCODE_ALTERASE,
    sysreq = c.SDL_SCANCODE_SYSREQ,
    cancel = c.SDL_SCANCODE_CANCEL,
    clear = c.SDL_SCANCODE_CLEAR,
    prior = c.SDL_SCANCODE_PRIOR,
    return2 = c.SDL_SCANCODE_RETURN2,
    separator = c.SDL_SCANCODE_SEPARATOR,
    out = c.SDL_SCANCODE_OUT,
    oper = c.SDL_SCANCODE_OPER,
    clearagain = c.SDL_SCANCODE_CLEARAGAIN,
    crsel = c.SDL_SCANCODE_CRSEL,
    exsel = c.SDL_SCANCODE_EXSEL,
    kp_00 = c.SDL_SCANCODE_KP_00,
    kp_000 = c.SDL_SCANCODE_KP_000,
    thousandsseparator = c.SDL_SCANCODE_THOUSANDSSEPARATOR,
    decimalseparator = c.SDL_SCANCODE_DECIMALSEPARATOR,
    currencyunit = c.SDL_SCANCODE_CURRENCYUNIT,
    currencysubunit = c.SDL_SCANCODE_CURRENCYSUBUNIT,
    kp_leftparen = c.SDL_SCANCODE_KP_LEFTPAREN,
    kp_rightparen = c.SDL_SCANCODE_KP_RIGHTPAREN,
    kp_leftbrace = c.SDL_SCANCODE_KP_LEFTBRACE,
    kp_rightbrace = c.SDL_SCANCODE_KP_RIGHTBRACE,
    kp_tab = c.SDL_SCANCODE_KP_TAB,
    kp_backspace = c.SDL_SCANCODE_KP_BACKSPACE,
    kp_a = c.SDL_SCANCODE_KP_A,
    kp_b = c.SDL_SCANCODE_KP_B,
    kp_c = c.SDL_SCANCODE_KP_C,
    kp_d = c.SDL_SCANCODE_KP_D,
    kp_e = c.SDL_SCANCODE_KP_E,
    kp_f = c.SDL_SCANCODE_KP_F,
    kp_xor = c.SDL_SCANCODE_KP_XOR,
    kp_power = c.SDL_SCANCODE_KP_POWER,
    kp_percent = c.SDL_SCANCODE_KP_PERCENT,
    kp_less = c.SDL_SCANCODE_KP_LESS,
    kp_greater = c.SDL_SCANCODE_KP_GREATER,
    kp_ampersand = c.SDL_SCANCODE_KP_AMPERSAND,
    kp_dblampersand = c.SDL_SCANCODE_KP_DBLAMPERSAND,
    kp_verticalbar = c.SDL_SCANCODE_KP_VERTICALBAR,
    kp_dblverticalbar = c.SDL_SCANCODE_KP_DBLVERTICALBAR,
    kp_colon = c.SDL_SCANCODE_KP_COLON,
    kp_hash = c.SDL_SCANCODE_KP_HASH,
    kp_space = c.SDL_SCANCODE_KP_SPACE,
    kp_at = c.SDL_SCANCODE_KP_AT,
    kp_exclam = c.SDL_SCANCODE_KP_EXCLAM,
    kp_memstore = c.SDL_SCANCODE_KP_MEMSTORE,
    kp_memrecall = c.SDL_SCANCODE_KP_MEMRECALL,
    kp_memclear = c.SDL_SCANCODE_KP_MEMCLEAR,
    kp_memadd = c.SDL_SCANCODE_KP_MEMADD,
    kp_memsubtract = c.SDL_SCANCODE_KP_MEMSUBTRACT,
    kp_memmultiply = c.SDL_SCANCODE_KP_MEMMULTIPLY,
    kp_memdivide = c.SDL_SCANCODE_KP_MEMDIVIDE,
    kp_plusminus = c.SDL_SCANCODE_KP_PLUSMINUS,
    kp_clear = c.SDL_SCANCODE_KP_CLEAR,
    kp_clearentry = c.SDL_SCANCODE_KP_CLEARENTRY,
    kp_binary = c.SDL_SCANCODE_KP_BINARY,
    kp_octal = c.SDL_SCANCODE_KP_OCTAL,
    kp_decimal = c.SDL_SCANCODE_KP_DECIMAL,
    kp_hexadecimal = c.SDL_SCANCODE_KP_HEXADECIMAL,
    lctrl = c.SDL_SCANCODE_LCTRL,
    lshift = c.SDL_SCANCODE_LSHIFT,
    lalt = c.SDL_SCANCODE_LALT,
    lgui = c.SDL_SCANCODE_LGUI,
    rctrl = c.SDL_SCANCODE_RCTRL,
    rshift = c.SDL_SCANCODE_RSHIFT,
    ralt = c.SDL_SCANCODE_RALT,
    rgui = c.SDL_SCANCODE_RGUI,
    mode = c.SDL_SCANCODE_MODE,
    audionext = c.SDL_SCANCODE_AUDIONEXT,
    audioprev = c.SDL_SCANCODE_AUDIOPREV,
    audiostop = c.SDL_SCANCODE_AUDIOSTOP,
    audioplay = c.SDL_SCANCODE_AUDIOPLAY,
    audiomute = c.SDL_SCANCODE_AUDIOMUTE,
    mediaselect = c.SDL_SCANCODE_MEDIASELECT,
    www = c.SDL_SCANCODE_WWW,
    mail = c.SDL_SCANCODE_MAIL,
    calculator = c.SDL_SCANCODE_CALCULATOR,
    computer = c.SDL_SCANCODE_COMPUTER,
    ac_search = c.SDL_SCANCODE_AC_SEARCH,
    ac_home = c.SDL_SCANCODE_AC_HOME,
    ac_back = c.SDL_SCANCODE_AC_BACK,
    ac_forward = c.SDL_SCANCODE_AC_FORWARD,
    ac_stop = c.SDL_SCANCODE_AC_STOP,
    ac_refresh = c.SDL_SCANCODE_AC_REFRESH,
    ac_bookmarks = c.SDL_SCANCODE_AC_BOOKMARKS,
    brightnessdown = c.SDL_SCANCODE_BRIGHTNESSDOWN,
    brightnessup = c.SDL_SCANCODE_BRIGHTNESSUP,
    displayswitch = c.SDL_SCANCODE_DISPLAYSWITCH,
    kbdillumtoggle = c.SDL_SCANCODE_KBDILLUMTOGGLE,
    kbdillumdown = c.SDL_SCANCODE_KBDILLUMDOWN,
    kbdillumup = c.SDL_SCANCODE_KBDILLUMUP,
    eject = c.SDL_SCANCODE_EJECT,
    sleep = c.SDL_SCANCODE_SLEEP,
    app1 = c.SDL_SCANCODE_APP1,
    app2 = c.SDL_SCANCODE_APP2,
    audiorewind = c.SDL_SCANCODE_AUDIOREWIND,
    audiofastforward = c.SDL_SCANCODE_AUDIOFASTFORWARD,
    softleft = c.SDL_SCANCODE_SOFTLEFT,
    softright = c.SDL_SCANCODE_SOFTRIGHT,
    call = c.SDL_SCANCODE_CALL,
    endcall = c.SDL_SCANCODE_ENDCALL,
    scancodes = c.SDL_NUM_SCANCODES,
};

pub const Keycode = enum(c_int) {
    unknown = c.SDLK_UNKNOWN,
    @"return" = c.SDLK_RETURN,
    escape = c.SDLK_ESCAPE,
    backspace = c.SDLK_BACKSPACE,
    tab = c.SDLK_TAB,
    space = c.SDLK_SPACE,
    exclaim = c.SDLK_EXCLAIM,
    quotedbl = c.SDLK_QUOTEDBL,
    hash = c.SDLK_HASH,
    percent = c.SDLK_PERCENT,
    dollar = c.SDLK_DOLLAR,
    ampersand = c.SDLK_AMPERSAND,
    quote = c.SDLK_QUOTE,
    leftparen = c.SDLK_LEFTPAREN,
    rightparen = c.SDLK_RIGHTPAREN,
    asterisk = c.SDLK_ASTERISK,
    plus = c.SDLK_PLUS,
    comma = c.SDLK_COMMA,
    minus = c.SDLK_MINUS,
    period = c.SDLK_PERIOD,
    slash = c.SDLK_SLASH,
    @"0" = c.SDLK_0,
    @"1" = c.SDLK_1,
    @"2" = c.SDLK_2,
    @"3" = c.SDLK_3,
    @"4" = c.SDLK_4,
    @"5" = c.SDLK_5,
    @"6" = c.SDLK_6,
    @"7" = c.SDLK_7,
    @"8" = c.SDLK_8,
    @"9" = c.SDLK_9,
    colon = c.SDLK_COLON,
    semicolon = c.SDLK_SEMICOLON,
    less = c.SDLK_LESS,
    equals = c.SDLK_EQUALS,
    greater = c.SDLK_GREATER,
    question = c.SDLK_QUESTION,
    at = c.SDLK_AT,
    leftbracket = c.SDLK_LEFTBRACKET,
    backslash = c.SDLK_BACKSLASH,
    rightbracket = c.SDLK_RIGHTBRACKET,
    caret = c.SDLK_CARET,
    underscore = c.SDLK_UNDERSCORE,
    backquote = c.SDLK_BACKQUOTE,
    a = c.SDLK_a,
    b = c.SDLK_b,
    c = c.SDLK_c,
    d = c.SDLK_d,
    e = c.SDLK_e,
    f = c.SDLK_f,
    g = c.SDLK_g,
    h = c.SDLK_h,
    i = c.SDLK_i,
    j = c.SDLK_j,
    k = c.SDLK_k,
    l = c.SDLK_l,
    m = c.SDLK_m,
    n = c.SDLK_n,
    o = c.SDLK_o,
    p = c.SDLK_p,
    q = c.SDLK_q,
    r = c.SDLK_r,
    s = c.SDLK_s,
    t = c.SDLK_t,
    u = c.SDLK_u,
    v = c.SDLK_v,
    w = c.SDLK_w,
    x = c.SDLK_x,
    y = c.SDLK_y,
    z = c.SDLK_z,
    capslock = c.SDLK_CAPSLOCK,
    f1 = c.SDLK_F1,
    f2 = c.SDLK_F2,
    f3 = c.SDLK_F3,
    f4 = c.SDLK_F4,
    f5 = c.SDLK_F5,
    f6 = c.SDLK_F6,
    f7 = c.SDLK_F7,
    f8 = c.SDLK_F8,
    f9 = c.SDLK_F9,
    f10 = c.SDLK_F10,
    f11 = c.SDLK_F11,
    f12 = c.SDLK_F12,
    printscreen = c.SDLK_PRINTSCREEN,
    scrolllock = c.SDLK_SCROLLLOCK,
    pause = c.SDLK_PAUSE,
    insert = c.SDLK_INSERT,
    home = c.SDLK_HOME,
    pageup = c.SDLK_PAGEUP,
    delete = c.SDLK_DELETE,
    end = c.SDLK_END,
    pagedown = c.SDLK_PAGEDOWN,
    right = c.SDLK_RIGHT,
    left = c.SDLK_LEFT,
    down = c.SDLK_DOWN,
    up = c.SDLK_UP,
    numlockclear = c.SDLK_NUMLOCKCLEAR,
    kp_divide = c.SDLK_KP_DIVIDE,
    kp_multiply = c.SDLK_KP_MULTIPLY,
    kp_minus = c.SDLK_KP_MINUS,
    kp_plus = c.SDLK_KP_PLUS,
    kp_enter = c.SDLK_KP_ENTER,
    kp_1 = c.SDLK_KP_1,
    kp_2 = c.SDLK_KP_2,
    kp_3 = c.SDLK_KP_3,
    kp_4 = c.SDLK_KP_4,
    kp_5 = c.SDLK_KP_5,
    kp_6 = c.SDLK_KP_6,
    kp_7 = c.SDLK_KP_7,
    kp_8 = c.SDLK_KP_8,
    kp_9 = c.SDLK_KP_9,
    kp_0 = c.SDLK_KP_0,
    kp_period = c.SDLK_KP_PERIOD,
    application = c.SDLK_APPLICATION,
    power = c.SDLK_POWER,
    kp_equals = c.SDLK_KP_EQUALS,
    f13 = c.SDLK_F13,
    f14 = c.SDLK_F14,
    f15 = c.SDLK_F15,
    f16 = c.SDLK_F16,
    f17 = c.SDLK_F17,
    f18 = c.SDLK_F18,
    f19 = c.SDLK_F19,
    f20 = c.SDLK_F20,
    f21 = c.SDLK_F21,
    f22 = c.SDLK_F22,
    f23 = c.SDLK_F23,
    f24 = c.SDLK_F24,
    execute = c.SDLK_EXECUTE,
    help = c.SDLK_HELP,
    menu = c.SDLK_MENU,
    select = c.SDLK_SELECT,
    stop = c.SDLK_STOP,
    again = c.SDLK_AGAIN,
    undo = c.SDLK_UNDO,
    cut = c.SDLK_CUT,
    copy = c.SDLK_COPY,
    paste = c.SDLK_PASTE,
    find = c.SDLK_FIND,
    mute = c.SDLK_MUTE,
    volumeup = c.SDLK_VOLUMEUP,
    volumedown = c.SDLK_VOLUMEDOWN,
    kp_comma = c.SDLK_KP_COMMA,
    kp_equalsas400 = c.SDLK_KP_EQUALSAS400,
    alterase = c.SDLK_ALTERASE,
    sysreq = c.SDLK_SYSREQ,
    cancel = c.SDLK_CANCEL,
    clear = c.SDLK_CLEAR,
    prior = c.SDLK_PRIOR,
    return2 = c.SDLK_RETURN2,
    separator = c.SDLK_SEPARATOR,
    out = c.SDLK_OUT,
    oper = c.SDLK_OPER,
    clearagain = c.SDLK_CLEARAGAIN,
    crsel = c.SDLK_CRSEL,
    exsel = c.SDLK_EXSEL,
    kp_00 = c.SDLK_KP_00,
    kp_000 = c.SDLK_KP_000,
    thousandsseparator = c.SDLK_THOUSANDSSEPARATOR,
    decimalseparator = c.SDLK_DECIMALSEPARATOR,
    currencyunit = c.SDLK_CURRENCYUNIT,
    currencysubunit = c.SDLK_CURRENCYSUBUNIT,
    kp_leftparen = c.SDLK_KP_LEFTPAREN,
    kp_rightparen = c.SDLK_KP_RIGHTPAREN,
    kp_leftbrace = c.SDLK_KP_LEFTBRACE,
    kp_rightbrace = c.SDLK_KP_RIGHTBRACE,
    kp_tab = c.SDLK_KP_TAB,
    kp_backspace = c.SDLK_KP_BACKSPACE,
    kp_a = c.SDLK_KP_A,
    kp_b = c.SDLK_KP_B,
    kp_c = c.SDLK_KP_C,
    kp_d = c.SDLK_KP_D,
    kp_e = c.SDLK_KP_E,
    kp_f = c.SDLK_KP_F,
    kp_xor = c.SDLK_KP_XOR,
    kp_power = c.SDLK_KP_POWER,
    kp_percent = c.SDLK_KP_PERCENT,
    kp_less = c.SDLK_KP_LESS,
    kp_greater = c.SDLK_KP_GREATER,
    kp_ampersand = c.SDLK_KP_AMPERSAND,
    kp_dblampersand = c.SDLK_KP_DBLAMPERSAND,
    kp_verticalbar = c.SDLK_KP_VERTICALBAR,
    kp_dblverticalbar = c.SDLK_KP_DBLVERTICALBAR,
    kp_colon = c.SDLK_KP_COLON,
    kp_hash = c.SDLK_KP_HASH,
    kp_space = c.SDLK_KP_SPACE,
    kp_at = c.SDLK_KP_AT,
    kp_exclam = c.SDLK_KP_EXCLAM,
    kp_memstore = c.SDLK_KP_MEMSTORE,
    kp_memrecall = c.SDLK_KP_MEMRECALL,
    kp_memclear = c.SDLK_KP_MEMCLEAR,
    kp_memadd = c.SDLK_KP_MEMADD,
    kp_memsubtract = c.SDLK_KP_MEMSUBTRACT,
    kp_memmultiply = c.SDLK_KP_MEMMULTIPLY,
    kp_memdivide = c.SDLK_KP_MEMDIVIDE,
    kp_plusminus = c.SDLK_KP_PLUSMINUS,
    kp_clear = c.SDLK_KP_CLEAR,
    kp_clearentry = c.SDLK_KP_CLEARENTRY,
    kp_binary = c.SDLK_KP_BINARY,
    kp_octal = c.SDLK_KP_OCTAL,
    kp_decimal = c.SDLK_KP_DECIMAL,
    kp_hexadecimal = c.SDLK_KP_HEXADECIMAL,
    lctrl = c.SDLK_LCTRL,
    lshift = c.SDLK_LSHIFT,
    lalt = c.SDLK_LALT,
    lgui = c.SDLK_LGUI,
    rctrl = c.SDLK_RCTRL,
    rshift = c.SDLK_RSHIFT,
    ralt = c.SDLK_RALT,
    rgui = c.SDLK_RGUI,
    mode = c.SDLK_MODE,
    audionext = c.SDLK_AUDIONEXT,
    audioprev = c.SDLK_AUDIOPREV,
    audiostop = c.SDLK_AUDIOSTOP,
    audioplay = c.SDLK_AUDIOPLAY,
    audiomute = c.SDLK_AUDIOMUTE,
    mediaselect = c.SDLK_MEDIASELECT,
    www = c.SDLK_WWW,
    mail = c.SDLK_MAIL,
    calculator = c.SDLK_CALCULATOR,
    computer = c.SDLK_COMPUTER,
    ac_search = c.SDLK_AC_SEARCH,
    ac_home = c.SDLK_AC_HOME,
    ac_back = c.SDLK_AC_BACK,
    ac_forward = c.SDLK_AC_FORWARD,
    ac_stop = c.SDLK_AC_STOP,
    ac_refresh = c.SDLK_AC_REFRESH,
    ac_bookmarks = c.SDLK_AC_BOOKMARKS,
    brightnessdown = c.SDLK_BRIGHTNESSDOWN,
    brightnessup = c.SDLK_BRIGHTNESSUP,
    displayswitch = c.SDLK_DISPLAYSWITCH,
    kbdillumtoggle = c.SDLK_KBDILLUMTOGGLE,
    kbdillumdown = c.SDLK_KBDILLUMDOWN,
    kbdillumup = c.SDLK_KBDILLUMUP,
    eject = c.SDLK_EJECT,
    sleep = c.SDLK_SLEEP,
    app1 = c.SDLK_APP1,
    app2 = c.SDLK_APP2,
    audiorewind = c.SDLK_AUDIOREWIND,
    audiofastforward = c.SDLK_AUDIOFASTFORWARD,
    softleft = c.SDLK_SOFTLEFT,
    softright = c.SDLK_SOFTRIGHT,
    call = c.SDLK_CALL,
    endcall = c.SDLK_ENDCALL,
};

pub const Keysym = extern struct {
    scancode: Scancode,
    sym: Keycode,
    mod: ModFlags,
    unused: u32,

    pub const ModFlags = packed struct {
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
        _reserved: u4 = 0,

        pub fn ctrl(self: ModFlags) bool {
            return self.lctrl || self.rctrl;
        }

        pub fn shift(self: ModFlags) bool {
            return self.lshift || self.rshift;
        }

        pub fn alt(self: ModFlags) bool {
            return self.lalt || self.ralt;
        }

        pub fn gui(self: ModFlags) bool {
            return self.lgui || self.rgui;
        }

        pub fn fromInt(value: u16) ModFlags {
            return @bitCast(value);
        }

        pub fn toInt(self: ModFlags) u16 {
            return @bitCast(self);
        }

        comptime {
            std.debug.assert(@sizeOf(ModFlags) == @sizeOf(u16));
        }
    };
};

pub const Event = struct {
    timestamp: u32, // ms
    type: Type,

    pub const Type = union(enum) {
        display: DisplayEvent,
        window: WindowEvent,
        key: KeyboardEvent,
        textedit: TextEditingEvent,
        textedit_ext: TextEditingExtEvent,
        text: c.SDL_TextInputEvent,
        // motion: c.SDL_MouseMotionEvent,
        // button: c.SDL_MouseButtonEvent,
        // wheel: c.SDL_MouseWheelEvent,
        // jaxis: c.SDL_JoyAxisEvent,
        // jball: c.SDL_JoyBallEvent,
        // jhat: c.SDL_JoyHatEvent,
        // jbutton: c.SDL_JoyButtonEvent,
        // jdevice: c.SDL_JoyDeviceEvent,
        // jbattery: c.SDL_JoyBatteryEvent,
        // caxis: c.SDL_ControllerAxisEvent,
        // cbutton: c.SDL_ControllerButtonEvent,
        // cdevice: c.SDL_ControllerDeviceEvent,
        // ctouchpad: c.SDL_ControllerTouchpadEvent,
        // csensor: c.SDL_ControllerSensorEvent,
        // adevice: c.SDL_AudioDeviceEvent,
        // sensor: c.SDL_SensorEvent,
        quit: void,
        // user: c.SDL_UserEvent,
        syswm: ?*anyopaque,
        // tfinger: c.SDL_TouchFingerEvent,
        // mgesture: c.SDL_MultiGestureEvent,
        // dgesture: c.SDL_DollarGestureEvent,
        // drop: c.SDL_DropEvent,

        app_terminating: void,
        app_low_memory: void,
        app_will_enter_background: void,
        app_did_enter_background: void,
        app_will_enter_foreground: void,
        app_did_enter_foreground: void,

        locale_changed: void,

        todo: void,
    };

    pub fn poll() ?Event {
        var event: c.SDL_Event = undefined;
        return if (c.SDL_PollEvent(&event) != 0)
            fromSdl(&event)
        else
            null;
    }

    pub fn wait() ?Event {
        var event: c.SDL_Event = undefined;
        return if (c.SDL_WaitEvent(&event) != 0)
            fromSdl(&event)
        else
            null;
    }

    pub fn waitTimeout(timeout: c_int) ?Event {
        var event: c.SDL_Event = undefined;
        return if (c.SDL_WaitEventTimeout(&event, timeout) != 0)
            fromSdl(&event)
        else
            null;
    }

    pub fn fromSdl(event: *const c.SDL_Event) Event {
        const ty: Type = switch (event.type) {
            c.SDL_QUIT => .quit,

            c.SDL_APP_TERMINATING => .app_terminating,
            c.SDL_APP_LOWMEMORY => .app_low_memory,
            c.SDL_APP_WILLENTERBACKGROUND => .app_will_enter_background,
            c.SDL_APP_DIDENTERBACKGROUND => .app_did_enter_background,
            c.SDL_APP_WILLENTERFOREGROUND => .app_will_enter_foreground,
            c.SDL_APP_DIDENTERFOREGROUND => .app_did_enter_foreground,

            c.SDL_LOCALECHANGED => .locale_changed,

            c.SDL_DISPLAYEVENT => .{ .display = .{
                .display = event.display.display,
                .event = @enumFromInt(event.display.event),
                .data = event.display.data1,
            } },

            c.SDL_WINDOWEVENT => .{ .window = .{
                .windowID = event.window.windowID,
                .event = @enumFromInt(event.window.event),
                .data1 = event.window.data1,
                .data2 = event.window.data2,
            } },

            c.SDL_SYSWMEVENT => .{ .syswm = event.syswm.msg },

            // FIXME: Workarround as `c.SDL_KEYDOWN | c.SDL_KEYUP =>` syntax seems to be broken
            //  it only runs for the last one, resulting in only keyup events
            c.SDL_KEYDOWN => .{ .key = createKeyboardEvent(event.key) },
            c.SDL_KEYUP => .{ .key = createKeyboardEvent(event.key) },

            c.SDL_TEXTEDITING => .{ .textedit = .{
                .windowID = event.edit.windowID,
                .text = event.edit.text,
                .start = event.edit.start,
                .length = event.edit.length,
            } },
            c.SDL_TEXTEDITING_EXT => .{ .textedit_ext = .{
                .windowID = event.editExt.windowID,
                .text = event.editExt.text,
                .start = event.editExt.start,
                .length = event.editExt.length,
            } },
            c.SDL_TEXTINPUT => .{ .text = .{
                .windowID = event.text.windowID,
                .text = event.text.text,
            } },

            // c.SDL_KEYMAPCHANGED => {},
            // c.SDL_MOUSEMOTION => {},
            // c.SDL_MOUSEBUTTONDOWN => {},
            // c.SDL_MOUSEBUTTONUP => {},
            // c.SDL_MOUSEWHEEL => {},
            // c.SDL_JOYAXISMOTION => {},
            // c.SDL_JOYBALLMOTION => {},
            // c.SDL_JOYHATMOTION => {},
            // c.SDL_JOYBUTTONDOWN => {},
            // c.SDL_JOYBUTTONUP => {},
            // c.SDL_JOYDEVICEADDED => {},
            // c.SDL_JOYDEVICEREMOVED => {},
            // c.SDL_JOYBATTERYUPDATED => {},
            // c.SDL_CONTROLLERAXISMOTION => {},
            // c.SDL_CONTROLLERBUTTONDOWN => {},
            // c.SDL_CONTROLLERBUTTONUP => {},
            // c.SDL_CONTROLLERDEVICEADDED => {},
            // c.SDL_CONTROLLERDEVICEREMOVED => {},
            // c.SDL_CONTROLLERDEVICEREMAPPED => {},
            // c.SDL_CONTROLLERTOUCHPADDOWN => {},
            // c.SDL_CONTROLLERTOUCHPADMOTION => {},
            // c.SDL_CONTROLLERTOUCHPADUP => {},
            // c.SDL_CONTROLLERSENSORUPDATE => {},
            // c.SDL_CONTROLLERUPDATECOMPLETE_RESERVED_FOR_SDL3 => {},
            // c.SDL_CONTROLLERSTEAMHANDLEUPDATED => {},
            // c.SDL_FINGERDOWN => {},
            // c.SDL_FINGERUP => {},
            // c.SDL_FINGERMOTION => {},
            // c.SDL_DOLLARGESTURE => {},
            // c.SDL_DOLLARRECORD => {},
            // c.SDL_MULTIGESTURE => {},
            // c.SDL_CLIPBOARDUPDATE => {},
            // c.SDL_DROPFILE => {},
            // c.SDL_DROPTEXT => {},
            // c.SDL_DROPBEGIN => {},
            // c.SDL_DROPCOMPLETE => {},
            // c.SDL_AUDIODEVICEADDED => {},
            // c.SDL_AUDIODEVICEREMOVED => {},
            // c.SDL_SENSORUPDATE => {},
            // c.SDL_RENDER_TARGETS_RESET => {},
            // c.SDL_RENDER_DEVICE_RESET => {},
            // c.SDL_POLLSENTINEL => {},
            // c.SDL_USEREVENT => {},

            else => .todo,
        };
        return .{ .timestamp = event.common.timestamp, .type = ty };
    }

    fn createKeyboardEvent(key: c.SDL_KeyboardEvent) KeyboardEvent {
        return .{
            .windowID = key.windowID,
            .state = @enumFromInt(key.state),
            .repeat = key.repeat,
            .keysym = @bitCast(key.keysym),
        };
    }
};

pub const DisplayEvent = struct {
    display: u32,
    event: ID,
    data: i32,

    pub const ID = enum(u8) {
        none = c.SDL_DISPLAYEVENT_NONE,
        orientation = c.SDL_DISPLAYEVENT_ORIENTATION,
        connected = c.SDL_DISPLAYEVENT_CONNECTED,
        disconnected = c.SDL_DISPLAYEVENT_DISCONNECTED,
        moved = c.SDL_DISPLAYEVENT_MOVED,
    };
};

pub const WindowEvent = struct {
    windowID: u32,
    event: ID,
    data1: i32,
    data2: i32,

    pub const ID = enum(u8) {
        none = c.SDL_WINDOWEVENT_NONE,
        shown = c.SDL_WINDOWEVENT_SHOWN,
        hidden = c.SDL_WINDOWEVENT_HIDDEN,
        exposed = c.SDL_WINDOWEVENT_EXPOSED,
        moved = c.SDL_WINDOWEVENT_MOVED,
        resized = c.SDL_WINDOWEVENT_RESIZED,
        size_changed = c.SDL_WINDOWEVENT_SIZE_CHANGED,
        minimized = c.SDL_WINDOWEVENT_MINIMIZED,
        maximized = c.SDL_WINDOWEVENT_MAXIMIZED,
        restored = c.SDL_WINDOWEVENT_RESTORED,
        enter = c.SDL_WINDOWEVENT_ENTER,
        leave = c.SDL_WINDOWEVENT_LEAVE,
        focus_gained = c.SDL_WINDOWEVENT_FOCUS_GAINED,
        focus_lost = c.SDL_WINDOWEVENT_FOCUS_LOST,
        close = c.SDL_WINDOWEVENT_CLOSE,
        take_focus = c.SDL_WINDOWEVENT_TAKE_FOCUS,
        hit_test = c.SDL_WINDOWEVENT_HIT_TEST,
        iccprof_changed = c.SDL_WINDOWEVENT_ICCPROF_CHANGED,
        display_changed = c.SDL_WINDOWEVENT_DISPLAY_CHANGED,
    };
};

pub const KeyboardEvent = struct {
    windowID: u32,
    state: State,
    repeat: u8,
    keysym: Keysym,

    pub const State = enum(u8) {
        released = 0,
        pressed = 1,
    };
};

pub const TextEditingEvent = struct {
    windowID: u32,
    text: [32]u8,
    start: i32,
    length: i32,
};

pub const TextEditingExtEvent = struct {
    windowID: u32,
    text: [*c]u8,
    start: i32,
    length: i32,
};

pub const TextInputEvent = struct {
    windowID: u32,
    text: [32:0]u8,
};

pub const MemoryFunctions = struct {
    malloc: c.SDL_malloc_func,
    calloc: c.SDL_calloc_func,
    realloc: c.SDL_realloc_func,
    free: c.SDL_free_func,
};

pub fn setMemoryFunctions(funcs: MemoryFunctions) !void {
    if (c.SDL_SetMemoryFunctions(
        funcs.malloc,
        funcs.calloc,
        funcs.realloc,
        funcs.free,
    ) != 0)
        return error.Sdl;
}

pub fn getMemoryFunctions() MemoryFunctions {
    var funcs: MemoryFunctions = undefined;
    c.SDL_GetMemoryFunctions(
        &funcs.malloc,
        &funcs.calloc,
        &funcs.realloc,
        &funcs.free,
    );
    return funcs;
}
