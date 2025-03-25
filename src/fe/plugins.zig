const std = @import("std");
const assert = std.debug.assert;

const wasm = @import("wasm.zig");
const PluginSchema = @import("plugin-schema").PluginSchema;

const logFn = @import("logFn.zig");

const log = std.log.scoped(.plugins);

pub fn printLastWasmError() void {
    if (wasm.getLastError()) |e| {
        defer e.deinit();
        var message = e.message();
        defer message.deinit();
        std.log.err("[WASM]: {s}", .{message.slice()});
    }
}

pub fn printTrap(trap: *wasm.Trap) void {
    defer trap.deinit();
    var msg = trap.message();
    defer msg.deinit();
    log.err("trap: {s}", .{msg.slice()});
}

pub fn sliceWasmMemory(data: [*]u8, ptr: i32, len: i32) []u8 {
    const ptr_usize = @as(usize, @intCast(ptr));
    const len_usize = @as(usize, @intCast(len));
    return data[ptr_usize..(ptr_usize + len_usize)];
}

pub const WasmGuestAllocator = struct {
    const Self = @This();
    const Allocator = std.mem.Allocator;
    const Alignment = std.mem.Alignment;
    const alloc_log = std.log.scoped(.WasmGuestAllocator);

    context: *wasm.Context,
    guest_mem: [*]u8,
    alloc_func: wasm.Func,
    resize_func: wasm.Func,
    remap_func: wasm.Func,
    free_func: wasm.Func,

    pub fn init(context: *wasm.Context, instance: *wasm.Instance) !Self {
        const guest_mem = instance.getMemoryData(context) orelse return error.noMemory;
        const alloc_func = instance.exportGetFunc(context, "Allocator_alloc") orelse return error.exportGet;
        const resize_func = instance.exportGetFunc(context, "Allocator_resize") orelse return error.exportGet;
        const remap_func = instance.exportGetFunc(context, "Allocator_remap") orelse return error.exportGet;
        const free_func = instance.exportGetFunc(context, "Allocator_free") orelse return error.exportGet;

        return .{
            .context = context,
            .guest_mem = guest_mem,
            .alloc_func = alloc_func,
            .resize_func = resize_func,
            .remap_func = remap_func,
            .free_func = free_func,
        };
    }

    pub fn allocator(self: *Self) Allocator {
        return .{
            .ptr = self,
            .vtable = &.{
                .alloc = alloc,
                .resize = resize,
                .remap = remap,
                .free = free,
            },
        };
    }

    pub fn toWasmPtr(self: *Self, comptime T: type, ptr: *const T) i32 {
        return @intCast(@intFromPtr(ptr) - @intFromPtr(self.guest_mem));
    }

    pub fn toWasmSlice(self: *Self, comptime T: type, slice: []const T) struct { i32, i32 } {
        const ptr = self.toWasmPtr(T, @ptrCast(slice.ptr));
        const len: i32 = @intCast(slice.len);
        return .{ ptr, len };
    }

    fn alloc(ctx: *anyopaque, len: usize, alignment: Alignment, ret_addr: usize) ?[*]u8 {
        _ = ret_addr;

        alloc_log.debug("alloc(len: {d}, alignment: {s})", .{ len, @tagName(alignment) });

        const self: *Self = @ptrCast(@alignCast(ctx));

        const len_i32: i32 = @intCast(len);
        const alignment_i32: i32 = @intCast(alignment.toByteUnits());

        const args = [_]wasm.Val{ .newI32(len_i32), .newI32(alignment_i32) };
        var result: [1]wasm.Val = undefined;

        const trap = self.alloc_func.call(self.context, &args, &result) catch {
            printLastWasmError();
            @panic("WasmGuestAllocator: wasm error");
        };
        if (trap) |t| {
            printTrap(t);
            @panic("WasmGuestAllocator: wasm trapped");
        }

        assert(result[0].kind == .i32);
        const guest_ptr = result[0].of.i32;
        if (guest_ptr == 0) return null;

        const guest_ptr_usize: usize = @intCast(guest_ptr);
        const host_ptr = &self.guest_mem[guest_ptr_usize];
        const ret: [*]u8 = @ptrCast(host_ptr);

        alloc_log.debug(" -- return: {*}", .{ret});

        return ret;
    }

    fn resize(ctx: *anyopaque, memory: []u8, alignment: Alignment, new_len: usize, ret_addr: usize) bool {
        _ = ret_addr;

        alloc_log.debug("resize(memory: {*}, alignment: {s}, new_len: {d})", .{ memory, @tagName(alignment), new_len });

        const self: *Self = @ptrCast(@alignCast(ctx));

        const memory_ptr_i32, const memory_len_i32 = self.toWasmSlice(u8, memory);
        const alignment_i32: i32 = @intCast(alignment.toByteUnits());
        const new_len_i32: i32 = @intCast(new_len);

        const args = [_]wasm.Val{ .newI32(memory_ptr_i32), .newI32(memory_len_i32), .newI32(alignment_i32), .newI32(new_len_i32) };
        var result: [1]wasm.Val = undefined;

        const trap = self.resize_func.call(self.context, &args, &result) catch {
            printLastWasmError();
            @panic("WasmGuestAllocator: wasm error");
        };
        if (trap) |t| {
            printTrap(t);
            @panic("WasmGuestAllocator: wasm trapped");
        }

        assert(result[0].kind == .i32);
        const success = result[0].of.i32;
        const ret = success == 0;

        alloc_log.debug(" -- return: {}", .{ret});

        return ret;
    }

    fn remap(ctx: *anyopaque, memory: []u8, alignment: Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
        _ = ret_addr;

        alloc_log.debug("remap(memory: {*}, alignment: {s}, new_len: {d})", .{ memory, @tagName(alignment), new_len });

        const self: *Self = @ptrCast(@alignCast(ctx));

        const memory_ptr_i32, const memory_len_i32 = self.toWasmSlice(u8, memory);
        const alignment_i32: i32 = @intCast(alignment.toByteUnits());
        const new_len_i32: i32 = @intCast(new_len);

        const args = [_]wasm.Val{ .newI32(memory_ptr_i32), .newI32(memory_len_i32), .newI32(alignment_i32), .newI32(new_len_i32) };
        var result: [1]wasm.Val = undefined;

        const trap = self.remap_func.call(self.context, &args, &result) catch {
            printLastWasmError();
            @panic("WasmGuestAllocator: wasm error");
        };
        if (trap) |t| {
            printTrap(t);
            @panic("WasmGuestAllocator: wasm trapped");
        }

        assert(result[0].kind == .i32);
        const guest_ptr = result[0].of.i32;
        if (guest_ptr == 0) return null;

        const guest_ptr_usize: usize = @intCast(guest_ptr);
        const host_ptr = &self.guest_mem[guest_ptr_usize];
        const ret: [*]u8 = @ptrCast(host_ptr);

        alloc_log.debug(" -- return: {*}", .{ret});

        return ret;
    }

    fn free(ctx: *anyopaque, memory: []u8, alignment: Alignment, ret_addr: usize) void {
        _ = ret_addr;

        alloc_log.debug("free(memory: {*}, alignment: {s})", .{ memory, @tagName(alignment) });

        const self: *Self = @ptrCast(@alignCast(ctx));

        const memory_ptr_i32, const memory_len_i32 = self.toWasmSlice(u8, memory);
        const alignment_i32: i32 = @intCast(alignment.toByteUnits());

        const args = [_]wasm.Val{ .newI32(memory_ptr_i32), .newI32(memory_len_i32), .newI32(alignment_i32) };

        const trap = self.free_func.call(self.context, &args, &.{}) catch {
            printLastWasmError();
            @panic("WasmGuestAllocator: wasm error");
        };
        if (trap) |t| {
            printTrap(t);
            @panic("WasmGuestAllocator: wasm trapped");
        }
    }
};

pub const Plugin = struct {
    schema: PluginSchema,
    context: *wasm.Context,
    linker: *wasm.Linker,
    module: *wasm.Module,
    instance: wasm.Instance,
    wasm_allocator: WasmGuestAllocator,

    pub fn init(
        allocator: std.mem.Allocator,
        engine: *wasm.Engine,
        context: *wasm.Context,
        plugin_dir: std.fs.Dir,
    ) !Plugin {
        const schema = try loadSchema(allocator, plugin_dir);
        const module = try loadModule(allocator, plugin_dir, schema.id, engine);
        const linker = try setupCallbacks(engine, context, schema.id, module);

        var instance = switch (try linker.instantiate(context, module)) {
            .value => |inst| inst,
            .trap => |trap| {
                printTrap(trap);
                return error.trap;
            },
        };

        const wasm_allocator = try WasmGuestAllocator.init(context, &instance);
        return .{
            .schema = schema,
            .context = context,
            .linker = linker,
            .module = module,
            .instance = instance,
            .wasm_allocator = wasm_allocator,
        };
    }

    pub fn deinit(plugin: *Plugin, allocator: std.mem.Allocator) void {
        defer plugin.* = undefined;
        defer plugin.linker.deinit();
        defer plugin.module.deinit();
        defer std.zon.parse.free(allocator, plugin.schema);
    }

    fn loadSchema(
        allocator: std.mem.Allocator,
        plugin_dir: std.fs.Dir,
    ) !PluginSchema {
        log.info("loading schema", .{});

        const file = try plugin_dir.openFile("plugin.zon", .{});
        defer file.close();

        const size = try file.getEndPos();

        const buffer: [:0]u8 = try allocator.allocSentinel(u8, size, 0);
        defer allocator.free(buffer);
        const read = try file.readAll(buffer);
        assert(read == buffer.len);

        var status = std.zon.parse.Status{};
        defer status.deinit(allocator);
        const schema = std.zon.parse.fromSlice(
            PluginSchema,
            allocator,
            buffer,
            &status,
            .{},
        ) catch |err| {
            if (err == error.ParseZon)
                log.err("Failed to parse plugin schema: \n{}", .{status});
            return err;
        };

        return schema;
    }

    fn loadModule(
        allocator: std.mem.Allocator,
        plugin_dir: std.fs.Dir,
        id: []const u8,
        engine: *wasm.Engine,
    ) !*wasm.Module {
        log.info("loading wasm", .{});
        const file_path = try std.fmt.allocPrint(allocator, "{s}.wasm", .{id});
        defer allocator.free(file_path);

        const file = try plugin_dir.openFile(file_path, .{});
        defer file.close();

        const size = try file.getEndPos();
        const bytes = try file.readToEndAlloc(allocator, size);
        defer allocator.free(bytes);

        log.info("init module", .{});
        const module = try wasm.Module.init(engine, bytes);
        return module;
    }

    fn defineCallback(
        linker: *wasm.Linker,
        module: []const u8,
        name: []const u8,
        functype: *wasm.Functype,
        callback: wasm.FuncCallback,
    ) !void {
        defer functype.deinit();
        log.debug("defining callback '{s}::{s}'", .{ module, name });
        try linker.defineFunc(module, name, functype, callback, null, null);
    }

    fn setupCallbacks(
        engine: *wasm.Engine,
        context: *wasm.Context,
        module_name: []const u8,
        module: *wasm.Module,
    ) !*wasm.Linker {
        log.info("init linker", .{});
        const linker = wasm.Linker.init(engine);
        try linker.defineWasi();

        log.info("defining callbacks", .{});
        try defineCallback(linker, "fe", "callback", wasm.Functype.init_0_0(), wasmCallback);
        try defineCallback(linker, "fe", "FooType_inc", wasm.Functype.init_1_0(.newI64()), FooType_inc_wasm);
        try defineCallback(linker, "fe", "takeString", .init_2_0(.newI32(), .newI32()), takeString);
        {
            var params = wasm.ValtypeVec.init(&.{ .newI32(), .newI32(), .newI32(), .newI32(), .newI32() });
            var results = wasm.ValtypeVec.initEmpty();
            const functype = wasm.Functype.init(&params, &results);
            try defineCallback(linker, "fe", "hostLogFn", functype, logFnCallback);
        }

        log.info("linking module", .{});
        try linker.linkModule(context, module_name, module);

        return linker;
    }

    const NamedFunc = struct {
        context: *wasm.Context,
        func: wasm.Func,
        name: []const u8,

        pub fn call(func: NamedFunc, args: []const wasm.Val, results: []wasm.Val) !void {
            log.debug("calling function '{s}'", .{func.name});
            const trap = try func.func.call(func.context, args, results);
            if (trap) |t| {
                printTrap(t);
                return error.traps;
            }
        }
    };

    fn getFunc(plugin: *Plugin, name: []const u8) !NamedFunc {
        log.debug("getting function '{s}'", .{name});
        const func = plugin.instance.exportGetFunc(plugin.context, name) orelse return error.exportGet;
        return .{ .context = plugin.context, .func = func, .name = name };
    }
};

pub const PluginHost = struct {
    engine: *wasm.Engine,
    store: *wasm.Store,
    context: *wasm.Context,
    plugins: []Plugin,

    pub fn init(gpa: std.mem.Allocator) !PluginHost {
        log.info("setup engine, store and context", .{});
        const engine = try wasm.Engine.init();
        const store = try wasm.Store.init(engine, null, null);
        const context = store.context();

        log.info("setup wasi", .{});
        const wasi_config = try wasm.WasiConfig.init();
        // defer wasi_config.deinit(); // panics
        // wasi_config.inheritArgv();
        wasi_config.inheritEnv();
        // wasi_config.inheritStdin();
        wasi_config.inheritStdout();
        wasi_config.inheritStderr();

        log.info("set wasi to context", .{});
        try context.setWasi(wasi_config);

        var plugins = std.ArrayList(Plugin).init(gpa);
        log.info("finding plugins", .{});

        const cwd = std.fs.cwd();
        var plugins_dir = try cwd.openDir("zig-out/plugins", .{ .access_sub_paths = true, .iterate = true });
        defer plugins_dir.close();
        var plugin_dir_iter = plugins_dir.iterate();
        while (try plugin_dir_iter.next()) |entry| {
            if (entry.kind != .directory) continue;

            var plugin_dir = try plugins_dir.openDir(entry.name, .{});
            defer plugin_dir.close();

            log.info("setting up plugin in dir: '{s}'", .{entry.name});
            const plugin = try Plugin.init(gpa, engine, context, plugin_dir);
            log.info("finshed setting up plugin in dir: '{s}'", .{entry.name});

            try plugins.append(plugin);
        }
        plugins.shrinkAndFree(plugins.items.len);

        return .{
            .engine = engine,
            .store = store,
            .context = context,
            .plugins = plugins.items,
        };
    }

    pub fn deinit(host: PluginHost, gpa: std.mem.Allocator) void {
        defer host.engine.deinit();
        defer host.store.deinit();
        defer gpa.free(host.plugins);
        defer for (host.plugins) |*plugin| {
            plugin.deinit(gpa);
        };
    }
};

fn logFnCallback(
    env: ?*anyopaque,
    caller: *wasm.Caller,
    args: [*]const wasm.Val,
    nargs: usize,
    results: [*]wasm.Val,
    nresults: usize,
) callconv(.c) ?*wasm.Trap {
    _ = env;
    _ = results;
    _ = nresults;

    assert(nargs == 5);
    for (args[0..5]) |arg| assert(arg.kind == .i32);

    const level_int = args[0].of.i32;
    const scope_ptr = args[1].of.i32;
    const scope_len = args[2].of.i32;
    const message_ptr = args[3].of.i32;
    const message_len = args[4].of.i32;

    const level: std.log.Level = @enumFromInt(level_int);

    const data = caller.getMemoryData() orelse @panic("wasm: no memory export");
    const scope = sliceWasmMemory(data, scope_ptr, scope_len);
    const message = sliceWasmMemory(data, message_ptr, message_len);

    logFn.logFnRuntime(level, scope, message);

    return null;
}

// =-=-=

pub fn doTest(plugin: *Plugin) !void {
    log.info("getting guest functions", .{});

    const func_hello_world = try plugin.getFunc("helloWorld");
    const func_add = try plugin.getFunc("add");
    const func_addi64 = try plugin.getFunc("addi64");
    const func_run_callback = try plugin.getFunc("runCallback");
    const func_take_foo_type = try plugin.getFunc("takeFooType");
    const func_give_string = try plugin.getFunc("giveString");
    const func_use_string = try plugin.getFunc("useString");

    log.info("calling guest functions", .{});

    try func_hello_world.call(&.{}, &.{});

    { // add
        const args = [_]wasm.Val{ .newI32(42), .newI32(420) };
        var results: [1]wasm.Val = undefined;
        try func_add.call(&args, &results);
        assert(results[0].kind == .i32);
        std.debug.print("add: {d} + {d} = {d}\n", .{ args[0].of.i32, args[1].of.i32, results[0].of.i32 });
    }

    { // addi64
        const args = [_]wasm.Val{ .newI64(42), .newI64(420) };
        var results: [1]wasm.Val = undefined;
        try func_addi64.call(&args, &results);
        assert(results[0].kind == .i64);
        std.debug.print("addi64: {d} + {d} = {d}\n", .{ args[0].of.i64, args[1].of.i64, results[0].of.i64 });
    }

    try func_run_callback.call(&.{}, &.{});

    { // takeFooType
        const foo = &FooType{ .string = "foo bar", .int = 32 };
        std.debug.print("foo int (before): {d}\n", .{foo.int});

        const args = [_]wasm.Val{.newI64(@intCast(@intFromPtr(foo)))};
        try func_take_foo_type.call(&args, &.{});

        std.debug.print("foo int (after): {d}\n", .{foo.int});
    }

    try func_give_string.call(&.{}, &.{});

    { // useString
        const alloc = plugin.wasm_allocator.allocator();

        const string = try std.fmt.allocPrint(alloc, "Hello, {s}!", .{"allocator"});
        defer alloc.free(string);

        const string_ptr, const string_len = plugin.wasm_allocator.toWasmSlice(u8, string);
        const args = [_]wasm.Val{ .newI32(@intCast(string_ptr)), .newI32(string_len) };
        try func_use_string.call(&args, &.{});
    }
}

// =-=-=

pub const FooType = struct {
    string: []const u8,
    int: i32,

    fn inc(self: *FooType) void {
        self.int += 1;
    }
};

fn FooType_inc_wasm(
    data: ?*anyopaque,
    caller: *wasm.Caller,
    args: [*]const wasm.Val,
    nargs: usize,
    results: [*]wasm.Val,
    nresults: usize,
) callconv(.c) ?*wasm.Trap {
    _ = data;
    _ = caller;
    _ = results;
    _ = nresults;

    assert(nargs == 1);
    const foo = args[0];
    assert(foo.kind == .i64);

    const ptr: *FooType = @ptrFromInt(@as(usize, @intCast(foo.of.i64)));
    ptr.inc();

    return null;
}

fn wasmCallback(
    data: ?*anyopaque,
    caller: *wasm.Caller,
    args: [*]const wasm.Val,
    nargs: usize,
    results: [*]wasm.Val,
    nresults: usize,
) callconv(.c) ?*wasm.Trap {
    _ = data;
    _ = caller;
    _ = args;
    _ = nargs;
    _ = results;
    _ = nresults;

    std.debug.print("zig callback!\n", .{});

    return null;
}

fn takeString(
    env: ?*anyopaque,
    caller: *wasm.Caller,
    args: [*]const wasm.Val,
    nargs: usize,
    results: [*]wasm.Val,
    nresults: usize,
) callconv(.c) ?*wasm.Trap {
    _ = env;
    _ = results;
    _ = nresults;

    assert(nargs == 2);
    assert(args[0].kind == .i32);
    assert(args[1].kind == .i32);
    const ptr = args[0].of.i32;
    const len = args[1].of.i32;

    const data = caller.getMemoryData() orelse @panic("wasm: no memory export");
    const string = sliceWasmMemory(data, ptr, len);
    std.debug.print("got string: '{s}'\n", .{string});

    return null;
}
