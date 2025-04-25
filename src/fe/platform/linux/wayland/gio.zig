const std = @import("std");

pub const c = @cImport({
    @cInclude("gio/gio.h");
});

pub usingnamespace c;

pub const Error = extern struct {
    domain: u32,
    code: i32,
    message: [*:0]u8,

    pub fn clear(err: ?*?*Error) void {
        c.g_clear_error(@ptrCast(err));
    }
};

pub const DBusProxy = extern struct {
    parent_instance: c.GObject,
    priv: ?*c.GDBusProxyPrivate,

    pub fn newForBusSync(
        ty: BusType,
        flags: DBusProxyFlags,
        info: ?*c.GDBusInterfaceInfo,
        name: [*:0]const u8,
        object_path: [*:0]const u8,
        interface_name: [*:0]const u8,
        cancellable: ?*c.GCancellable,
        err: ?*?*Error,
    ) ?*DBusProxy {
        return @ptrCast(c.g_dbus_proxy_new_for_bus_sync(
            @intFromEnum(ty),
            @intFromEnum(flags),
            info,
            name,
            object_path,
            interface_name,
            cancellable,
            @ptrCast(err),
        ));
    }

    pub fn unref(proxy: *DBusProxy) void {
        return c.g_object_unref(@ptrCast(proxy));
    }

    pub fn callSync(
        proxy: *DBusProxy,
        method_name: [*:0]const u8,
        parameters: ?*Variant,
        flags: DBusCallFlags,
        timeout_msec: i32,
        cancellable: ?*c.GCancellable,
        err: ?*?*Error,
    ) ?*Variant {
        return @ptrCast(c.g_dbus_proxy_call_sync(
            @ptrCast(proxy),
            method_name,
            @ptrCast(parameters),
            @intFromEnum(flags),
            timeout_msec,
            cancellable,
            @ptrCast(err),
        ));
    }
};

pub const BusType = enum(c_int) {
    starter = c.G_BUS_TYPE_STARTER,
    none = c.G_BUS_TYPE_NONE,
    system = c.G_BUS_TYPE_SYSTEM,
    session = c.G_BUS_TYPE_SESSION,
    _,
};

pub const DBusProxyFlags = enum(c_uint) {
    _,

    pub const none = c.G_DBUS_PROXY_FLAGS_NONE;
    pub const do_not_load_properties = c.G_DBUS_PROXY_FLAGS_DO_NOT_LOAD_PROPERTIES;
    pub const do_not_connect_signals = c.G_DBUS_PROXY_FLAGS_DO_NOT_CONNECT_SIGNALS;
    pub const do_not_auto_start = c.G_DBUS_PROXY_FLAGS_DO_NOT_AUTO_START;
    pub const get_invalidated_properties = c.G_DBUS_PROXY_FLAGS_GET_INVALIDATED_PROPERTIES;
    pub const do_not_auto_start_at_construction = c.G_DBUS_PROXY_FLAGS_DO_NOT_AUTO_START_AT_CONSTRUCTION;
    pub const no_match_rule = c.G_DBUS_PROXY_FLAGS_NO_MATCH_RULE;
};

pub const DBusCallFlags = enum(c_uint) {
    _,

    pub const none = c.G_DBUS_CALL_FLAGS_NONE;
    pub const no_auto_start = c.G_DBUS_CALL_FLAGS_NO_AUTO_START;
    pub const allow_interactive_authorization = c.G_DBUS_CALL_FLAGS_ALLOW_INTERACTIVE_AUTHORIZATION;
};

pub const Variant = opaque {
    /// The type contract between format_string and args is not checked.
    ///
    /// Currently only supports strings
    pub fn new(
        comptime format_string: [:0]const u8,
        args: anytype,
    ) *Variant {
        const CArgs = comptime make_type: {
            const ArgsType = @TypeOf(args);
            const args_info = @typeInfo(ArgsType);
            if (args_info != .@"struct") {
                @compileError("expected tuple or struct argument, found " ++ @typeName(ArgsType));
            }
            var info = args_info.@"struct";
            var c_string_fields: [info.fields.len]std.builtin.Type.StructField = undefined;

            // @TODO: determine type of field based on format_string

            for (&c_string_fields, info.fields) |*c_string_field, nvp_field| {
                c_string_field.* = .{
                    .name = nvp_field.name,
                    .type = [*:0]const u8,
                    .default_value_ptr = null,
                    .is_comptime = false,
                    .alignment = @alignOf([*:0]const u8),
                };
            }
            info.fields = &c_string_fields;
            break :make_type @Type(.{ .@"struct" = info });
        };

        return @ptrCast(@call(
            .auto,
            c.g_variant_new,
            .{format_string} ++ @as(CArgs, args),
        ));
    }

    pub fn unref(variant: *Variant) void {
        return c.g_variant_unref(@ptrCast(variant));
    }

    pub fn getString(variant: *Variant) ?[:0]const u8 {
        var len: usize = undefined;
        const ptr = c.g_variant_get_string(@ptrCast(variant), &len) orelse return null;
        return @ptrCast(ptr[0..len]);
    }

    pub fn getChildValue(variant: *Variant, index: usize) ?*Variant {
        return @ptrCast(c.g_variant_get_child_value(@ptrCast(variant), index));
    }

    pub fn getVariant(variant: *Variant) ?*Variant {
        return @ptrCast(c.g_variant_get_variant(@ptrCast(variant)));
    }

    pub fn getInt32(variant: *Variant) i32 {
        return c.g_variant_get_int32(@ptrCast(variant));
    }
};
