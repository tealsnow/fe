const std = @import("std");
const SourceLocation = std.builtin.SourceLocation;
const out = @import("out.zig");

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

    // pub fn asStr() []u8 {
    //     @tagName()
    // }
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
    ptr: *const anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        enabled: *const fn (
            self: *const anyopaque,
            level: Level,
            target: []const u8,
        ) bool,
        log: *const fn (
            self: *const anyopaque,
            allocator: std.mem.Allocator,
            location: SourceLocation,
            level: Level,
            target: []const u8,
            message: []const u8,
            kv: []const KeyValue,
        ) void,
        flush: *const fn (self: *const anyopaque) void,
    };
};

const GlobalState = struct {
    allocator: std.mem.Allocator,
    log: *const Log,
};

var gs: ?GlobalState = null;

pub fn setup(
    allocator: std.mem.Allocator,
    l: *const Log,
) void {
    gs = .{ .allocator = allocator, .log = l };
}

pub const KeyValue = struct {
    key: []const u8,
    value: []const u8,
};

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

    const g = gs orelse return;
    const l = g.log;
    if (!l.vtable.enabled(l.ptr, level, target)) return;

    // var buf: [1024]u8 = undefined;
    // const message = std.fmt.bufPrint(&buf, format, args) catch unreachable;
    const message = std.fmt.allocPrint(g.allocator, format, args) catch unreachable;
    defer g.allocator.free(message);

    const kv_array = kvToArray(KvType, g.allocator, kv);

    l.vtable.log(l.ptr, g.allocator, location, level, target, message, kv_array);

    l.vtable.flush(l.ptr);
}

fn kvToArray(comptime T: type, allocator: std.mem.Allocator, kv: T) []const KeyValue {
    const fields = std.meta.fields(T);
    var result: [fields.len]KeyValue = undefined;

    inline for (fields, 0..) |field, i| {
        const value = @field(kv, field.name);
        result[i] = .{
            .key = field.name,
            .value = std.fmt.allocPrint(allocator, "{any}", .{value}) catch unreachable,
        };
    }

    return &result;
}

pub fn Scoped(comptime target: []const u8) type {
    return struct {
        pub fn l(
            location: SourceLocation,
            level: Level,
            comptime format: []const u8,
            args: anytype,
            kv: anytype,
        ) void {
            log(location, level, target, format, args, kv);
        }

        pub fn fatal(
            location: SourceLocation,
            comptime format: []const u8,
            args: anytype,
            kv: anytype,
        ) void {
            l(location, .fatal, format, args, kv);
        }

        pub fn err(
            location: SourceLocation,
            comptime format: []const u8,
            args: anytype,
            kv: anytype,
        ) void {
            l(location, .err, format, args, kv);
        }

        pub fn warn(
            location: SourceLocation,
            comptime format: []const u8,
            args: anytype,
            kv: anytype,
        ) void {
            l(location, .warn, format, args, kv);
        }

        pub fn info(
            location: SourceLocation,
            comptime format: []const u8,
            args: anytype,
            kv: anytype,
        ) void {
            l(location, .info, format, args, kv);
        }

        pub fn debug(
            location: SourceLocation,
            comptime format: []const u8,
            args: anytype,
            kv: anytype,
        ) void {
            l(location, .debug, format, args, kv);
        }

        pub fn trace(
            location: SourceLocation,
            comptime format: []const u8,
            args: anytype,
            kv: anytype,
        ) void {
            l(location, .trace, format, args, kv);
        }
    };
}

pub const ConsoleLogger = struct {
    bw: *BufferedWriter,

    const BufferedWriter = std.io.BufferedWriter(4096, std.fs.File.Writer);

    pub fn new(allocator: std.mem.Allocator) !ConsoleLogger {
        const stderr = std.io.getStdErr();

        var bw = try allocator.create(BufferedWriter);
        bw.unbuffered_writer = stderr.writer();
        bw.end = 0;
        bw.buf = undefined;

        return .{
            .bw = bw,
        };
    }

    pub fn deinit(self: *ConsoleLogger, allocator: std.mem.Allocator) void {
        allocator.destroy(self.bw);
    }

    pub fn asLog(self: *const ConsoleLogger) Log {
        return .{
            .ptr = @ptrCast(self),
            .vtable = &.{
                .enabled = &enabled,
                .log = &doLog,
                .flush = &flush,
            },
        };
    }

    pub fn enabled(_: *const anyopaque, _: Level, _: []const u8) bool {
        return true;
    }

    pub fn doLog(
        ctx: *const anyopaque,
        allocator: std.mem.Allocator,
        location: SourceLocation,
        level: Level,
        target: []const u8,
        message: []const u8,
        kv: []const KeyValue,
    ) void {
        _ = allocator;

        const self: *const ConsoleLogger = @ptrCast(@alignCast(ctx));
        self.bw.writer().print(
            "[{s} {s}:{}@{s}] {s} - {s}",
            .{
                // now.timestamp,
                target,
                location.file,
                location.line,
                location.fn_name,
                @tagName(level),
                message,
            },
        ) catch unreachable;

        if (kv.len > 0) {
            self.bw.writer().print(
                " -- {any}",
                .{kv},
            ) catch unreachable;
        }

        // self.w.writeByte('\n') catch unreachable;
        self.bw.writer().writeByte('\n') catch unreachable;
        self.bw.flush() catch unreachable;
    }

    pub fn flush(ctx: *const anyopaque) void {
        const self: *const ConsoleLogger = @ptrCast(@alignCast(ctx));
        self.bw.flush() catch unreachable;
    }
};
