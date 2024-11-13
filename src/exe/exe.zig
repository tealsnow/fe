const builtin = @import("builtin");
const std = @import("std");
const log = std.log;

const sdl = @import("sdl.zig");

const common = @import("common");
const out = common.out;

const debugging = builtin.mode == .Debug;

// FIXME: Keep all global state in one place
var shared_lib_recompiled = false;
// FIXME: Keep all global state in one place
var sdl_allocator: std.mem.Allocator = undefined;

pub fn main() !void {
    run() catch |err| {
        const exit_code = switch (err) {
            error.Sdl => blk: {
                log.err("Fatal SDL error: {?s}", .{sdl.getError()});
                break :blk ExitCode.Sdl;
            },
            else => blk: {
                log.err("Fatal error: {}", .{err});
                break :blk ExitCode.General;
            },
        };

        // FIXME: Should probably put stacktrace in a log file for bug reports
        if (!debugging)
            exit_code.exit();

        return err;
    };
}

const ExitCode = enum(u8) {
    Successful = 0,
    General = 1,
    Sdl = 2,

    pub fn exit(self: ExitCode) noreturn {
        if (self == .Successful)
            std.process.cleanExit();
        std.process.exit(@intFromEnum(self));
    }
};

fn run() !void {
    log.debug("Starting application", .{});
    defer log.debug("Exiting application", .{});

    // var gpa = std.heap.GeneralPurposeAllocator(.{
    //     // .never_unmap = true,
    //     // .retain_metadata = true,

    //     // .verbose_log = true,
    // }){};
    // const allocator = gpa.allocator();
    // defer {
    //     const status = gpa.deinit();
    //     if (status == .leak) {
    //         out.println("Exited with memory leak");
    //     }
    // }

    // sdl_allocator = allocator;
    sdl_allocator = std.heap.raw_c_allocator;
    try sdl.setMemoryFunctions(.{
        .malloc = sdlMalloc,
        .calloc = sdlCalloc,
        .realloc = sdlRealloc,
        .free = sdlFree,
    });

    try installSigaction();

    try sdl.init(.{ .video = true, .events = true });
    defer sdl.quit();

    const window = try sdl.Window.init(.{
        .title = "cu",
        .position = .{
            .x = .centered,
            .y = .centered,
        },
        .size = .{ .w = 800, .h = 600 },
        .flags = .{
            .hidden = true,
            .allow_highdpi = true,
            .resizable = false,
        },
    });
    defer window.deinit();

    const renderer = try sdl.Renderer.init(.{
        .window = window,
        .flags = .{ .accelerated = true },
    });
    defer renderer.deinit();

    var library: std.DynLib = undefined;
    var api: common.Api = undefined;
    try loadLibrary(&library, &api);
    defer library.close();

    var arena = std.heap.ArenaAllocator.init(std.heap.c_allocator);
    const allocator = arena.allocator();

    const event_timeout = 16; // ms
    const update_60_times_a_second = 16 * 1000 * 1000; // ns

    var ticker = try TickerTimer(2).start();
    const update = &ticker.tickers[0];
    const render = &ticker.tickers[1];
    update.timestep = update_60_times_a_second;
    render.timestep = update_60_times_a_second;

    var show_failed_reset = if (builtin.mode == .Debug) false;

    window.show();
    var running = true;
    while (running) {
        defer {
            const failed = arena.reset(.retain_capacity); // FIXME: Limit this accordingly!
            if (debugging and failed and !show_failed_reset) {
                show_failed_reset = true;
                log.err("Arena reset failed, Not showing again. Press (r) to reset showing this message", .{});
            }
        }

        ticker.lap();

        if (sdl.Event.waitTimeout(event_timeout)) |ev| {
            switch (ev.type) {
                .quit => running = false,

                .key => |key| blk: {
                    if (key.state != .pressed)
                        break :blk;
                    switch (key.keysym.sym) {
                        .q => {
                            out.println("Quiting...");
                            running = false;
                        },

                        .r => {
                            out.print("Reloading...");
                            defer out.println(" Done");

                            library.close();
                            try loadLibrary(&library, &api);

                            if (debugging)
                                show_failed_reset = false;
                        },

                        .h => {
                            api.greet("main");
                        },

                        .f => {
                            const msg = try std.fmt.allocPrint(allocator, "Some int: {d}", .{15});
                            api.greet(msg);
                        },

                        else => {},
                    }
                },

                else => {},
            }
        }

        while (update.shouldTick()) {
            if (shared_lib_recompiled) {
                out.print("Reloading (from signal)...");
                defer out.println(" Done");

                shared_lib_recompiled = false;

                library.close();
                try loadLibrary(&library, &api);
            }
        }

        while (render.shouldTick()) {
            var r: u8 = undefined;
            var g: u8 = undefined;
            var b: u8 = undefined;
            api.getColor(&r, &g, &b);

            renderer.setDrawColor(r, g, b, 255) catch {};

            renderer.clear() catch {};
            renderer.present();
        }
    }
}

pub fn TickerTimer(comptime ticker_count: comptime_int) type {
    return struct {
        timer: std.time.Timer,
        tickers: [ticker_count]Ticker,

        const Self = @This();

        pub fn start() !Self {
            return Self{
                .timer = try std.time.Timer.start(),
                .tickers = [_]Ticker{.{}} ** ticker_count,
            };
        }

        pub fn lap(self: *Self) void {
            const elapsed = self.timer.lap();
            inline for (0..ticker_count) |i| {
                self.tickers[i].correction += elapsed;
            }
        }

        pub const Ticker = struct {
            timestep: u64 = 0,
            correction: u64 = 0,

            pub fn shouldTick(self: *Ticker) bool {
                const cond = self.correction >= self.timestep;
                if (cond) self.correction -= self.timestep;
                return cond;
            }
        };
    };
}

fn loadLibrary(lib: *std.DynLib, api: *common.Api) !void {
    lib.* = try std.DynLib.open("zig-out/lib/libdynlib.so");
    errdefer lib.close();
    try api.load(lib);
}

fn installSigaction() !void {
    const act = std.os.linux.Sigaction{
        .handler = .{ .handler = handleSignal },
        .mask = std.os.linux.empty_sigset,
        .flags = 0,
    };
    const sigaction_res = std.os.linux.sigaction(std.os.linux.SIG.USR1, &act, null);
    if (sigaction_res != 0) {
        const err = std.posix.errno(sigaction_res);
        log.err("Failed to setup sigaction: {}", .{err});
        return error.FailedToSetSigaction;
    }
}

fn handleSignal(sig: c_int) callconv(.C) void {
    switch (sig) {
        std.os.linux.SIG.USR1 => {
            log.info("Got USR1 signal, shared lib has recompiled", .{});
            shared_lib_recompiled = true;
        },
        else => {
            log.warn("Got unknown signal: {d}", .{sig});
        },
    }
}

export fn sdlMalloc(size: usize) ?*anyopaque {
    const allocation = sdl_allocator.alloc(u8, size) catch return null;
    return @ptrCast(allocation.ptr);
}

export fn sdlCalloc(nitems: usize, size: usize) ?*anyopaque {
    const allocation = sdl_allocator
        .alignedAlloc(u8, @alignOf(u8), nitems * size) catch return null;
    @memset(allocation, 0);
    return @ptrCast(allocation.ptr);
}

export fn sdlRealloc(ptr: ?*anyopaque, size: usize) ?*anyopaque {
    if (ptr == null) return sdlMalloc(size);
    const old_slice = @as([*]u8, @ptrCast(@alignCast(ptr)))[0..size];
    const new_slice = sdl_allocator.realloc(old_slice, size) catch return null;
    return @ptrCast(new_slice.ptr);
}

export fn sdlFree(ptr: ?*anyopaque) void {
    if (ptr == null) return;
    const slice = @as([*]u8, @ptrCast(@alignCast(ptr)))[0..0];
    sdl_allocator.free(slice);
}
