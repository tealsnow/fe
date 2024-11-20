const std = @import("std");

const common = @import("common");
const log = common.log.Scoped("dynlib");

export fn getApi(api: *common.Api) void {
    log.trace(@src(), "Populating Api", .{}, .{});
    api.* = .{
        .onStart = &onStart,
        .onEnd = &onEnd,

        .getColor = &getColor,
        .greet = &greet,
    };
}

const allocator = std.heap.c_allocator;
var console_logger: common.log.ConsoleLogger = undefined;

fn onStart() void {
    console_logger = common.log.ConsoleLogger.new(allocator) catch unreachable;
    common.log.setup(allocator, &console_logger.asLog());
}

fn onEnd() void {
    console_logger.deinit(allocator);
}

fn getColor(r: *u8, g: *u8, b: *u8) void {
    r.* = 30;
    g.* = 30;
    b.* = 30;
}

fn greet(name: []const u8) void {
    log.trace(@src(), "Greeting", .{}, .{ .name = name });

    common.out.printfln("Hello, {s}!", .{name});
}
