const std = @import("std");

const Api = @This();

onLoad: *const fn (allocator: std.mem.Allocator) void,
onUnload: *const fn (allocator: std.mem.Allocator) void,

getColor: *const fn (r: *u8, g: *u8, b: *u8) void,
greet: *const fn (name: []const u8) void,

pub fn load(lib: *std.DynLib) !Api {
    var api: Api = undefined;
    try api.reload(lib);
    return api;
}

pub fn reload(api: *Api, lib: *std.DynLib) !void {
    const GetApi = *const fn (*Api) callconv(.C) void;
    const getApi = lib.lookup(GetApi, "getApi") orelse
        return error.SymbolNotFount;
    getApi(api);
}
