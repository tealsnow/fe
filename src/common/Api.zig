const std = @import("std");
const log = @import("log.zig");

const sdl = @import("sdl.zig");

const Api = @This();

// FIXME: do we need these?
onLoad: *const fn (allocator: std.mem.Allocator, log_state: log.State) void,
onUnload: *const fn (allocator: std.mem.Allocator) void,

init: *const fn (allocator: std.mem.Allocator, window: *sdl.Window) void,
deinit: *const fn (allocator: std.mem.Allocator) void,

getMemory: *const fn () *anyopaque,
setMemory: *const fn (memory: *anyopaque) void,

greet: *const fn (name: []const u8) void,

getCounter: *const fn () u32,

doImgui: *const fn () void,

onUpdate: *const fn () void,
onRender: *const fn () void,

// TODO: We should just have a generic event callback
onResize: *const fn () void,

pub const GetApiSig = struct {
    pub const Name = "fe__getApi";
    pub const FuncSig = fn (out_api: *Api) callconv(.C) void;
    pub const FuncSigPtr = *const FuncSig;
};

pub inline fn exportGetApi(func: GetApiSig.FuncSig) void {
    comptime {
        @export(func, .{ .name = GetApiSig.Name });
    }
}

pub fn load(lib: *std.DynLib, out_api: *Api) !void {
    const get = lib.lookup(
        GetApiSig.FuncSigPtr,
        GetApiSig.Name,
    ) orelse
        return error.LookupError;
    get(out_api);
}
