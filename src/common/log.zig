const std = @import("std");
const SourceLocation = std.builtin.SourceLocation;
const out = @import("out.zig");
const Allocator = std.mem.Allocator;
const DateTime = @import("datetime").DateTime;
const tracy = @import("tracy");

pub var global_state = State{};

pub const State = struct {
    allocator: Allocator = std.heap.page_allocator,
    level_filter: LevelFilter = .trace,
    logger: Logger = noop_logger,
};

pub fn setup(state: State) void {
    global_state = state;
}

pub const LevelFilter = enum(u8) {
    off = 0,
    fatal = 1,
    err = 2,
    warn = 3,
    info = 4,
    debug = 5,
    trace = 6,

    pub fn max() LevelFilter {
        return .trace;
    }

    pub fn toLevel(self: LevelFilter) ?Level {
        if (self == .off)
            return null
        else
            return @bitCast(self);
    }
};

pub const Level = enum(u8) {
    fatal = 1,
    err = 2,
    warn = 3,
    info = 4,
    debug = 5,
    trace = 6,

    pub fn max() Level {
        return .trace;
    }

    pub fn toLevelFilter(self: Level) LevelFilter {
        return @bitCast(self);
    }
};

pub const Logger = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        enabled: *const fn (
            self: *anyopaque,
            level: Level,
            target: []const u8,
        ) bool,
        log: *const fn (
            self: *anyopaque,
            allocator: Allocator,
            location: SourceLocation,
            level: Level,
            target: []const u8,
            message: []const u8,
            kv: []const KeyValue,
        ) void,
        flush: *const fn (self: *anyopaque) void,
    };

    pub fn enabled(
        self: Logger,
        level: Level,
        target: []const u8,
    ) bool {
        return self.vtable.enabled(self.ptr, level, target);
    }

    pub fn log(
        self: Logger,
        allocator: Allocator,
        location: SourceLocation,
        level: Level,
        target: []const u8,
        message: []const u8,
        kv: []const KeyValue,
    ) void {
        self.vtable.log(self.ptr, allocator, location, level, target, message, kv);
    }

    pub fn flush(self: Logger) void {
        self.vtable.flush(self.ptr);
    }
};

fn logfnEnabled(level: Level, target: []const u8) bool {
    if (@intFromEnum(level) > @intFromEnum(global_state.level_filter))
        return false;
    const logger = global_state.logger;
    return logger.enabled(level, target);
}

pub fn logfn(
    location: SourceLocation,
    level: Level,
    target: []const u8,
    comptime message: []const u8,
) void {
    if (!logfnEnabled(level, target)) return;

    global_state.logger.log(global_state.allocator, location, level, target, message, &[_]KeyValue{});
    global_state.logger.flush();
}

pub fn logfnf(
    location: SourceLocation,
    level: Level,
    target: []const u8,
    comptime format: []const u8,
    args: anytype,
) void {
    if (!logfnEnabled(level, target)) return;

    const message = std.fmt.allocPrint(global_state.allocator, format, args) catch unreachable;
    defer global_state.allocator.free(message);

    global_state.logger.log(global_state.allocator, location, level, target, message, &[_]KeyValue{});
    global_state.logger.flush();
}

pub fn logfnkv(
    location: SourceLocation,
    level: Level,
    target: []const u8,
    comptime message: []const u8,
    kv: anytype,
) void {
    const KvType = @TypeOf(kv);
    const kv_type_info = @typeInfo(KvType);
    if (kv_type_info != .Struct) {
        @compileError("expected tuple or struct argument, found " ++ @typeName(KvType));
    }

    if (!logfnEnabled(level, target)) return;

    const kv_array = kvToArray(KvType, kv, global_state.allocator) catch unreachable;
    defer freeKvArray(KvType, kv_array, global_state.allocator);

    global_state.logger.log(global_state.allocator, location, level, target, message, &kv_array);
    global_state.logger.flush();
}

pub fn logfnfkv(
    location: SourceLocation,
    level: Level,
    target: []const u8,
    comptime format: []const u8,
    args: anytype,
    kv: anytype,
) void {
    const KvType = @TypeOf(kv);
    const kv_type_info = @typeInfo(KvType);
    if (kv_type_info != .Struct) {
        @compileError("expected tuple or struct argument, found " ++ @typeName(KvType));
    }

    if (!logfnEnabled(level, target)) return;

    const message = std.fmt.allocPrint(global_state.allocator, format, args) catch unreachable;
    defer global_state.allocator.free(message);

    const kv_array = kvToArray(KvType, kv, global_state.allocator) catch unreachable;
    defer freeKvArray(KvType, kv_array, global_state.allocator);

    global_state.logger.log(global_state.allocator, location, level, target, message, &kv_array);
    global_state.logger.flush();
}

pub const KeyValue = struct {
    key: []const u8,
    value: []const u8,
};

fn kvToArray(comptime KvType: type, kv: KvType, allocator: Allocator) ![std.meta.fields(KvType).len]KeyValue {
    const fields = std.meta.fields(KvType);
    var result: [fields.len]KeyValue = undefined;

    inline for (fields, 0..) |field, i| {
        const value = @field(kv, field.name);

        result[i] = .{
            .key = field.name,
            .value = blk: {
                // this is a hack to check if the value is a string, and to format it as such
                switch (@typeInfo(@TypeOf(value))) {
                    .Array => |arr_info| if (arr_info.child == u8)
                        break :blk try std.fmt.allocPrint(allocator, "\"{s}\"", .{value}),
                    .Pointer => |ptr_info| if (ptr_info.child == u8)
                        break :blk try std.fmt.allocPrint(allocator, "\"{s}\"", .{value})
                    else switch (@typeInfo(ptr_info.child)) {
                        .Array => |arr_info| if (arr_info.child == u8)
                            break :blk try std.fmt.allocPrint(allocator, "\"{s}\"", .{value}),
                        .Pointer => |array_ptr_info| if (array_ptr_info.child == u8)
                            break :blk try std.fmt.allocPrint(allocator, "\"{s}\"", .{value}),
                        else => {},
                    },
                    else => {},
                }

                break :blk try std.fmt.allocPrint(allocator, "{any}", .{value});
            },
        };
    }

    return result;
}

fn freeKvArray(comptime KvType: type, kv_array: [std.meta.fields(KvType).len]KeyValue, allocator: Allocator) void {
    inline for (kv_array) |i| {
        allocator.free(i.value);
    }
}

pub fn fatal(location: SourceLocation, target: []const u8, comptime message: []const u8) void {
    logfn(location, .fatal, target, message);
}

pub fn fatalf(location: SourceLocation, target: []const u8, comptime format: []const u8, args: anytype) void {
    logfnf(location, .fatal, target, format, args);
}

pub fn fatalkv(location: SourceLocation, target: []const u8, comptime message: []const u8, kv: anytype) void {
    logfnkv(location, .fatal, target, message, kv);
}

pub fn fatalfkv(location: SourceLocation, target: []const u8, comptime format: []const u8, args: anytype, kv: anytype) void {
    logfnfkv(location, .fatal, target, format, args, kv);
}

pub fn err(location: SourceLocation, target: []const u8, comptime message: []const u8) void {
    logfn(location, .err, target, message);
}

pub fn errf(location: SourceLocation, target: []const u8, comptime format: []const u8, args: anytype) void {
    logfnf(location, .err, target, format, args);
}

pub fn errkv(location: SourceLocation, target: []const u8, comptime message: []const u8, kv: anytype) void {
    logfnkv(location, .err, target, message, kv);
}

pub fn errfkv(location: SourceLocation, target: []const u8, comptime format: []const u8, args: anytype, kv: anytype) void {
    logfnfkv(location, .err, target, format, args, kv);
}

pub fn warn(location: SourceLocation, target: []const u8, comptime message: []const u8) void {
    logfn(location, .warn, target, message);
}

pub fn warnf(location: SourceLocation, target: []const u8, comptime format: []const u8, args: anytype) void {
    logfnf(location, .warn, target, format, args);
}

pub fn warnkv(location: SourceLocation, target: []const u8, comptime message: []const u8, kv: anytype) void {
    logfnkv(location, .warn, target, message, kv);
}

pub fn warnfkv(location: SourceLocation, target: []const u8, comptime format: []const u8, args: anytype, kv: anytype) void {
    logfnfkv(location, .warn, target, format, args, kv);
}

pub fn info(location: SourceLocation, target: []const u8, comptime message: []const u8) void {
    logfn(location, .info, target, message);
}

pub fn infof(location: SourceLocation, target: []const u8, comptime format: []const u8, args: anytype) void {
    logfnf(location, .info, target, format, args);
}

pub fn infokv(location: SourceLocation, target: []const u8, comptime message: []const u8, kv: anytype) void {
    logfnkv(location, .info, target, message, kv);
}

pub fn infofkv(location: SourceLocation, target: []const u8, comptime format: []const u8, args: anytype, kv: anytype) void {
    logfnfkv(location, .info, target, format, args, kv);
}

pub fn debug(location: SourceLocation, target: []const u8, comptime message: []const u8) void {
    logfn(location, .debug, target, message);
}

pub fn debugf(location: SourceLocation, target: []const u8, comptime format: []const u8, args: anytype) void {
    logfnf(location, .debug, target, format, args);
}

pub fn debugkv(location: SourceLocation, target: []const u8, comptime message: []const u8, kv: anytype) void {
    logfnkv(location, .debug, target, message, kv);
}

pub fn debugfkv(location: SourceLocation, target: []const u8, comptime format: []const u8, args: anytype, kv: anytype) void {
    logfnfkv(location, .debug, target, format, args, kv);
}

pub fn trace(location: SourceLocation, target: []const u8, comptime message: []const u8) void {
    logfn(location, .trace, target, message);
}

pub fn tracef(location: SourceLocation, target: []const u8, comptime format: []const u8, args: anytype) void {
    logfnf(location, .trace, target, format, args);
}

pub fn tracekv(location: SourceLocation, target: []const u8, comptime message: []const u8, kv: anytype) void {
    logfnkv(location, .trace, target, message, kv);
}

pub fn tracefkv(location: SourceLocation, target: []const u8, comptime format: []const u8, args: anytype, kv: anytype) void {
    logfnfkv(location, .trace, target, format, args, kv);
}

pub fn Scoped(comptime target: []const u8) type {
    return struct {
        pub fn fatal(location: SourceLocation, comptime message: []const u8) void {
            logfn(location, .fatal, target, message);
        }

        pub fn fatalf(location: SourceLocation, comptime format: []const u8, args: anytype) void {
            logfnf(location, .fatal, target, format, args);
        }

        pub fn fatalkv(location: SourceLocation, comptime message: []const u8, kv: anytype) void {
            logfnkv(location, .fatal, target, message, kv);
        }

        pub fn fatalfkv(location: SourceLocation, comptime format: []const u8, args: anytype, kv: anytype) void {
            logfnfkv(location, .fatal, target, format, args, kv);
        }

        pub fn err(location: SourceLocation, comptime message: []const u8) void {
            logfn(location, .err, target, message);
        }

        pub fn errf(location: SourceLocation, comptime format: []const u8, args: anytype) void {
            logfnf(location, .err, target, format, args);
        }

        pub fn errkv(location: SourceLocation, comptime message: []const u8, kv: anytype) void {
            logfnkv(location, .err, target, message, kv);
        }

        pub fn errfkv(location: SourceLocation, comptime format: []const u8, args: anytype, kv: anytype) void {
            logfnfkv(location, .err, target, format, args, kv);
        }

        pub fn warn(location: SourceLocation, comptime message: []const u8) void {
            logfn(location, .warn, target, message);
        }

        pub fn warnf(location: SourceLocation, comptime format: []const u8, args: anytype) void {
            logfnf(location, .warn, target, format, args);
        }

        pub fn warnkv(location: SourceLocation, comptime message: []const u8, kv: anytype) void {
            logfnkv(location, .warn, target, message, kv);
        }

        pub fn warnfkv(location: SourceLocation, comptime format: []const u8, args: anytype, kv: anytype) void {
            logfnfkv(location, .warn, target, format, args, kv);
        }

        pub fn info(location: SourceLocation, comptime message: []const u8) void {
            logfn(location, .info, target, message);
        }

        pub fn infof(location: SourceLocation, comptime format: []const u8, args: anytype) void {
            logfnf(location, .info, target, format, args);
        }

        pub fn infokv(location: SourceLocation, comptime message: []const u8, kv: anytype) void {
            logfnkv(location, .info, target, message, kv);
        }

        pub fn infofkv(location: SourceLocation, comptime format: []const u8, args: anytype, kv: anytype) void {
            logfnfkv(location, .info, target, format, args, kv);
        }

        pub fn debug(location: SourceLocation, comptime message: []const u8) void {
            logfn(location, .debug, target, message);
        }

        pub fn debugf(location: SourceLocation, comptime format: []const u8, args: anytype) void {
            logfnf(location, .debug, target, format, args);
        }

        pub fn debugkv(location: SourceLocation, comptime message: []const u8, kv: anytype) void {
            logfnkv(location, .debug, target, message, kv);
        }

        pub fn debugfkv(location: SourceLocation, comptime format: []const u8, args: anytype, kv: anytype) void {
            logfnfkv(location, .debug, target, format, args, kv);
        }

        pub fn trace(location: SourceLocation, comptime message: []const u8) void {
            logfn(location, .trace, target, message);
        }

        pub fn tracef(location: SourceLocation, comptime format: []const u8, args: anytype) void {
            logfnf(location, .trace, target, format, args);
        }

        pub fn tracekv(location: SourceLocation, comptime message: []const u8, kv: anytype) void {
            logfnkv(location, .trace, target, message, kv);
        }

        pub fn tracefkv(location: SourceLocation, comptime format: []const u8, args: anytype, kv: anytype) void {
            logfnfkv(location, .trace, target, format, args, kv);
        }
    };
}

pub const Span = struct {
    src: SourceLocation,
    start_time: std.time.Instant,
    opts: Options,
    tracy_ctx: ?tracy.ZoneContext = null,

    pub const LogContext = struct {
        level: Level,
        target: []const u8,
    };

    pub const TracyOptions = struct {
        active: bool = true,
        color: ?u32 = null,
    };

    pub const Options = struct {
        name: ?[:0]const u8 = null,
        log: ?LogContext = null,
        tracy: ?TracyOptions = null,
    };

    pub fn start(src: SourceLocation, options: Options) Span {
        const now = std.time.Instant.now() catch @panic("can't time");

        var self = Span{
            .src = src,
            .start_time = now,
            .opts = options,
            .tracy_ctx = undefined,
        };

        if (self.opts.log) |ctx| {
            logfnf(
                src,
                ctx.level,
                ctx.target,
                "span '{s}' start",
                .{self.opts.name orelse "null"},
            );
        }

        self.tracy_ctx = if (self.opts.tracy) |opts|
            tracy.initZone(src, .{
                .name = self.opts.name,
                .active = opts.active,
                .color = opts.color,
            })
        else
            null;

        return self;
    }

    // returns elapsed time in nanoseconds
    pub fn end(self: *const Span, src: SourceLocation) u64 {
        const now = std.time.Instant.now() catch @panic("can't time");
        const elapsed = now.since(self.start_time);

        const duration = NsDurationFormatter { .duration = elapsed };

        if (self.opts.log) |ctx| {
            logfnf(
                src,
                ctx.level,
                ctx.target,
                "span '{s}' end - elapsed: {} ({d})",
                .{ self.opts.name orelse "null", duration, elapsed },
            );
        }

        if (self.tracy_ctx) |ctx| {
            ctx.deinit();
        }

        return elapsed;
    }
};

pub const NsDurationFormatter = struct {
    duration: u64, // ns

    pub fn format(
        self: NsDurationFormatter,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;

        var accum: u64 = 0;

        const weeks = (self.duration - accum) / std.time.ns_per_week;
        accum += weeks * std.time.ns_per_week;

        const days = (self.duration - accum) / std.time.ns_per_day;
        accum += days * std.time.ns_per_day;

        const hours = (self.duration - accum) / std.time.ns_per_hour;
        accum += hours * std.time.ns_per_hour;

        const mins = (self.duration - accum) / std.time.ns_per_min;
        accum += mins * std.time.ns_per_min;

        const s = (self.duration - accum) / std.time.ns_per_s;
        accum += s * std.time.ns_per_s;

        const ms = (self.duration - accum) / std.time.ns_per_ms;
        accum += ms * std.time.ns_per_ms;

        const us = (self.duration - accum) / std.time.ns_per_us;
        accum += us * std.time.ns_per_us;

        const ns = self.duration - accum;

        const Spacer = struct {
            do_space: bool = false,

            const Self = @This();

            pub inline fn put(spacer: *Self, w: anytype) !void {
                if (spacer.do_space)
                    try w.writeByte(' ');
                spacer.do_space = false;
            }

            pub inline fn mark(spacer: *Self) void {
                spacer.do_space = true;
            }

            pub inline fn print(spacer: *Self, w: anytype, comptime f: []const u8, args: anytype) !void {
                try spacer.put(w);
                try w.print(f, args);
                spacer.mark();
            }
        };

        var spacer = Spacer{};

        if (weeks > 0) {
            try writer.print("{d} weeks", .{weeks});
            spacer.mark();
        }
        if (days > 0) try spacer.print(writer, "{d} days", .{days});
        if (hours > 0) try spacer.print(writer, "{d} hours", .{hours});
        if (mins > 0) try spacer.print(writer, "{d} mins", .{mins});
        if (s > 0) try spacer.print(writer, "{d} s", .{s});
        if (ms > 0) try spacer.print(writer, "{d} ms", .{ms});
        if (us > 0) try spacer.print(writer, "{d} us", .{us});
        if (ns > 0) try spacer.print(writer, "{d} ns", .{ns});
    }
};

pub const noop_logger = Logger{
    .ptr = undefined,
    .vtable = &noop_logger_vtable,
};
const noop_logger_vtable = Logger.VTable{
    .enabled = &NoopLogger.enabled,
    .log = &NoopLogger.log,
    .flush = &NoopLogger.flush,
};

const NoopLogger = struct {
    pub fn enabled(_: *anyopaque, _: Level, _: []const u8) bool {
        return false;
    }

    pub fn log(_: *anyopaque, _: Allocator, _: SourceLocation, _: Level, _: []const u8, _: []const u8, _: []const KeyValue,) void {}

    pub fn flush(_: *anyopaque) void {}
};

pub const ConsoleLogger = struct {
    level_filter: LevelFilter,
    bw: BufferedWriter,

    const BufferedWriter = std.io.BufferedWriter(4096, std.fs.File.Writer);

    pub fn new(level_filter: LevelFilter) ConsoleLogger {
        const stderr = std.io.getStdErr();
        const bw = BufferedWriter{
            .unbuffered_writer = stderr.writer(),
            .end = 0,
            .buf = undefined,
        };
        return .{ .level_filter = level_filter, .bw = bw };
    }

    pub fn logger(self: *ConsoleLogger) Logger {
        return .{
            .ptr = @ptrCast(self),
            .vtable = &.{
                .enabled = &enabled,
                .log = &log,
                .flush = &flush,
            },
        };
    }

    pub fn enabled(ctx: *anyopaque, level: Level, _: []const u8) bool {
        const self: *ConsoleLogger = @ptrCast(@alignCast(ctx));
        if (@intFromEnum(level) > @intFromEnum(self.level_filter))
            return false;
        return true;
    }

    pub fn log(
        ctx: *anyopaque,
        allocator: Allocator,
        location: SourceLocation,
        level: Level,
        target: []const u8,
        message: []const u8,
        kvs: []const KeyValue,
    ) void {
        _ = allocator;

        const level_colors = [_][]const u8{
            "", // off
            "\x1b[1;41m", // fatal - bold red background
            "\x1b[0;41m", // err - red background
            "\x1b[0;43m", // warn - yellow background
            "\x1b[0;44m", // info - blue background
            "\x1b[0;45m", // debug - purple background
            "\x1b[0;42m", // trace - green background
        };
        const reset_color = "\x1b[0m";
        const deemphasis_color = "\x1b[90m"; // grey color

        const dt = DateTime.fromMillis(std.time.milliTimestamp());
        var dt_buffer: [30]u8 = undefined;
        const dt_str = dt.toRfc3339(&dt_buffer) catch unreachable;

        const self: *ConsoleLogger = @ptrCast(@alignCast(ctx));
        self.bw.writer().print(
            "{s}[{s} {s}{s}{s} {s}:{d}@{s}] {s}{s} {s} {s} {s}",
            .{
                deemphasis_color,
                dt_str,
                reset_color,
                target,
                deemphasis_color,
                location.file,
                location.line,
                location.fn_name,
                reset_color,
                level_colors[@intFromEnum(level)],
                @tagName(level),
                reset_color,
                message,
            },
        ) catch unreachable;

        if (kvs.len > 0) {
            self.bw.writer().writeAll(" -- { ") catch unreachable;
            for (kvs, 0..) |kv, i| {
                self.bw.writer().print(
                    ".{s}: {s}",
                    .{ kv.key, kv.value },
                ) catch unreachable;

                if (i + 1 < kvs.len) {
                    self.bw.writer().writeByte(',') catch unreachable;
                }
                self.bw.writer().writeByte(' ') catch unreachable;
            }

            self.bw.writer().writeAll("}") catch unreachable;
        }

        self.bw.writer().writeByte('\n') catch unreachable;
        // self.bw.flush() catch unreachable;
    }

    pub fn flush(ctx: *anyopaque) void {
        const self: *ConsoleLogger = @ptrCast(@alignCast(ctx));
        self.bw.flush() catch unreachable;
    }
};
