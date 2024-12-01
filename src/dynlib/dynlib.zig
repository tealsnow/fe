const std = @import("std");

const common = @import("common");
const Api = common.Api;

const log = common.log.Scoped("dynlib");

comptime {
    Api.exportGetApi(getApi);
}

fn getApi(out_api: *Api) callconv(.C) void {
    out_api.* = .{
        .onLoad = &onLoad,
        .onUnload = &onUnload,

        .getColor = &getColor,
        .greet = &greet,
    };
}

fn onLoad(allocator: std.mem.Allocator, log_state: common.log.State) void {
    _ = allocator;

    common.log.setup(log_state);

    log.debug(@src(), "onLoad");
}

fn onUnload(allocator: std.mem.Allocator) void {
    _ = allocator;
    log.debug(@src(), "onUnload");
}

fn getColor() Api.Color {
    return .{ .r = 10, .g = 20, .b = 20 };
}

fn greet(name: []const u8) void {
    common.tracy.message("greet from dynlib");
    log.tracekv(@src(), "greeting", .{ .name = name });

    common.out.printfln("Hello, {s}!", .{name});
}
