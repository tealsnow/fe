const c = @cImport({
    @cInclude("SDL3/SDL_init.h");
});
const Error = @import("sdl3.zig").Error;

pub const AppResult = c_uint;

pub const AppInitFunc = ?*const fn ([*c]?*anyopaque, c_int, [*c][*c]u8) callconv(.c) AppResult;

pub const AppIterateFunc = ?*const fn (?*anyopaque) callconv(.c) AppResult;

pub const AppQuitFunc = ?*const fn (?*anyopaque, AppResult) callconv(.c) void;

pub const MainThreadCallback = ?*const fn (?*anyopaque) callconv(.c) void;

pub const InitFlag = struct {
    pub const audio = c.SDL_INIT_AUDIO;
    pub const video = c.SDL_INIT_VIDEO;
    pub const joystick = c.SDL_INIT_JOYSTICK;
    pub const haptic = c.SDL_INIT_HAPTIC;
    pub const gamepad = c.SDL_INIT_GAMEPAD;
    pub const events = c.SDL_INIT_EVENTS;
    pub const sensor = c.SDL_INIT_SENSOR;
    pub const camera = c.SDL_INIT_CAMERA;

    pub const all = audio | video | joystick | haptic | gamepad | events | sensor | camera;
};

/// see `InitFlag`
pub const InitFlags = u32;

pub fn init(flags: InitFlags) Error!void {
    if (!c.SDL_Init(@intCast(flags))) return error.sdl;
}

pub fn initSubSystem(flags: InitFlags) Error!void {
    if (!c.SDL_InitSubSystem(flags)) return error.sdl;
}

pub fn quit() void {
    c.SDL_Quit();
}

pub fn quitSubSystem(flags: InitFlags) void {
    c.SDL_QuitSubSystem(flags);
}

pub fn wasInit(flags: InitFlags) InitFlags {
    return c.SDL_WasInit(flags);
}

pub fn isMainThread() bool {
    return c.SDL_IsMainThread();
}

pub fn runOnMainThread(callback: MainThreadCallback, userdata: ?*anyopaque, wait_complete: bool) !void {
    if (!c.SDL_RunOnMainThread(callback, userdata, wait_complete)) return error.sdl;
}

pub fn setAppMetadata(appname: [*:0]const u8, appversion: [*:0]const u8, appidentifier: [*:0]const u8) !void {
    if (!c.SDL_SetAppMetadata(appname, appversion, appidentifier)) return error.sdl;
}

pub fn setAppMetadataProperty(name: [*:0]const u8, value: [*:0]const u8) !void {
    if (!c.SDL_SetAppMetadataProperty(name, value)) return error.sdl;
}

pub fn getAppMetadataProperty(name: [*:0]const u8) [*:0]const u8 {
    return c.SDL_GetAppMetadataProperty(name);
}
