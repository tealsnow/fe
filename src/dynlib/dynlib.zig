const std = @import("std");

const common = @import("common");
const Api = common.Api;

const log = common.log.Scoped("dynlib");

const imgui = common.imgui.c;

comptime {
    Api.exportGetApi(getApi);
}

const Memory = struct {
    counter: u32 = 0,
};

var g_memory: *Memory = undefined;

fn getApi(out_api: *Api) callconv(.C) void {
    out_api.* = .{
        .onLoad = &onLoad,
        .onUnload = &onUnload,

        .init = &init,
        .deinit = &deinit,

        .getMemory = &getMemory,
        .setMemory = &setMemory,

        .getColor = &getColor,
        .greet = &greet,

        .getCounter = &getCounter,

        .doImgui = &doImgui,
    };
}

fn onLoad(allocator: std.mem.Allocator, log_state: common.log.State) void {
    _ = allocator;

    common.log.setup(log_state);
    // log.debug(@src(), "onLoad");
}

fn onUnload(allocator: std.mem.Allocator) void {
    _ = allocator;

    // log.debug(@src(), "onUnload");
}

fn init(allocator: std.mem.Allocator) void {
    // log.debug(@src(), "init");
    g_memory = allocator.create(Memory) catch @panic("oom");
    g_memory.* = .{};
}

fn deinit(allocator: std.mem.Allocator) void {
    // log.debug(@src(), "deinit");
    allocator.destroy(g_memory);
}

fn getMemory() *anyopaque {
    return @alignCast(@ptrCast(g_memory));
}

fn setMemory(memory: *anyopaque) void {
    g_memory = @alignCast(@ptrCast(memory));
}

fn getColor() Api.Color {
    return .{ .r = 10, .g = 20, .b = 20 };
}

fn greet(name: []const u8) void {
    log.tracef(@src(), "{d}: Hello, {s}!", .{ g_memory.counter, name });

    g_memory.counter += 1;
}

fn getCounter() u32 {
    return g_memory.counter;
}

fn doImgui() void {
    if (imgui.igBegin("dynlib window", null, 0)) {
        imgui.igText("This is window from dynlib -- dynamic");
        imgui.igText("count: %d", g_memory.counter);

        if (imgui.igSmallButton("incremnt counter")) {
            g_memory.counter += 1;
        }
    }
    imgui.igEnd();
}
