const builtin = @import("builtin");
const std = @import("std");
const Allocator = std.mem.Allocator;

const sdl = @import("sdl.zig");

const common = @import("common");
const out = common.out;
const tracy = common.tracy;

const log = common.log.Scoped("exe");

const options = @import("options");

const debug_mode = builtin.mode == .Debug;
const debugger_attached = options.debugger_attached;

// FIXME: Keep all global state in one place
var dynlib_recompiled = false;
// FIXME: Keep all global state in one place
var sdl_allocator: Allocator = undefined;

pub fn main() !void {
    tracy.setThreadName("Main");

    const exit_code: ExitCode = run() catch |err| switch (err) {
        error.Sdl => blk: {
            log.fatalkv(
                @src(),
                "Fatal SDL error",
                .{ .err = sdl.getError() },
            );
            if (debug_mode)
                return err;
            break :blk .sdl;
        },
        else => blk: {
            log.fatalkv(
                @src(),
                "Fatal error",
                .{ .err = err },
            );
            if (debug_mode)
                return err;
            break :blk .general;
        },
    };

    exit_code.exit();
}

const ExitCode = enum(u8) {
    successful = 0,
    general = 1,
    sdl = 2,

    pub fn exit(self: ExitCode) noreturn {
        if (self == .successful)
            std.process.cleanExit();
        std.process.exit(@intFromEnum(self));
    }
};

fn run() !ExitCode {
    const init_zone = tracy.initZone(@src(), .{ .name = "init" });

    var gpa = std.heap.GeneralPurposeAllocator(.{
        // .never_unmap = true,
        // .retain_metadata = true,

        // .verbose_log = true,
    }){};
    gpa.backing_allocator = std.heap.c_allocator;
    // const allocator = gpa.allocator();
    var tracing_allocator = tracy.TracingAllocator.initNamed("main", gpa.allocator());
    const allocator = tracing_allocator.allocator();
    defer {
        const status = gpa.deinit();
        if (status == .leak) {
            log.fatal(@src(), "Exited with memory leak");
        }
    }

    const level_filter = common.log.LevelFilter.trace;
    var console_logger = try common.log.ConsoleLogger.new(level_filter);
    common.log.setup(.{
        .allocator = allocator,
        .level_filter = level_filter,
        .logger = console_logger.logger(),
    });

    log.debug(@src(), "starting application");
    defer log.debug(@src(), "exiting application");

    if (debug_mode) {
        log.info(@src(), "running in debug mode");
    }

    if (debugger_attached) {
        log.warn(
            @src(),
            "running with the assumption that a debugger will be attached",
        );
    }

    // We use the (raw) c allocator here and not the gpa since sdl does not
    // properly deinit its memory on applicaiton exit. Which ends up triggering
    // the gpa
    // NOTE(ketanr): I'm not sure if theres much need for this. The only
    //  usecase I can think of is just trying to so see and minimize
    //  allocations in our use of sdl. Time will tell
    var sdl_tracing_allocator = tracy.TracingAllocator.initNamed("sdl", std.heap.raw_c_allocator);
    sdl_allocator = sdl_tracing_allocator.allocator();
    // sdl_allocator = std.heap.raw_c_allocator;

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
        .title = "fe",
        .position = .{
            .x = .centered,
            .y = .centered,
        },
        .size = .{ .w = 800, .h = 600 },
        .flags = .{
            .hidden = true,
            .allow_highdpi = true,
            .resizable = true,
        },
    });
    defer window.deinit();

    const renderer = try sdl.Renderer.init(.{
        .window = window,
        .flags = .{ .accelerated = true },
    });
    defer renderer.deinit();

    var dynlib = try Dynlib.load(allocator);
    defer dynlib.close(allocator);

    var arena = std.heap.ArenaAllocator.init(std.heap.raw_c_allocator);
    // var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    var tracing_arena_allocator = tracy.TracingAllocator.initNamed("arena", arena.allocator());
    defer tracing_arena_allocator.discard();
    const arena_allocator = tracing_arena_allocator.allocator();

    // HACK: workaround for the memory tracing not getting the right timing
    //  information. Without it allocations are reported as being a long time
    //  before actuality
    _ = arena_allocator.alloc(u8, 1) catch {};

    const event_timeout = 16; // ms
    const update_60_times_a_second = 16 * 1000 * 1000; // ns

    var ticker = try TickerTimer(2).start();
    const update = ticker.getTicker(0, update_60_times_a_second);
    const render = ticker.getTicker(1, update_60_times_a_second);

    var show_failed_reset = if (builtin.mode == .Debug) false;

    var should_reload_dynlib = false;

    window.show();
    var running = true;

    common.log.global_state.allocator = arena_allocator;

    init_zone.deinit();

    while (running) {
        defer tracy.frameMark();
        ticker.lap();

        if (sdl.Event.waitTimeout(event_timeout)) |ev| {
            const events_zone = tracy.initZone(@src(), .{ .name = "events" });
            defer events_zone.deinit();

            switch (ev.type) {
                .quit => {
                    log.trace(@src(), "quit event recived, quiting...");
                    running = false;
                },

                .key => |key| blk: {
                    if (key.state != .pressed)
                        break :blk;
                    switch (key.keysym.sym) {
                        .q => {
                            log.trace(@src(), "quiting...");
                            running = false;
                        },

                        .r => {
                            should_reload_dynlib = true;
                            if (debug_mode)
                                show_failed_reset = false;
                        },

                        .h => {
                            tracy.message("greet");

                            const name = "ketan";

                            log.tracekv(@src(), "doing greet", .{ .name = name });
                            dynlib.api.greet(name);
                        },

                        .f => {
                            const msg = try std.fmt.allocPrint(
                                arena_allocator,
                                "Some int: {d}",
                                .{15},
                            );
                            dynlib.api.greet(msg);
                        },

                        .l => {
                            tracy.message("test log");
                            log.tracekv(
                                @src(),
                                "test log message that allocates",
                                .{
                                    .foo = "bar",
                                    .int = 42,
                                    .float = 36.7,
                                    .boolean = false,
                                },
                            );
                        },

                        else => {},
                    }
                },

                else => {},
            }
        }

        while (update.shouldTick()) {
            const update_zone = tracy.initZone(@src(), .{ .name = "update" });
            defer update_zone.deinit();

            if (dynlib_recompiled)
                should_reload_dynlib = true;

            if (should_reload_dynlib) {
                should_reload_dynlib = false;

                log.trace(@src(), "reloading dynlib...");
                defer log.trace(@src(), "reloading dynlib done");

                dynlib_recompiled = false;

                try dynlib.reload(allocator);
            }
        }

        while (render.shouldTick()) {
            const render_zone = tracy.initZone(@src(), .{ .name = "render" });
            defer render_zone.deinit();

            var r: u8 = undefined;
            var g: u8 = undefined;
            var b: u8 = undefined;
            dynlib.api.getColor(&r, &g, &b);

            renderer.setDrawColor(r, g, b, 255) catch {};

            renderer.clear() catch {};
            renderer.present();
        }

        // FIXME: Limit this accordingly!
        // FIXME: Figure out why this always fails to reset
        // const area_reset_failed = arena.reset(.retain_capacity);
        const area_reset_failed = arena.reset(.free_all);
        tracing_arena_allocator.discard();
        if (debug_mode and area_reset_failed and !show_failed_reset) {
            show_failed_reset = true;
            log.err(
                @src(),
                "Arena reset failed. This is likely to happen again " ++
                    "so this message will not repeat. To reset this flag press r",
            );
        }
    }

    return .successful;
}

pub fn TickerTimer(comptime ticker_count: comptime_int) type {
    return struct {
        timer: std.time.Timer,
        tickers: [ticker_count]Ticker,

        const Self = @This();

        pub fn start() !Self {
            return Self{
                .timer = try std.time.Timer.start(),
                .tickers = undefined,
            };
        }

        pub fn lap(self: *Self) void {
            const elapsed = self.timer.lap();
            inline for (0..ticker_count) |i| {
                self.tickers[i].correction += elapsed;
            }
        }

        pub fn getTicker(self: *Self, comptime index: comptime_int, timestep: u64) *Ticker {
            const ticker = &self.tickers[index];
            ticker.* = .{ .timestep = timestep, .correction = timestep };
            return ticker;
        }

        pub const Ticker = struct {
            timestep: u64,
            correction: u64,

            pub fn shouldTick(self: *Ticker) bool {
                const cond = self.correction >= self.timestep;
                if (cond) self.correction -= self.timestep;
                // This should only allow one iteration at a time in debug mode
                if (debugger_attached) self.correction = 0;
                return cond;
            }
        };
    };
}

pub const Dynlib = struct {
    library: std.DynLib,
    api: common.Api,

    const Path = "zig-out/lib/libdynlib.so";

    pub fn load(allocator: Allocator) !Dynlib {
        var dynlib: Dynlib = undefined;
        dynlib.library = try std.DynLib.open(Path);
        errdefer dynlib.library.close();
        dynlib.api = try common.Api.load(&dynlib.library);
        dynlib.api.onLoad(allocator, common.log.global_state);
        return dynlib;
    }

    pub fn reload(dynlib: *Dynlib, allocator: Allocator) !void {
        tracy.message("reloading dynamic lib");

        dynlib.api.onUnload(allocator);
        dynlib.library.close();

        dynlib.library = try std.DynLib.open(Path);
        errdefer dynlib.library.close();
        try dynlib.api.reload(&dynlib.library);
        dynlib.api.onLoad(allocator, common.log.global_state);
    }

    pub fn close(dynlib: *Dynlib, allocator: Allocator) void {
        dynlib.api.onUnload(allocator);
        dynlib.library.close();
    }
};

fn installSigaction() !void {
    const act = std.os.linux.Sigaction{
        .handler = .{ .handler = handleSignal },
        .mask = std.os.linux.empty_sigset,
        .flags = 0,
    };
    const sigaction_res = std.os.linux.sigaction(std.os.linux.SIG.USR1, &act, null);
    if (sigaction_res != 0) {
        const err = std.posix.errno(sigaction_res);
        log.errkv(
            @src(),
            "Failed to setup sigaction",
            .{ .errno = err },
        );
        return error.FailedToSetSigaction;
    }
}

fn handleSignal(sig: c_int) callconv(.C) void {
    switch (sig) {
        std.os.linux.SIG.USR1 => {
            log.info(
                @src(),
                "Got USR1 signal, dynlib marked out of date",
            );
            dynlib_recompiled = true;
        },
        else => {
            log.warnkv(
                @src(),
                "Got unknown signal",
                .{ .sig = sig },
            );
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
