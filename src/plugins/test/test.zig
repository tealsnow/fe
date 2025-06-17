const std = @import("std");

const lib = @import("plugin-lib");
const PackedSlice = lib.PackedSlice;

const schema: lib.PluginSchema = @import("plugin.zon");

pub const std_options = std.Options{
    .logFn = lib.mkLogFn(schema.id),
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
    std.log.debug("running callback", .{});
    callback();
}

const FooType_Ref = enum(u64) { _ };

extern "fe" fn FooType_inc(ptr: FooType_Ref) void;

export fn takeFooType(ptr: FooType_Ref) void {
    std.log.debug("taking footype + inc ; ptr: {x}", .{@intFromEnum(ptr)});
    FooType_inc(ptr);
}

extern "fe" fn takeString(string_packed: PackedSlice([]const u8)) void;

export fn giveString() void {
    const string = "Hello, Zig!";
    takeString(.fromSlice(string));
}

export fn useString(string_packed: PackedSlice([]const u8)) void {
    std.log.debug("> useString(ptr: {*}, len: {d})", .{ string_packed.ptr, string_packed.len });

    const slice = string_packed.toSlice();
    std.debug.print("using string: {s}\n", .{slice});
}

fn returnedFunc() callconv(.{ .wasm_mvp = .{} }) i32 {
    std.log.debug("returned func: wasm run function!", .{});
    return add(1, 2);
}

export fn returnFunc() *const fn () callconv(.{ .wasm_mvp = .{} }) i32 {
    std.log.debug("returning wasm function", .{});
    return &returnedFunc;
}
