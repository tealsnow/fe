const std = @import("std");

const lib = @import("plugin-lib");

pub const plugin: lib.PluginSchema = @import("plugin.zon");

pub const std_options = std.Options{
    .logFn = lib.mkLogFn(plugin.id),
};

fn now() std.time.Instant {
    return std.time.Instant.now() catch @panic("precise time unavailable");
}

export fn helloWorld() void {
    std.log.info("running hello world!", .{});
    std.debug.print("Hello, World!\n", .{});
    const start = now();
    std.time.sleep(100 * std.time.ns_per_ms);
    std.debug.print("Napped for {d}ms\n", .{now().since(start) / std.time.ns_per_ms});
}

export fn add(a: i32, b: i32) i32 {
    return a + b;
}

export fn addi64(a: i64, b: i64) i64 {
    return a + b;
}

extern "fe" fn callback() void;

export fn runCallback() void {
    std.debug.print("> running callback\n", .{});
    callback();
}

const FooType_Ref = enum(i64) { _ };

extern "fe" fn FooType_inc(ptr: FooType_Ref) void;

export fn takeFooType(ptr: FooType_Ref) void {
    std.debug.print("taking footype + inc\n", .{});
    FooType_inc(ptr);
}

extern "fe" fn takeString(ptr: [*]const u8, length: u32) void;

export fn giveString() void {
    const string = "Hello, Zig!";
    takeString(string, string.len);
}

export fn useString(ptr: [*]const u8, length: u32) void {
    std.debug.print("> useString(ptr: {*}/{d}, len: {d})\n", .{ ptr, @intFromPtr(ptr), length });

    const slice = ptr[0..length];
    std.debug.print("using string: {s}\n", .{slice});
}
