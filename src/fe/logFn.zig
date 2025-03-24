const std = @import("std");
const TermColor = @import("TermColor.zig");

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
    const now = std.time.milliTimestamp();

    const level_str, const level_color = switch (level) {
        .err => .{ "ERROR", TermColor{ .color = .red, .layer = .background } },
        .warn => .{ "WARNING", TermColor{ .color = .yellow, .layer = .background } },
        .info => .{ "INFO", TermColor{ .color = .blue, .layer = .background } },
        .debug => .{ "DEBUG", TermColor{ .color = .magenta, .layer = .background } },
    };

    const faint = TermColor{ .style = .{ .faint = true } };
    const reset = TermColor.reset;

    const stderr = std.io.getStdErr().writer();
    var bw = std.io.bufferedWriter(stderr);
    const writer = bw.writer();

    std.debug.lockStdErr();
    defer std.debug.unlockStdErr();
    nosuspend {
        writer.print(
            "{[faint]}[{[now]d}{[reset]}{[scope]s}{[faint]}]{[reset]} {[level_color]} {[level]s} {[reset]} ",
            .{
                .faint = faint,
                .reset = reset,
                .now = now,
                .scope = scope,
                .level = level_str,
                .level_color = level_color,
            },
        ) catch return;

        writer.print("{s}" ++ "\n", .{message}) catch return;

        bw.flush() catch return;
    }
}
