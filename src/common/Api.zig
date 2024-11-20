const std = @import("std");

const Api = @This();

onStart: *const fn () void,
onEnd: *const fn () void,

getColor: *const fn (r: *u8, g: *u8, b: *u8) void,
greet: *const fn (name: []const u8) void,

pub fn load(api: *Api, lib: *std.DynLib) !void {
    const GetApi = *const fn (*Api) callconv(.C) void;
    const getApi = lib.lookup(GetApi, "getApi") orelse
        return error.SymbolNotFount;
    getApi(api);
}
