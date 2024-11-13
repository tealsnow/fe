const std = @import("std");

const common = @import("common");

export fn getApi(api: *common.Api) void {
    api.greet = &greet;
    api.getColor = &getColor;
}

fn getColor(r: *u8, g: *u8, b: *u8) void {
    r.* = 30;
    g.* = 30;
    b.* = 30;
}

fn greet(name: []const u8) void {
    common.out.printfln("Hello (testing), {s}!", .{name});
}
