const std = @import("std");

pub const printf = std.debug.print;

pub fn printfln(comptime fmt: []const u8, args: anytype) void {
    printf(fmt ++ "\n", args);
}

pub fn print(comptime str: []const u8) void {
    printf(str, .{});
}

pub fn println(comptime str: []const u8) void {
    print(str ++ "\n");
}
