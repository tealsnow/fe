const std = @import("std");
const assert = std.debug.assert;

const wasm = @import("wasm.zig");
const PluginSchema = @import("plugin-schema").PluginSchema;

const logFn = @import("logFn.zig");

const log = std.log.scoped(.@"fe::plugins");

// Mirrored in plugin-lib
pub fn PackedSlice(comptime T: type) type {
    const TypeInfo = @typeInfo(T);
    const ChildType, const is_const = switch (TypeInfo) {
        .pointer => |ptr| child: {
            if (ptr.size != .slice)
                @compileError("PackedSlice can only take slice");
            break :child .{ ptr.child, ptr.is_const };
        },
        else => @compileError("PackedSlice can only take slice"),
    };

    return packed struct(u64) {
        ptr: u32,
        len: u32,

        pub const Child = ChildType;
        pub const Ptr = if (is_const) [*]const Child else [*]Child; // 32 bits wide
        pub const Slice = T;

        const Self = @This();

        /// Ensure that the passed slice is actualy in the wasm memory space
        pub fn fromSlice(slice: Slice) Self {
            return .{
                .ptr = @intCast(@intFromPtr(slice.ptr)),
                .len = @intCast(slice.len),
            };
        }

        pub fn toSlice(self: Self, data: [*]u8) Slice {
            return sliceWasmMemory(Slice, data, @intCast(self.ptr), @intCast(self.len));
        }
    };
}

pub fn printLastWasmError() void {
    if (wasm.getLastError()) |e| {
        defer e.deinit();
        var message = e.message();
        defer message.deinit();
        log.err("[WASM]: {s}", .{message.slice()});
    }
}

pub fn printTrap(trap: *wasm.Trap) void {
    defer trap.deinit();
    var msg = trap.message();
    defer msg.deinit();
    log.err("trap: {s}", .{msg.slice()});
}

pub fn sliceWasmMemory(comptime Slice: type, data: [*]u8, ptr: i32, len: i32) Slice {
    const ChildType = switch (@typeInfo(Slice)) {
        .pointer => |pointer| child: {
            if (pointer.size != .slice)
                @compileError("sliceWasmMemory can only take slice");
            break :child pointer.child;
        },
        else => @compileError("sliceWasmMemory can only take slice"),
    };

    const ptr_usize = @as(usize, @intCast(ptr));
    const base_ptr: [*]ChildType = @ptrCast(&data[ptr_usize]);
    const len_usize = @as(usize, @intCast(len));
    return base_ptr[0..len_usize];
}

pub const WasmGuestAllocator = struct {
    const Self = @This();
    const Allocator = std.mem.Allocator;
    const Alignment = std.mem.Alignment;
    const alloc_log = std.log.scoped(.@"fe::WasmGuestAllocator");

    context: *wasm.Context,
    memory: wasm.Memory,
    alloc_func: wasm.Func,
    resize_func: wasm.Func,
    remap_func: wasm.Func,
    free_func: wasm.Func,

    pub fn init(context: *wasm.Context, instance: *wasm.Instance, memory: wasm.Memory) !Self {
        const alloc_func = instance.exportGetFunc(context, "Allocator_alloc") orelse return error.exportGet;
        const resize_func = instance.exportGetFunc(context, "Allocator_resize") orelse return error.exportGet;
        const remap_func = instance.exportGetFunc(context, "Allocator_remap") orelse return error.exportGet;
        const free_func = instance.exportGetFunc(context, "Allocator_free") orelse return error.exportGet;

        return .{
            .context = context,
            .memory = memory,
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
        const data = self.memory.data(self.context);
        return @intCast(@intFromPtr(ptr) - @intFromPtr(data));
    }

    pub fn toWasmSlice(self: *Self, comptime Slice: type, slice: Slice) PackedSlice(Slice) {
        const Packed = PackedSlice(Slice);
        const ptr: u32 = @intCast(self.toWasmPtr(Packed.Child, @ptrCast(slice.ptr)));
        const len: u32 = @intCast(slice.len);
        return .{ .ptr = ptr, .len = len };
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
        const guest_mem = self.memory.data(self.context);
        const host_ptr = &guest_mem[guest_ptr_usize];
        const ret: [*]u8 = @ptrCast(host_ptr);

        alloc_log.debug(" -- return: {*}", .{ret});

        return ret;
    }

    fn resize(ctx: *anyopaque, memory: []u8, alignment: Alignment, new_len: usize, ret_addr: usize) bool {
        _ = ret_addr;

        alloc_log.debug("resize(memory: {*}, alignment: {s}, new_len: {d})", .{ memory, @tagName(alignment), new_len });

        const self: *Self = @ptrCast(@alignCast(ctx));

        const memory_packed = self.toWasmSlice([]u8, memory);
        const alignment_i32: i32 = @intCast(alignment.toByteUnits());
        const new_len_i32: i32 = @intCast(new_len);

        const args = [_]wasm.Val{ .newI64(@bitCast(memory_packed)), .newI32(alignment_i32), .newI32(new_len_i32) };
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

        const memory_packed = self.toWasmSlice([]u8, memory);
        const alignment_i32: i32 = @intCast(alignment.toByteUnits());
        const new_len_i32: i32 = @intCast(new_len);

        const args = [_]wasm.Val{ .newI64(@bitCast(memory_packed)), .newI32(alignment_i32), .newI32(new_len_i32) };
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
        const guest_mem = self.memory.data(self.context);
        const host_ptr = &guest_mem[guest_ptr_usize];
        const ret: [*]u8 = @ptrCast(host_ptr);

        alloc_log.debug(" -- return: {*}", .{ret});

        return ret;
    }

    fn free(ctx: *anyopaque, memory: []u8, alignment: Alignment, ret_addr: usize) void {
        _ = ret_addr;

        alloc_log.debug("free(memory: {*}, alignment: {s})", .{ memory, @tagName(alignment) });

        const self: *Self = @ptrCast(@alignCast(ctx));

        const memory_packed = self.toWasmSlice([]u8, memory);
        const alignment_i32: i32 = @intCast(alignment.toByteUnits());

        const args = [_]wasm.Val{ .newI64(@bitCast(memory_packed)), .newI32(alignment_i32) };

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
    function_table: wasm.Table,
    wasm_allocator: WasmGuestAllocator,

    pub fn init(
        gpa: std.mem.Allocator,
        engine: *wasm.Engine,
        context: *wasm.Context,
        plugin_dir: std.fs.Dir,
    ) !*Plugin {
        const plugin_ptr = try gpa.create(Plugin);

        const memory = try wasm.Memory.init(context, try wasm.Memorytype.init(257, null, false, false));

        const schema = try loadSchema(gpa, plugin_dir);
        const module = try loadModule(gpa, plugin_dir, schema.id, engine);
        const linker = try setupCallbacks(engine, context, schema.id, module, memory, plugin_ptr);

        var instance = switch (try linker.instantiate(context, module)) {
            .value => |inst| inst,
            .trap => |trap| {
                printTrap(trap);
                return error.trap;
            },
        };

        const table_ext = instance.exportGet(context, "__indirect_function_table") orelse return error.no_table;
        assert(table_ext.kind == .table);
        const function_table = table_ext.of.table;

        const wasm_allocator = try WasmGuestAllocator.init(context, &instance, memory);
        plugin_ptr.* = .{
            .schema = schema,
            .context = context,
            .linker = linker,
            .module = module,
            .instance = instance,
            .function_table = function_table,
            .wasm_allocator = wasm_allocator,
        };
        return plugin_ptr;
    }

    pub fn deinit(plugin: *Plugin, gpa: std.mem.Allocator) void {
        std.zon.parse.free(gpa, plugin.schema);
        plugin.module.deinit();
        plugin.linker.deinit();
        plugin.* = undefined;
        gpa.destroy(plugin);
    }

    fn loadSchema(
        gpa: std.mem.Allocator,
        plugin_dir: std.fs.Dir,
    ) !PluginSchema {
        log.info("loading schema", .{});

        const file = try plugin_dir.openFile("plugin.zon", .{});
        defer file.close();

        const size = try file.getEndPos();

        const buffer: [:0]u8 = try gpa.allocSentinel(u8, size, 0);
        defer gpa.free(buffer);
        const read = try file.readAll(buffer);
        assert(read == buffer.len);

        var status = std.zon.parse.Status{};
        defer status.deinit(gpa);
        const schema = std.zon.parse.fromSlice(
            PluginSchema,
            gpa,
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
        gpa: std.mem.Allocator,
        plugin_dir: std.fs.Dir,
        id: []const u8,
        engine: *wasm.Engine,
    ) !*wasm.Module {
        log.info("loading wasm", .{});
        const file_path = try std.fmt.allocPrint(gpa, "{s}.wasm", .{id});
        defer gpa.free(file_path);

        const file = try plugin_dir.openFile(file_path, .{});
        defer file.close();

        const size = try file.getEndPos();
        const bytes = try file.readToEndAlloc(gpa, size);
        defer gpa.free(bytes);

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
        plugin_ptr: *Plugin,
    ) !void {
        defer functype.deinit();
        log.debug("defining callback '{s}::{s}'", .{ module, name });
        try linker.defineFunc(module, name, functype, callback, plugin_ptr, null);
    }

    fn setupCallbacks(
        engine: *wasm.Engine,
        context: *wasm.Context,
        module_name: []const u8,
        module: *wasm.Module,
        memory: wasm.Memory,
        plugin_ptr: *Plugin,
    ) !*wasm.Linker {
        log.info("init linker", .{});
        const linker = wasm.Linker.init(engine);
        try linker.defineWasi();

        const item = wasm.Extern.newMemory(memory);
        try linker.define(context, "env", "memory", &item);

        log.info("defining callbacks", .{});
        try defineCallback(linker, "fe", "callback", wasm.Functype.init_0_0(), wasmCallback, plugin_ptr);
        try defineCallback(linker, "fe", "FooType_inc", wasm.Functype.init_1_0(.newI64()), FooType_inc_wasm, plugin_ptr);
        try defineCallback(linker, "fe", "takeString", .init_1_0(.newI64()), takeString, plugin_ptr);
        {
            var params = wasm.ValtypeVec.init(&.{ .newI32(), .newI64(), .newI64() });
            var results = wasm.ValtypeVec.initEmpty();
            const functype = wasm.Functype.init(&params, &results);
            try defineCallback(linker, "fe", "hostLogFn", functype, logFnCallback, plugin_ptr);
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
    plugins: []*Plugin,

    pub fn init(gpa: std.mem.Allocator) !PluginHost {
        log.info("setup engine, store and context", .{});

        const config = try wasm.Config.init();
        config.wasmTailCallSet(true);
        config.wasmReferenceTypesSet(true);
        config.wasmSimdSet(true);
        config.wasmRelaxedSimdDeterministicSet(true);
        config.wasmBulkMemorySet(true);
        config.wasmMultiValueSet(true);
        // config.wasmMultiMemorySet(true);

        const engine = try wasm.Engine.initWithConfig(config);
        const store = try wasm.Store.init(engine, null, null);
        const context = store.context();

        log.info("setup wasi", .{});
        const wasi_config = try wasm.WasiConfig.init();
        // wasi_config.inheritArgv();
        wasi_config.inheritEnv();
        // wasi_config.inheritStdin();
        wasi_config.inheritStdout();
        wasi_config.inheritStderr();

        log.info("set wasi to context", .{});
        try context.setWasi(wasi_config);

        var plugins = std.ArrayList(*Plugin).init(gpa);
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
        defer for (host.plugins) |plugin| {
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
    _ = caller;
    _ = results;
    _ = nresults;

    const plugin: *Plugin = @alignCast(@ptrCast(env));

    assert(nargs == 3);
    assert(args[0].kind == .i32);
    assert(args[1].kind == .i64);
    assert(args[2].kind == .i64);

    const level_int = args[0].of.i32;
    const level: std.log.Level = @enumFromInt(level_int);

    const scope_slice: PackedSlice([]const u8) = @bitCast(args[1].of.i64);
    const message_slice: PackedSlice([]const u8) = @bitCast(args[2].of.i64);

    const data = plugin.wasm_allocator.memory.data(plugin.context);
    const scope = scope_slice.toSlice(data);
    const message = message_slice.toSlice(data);

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
    const func_return_func = try plugin.getFunc("returnFunc");

    log.info("calling guest functions", .{});

    try func_hello_world.call(&.{}, &.{});

    { // add
        const args = [_]wasm.Val{ .newI32(42), .newI32(420) };
        var results: [1]wasm.Val = undefined;
        try func_add.call(&args, &results);
        assert(results[0].kind == .i32);
        log.debug("add: {d} + {d} = {d}", .{ args[0].of.i32, args[1].of.i32, results[0].of.i32 });
    }

    { // addi64
        const args = [_]wasm.Val{ .newI64(42), .newI64(420) };
        var results: [1]wasm.Val = undefined;
        try func_addi64.call(&args, &results);
        assert(results[0].kind == .i64);
        log.debug("addi64: {d} + {d} = {d}", .{ args[0].of.i64, args[1].of.i64, results[0].of.i64 });
    }

    try func_run_callback.call(&.{}, &.{});

    { // takeFooType
        var foo = FooType{ .string = "foo bar", .int = 32 };
        const ptr: *FooType = &foo;
        log.debug("foo int (before): {d} ; ptr: {*}", .{ foo.int, ptr });

        const args = [_]wasm.Val{.newI64(@intCast(@intFromPtr(ptr)))};
        try func_take_foo_type.call(&args, &.{});

        log.debug("foo int (after): {d}", .{foo.int});
    }

    try func_give_string.call(&.{}, &.{});

    { // useString
        const alloc = plugin.wasm_allocator.allocator();

        const string = try std.fmt.allocPrint(alloc, "Hello, {s}!", .{"allocator"});
        defer alloc.free(string);

        const string_packed = plugin.wasm_allocator.toWasmSlice([]const u8, string);
        const args = [_]wasm.Val{.newI64(@bitCast(string_packed))};
        try func_use_string.call(&args, &.{});
    }

    { // returnFunc
        const func_idx = blk: {
            var results: [1]wasm.Val = undefined;
            try func_return_func.call(&.{}, &results);
            const result = results[0];
            assert(result.kind == .i32);
            log.debug("got func index", .{});
            break :blk result.of.i32;
        };

        const func = func: {
            log.debug("geting func from table", .{});
            const val = plugin.function_table.get(plugin.context, @intCast(func_idx)) orelse return error.table_get;
            assert(val.kind == .funcref);
            break :func val.of.funcref;
        };

        {
            log.debug("calling returned and table indexed func", .{});

            var results: [1]wasm.Val = undefined;
            const trap = try func.call(plugin.context, &.{}, &results);
            if (trap) |t| {
                printTrap(t);
                return error.trap;
            }
            assert(results[0].kind == .i32);
            assert(results[0].of.i32 == 3);
        }
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
    assert(args[0].kind == .i64);

    const ptr: *FooType = @ptrFromInt(@as(usize, @intCast(args[0].of.i64)));
    log.debug("foo type inc ; ptr: {*}", .{ptr});
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
    _ = caller; // autofix
    _ = results;
    _ = nresults;

    const plugin: *Plugin = @alignCast(@ptrCast(env));

    assert(nargs == 1);
    assert(args[0].kind == .i64);
    const string_packed: PackedSlice([]const u8) = @bitCast(args[0].of.i64);

    const data = plugin.wasm_allocator.memory.data(plugin.context);
    const string = string_packed.toSlice(data);
    std.debug.print("got string: '{s}'\n", .{string});

    return null;
}
