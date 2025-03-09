const std = @import("std");

pub const c = @cImport({
    @cInclude("SDL2/SDL.h");
    @cInclude("SDL2/SDL_syswm.h");
    @cInclude("SDL2/SDL_ttf.h");
});

pub const ttf = @import("ttf.zig");

pub const Error = error{Sdl};

pub const Rect = c.SDL_Rect;
pub const FRect = c.SDL_FRect;
pub const Point = c.SDL_Point;
pub const FPoint = c.SDL_FPoint;
pub const Color = c.SDL_Color;

pub const InitFlags = packed struct(u32) {
    timer: bool = false,
    audio: bool = false,
    video: bool = false,
    joystick: bool = false,
    haptic: bool = false,
    gamecontroller: bool = false,
    events: bool = false,
    sensor: bool = false,
    _padding: enum(u24) { zero } = .zero,

    pub const All = InitFlags{
        .timer = true,
        .audio = true,
        .video = true,
        .joystick = true,
        .haptic = true,
        .gamecontroller = true,
        .events = true,
        .sensor = true,
    };

    pub inline fn fromInt(value: u32) InitFlags {
        return @bitCast(value);
    }

    pub inline fn asInt(self: InitFlags) u32 {
        return @bitCast(self);
    }
};

pub fn init(flags: InitFlags) Error!void {
    if (c.SDL_Init(flags.asInt()) != 0)
        return error.Sdl;
}

pub fn quit() void {
    c.SDL_Quit();
}

pub fn getError() ?[:0]const u8 {
    const err = c.SDL_GetError();
    return if (err != null)
        std.mem.sliceTo(err, 0)
    else
        null;
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

    // @FIXME: might be a better idea to make this an actual bit set
    pub const Flag = struct {
        pub const fullscreen = @as(Flags, c.SDL_WINDOW_FULLSCREEN);
        pub const opengl = @as(Flags, c.SDL_WINDOW_OPENGL);
        pub const shown = @as(Flags, c.SDL_WINDOW_SHOWN);
        pub const hidden = @as(Flags, c.SDL_WINDOW_HIDDEN);
        pub const borderless = @as(Flags, c.SDL_WINDOW_BORDERLESS);
        pub const resizable = @as(Flags, c.SDL_WINDOW_RESIZABLE);
        pub const minimized = @as(Flags, c.SDL_WINDOW_MINIMIZED);
        pub const maximized = @as(Flags, c.SDL_WINDOW_MAXIMIZED);
        pub const mouse_grabbed = @as(Flags, c.SDL_WINDOW_MOUSE_GRABBED);
        pub const input_focus = @as(Flags, c.SDL_WINDOW_INPUT_FOCUS);
        pub const mouse_focus = @as(Flags, c.SDL_WINDOW_MOUSE_FOCUS);
        pub const fullscreen_desktop = @as(Flags, c.SDL_WINDOW_FULLSCREEN_DESKTOP);
        pub const foreign = @as(Flags, c.SDL_WINDOW_FOREIGN);
        pub const allow_highdpi = @as(Flags, c.SDL_WINDOW_ALLOW_HIGHDPI);
        pub const mouse_capture = @as(Flags, c.SDL_WINDOW_MOUSE_CAPTURE);
        pub const always_on_top = @as(Flags, c.SDL_WINDOW_ALWAYS_ON_TOP);
        pub const skip_taskbar = @as(Flags, c.SDL_WINDOW_SKIP_TASKBAR);
        pub const utility = @as(Flags, c.SDL_WINDOW_UTILITY);
        pub const tooltip = @as(Flags, c.SDL_WINDOW_TOOLTIP);
        pub const popup_menu = @as(Flags, c.SDL_WINDOW_POPUP_MENU);
        pub const keyboard_grabbed = @as(Flags, c.SDL_WINDOW_KEYBOARD_GRABBED);
        pub const vulkan = @as(Flags, c.SDL_WINDOW_VULKAN);
        pub const metal = @as(Flags, c.SDL_WINDOW_METAL);
        pub const input_grabbed = @as(Flags, c.SDL_WINDOW_INPUT_GRABBED);
    };

    pub const Flags = c_uint;

    pub fn init(params: struct {
        title: [*c]const u8,
        position: Position,
        size: Size,
        flags: Flags,
    }) Error!*Window {
        const pos = params.position.resolve();
        const window = c.SDL_CreateWindow(
            params.title,
            pos.x,
            pos.y,
            params.size.w,
            params.size.h,
            params.flags,
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

    pub fn size(self: *Window) Size {
        var s: Size = undefined;
        c.SDL_GetWindowSize(@ptrCast(self), &s.w, &s.h);
        return s;
    }

    pub fn getID(self: *Window) u32 {
        return c.SDL_GetWindowID(@ptrCast(self));
    }
};

pub const Renderer = opaque {
    pub const Flags = packed struct(u32) {
        software: bool = false,
        accelerated: bool = false,
        present_vsync: bool = false,
        target_texture: bool = false,
        _padding: enum(u28) { zero } = .zero,

        pub inline fn fromInt(value: u32) Flags {
            return @bitCast(value);
        }

        pub inline fn asInt(self: Flags) u32 {
            return @bitCast(self);
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
            params.flags.asInt(),
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

    pub fn setDrawColorT(self: *Renderer, color: Color) Error!void {
        if (c.SDL_SetRenderDrawColor(@ptrCast(self), color.r, color.g, color.b, color.a) != 0)
            return error.Sdl;
    }

    pub fn drawRect(self: *Renderer, rect: *const Rect) Error!void {
        if (c.SDL_RenderDrawRect(@ptrCast(self), rect) != 0)
            return error.Sdl;
    }

    pub fn drawRectF(self: *Renderer, rect: *const FRect) Error!void {
        if (c.SDL_RenderDrawRectF(@ptrCast(self), rect) != 0)
            return error.Sdl;
    }

    pub fn fillRectF(self: *Renderer, rect: *const FRect) Error!void {
        if (c.SDL_RenderFillRectF(@ptrCast(self), rect) != 0)
            return error.Sdl;
    }

    pub fn drawLineF(self: *Renderer, x1: f32, y1: f32, x2: f32, y2: f32) Error!void {
        if (c.SDL_RenderDrawLineF(@ptrCast(self), x1, y1, x2, y2) != 0)
            return error.Sdl;
    }

    pub fn drawLinesF(self: *Renderer, points: []const FPoint) Error!void {
        if (c.SDL_RenderDrawLinesF(@ptrCast(self), points.ptr, @intCast(points.len)) != 0)
            return error.Sdl;
    }

    pub fn setClipRect(self: *Renderer, rect: ?*const Rect) Error!void {
        if (c.SDL_RenderSetClipRect(@ptrCast(self), rect) != 0)
            return error.Sdl;
    }

    pub fn clear(self: *Renderer) Error!void {
        if (c.SDL_RenderClear(@ptrCast(self)) != 0)
            return error.Sdl;
    }

    pub fn present(self: *Renderer) void {
        c.SDL_RenderPresent(@ptrCast(self));
    }

    pub fn createTextureFromSurface(self: *Renderer, surface: *Surface) Error!*Texture {
        const texture = c.SDL_CreateTextureFromSurface(
            @ptrCast(self),
            @alignCast(@ptrCast(surface)),
        ) orelse return error.Sdl;
        return @ptrCast(@alignCast(texture));
    }

    pub fn renderCopy(
        self: *Renderer,
        texture: *Texture,
        src_rect: ?*const Rect,
        dest_rect: ?*const Rect,
    ) Error!void {
        if (c.SDL_RenderCopy(
            @ptrCast(self),
            @ptrCast(texture),
            src_rect,
            dest_rect,
        ) != 0)
            return error.Sdl;
    }

    pub fn renderCopyF(
        self: *Renderer,
        texture: *Texture,
        src_rect: ?*const Rect,
        dest_rect: ?*const FRect,
    ) Error!void {
        if (c.SDL_RenderCopyF(
            @ptrCast(self),
            @ptrCast(texture),
            src_rect,
            dest_rect,
        ) != 0)
            return error.Sdl;
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
    _unused: u32 = 0,

    pub const ModFlags = packed struct(u16) {
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

        pub fn ctrl(self: ModFlags) bool {
            return self.lctrl or self.rctrl;
        }

        pub fn shift(self: ModFlags) bool {
            return self.lshift or self.rshift;
        }

        pub fn alt(self: ModFlags) bool {
            return self.lalt or self.ralt;
        }

        pub fn gui(self: ModFlags) bool {
            return self.lgui or self.rgui;
        }

        pub inline fn fromInt(value: u16) ModFlags {
            return @bitCast(value);
        }

        pub inline fn toInt(self: ModFlags) u16 {
            return @bitCast(self);
        }
    };
};

pub const Event = struct {
    original: *const c.SDL_Event,
    timestamp: u32, // ms
    type: Type,

    pub const Type = union(enum) {
        display: DisplayEvent,
        window: WindowEvent,
        key: KeyboardEvent,
        textedit: TextEditingEvent,
        textedit_ext: TextEditingExtEvent,
        text: TextInputEvent,
        motion: MouseMotionEvent,
        button: MouseButtonEvent,
        tfinger: TouchFingerEvent,
        mgesture: MultiGestureEvent,
        wheel: MouseWheelEvent,
        //
        // jaxis: c.SDL_JoyAxisEvent,
        // jball: c.SDL_JoyBallEvent,
        // jhat: c.SDL_JoyHatEvent,
        // jbutton: c.SDL_JoyButtonEvent,
        // jdevice: c.SDL_JoyDeviceEvent,
        // jbattery: c.SDL_JoyBatteryEvent,
        //
        // caxis: c.SDL_ControllerAxisEvent,
        // cbutton: c.SDL_ControllerButtonEvent,
        // cdevice: c.SDL_ControllerDeviceEvent,
        // ctouchpad: c.SDL_ControllerTouchpadEvent,
        // csensor: c.SDL_ControllerSensorEvent,
        //
        // adevice: c.SDL_AudioDeviceEvent,
        // sensor: c.SDL_SensorEvent,
        //
        quit: void,
        // user: c.SDL_UserEvent,
        syswm: ?*anyopaque,
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
            decode(&event)
        else
            null;
    }

    pub fn wait() ?Event {
        var event: c.SDL_Event = undefined;
        return if (c.SDL_WaitEvent(&event) != 0)
            decode(&event)
        else
            null;
    }

    pub fn waitTimeout(timeout: c_int) ?Event {
        var event: c.SDL_Event = undefined;
        return if (c.SDL_WaitEventTimeout(&event, timeout) != 0)
            decode(&event)
        else
            null;
    }

    pub fn decode(event: *const c.SDL_Event) Event {
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

            c.SDL_KEYDOWN, c.SDL_KEYUP => .{ .key = .{
                .windowID = event.key.windowID,
                .state = @enumFromInt(event.key.state),
                .repeat = event.key.repeat,
                .keysym = @bitCast(event.key.keysym),
            } },

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

            c.SDL_MOUSEMOTION => .{ .motion = .{
                .windowID = event.motion.windowID,
                .which = event.motion.which,
                .state = @bitCast(event.motion.state),
                .x = event.motion.x,
                .y = event.motion.y,
                .xrel = event.motion.xrel,
                .yrel = event.motion.yrel,
            } },
            c.SDL_MOUSEBUTTONDOWN, c.SDL_MOUSEBUTTONUP => .{ .button = .{
                .windowID = event.button.windowID,
                .which = event.button.which,
                .button = @enumFromInt(event.button.button),
                .state = @enumFromInt(event.button.state),
                .clicks = event.button.clicks,
                .x = event.button.x,
                .y = event.button.y,
            } },

            c.SDL_FINGERDOWN, c.SDL_FINGERUP, c.SDL_FINGERMOTION => .{ .tfinger = .{
                .type = @enumFromInt(event.tfinger.type),
                .touchId = event.tfinger.touchId,
                .fingerId = event.tfinger.fingerId,
                .x = event.tfinger.x,
                .y = event.tfinger.y,
                .dx = event.tfinger.dx,
                .dy = event.tfinger.dy,
                .pressure = event.tfinger.pressure,
                .windowID = event.tfinger.windowID,
            } },
            c.SDL_MULTIGESTURE => .{ .mgesture = .{
                .touchId = event.mgesture.touchId,
                .dTheta = event.mgesture.dTheta,
                .dDist = event.mgesture.dDist,
                .x = event.mgesture.x,
                .y = event.mgesture.y,
                .numFingers = event.mgesture.numFingers,
            } },

            c.SDL_MOUSEWHEEL => .{ .wheel = .{
                .windowID = event.wheel.windowID,
                .which = event.wheel.which,
                .x = event.wheel.x,
                .y = event.wheel.y,
                .direction = @enumFromInt(event.wheel.direction),
                .preciseX = event.wheel.preciseX,
                .preciseY = event.wheel.preciseY,
                .mouseX = event.wheel.mouseX,
                .mouseY = event.wheel.mouseY,
            } },

            // c.SDL_MOUSEWHEEL => {},

            // c.SDL_KEYMAPCHANGED => {},
            //
            // c.SDL_JOYAXISMOTION => {},
            // c.SDL_JOYBALLMOTION => {},
            // c.SDL_JOYHATMOTION => {},
            // c.SDL_JOYBUTTONDOWN => {},
            // c.SDL_JOYBUTTONUP => {},
            // c.SDL_JOYDEVICEADDED => {},
            // c.SDL_JOYDEVICEREMOVED => {},
            // c.SDL_JOYBATTERYUPDATED => {},
            //
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
            //
            // c.SDL_DOLLARGESTURE => {},
            // c.SDL_DOLLARRECORD => {},
            //
            // c.SDL_CLIPBOARDUPDATE => {},
            //
            // c.SDL_DROPFILE => {},
            // c.SDL_DROPTEXT => {},
            // c.SDL_DROPBEGIN => {},
            // c.SDL_DROPCOMPLETE => {},
            //
            // c.SDL_AUDIODEVICEADDED => {},
            // c.SDL_AUDIODEVICEREMOVED => {},
            //
            // c.SDL_SENSORUPDATE => {},
            //
            // c.SDL_RENDER_TARGETS_RESET => {},
            // c.SDL_RENDER_DEVICE_RESET => {},
            //
            // c.SDL_POLLSENTINEL => {},
            //
            // c.SDL_USEREVENT => {},

            else => .todo,
        };
        return .{
            .original = event,
            .timestamp = event.common.timestamp,
            .type = ty,
        };
    }

    pub fn encode(ty: Type) c.SDL_Event {
        switch (ty) {
            .quit => return .{ .type = c.SDL_QUIT },
            else => @panic("todo"),
        }
    }

    pub fn push(ty: Type) void {
        var event = encode(ty);
        _ = c.SDL_PushEvent(&event);
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

pub const KeyButtonState = enum(u8) {
    released = 0,
    pressed = 1,
};

pub const KeyboardEvent = struct {
    windowID: u32,
    state: KeyButtonState,
    repeat: u8,
    keysym: Keysym,
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
    text: [32]u8,
};

// Flag set to true if button is down for event
pub const MouseMotionButtonState = packed struct(u32) {
    none: bool,
    left: bool,
    middle: bool,
    right: bool,
    back: bool,
    forward: bool,

    _padding: enum(u26) { zero } = .zero,
};

pub const MouseMotionEvent = struct {
    windowID: u32,
    which: u32,
    state: MouseMotionButtonState,
    x: i32,
    y: i32,
    xrel: i32,
    yrel: i32,
};

// Which button triggered the event,
// its state (pressed or released) indicated with `MouseButtonEvent.state`
pub const MouseButton = enum(u3) {
    none,
    left,
    middle,
    right,
    back,
    forward,
};

pub const MouseButtonEvent = struct {
    windowID: u32,
    which: u32,
    button: MouseButton,
    state: KeyButtonState,
    clicks: u8,
    x: i32,
    y: i32,
};

pub const TouchFingerEventType = enum(u32) {
    motion = c.SDL_FINGERMOTION,
    down = c.SDL_FINGERDOWN,
    up = c.SDL_FINGERUP,
};

pub const TouchFingerEvent = struct {
    type: TouchFingerEventType,
    touchId: c.SDL_TouchID,
    fingerId: c.SDL_FingerID,
    x: f32,
    y: f32,
    dx: f32,
    dy: f32,
    pressure: f32,
    windowID: u32,
};

pub const MultiGestureEvent = struct {
    touchId: c.SDL_TouchID,
    dTheta: f32,
    dDist: f32,
    x: f32,
    y: f32,
    numFingers: u16,
};

pub const MouseWheelEvent = struct {
    windowID: u32,
    which: u32,
    x: i32,
    y: i32,
    direction: Direction,
    preciseX: f32,
    preciseY: f32,
    mouseX: i32,
    mouseY: i32,

    pub const Direction = enum(u32) {
        normal = c.SDL_MOUSEWHEEL_NORMAL,
        flipped = c.SDL_MOUSEWHEEL_FLIPPED,
    };
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

// pub const SDLMEM = struct {
//     pub fn init(allocator: std.mem.Allocator) void {
//         // state.mutex.lock();
//         // defer state.mutex.unlock();

//         state.allocations_list = std.AutoHashMap(usize, usize).init(allocator);
//     }

//     pub fn deinit() void {
//         // state.mutex.lock();
//         // defer state.mutex.unlock();

//         state.allocations_list.?.deinit();
//         state.allocations_list = null;
//     }

//     pub fn setAllocator(allocator: std.mem.Allocator) !void {
//         state.mutex.lock();
//         defer state.mutex.unlock();

//         state.allocator = allocator;
//         try setMemoryFunctions(.{
//             .malloc = sdlMalloc,
//             .calloc = sdlCalloc,
//             .realloc = sdlRealloc,
//             .free = sdlFree,
//         });
//     }

//     const State = struct {
//         allocator: ?std.mem.Allocator = null,
//         allocations_list: ?std.AutoHashMap(usize, usize) = null,
//         mutex: std.Thread.Mutex = .{},
//     };

//     pub var state = State{};

//     const sdl_mem_alignment = 16;

//     pub export fn sdlMalloc(size: usize) callconv(.C) ?*anyopaque {
//         state.mutex.lock();
//         defer state.mutex.unlock();

//         const mem = state.allocator.?.alignedAlloc(
//             u8,
//             sdl_mem_alignment,
//             size,
//         ) catch @panic("sdl alloc: out of memory");

//         state.allocations_list.?.put(@intFromPtr(mem.ptr), size) catch
//             @panic("sdl alloc: out of memory");

//         return mem.ptr;
//     }

//     pub export fn sdlCalloc(count: usize, size: usize) callconv(.C) ?*anyopaque {
//         state.mutex.lock();
//         defer state.mutex.unlock();

//         const total_size = count * size;
//         const mem = state.allocator.?.alignedAlloc(
//             u8,
//             sdl_mem_alignment,
//             total_size,
//         ) catch @panic("sdl alloc: out of memory");

//         @memset(mem, 0);

//         state.allocations_list.?.put(@intFromPtr(mem.ptr), total_size) catch
//             @panic("sdl alloc: out of memory");

//         return mem.ptr;
//     }

//     pub export fn sdlRealloc(ptr: ?*anyopaque, size: usize) callconv(.C) ?*anyopaque {
//         state.mutex.lock();
//         defer state.mutex.unlock();

//         const old_size = if (ptr != null)
//             state.allocations_list.?.get(@intFromPtr(ptr.?)).?
//         else
//             0;
//         const old_mem = if (old_size > 0)
//             @as([*]align(sdl_mem_alignment) u8, @ptrCast(@alignCast(ptr)))[0..old_size]
//         else
//             @as([*]align(sdl_mem_alignment) u8, undefined)[0..0];

//         const new_mem = state.allocator.?.realloc(old_mem, size) catch
//             @panic("sdl alloc: out of memory");

//         if (ptr != null) {
//             const removed = state.allocations_list.?.remove(@intFromPtr(ptr.?));
//             std.debug.assert(removed);
//         }

//         state.allocations_list.?.put(@intFromPtr(new_mem.ptr), size) catch
//             @panic("sdl alloc: out of memory");

//         return new_mem.ptr;
//     }

//     pub export fn sdlFree(maybe_ptr: ?*anyopaque) callconv(.C) void {
//         if (maybe_ptr) |ptr| {
//             state.mutex.lock();
//             defer state.mutex.unlock();

//             const size = state.allocations_list.?.fetchRemove(@intFromPtr(ptr)).?.value;
//             const mem = @as([*]align(sdl_mem_alignment) u8, @ptrCast(@alignCast(ptr)))[0..size];
//             state.allocator.?.free(mem);
//         }
//     }
// };

pub const Surface = opaque {
    pub fn deinit(self: *Surface) void {
        c.SDL_FreeSurface(@ptrCast(@alignCast(self)));
    }
};

pub const Texture = opaque {
    pub fn deinit(self: *Texture) void {
        c.SDL_DestroyTexture(@ptrCast(self));
    }

    pub fn query(self: *Texture, format: ?*PixelFormat, access: ?*TextureAccess, w: ?*c_int, h: ?*c_int) !void {
        if (c.SDL_QueryTexture(@ptrCast(self), @ptrCast(format), @ptrCast(access), w, h) != 0)
            return error.Sdl;
    }
};

// @FIXME: fix clashes with `pub const` aliases
pub const PixelFormat = enum(c_uint) {
    unknown = c.SDL_PIXELFORMAT_UNKNOWN,
    index1lsb = c.SDL_PIXELFORMAT_INDEX1LSB,
    index1msb = c.SDL_PIXELFORMAT_INDEX1MSB,
    index2lsb = c.SDL_PIXELFORMAT_INDEX2LSB,
    index2msb = c.SDL_PIXELFORMAT_INDEX2MSB,
    index4lsb = c.SDL_PIXELFORMAT_INDEX4LSB,
    index4msb = c.SDL_PIXELFORMAT_INDEX4MSB,
    index8 = c.SDL_PIXELFORMAT_INDEX8,
    rgb332 = c.SDL_PIXELFORMAT_RGB332,
    // xrgb4444 = c.SDL_PIXELFORMAT_XRGB4444,
    rgb444 = c.SDL_PIXELFORMAT_RGB444,
    // xbgr4444 = c.SDL_PIXELFORMAT_XBGR4444,
    bgr444 = c.SDL_PIXELFORMAT_BGR444,
    // xrgb1555 = c.SDL_PIXELFORMAT_XRGB1555,
    rgb555 = c.SDL_PIXELFORMAT_RGB555,
    // xbgr1555 = c.SDL_PIXELFORMAT_XBGR1555,
    bgr555 = c.SDL_PIXELFORMAT_BGR555,
    argb4444 = c.SDL_PIXELFORMAT_ARGB4444,
    rgba4444 = c.SDL_PIXELFORMAT_RGBA4444,
    abgr4444 = c.SDL_PIXELFORMAT_ABGR4444,
    bgra4444 = c.SDL_PIXELFORMAT_BGRA4444,
    argb1555 = c.SDL_PIXELFORMAT_ARGB1555,
    rgba5551 = c.SDL_PIXELFORMAT_RGBA5551,
    abgr1555 = c.SDL_PIXELFORMAT_ABGR1555,
    bgra5551 = c.SDL_PIXELFORMAT_BGRA5551,
    rgb565 = c.SDL_PIXELFORMAT_RGB565,
    bgr565 = c.SDL_PIXELFORMAT_BGR565,
    rgb24 = c.SDL_PIXELFORMAT_RGB24,
    bgr24 = c.SDL_PIXELFORMAT_BGR24,
    // xrgb8888 = c.SDL_PIXELFORMAT_XRGB8888,
    rgb888 = c.SDL_PIXELFORMAT_RGB888,
    rgbx8888 = c.SDL_PIXELFORMAT_RGBX8888,
    // xbgr8888 = c.SDL_PIXELFORMAT_XBGR8888,
    bgr888 = c.SDL_PIXELFORMAT_BGR888,
    bgrx8888 = c.SDL_PIXELFORMAT_BGRX8888,
    argb8888 = c.SDL_PIXELFORMAT_ARGB8888,
    rgba8888 = c.SDL_PIXELFORMAT_RGBA8888,
    abgr8888 = c.SDL_PIXELFORMAT_ABGR8888,
    bgra8888 = c.SDL_PIXELFORMAT_BGRA8888,
    argb2101010 = c.SDL_PIXELFORMAT_ARGB2101010,
    // rgba32 = c.SDL_PIXELFORMAT_RGBA32,
    // argb32 = c.SDL_PIXELFORMAT_ARGB32,
    // bgra32 = c.SDL_PIXELFORMAT_BGRA32,
    // abgr32 = c.SDL_PIXELFORMAT_ABGR32,
    // rgbx32 = c.SDL_PIXELFORMAT_RGBX32,
    // xrgb32 = c.SDL_PIXELFORMAT_XRGB32,
    // bgrx32 = c.SDL_PIXELFORMAT_BGRX32,
    // xbgr32 = c.SDL_PIXELFORMAT_XBGR32,
    yv12 = c.SDL_PIXELFORMAT_YV12,
    iyuv = c.SDL_PIXELFORMAT_IYUV,
    yuy2 = c.SDL_PIXELFORMAT_YUY2,
    uyvy = c.SDL_PIXELFORMAT_UYVY,
    yvyu = c.SDL_PIXELFORMAT_YVYU,
    nv12 = c.SDL_PIXELFORMAT_NV12,
    nv21 = c.SDL_PIXELFORMAT_NV21,
    external_oes = c.SDL_PIXELFORMAT_EXTERNAL_OES,

    pub fn pixelType(self: PixelFormat) PixelType {
        return @enumFromInt(c.SDL_PIXELTYPE(@intFromEnum(self)));
    }

    pub fn pixelOrder(self: PixelFormat) PixelOrder {
        return @bitCast(c.SDL_PIXELORDER(@intFromEnum(self)));
    }

    pub fn pixelLayout(self: PixelFormat) PackedLayout {
        return @enumFromInt(c.SDL_PIXELLAYOUT(@intFromEnum(self)));
    }

    pub fn bitsPerPixel(self: PixelFormat) c_int {
        return c.SDL_BITSPERPIXEL(@intFromEnum(self));
    }

    pub fn bytesPerPixel(self: PixelFormat) c_int {
        return c.SDL_BYTESPERPIXEL(@intFromEnum(self));
    }

    pub fn isIndexed(self: PixelFormat) bool {
        return c.SDL_ISPIXELFORMAT_INDEXED(@intFromEnum(self));
    }

    pub fn isAlpha(self: PixelFormat) bool {
        return c.SDL_ISPIXELFORMAT_ALPHA(@intFromEnum(self));
    }

    pub fn isFourcc(self: PixelFormat) bool {
        return c.SDL_ISPIXELFORMAT_FOURCC(@intFromEnum(self));
    }
};

pub const PixelType = enum(c_uint) {
    unknown = c.SDL_PIXELTYPE_UNKNOWN,
    index1 = c.SDL_PIXELTYPE_INDEX1,
    index4 = c.SDL_PIXELTYPE_INDEX4,
    index8 = c.SDL_PIXELTYPE_INDEX8,
    packed8 = c.SDL_PIXELTYPE_PACKED8,
    packed16 = c.SDL_PIXELTYPE_PACKED16,
    packed32 = c.SDL_PIXELTYPE_PACKED32,
    arrayu8 = c.SDL_PIXELTYPE_ARRAYU8,
    arrayu16 = c.SDL_PIXELTYPE_ARRAYU16,
    arrayu32 = c.SDL_PIXELTYPE_ARRAYU32,
    arrayf16 = c.SDL_PIXELTYPE_ARRAYF16,
    arrayf32 = c.SDL_PIXELTYPE_ARRAYF32,
    index2 = c.SDL_PIXELTYPE_INDEX2,
};

pub const BitmapPixelOrder = enum(c_uint) {
    none = c.SDL_BITMAPORDER_NONE,
    @"4321" = c.SDL_BITMAPORDER_4321,
    @"1234" = c.SDL_BITMAPORDER_1234,
};

pub const PackedPixelOrder = enum(c_uint) {
    none = c.SDL_PACKEDORDER_NONE,
    xrgb = c.SDL_PACKEDORDER_XRGB,
    rgbx = c.SDL_PACKEDORDER_RGBX,
    argb = c.SDL_PACKEDORDER_ARGB,
    rgba = c.SDL_PACKEDORDER_RGBA,
    xbgr = c.SDL_PACKEDORDER_XBGR,
    bgrx = c.SDL_PACKEDORDER_BGRX,
    abgr = c.SDL_PACKEDORDER_ABGR,
    bgra = c.SDL_PACKEDORDER_BGRA,
};

pub const ArrayPixelOrder = enum(c_uint) {
    none = c.SDL_ARRAYORDER_NONE,
    rgb = c.SDL_ARRAYORDER_RGB,
    rgba = c.SDL_ARRAYORDER_RGBA,
    argb = c.SDL_ARRAYORDER_ARGB,
    bgr = c.SDL_ARRAYORDER_BGR,
    bgra = c.SDL_ARRAYORDER_BGRA,
    abgr = c.SDL_ARRAYORDER_ABGR,
};

pub const PixelOrder = extern union {
    bitmap: BitmapPixelOrder,
    @"packed": PackedPixelOrder,
    array: ArrayPixelOrder,
};

pub const PackedLayout = enum(c_uint) {
    none = c.SDL_PACKEDLAYOUT_NONE,
    @"332" = c.SDL_PACKEDLAYOUT_332,
    @"4444" = c.SDL_PACKEDLAYOUT_4444,
    @"1555" = c.SDL_PACKEDLAYOUT_1555,
    @"5551" = c.SDL_PACKEDLAYOUT_5551,
    @"565" = c.SDL_PACKEDLAYOUT_565,
    @"8888" = c.SDL_PACKEDLAYOUT_8888,
    @"2101010" = c.SDL_PACKEDLAYOUT_2101010,
    @"1010102" = c.SDL_PACKEDLAYOUT_1010102,
};

pub const TextureAccess = enum(c_uint) {
    static = c.SDL_TEXTUREACCESS_STATIC,
    streaming = c.SDL_TEXTUREACCESS_STREAMING,
    target = c.SDL_TEXTUREACCESS_TARGET,
};
