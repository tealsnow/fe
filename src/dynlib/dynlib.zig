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

var console_logger: *common.log.ConsoleLogger = undefined;

fn onLoad(allocator: std.mem.Allocator) void {
    const level_filter = common.log.LevelFilter.trace;
    console_logger = allocator.create(common.log.ConsoleLogger) catch unreachable;
    console_logger.* = common.log.ConsoleLogger.new(level_filter) catch unreachable;
    common.log.setup(.{ .allocator = allocator, .level_filter = level_filter, .logger = console_logger.createLog() });
}

fn onUnload(allocator: std.mem.Allocator) void {
    allocator.destroy(console_logger);
}

fn getColor(r: *u8, g: *u8, b: *u8) void {
    r.* = 30;
    g.* = 30;
    b.* = 30;
}

fn greet(name: []const u8) void {
    log.tracekv(@src(), "greeting", .{ .name = name });

    common.out.printfln("Hello, {s}!", .{name});
}
