const std = @import("std");
const log = @import("log.zig");

const Api = @This();

onLoad: *const fn (allocator: std.mem.Allocator, log_state: log.State) void,
onUnload: *const fn (allocator: std.mem.Allocator) void,

getColor: *const fn () Color,
greet: *const fn (name: []const u8) void,

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

pub const Color = struct {
    r: u8,
    g: u8,
    b: u8,
};
