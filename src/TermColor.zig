const TermColor = @This();

const std = @import("std");

color: Color = .none,
layer: Layer = .foreground,
style: StyleFlags = .{},
bright: bool = false,

const ESC = "\x1b[";

pub const reset = TermColor{ .color = .reset };

pub const StyleFlags = packed struct(u9) {
    bold: bool = false, // 1
    faint: bool = false, // 2
    italic: bool = false, // 3
    underline: bool = false, // 4
    _slow_blink: bool = false, // 5
    _fast_blink: bool = false, // 6
    reverse: bool = false, // 7
    _conceal: bool = false, // 8
    strikethrough: bool = false, // 9
};

pub fn format(value: @This(), comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
    _ = fmt;
    _ = options;

    if (value.color == .reset) {
        try writer.writeAll(ESC ++ "0m");
        return;
    }

    // iterate over each bit, writing if set
    const style_flags: u9 = @bitCast(value.style);
    for (0..9) |pos|
        if (style_flags & (@as(u64, 1) << @as(u6, @intCast(pos))) != 0)
            try writer.print(ESC ++ "{d}m", .{pos + 1});

    if (value.color == .none)
        return;

    try writer.writeAll(ESC);
    const int = @as(usize, @intFromEnum(value.color)) + 30;
    if (value.layer == .foreground)
        try writer.print("{d}", .{int})
    else
        try writer.print("{d}", .{int + 10});

    if (value.bright)
        try writer.print(";1", .{});

    try writer.print("m", .{});
}

pub const Layer = enum {
    foreground,
    background,
};

pub const Color = enum(u8) {
    //          normal /  bright /  bg  /  bg bright
    black, //   30     /  30;1   /  40  /  40;1
    red, //     31     /  31;1   /  41  /  41;1
    green, //   32     /  32;1   /  42  /  42;1
    yellow, //  33     /  33;1   /  43  /  43;1
    blue, //    34     /  34;1   /  44  /  44;1
    magenta, // 35     /  35;1   /  45  /  45;1
    cyan, //    36     /  36;1   /  46  /  46;1
    white, //   37     /  37;1   /  47  /  47;1
    reset, //   0
    none,
};

pub fn termColorTest() void {
    const red = TermColor{ .color = .red };
    const bright_red = TermColor{ .color = .red, .bright = true };
    const bold_red = TermColor{ .color = .red, .style = .{ .bold = true } };
    const red_bg = TermColor{ .color = .red, .layer = .background };
    const bright_red_bg = TermColor{ .color = .red, .layer = .background, .bright = true };
    const red_bg_bold = TermColor{
        .color = .red,
        .layer = .background,
        .style = .{ .bold = true },
    };
    const bold = TermColor{ .style = .{ .bold = true } };
    const faint = TermColor{ .style = .{ .faint = true } };
    const italic = TermColor{ .style = .{ .italic = true } };
    const underline = TermColor{ .style = .{ .underline = true } };
    const strikethrough = TermColor{ .style = .{ .strikethrough = true } };
    const all = TermColor{ .style = .{
        .bold = true,
        .faint = true,
        .italic = true,
        .underline = true,
        .strikethrough = true,
    } };

    std.debug.print("{}red{} not red\n", .{ red, reset });
    std.debug.print("{}bright red{} not bright red\n", .{ bright_red, reset });
    std.debug.print("{}bold red{} not bold red\n", .{ bold_red, reset });
    std.debug.print("{}red bg{} not red bg\n", .{ red_bg, reset });
    std.debug.print("{}bright red bg{} not bright red bg\n", .{ bright_red_bg, reset });
    std.debug.print("{}red bg bold{} not red bg bold\n", .{ red_bg_bold, reset });
    std.debug.print("{}bold{} bold\n", .{ bold, reset });
    std.debug.print("{}faint{} not faint\n", .{ faint, reset });
    std.debug.print("{}italic{} not italic\n", .{ italic, reset });
    std.debug.print("{}underline{} not underline\n", .{ underline, reset });
    std.debug.print("{}strikethrough{} not strikethrough\n", .{ strikethrough, reset });
    std.debug.print("{}all{} not all\n", .{ all, reset });
}
