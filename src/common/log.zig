const std = @import("std");
const SourceLocation = std.builtin.SourceLocation;
const out = @import("out.zig");
const Allocator = std.mem.Allocator;
const DateTime = @import("datetime").DateTime;

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

pub const Log = struct {
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
        self: Log,
        level: Level,
        target: []const u8,
    ) bool {
        return self.vtable.enabled(self.ptr, level, target);
    }

    pub fn log(
        self: Log,
        allocator: Allocator,
        location: SourceLocation,
        level: Level,
        target: []const u8,
        message: []const u8,
        kv: []const KeyValue,
    ) void {
        self.vtable.log(self.ptr, allocator, location, level, target, message, kv);
    }

    pub fn flush(self: Log) void {
        self.vtable.flush(self.ptr);
    }
};

const GlobalState = struct {
    allocator: Allocator,
    level_filter: LevelFilter,
    logger: Log,
};

var global_state: ?GlobalState = null;

pub fn setup(args: struct {
    allocator: Allocator,
    level_filter: LevelFilter = .trace,
    logger: Log,
}) void {
    global_state = .{
        .allocator = args.allocator,
        .level_filter = args.level_filter,
        .logger = args.logger,
    };
}

pub fn log(
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

    const gs = global_state orelse return;

    if (@intFromEnum(level) > @intFromEnum(gs.level_filter))
        return;

    const logger = gs.logger;
    if (!logger.enabled(level, target))
        return;

    const message = std.fmt.allocPrint(gs.allocator, format, args) catch unreachable;
    defer gs.allocator.free(message);

    const kv_array = kvToArray(KvType, kv, gs.allocator) catch unreachable;
    defer freeKvArray(KvType, kv_array, gs.allocator);

    logger.log(gs.allocator, location, level, target, message, &kv_array);

    logger.flush();
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

pub const ConsoleLogger = struct {
    level_filter: LevelFilter,
    bw: BufferedWriter,

    const BufferedWriter = std.io.BufferedWriter(4096, std.fs.File.Writer);

    pub fn new(level_filter: LevelFilter) !ConsoleLogger {
        const stderr = std.io.getStdErr();
        const bw = BufferedWriter{
            .unbuffered_writer = stderr.writer(),
            .end = 0,
            .buf = undefined,
        };
        return .{ .level_filter = level_filter, .bw = bw };
    }

    pub fn createLog(self: *ConsoleLogger) Log {
        return .{
            .ptr = @ptrCast(self),
            .vtable = &.{
                .enabled = &enabled,
                .log = &doLog,
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

    pub fn doLog(
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
            "{s}[{s} {s} {s}:{d}@{s}] {s}{s} {s} {s} {s}",
            .{
                deemphasis_color,
                dt_str,
                target,
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

pub fn fatal(location: SourceLocation, target: []const u8, comptime message: []const u8) void {
    log(location, .fatal, target, message, .{}, .{});
}

pub fn fatalf(location: SourceLocation, target: []const u8, comptime format: []const u8, args: anytype) void {
    log(location, .fatal, target, format, args, .{});
}

pub fn fatalkv(location: SourceLocation, target: []const u8, comptime message: []const u8, kv: anytype) void {
    log(location, .fatal, target, message, .{}, kv);
}

pub fn fatalfkv(location: SourceLocation, target: []const u8, comptime format: []const u8, args: anytype, kv: anytype) void {
    log(location, .fatal, target, format, args, kv);
}

pub fn err(location: SourceLocation, target: []const u8, comptime message: []const u8) void {
    log(location, .err, target, message, .{}, .{});
}

pub fn errf(location: SourceLocation, target: []const u8, comptime format: []const u8, args: anytype) void {
    log(location, .err, target, format, args, .{});
}

pub fn errkv(location: SourceLocation, target: []const u8, comptime message: []const u8, kv: anytype) void {
    log(location, .err, target, message, .{}, kv);
}

pub fn errfkv(location: SourceLocation, target: []const u8, comptime format: []const u8, args: anytype, kv: anytype) void {
    log(location, .err, target, format, args, kv);
}

pub fn warn(location: SourceLocation, target: []const u8, comptime message: []const u8) void {
    log(location, .warn, target, message, .{}, .{});
}

pub fn warnf(location: SourceLocation, target: []const u8, comptime format: []const u8, args: anytype) void {
    log(location, .warn, target, format, args, .{});
}

pub fn warnkv(location: SourceLocation, target: []const u8, comptime message: []const u8, kv: anytype) void {
    log(location, .warn, target, message, .{}, kv);
}

pub fn warnfkv(location: SourceLocation, target: []const u8, comptime format: []const u8, args: anytype, kv: anytype) void {
    log(location, .warn, target, format, args, kv);
}

pub fn info(location: SourceLocation, target: []const u8, comptime message: []const u8) void {
    log(location, .info, target, message, .{}, .{});
}

pub fn infof(location: SourceLocation, target: []const u8, comptime format: []const u8, args: anytype) void {
    log(location, .info, target, format, args, .{});
}

pub fn infokv(location: SourceLocation, target: []const u8, comptime message: []const u8, kv: anytype) void {
    log(location, .info, target, message, .{}, kv);
}

pub fn infofkv(location: SourceLocation, target: []const u8, comptime format: []const u8, args: anytype, kv: anytype) void {
    log(location, .info, target, format, args, kv);
}

pub fn debug(location: SourceLocation, target: []const u8, comptime message: []const u8) void {
    log(location, .debug, target, message, .{}, .{});
}

pub fn debugf(location: SourceLocation, target: []const u8, comptime format: []const u8, args: anytype) void {
    log(location, .debug, target, format, args, .{});
}

pub fn debugkv(location: SourceLocation, target: []const u8, comptime message: []const u8, kv: anytype) void {
    log(location, .debug, target, message, .{}, kv);
}

pub fn debugfkv(location: SourceLocation, target: []const u8, comptime format: []const u8, args: anytype, kv: anytype) void {
    log(location, .debug, target, format, args, kv);
}

pub fn trace(location: SourceLocation, target: []const u8, comptime message: []const u8) void {
    log(location, .trace, target, message, .{}, .{});
}

pub fn tracef(location: SourceLocation, target: []const u8, comptime format: []const u8, args: anytype) void {
    log(location, .trace, target, format, args, .{});
}

pub fn tracekv(location: SourceLocation, target: []const u8, comptime message: []const u8, kv: anytype) void {
    log(location, .trace, target, message, .{}, kv);
}

pub fn tracefkv(location: SourceLocation, target: []const u8, comptime format: []const u8, args: anytype, kv: anytype) void {
    log(location, .trace, target, format, args, kv);
}

pub fn Scoped(comptime target: []const u8) type {
    return struct {
        pub fn fatal(location: SourceLocation, comptime message: []const u8) void {
            log(location, .fatal, target, message, .{}, .{});
        }

        pub fn fatalf(location: SourceLocation, comptime format: []const u8, args: anytype) void {
            log(location, .fatal, target, format, args, .{});
        }

        pub fn fatalkv(location: SourceLocation, comptime message: []const u8, kv: anytype) void {
            log(location, .fatal, target, message, .{}, kv);
        }

        pub fn fatalfkv(location: SourceLocation, comptime format: []const u8, args: anytype, kv: anytype) void {
            log(location, .fatal, target, format, args, kv);
        }

        pub fn err(location: SourceLocation, comptime message: []const u8) void {
            log(location, .err, target, message, .{}, .{});
        }

        pub fn errf(location: SourceLocation, comptime format: []const u8, args: anytype) void {
            log(location, .err, target, format, args, .{});
        }

        pub fn errkv(location: SourceLocation, comptime message: []const u8, kv: anytype) void {
            log(location, .err, target, message, .{}, kv);
        }

        pub fn errfkv(location: SourceLocation, comptime format: []const u8, args: anytype, kv: anytype) void {
            log(location, .err, target, format, args, kv);
        }

        pub fn warn(location: SourceLocation, comptime message: []const u8) void {
            log(location, .warn, target, message, .{}, .{});
        }

        pub fn warnf(location: SourceLocation, comptime format: []const u8, args: anytype) void {
            log(location, .warn, target, format, args, .{});
        }

        pub fn warnkv(location: SourceLocation, comptime message: []const u8, kv: anytype) void {
            log(location, .warn, target, message, .{}, kv);
        }

        pub fn warnfkv(location: SourceLocation, comptime format: []const u8, args: anytype, kv: anytype) void {
            log(location, .warn, target, format, args, kv);
        }

        pub fn info(location: SourceLocation, comptime message: []const u8) void {
            log(location, .info, target, message, .{}, .{});
        }

        pub fn infof(location: SourceLocation, comptime format: []const u8, args: anytype) void {
            log(location, .info, target, format, args, .{});
        }

        pub fn infokv(location: SourceLocation, comptime message: []const u8, kv: anytype) void {
            log(location, .info, target, message, .{}, kv);
        }

        pub fn infofkv(location: SourceLocation, comptime format: []const u8, args: anytype, kv: anytype) void {
            log(location, .info, target, format, args, kv);
        }

        pub fn debug(location: SourceLocation, comptime message: []const u8) void {
            log(location, .debug, target, message, .{}, .{});
        }

        pub fn debugf(location: SourceLocation, comptime format: []const u8, args: anytype) void {
            log(location, .debug, target, format, args, .{});
        }

        pub fn debugkv(location: SourceLocation, comptime message: []const u8, kv: anytype) void {
            log(location, .debug, target, message, .{}, kv);
        }

        pub fn debugfkv(location: SourceLocation, comptime format: []const u8, args: anytype, kv: anytype) void {
            log(location, .debug, target, format, args, kv);
        }

        pub fn trace(location: SourceLocation, comptime message: []const u8) void {
            log(location, .trace, target, message, .{}, .{});
        }

        pub fn tracef(location: SourceLocation, comptime format: []const u8, args: anytype) void {
            log(location, .trace, target, format, args, .{});
        }

        pub fn tracekv(location: SourceLocation, comptime message: []const u8, kv: anytype) void {
            log(location, .trace, target, message, .{}, kv);
        }

        pub fn tracefkv(location: SourceLocation, comptime format: []const u8, args: anytype, kv: anytype) void {
            log(location, .trace, target, format, args, kv);
        }
    };
}
