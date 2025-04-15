const std = @import("std");
const log = std.log.scoped(.xdp);
const Allocator = std.mem.Allocator;

const gio = @import("gio.zig");

// @TODO: listen to changes in these settings
// @TODO: get appearance (theme)
pub const XdpSettings = struct {
    proxy: *gio.DBusProxy,

    pub fn init() !XdpSettings {
        var gio_err: ?*gio.Error = null;
        const xdp_settings_proxy = gio.DBusProxy.newForBusSync(
            .session,
            @enumFromInt(gio.DBusProxyFlags.none),
            null,
            "org.freedesktop.portal.Desktop",
            "/org/freedesktop/portal/desktop",
            "org.freedesktop.portal.Settings",
            null,
            &gio_err,
        ) orelse {
            const err = gio_err.?;
            log.err(
                "Failed to create proxy for xdg desktop settings portal: " ++
                    "domain: {d}, code: {d} -- {s}\n",
                .{ err.domain, err.code, err.message },
            );
            gio.Error.clear(&gio_err);
            return error.gio;
        };

        return .{
            .proxy = xdp_settings_proxy,
        };
    }

    pub fn deinit(xdp: XdpSettings) void {
        xdp.proxy.unref();
    }

    pub fn getCursorTheme(xdp: XdpSettings, gpa: Allocator) ![:0]u8 {
        var gio_err: ?*gio.Error = null;
        const read_cursor_theme = xdp.proxy.callSync(
            "Read",
            gio.Variant.new("(ss)", .{
                "org.gnome.desktop.interface",
                "cursor-theme",
            }),
            @enumFromInt(gio.DBusCallFlags.none),
            -1,
            null,
            &gio_err,
        ) orelse {
            const err = gio_err.?;
            log.err(
                "Read call to xdg desktop settings portal failed: " ++
                    "domain: {d}, code: {d} -- {s}",
                .{ err.domain, err.code, err.message },
            );
            gio.Error.clear(&gio_err);
            return error.gio;
        };
        defer read_cursor_theme.unref();

        const inner1 = read_cursor_theme.getChildValue(0).?;
        defer inner1.unref();
        const inner2 = inner1.getVariant().?;
        defer inner2.unref();
        const inner3 = inner2.getVariant().?;
        defer inner3.unref();

        const str_c = inner3.getString().?;
        return try gpa.dupeZ(u8, str_c);
    }

    pub fn getCursorSize(xdp: XdpSettings) !i32 {
        var gio_err: ?*gio.Error = null;
        const read_cursor_size = xdp.proxy.callSync(
            "Read",
            gio.Variant.new("(ss)", .{
                "org.gnome.desktop.interface",
                "cursor-size",
            }),
            @enumFromInt(gio.DBusCallFlags.none),
            -1,
            null,
            &gio_err,
        ) orelse {
            const err = gio_err.?;
            log.err(
                "Read call to xdg desktop settings portal failed: " ++
                    "domain: {d}, code: {d} -- {s}",
                .{ err.domain, err.code, err.message },
            );
            gio.Error.clear(&gio_err);
            return error.gio;
        };
        defer read_cursor_size.unref();

        const inner1 = read_cursor_size.getChildValue(0).?;
        defer inner1.unref();
        const inner2 = inner1.getVariant().?;
        defer inner2.unref();
        const inner3 = inner2.getVariant().?;
        defer inner3.unref();

        return inner3.getInt32();
    }
};
