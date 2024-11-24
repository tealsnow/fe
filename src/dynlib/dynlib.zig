const std = @import("std");

const common = @import("common");
const log = common.log.Scoped("dynlib");

export fn getApi(api: *common.Api) void {
    api.* = .{
        .onLoad = &onLoad,
        .onUnload = &onUnload,

        .getColor = &getColor,
        .greet = &greet,
    };
}

fn onLoad(allocator: std.mem.Allocator, log_state: common.log.State) void {
    _ = allocator;
    common.log.setup(log_state);
}

fn onUnload(allocator: std.mem.Allocator) void {
    _ = allocator;
}

fn getColor(r: *u8, g: *u8, b: *u8) void {
    r.* = 30;
    g.* = 30;
    b.* = 30;
}

fn greet(name: []const u8) void {
    common.tracy.message("greet from dynlib");
    log.tracekv(@src(), "greeting", .{ .name = name });

    common.out.printfln("Hello, {s}!", .{name});
}
