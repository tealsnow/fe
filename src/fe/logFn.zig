const builtin = @import("builtin");
const std = @import("std");
const TermColor = @import("TermColor.zig");

const tracy = @import("tracy");

const FileWriter = std.fs.File.Writer;
const BufferedFileWriter = std.io.BufferedWriter(4096, FileWriter);

const State = struct {
    file: std.fs.File,
};

var state: State = undefined;

pub fn init(log_file_name: []const u8) !void {
    const cwd = std.fs.cwd();
    const file = try cwd.createFile(log_file_name, .{});

    state = .{ .file = file };
}

pub fn deinit() void {
    state.file.close();
}

pub fn logFn(
    comptime message_level: std.log.Level,
    comptime scope: @TypeOf(.enum_literal),
    comptime format: []const u8,
    args: anytype,
) void {
    const scope_str = if (scope == .default) " fe" else " " ++ @tagName(scope);

    var buffer: [1024 * 4]u8 = undefined;
    const message = std.fmt.bufPrint(&buffer, format, args) catch return;

    logFnRuntime(message_level, scope_str, message);
}

pub fn logFnRuntime(
    level: std.log.Level,
    scope: []const u8,
    message: []const u8,
) void {
    const now_ms = std.time.milliTimestamp();
    const now = DateTime.fromMillis(now_ms);
    var now_str_buf: [30]u8 = @splat(0);
    const now_str = now.toRfc3339(&now_str_buf);

    const level_str, const level_color = switch (level) {
        .err => //
        .{ "ERROR", TermColor{ .color = .red, .layer = .background } },
        .warn => //
        .{ "WARNING", TermColor{ .color = .yellow, .layer = .background } },
        .info => //
        .{ "INFO", TermColor{ .color = .blue, .layer = .background } },
        .debug => //
        .{ "DEBUG", TermColor{ .color = .magenta, .layer = .background } },
    };

    const faint = TermColor{ .style = .{ .faint = true } };
    const reset = TermColor.reset;

    const tracy_fmt =
        "[{[scope]s}] {[level]s} {[message]s}";
    const tracy_args = .{
        .scope = scope,
        .level = level_str,
        .message = message,
    };
    const stderr_fmt =
        "{[faint]}[{[now]s}{[reset]}{[scope]s}{[faint]}]{[reset]} " ++
        "{[level_color]} {[level]s} {[reset]} {[message]s}";
    const stderr_args = .{
        .faint = faint,
        .reset = reset,
        .now = now_str,
        .scope = scope,
        .level = level_str,
        .level_color = level_color,
        .message = message,
    };
    const file_fmt =
        "[{[now]s}{[scope]s}] {[level]s}  {[message]s}";
    const file_args = .{
        .now = now_str,
        .scope = scope,
        .level = level_str,
        .message = message,
    };

    tracy.message(tracy_fmt, tracy_args);

    stderr: {
        const stderr = std.io.getStdErr().writer();
        var stderr_bw = std.io.bufferedWriter(stderr);
        const stderr_writer = stderr_bw.writer();

        std.debug.lockStdErr();
        defer std.debug.unlockStdErr();

        stderr_writer.print(stderr_fmt ++ "\n", stderr_args) catch {
            std.debug.print("log: failed to write to stderr buffered writer\n", .{});
            break :stderr;
        };
        stderr_bw.flush() catch {
            std.debug.print("log: failed to flush to stderr\n", .{});
            break :stderr;
        };
    }

    file: {
        const file_underlying_writer = state.file.writer();
        var file_bw = std.io.bufferedWriter(file_underlying_writer);
        const file_writer = file_bw.writer();

        file_writer.print(file_fmt ++ "\n", file_args) catch {
            std.debug.print("log: failed to write to file buffered writer\n", .{});
            break :file;
        };
        file_bw.flush() catch {
            std.debug.print("log: failed to flush to file\n", .{});
            break :file;
        };
    }
}

pub fn writeStackTrace(start_addr: ?usize) void {
    if (builtin.strip_debug_info) {
        logFn(.err, ._, "Unable to dump stack trace: debug info stripped", .{});
        return;
    }

    const debug_info = std.debug.getSelfDebugInfo() catch |err| {
        logFn(
            .err,
            ._,
            "Unable to dump stack trace: Unable to open debug info: {s}\n",
            .{@errorName(err)},
        );
        return;
    };

    const stderr = std.io.getStdErr();
    const stderr_writer = stderr.writer();

    std.debug.writeCurrentStackTrace(
        stderr_writer,
        debug_info,
        std.io.tty.detectConfig(stderr),
        start_addr,
    ) catch |err| {
        logFn(
            .err,
            ._,
            "Unable to dump stack trace: {s}\n",
            .{@errorName(err)},
        );
        return;
    };

    const file_writer = state.file.writer();
    std.debug.writeCurrentStackTrace(
        file_writer,
        debug_info,
        .no_color,
        start_addr,
    ) catch |err| {
        logFn(
            .err,
            ._,
            "Unable to dump stack trace to file: {s}\n",
            .{@errorName(err)},
        );
        return;
    };
}

/// Represents a date and time with timezone offset
pub const DateTime = struct {
    year: u16,
    month: u8,
    day: u8,
    hour: u8,
    minute: u8,
    second: u8,
    millisecond: u16,
    offset: i16,

    /// Creates a DateTime from Unix timestamp in milliseconds
    /// Note: This function assumes UTC (offset 0)
    // largely constructed from https://www.aolium.com/karlseguin/cf03dee6-90e1-85ac-8442-cf9e6c11602a
    pub fn fromMillis(ms: i64) DateTime {
        const ts: u64 = @intCast(@divTrunc(ms, 1000));
        const SECONDS_PER_DAY = std.time.s_per_day;
        const DAYS_PER_YEAR = 365;
        const DAYS_IN_4YEARS = 1461;
        const DAYS_IN_100YEARS = 36524;
        const DAYS_IN_400YEARS = 146097;
        const DAYS_BEFORE_EPOCH = 719468;

        const seconds_since_midnight: u64 = @rem(ts, SECONDS_PER_DAY);
        var day_n: u64 = DAYS_BEFORE_EPOCH + ts / SECONDS_PER_DAY;
        var temp: u64 = 0;

        temp = 4 * (day_n + DAYS_IN_100YEARS + 1) / DAYS_IN_400YEARS - 1;
        var year: u16 = @intCast(100 * temp);
        day_n -= DAYS_IN_100YEARS * temp + temp / 4;

        temp = 4 * (day_n + DAYS_PER_YEAR + 1) / DAYS_IN_4YEARS - 1;
        year += @intCast(temp);
        day_n -= DAYS_PER_YEAR * temp + temp / 4;

        var month: u8 = @intCast((5 * day_n + 2) / 153);
        const day: u8 =
            @intCast(day_n - (@as(u64, @intCast(month)) * 153 + 2) / 5 + 1);

        month += 3;
        if (month > 12) {
            month -= 12;
            year += 1;
        }

        return DateTime{
            .year = year,
            .month = month,
            .day = day,
            .hour = @intCast(seconds_since_midnight / 3600),
            .minute = @intCast(seconds_since_midnight % 3600 / 60),
            .second = @intCast(seconds_since_midnight % 60),
            .millisecond = @intCast(@rem(ms, 1000)),
            .offset = 0,
        };
    }

    fn getOffsetSign(offset: i16) u8 {
        return if (offset < 0) '-' else '+';
    }

    /// Converts the DateTime to an RFC 3339 formatted string
    pub fn toRfc3339(self: DateTime, buffer: *[30]u8) []const u8 {
        var fbs = std.io.fixedBufferStream(buffer);
        var writer = fbs.writer();

        // Write the date and time components
        writer.print(
            "{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}.{d:0>3}",
            .{
                self.year,        self.month,  self.day,
                self.hour,        self.minute, self.second,
                self.millisecond,
            },
        ) catch unreachable;

        // Write the timezone offset
        if (self.offset == 0) {
            _ = writer.write("Z") catch unreachable;
        } else {
            const abs_offset = @abs(self.offset);
            const offset_hours = @divFloor(abs_offset, 60);
            const offset_minutes = @mod(abs_offset, 60);
            writer.print("{c}{d:0>2}:{d:0>2}", .{
                getOffsetSign(self.offset),
                offset_hours,
                offset_minutes,
            }) catch unreachable;
        }

        return buffer[0..fbs.pos];
    }
};
