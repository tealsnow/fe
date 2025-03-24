const assert = @import("std").debug.assert;

pub const c = @cImport({
    @cInclude("wasi.h");
    @cInclude("wasm.h");
    @cInclude("wasmtime.h");
});

pub const Error = opaque {
    pub fn deinit(err: *Error) void {
        c.wasmtime_error_delete(@ptrCast(err));
    }

    pub fn message(err: *const Error) ByteVec {
        var msg: c.wasm_byte_vec_t = undefined;
        c.wasmtime_error_message(@ptrCast(err), &msg);
        return @bitCast(msg);
    }
};

pub const Trap = opaque {
    pub fn deinit(trap: *Trap) void {
        c.wasm_trap_delete(@ptrCast(trap));
    }

    pub fn message(trap: *const Trap) ByteVec {
        var msg: c.wasm_byte_vec_t = undefined;
        c.wasm_trap_message(@ptrCast(trap), &msg);
        return @bitCast(msg);
    }
};

pub const ByteVec = extern struct {
    size: usize,
    data: [*]u8,

    pub fn slice(vec: *const ByteVec) []const u8 {
        return vec.data[0..vec.size];
    }

    pub fn deinit(vec: *ByteVec) void {
        c.wasm_byte_vec_delete(@ptrCast(vec));
    }
};

var last_error: ?*Error = null;
fn maybeSetError(err: ?*c.wasmtime_error_t) bool {
    if (err) |e| {
        if (last_error) |last| {
            last.deinit();
        }

        last_error = @ptrCast(e);

        return true;
    }
    return false;
}

pub fn getLastError() ?*Error {
    if (last_error) |err| {
        last_error = null;
        return err;
    }

    return null;
}

pub fn TrapOr(comptime T: type) type {
    return union(enum) {
        trap: *Trap,
        value: T,
    };
}

pub const Engine = opaque {
    pub fn init() !*Engine {
        return @ptrCast(c.wasm_engine_new() orelse return error.wasm);
    }

    pub fn deinit(engine: *Engine) void {
        c.wasm_engine_delete(@ptrCast(engine));
    }
};

pub const Store = opaque {
    pub fn init(engine: *Engine, data: ?*anyopaque, finalizer: ?*const fn (?*anyopaque) callconv(.c) void) !*Store {
        return @ptrCast(c.wasmtime_store_new(@ptrCast(engine), data, finalizer) orelse return error.wasm);
    }

    pub fn deinit(store: *Store) void {
        c.wasmtime_store_delete(@ptrCast(store));
    }

    pub fn context(store: *Store) *Context {
        return @ptrCast(c.wasmtime_store_context(@ptrCast(store)).?);
    }
};

pub const Context = opaque {
    pub fn setWasi(context: *Context, wasi_config: *WasiConfig) !void {
        const err = c.wasmtime_context_set_wasi(@ptrCast(context), @ptrCast(wasi_config));
        if (maybeSetError(err)) return error.wasm;
    }
};

pub const Linker = opaque {
    pub fn init(engine: *Engine) *Linker {
        return @ptrCast(c.wasmtime_linker_new(@ptrCast(engine)).?);
    }

    pub fn deinit(linker: *Linker) void {
        c.wasmtime_linker_delete(@ptrCast(linker));
    }

    pub fn defineWasi(linker: *Linker) !void {
        const err = c.wasmtime_linker_define_wasi(@ptrCast(linker));
        if (maybeSetError(err)) return error.wasm;
    }

    pub fn defineFunc(
        linker: *Linker,
        module: []const u8,
        name: []const u8,
        ty: *Functype,
        cb: FuncCallback,
        data: ?*anyopaque,
        finalizer: ?*const fn (?*anyopaque) callconv(.c) void,
    ) !void {
        const err = c.wasmtime_linker_define_func(@ptrCast(linker), module.ptr, module.len, name.ptr, name.len, @ptrCast(ty), @ptrCast(cb), data, finalizer);
        if (maybeSetError(err)) return error.wasm;
    }

    pub fn linkModule(linker: *Linker, context: *Context, name: []const u8, module: *Module) !void {
        const err = c.wasmtime_linker_module(@ptrCast(linker), @ptrCast(context), name.ptr, name.len, @ptrCast(module));
        if (maybeSetError(err)) return error.wasm;
    }

    pub fn instantiate(linker: *Linker, context: *Context, module: *Module) !TrapOr(Instance) {
        var instance: c.wasmtime_instance_t = undefined;
        var trap: ?*c.wasm_trap_t = null;
        const err = c.wasmtime_linker_instantiate(@ptrCast(linker), @ptrCast(context), @ptrCast(module), &instance, &trap);
        if (maybeSetError(err)) return error.wasm;

        if (trap != null) return .{ .trap = @ptrCast(trap) };
        return .{ .value = @bitCast(instance) };
    }
};

pub const FuncCallback = *const fn (?*anyopaque, *Caller, [*]const Val, usize, [*]Val, usize) callconv(.c) ?*Trap;

pub const Instance = extern struct {
    store_id: u64,
    index: usize,

    pub fn deinit(instance: *Instance) void {
        c.wasm_instance_delete(@ptrCast(instance));
    }

    pub fn exportGet(instance: *Instance, context: *Context, name: []const u8) ?Extern {
        var ext: c.wasmtime_extern_t = undefined;
        const ok = c.wasmtime_instance_export_get(@ptrCast(context), @ptrCast(instance), name.ptr, name.len, &ext);
        if (!ok) return null;
        return @bitCast(ext);
    }

    pub fn exportGetFunc(instance: *Instance, context: *Context, name: []const u8) ?Func {
        const ext = instance.exportGet(context, name) orelse return null;
        if (ext.kind != .func) return null;
        return ext.of.func;
    }

    pub fn exportGetMemory(instance: *Instance, context: *Context, name: []const u8) ?Memory {
        const ext = instance.exportGet(context, name) orelse return null;
        if (ext.kind != .memory) return null;
        return ext.of.memory;
    }

    pub fn getMemory(instance: *Instance, context: *Context) ?Memory {
        return instance.exportGetMemory(context, "memory");
    }

    pub fn getMemoryData(instance: *Instance, context: *Context) ?[*]u8 {
        const memory = instance.getMemory(context) orelse return null;
        return memory.data(context);
    }
};

pub const ExternKind = enum(u8) {
    func = c.WASMTIME_EXTERN_FUNC,
    global = c.WASMTIME_EXTERN_GLOBAL,
    table = c.WASMTIME_EXTERN_TABLE,
    memory = c.WASMTIME_EXTERN_MEMORY,
    sharedmemory = c.WASMTIME_EXTERN_SHAREDMEMORY,
};

pub const ExternUnion = extern union {
    func: Func,
    global: Global,
    table: Table,
    memory: Memory,
    sharedmemory: *SharedMemory,
};

pub const Extern = extern struct {
    kind: ExternKind,
    of: ExternUnion,

    pub fn needsDeinit(ext: Extern) bool {
        return ext.kind == .sharedmemory;
    }

    pub fn deinit(ext: *Extern) void {
        c.wasmtime_extern_delete(@ptrCast(ext));
    }
};

pub const Func = extern struct {
    store_id: u64,
    __private: usize,

    pub fn call(func: *const Func, context: *Context, args: []const Val, results: []Val) !?*Trap {
        var trap: ?*c.wasm_trap_t = null;
        const err = c.wasmtime_func_call(@ptrCast(context), @ptrCast(func), @ptrCast(args.ptr), args.len, @ptrCast(results.ptr), results.len, &trap);
        if (maybeSetError(err)) return error.wasm;
        if (trap) |t| return @ptrCast(t);
        return null;
    }
};

pub const Global = extern struct {
    store_id: u64,
    __private: usize,

    pub fn get(global: *const Global, context: *Context) Val {
        var val: c.wasmtime_val_t = undefined;
        c.wasmtime_global_get(@ptrCast(context), @ptrCast(global), &val);
        return @bitCast(val);
    }
};

pub const Table = extern struct {
    store_id: u64,
    __private: usize,
};

pub const Memory = extern struct {
    store_id: u64,
    __private: usize,

    pub fn data(memory: *const Memory, context: *const Context) [*]u8 {
        return c.wasmtime_memory_data(@ptrCast(context), @ptrCast(memory));
    }
};

pub const SharedMemory = opaque {};

pub const Module = opaque {
    pub fn init(engine: *Engine, bytes: []const u8) !*Module {
        var module: ?*c.wasmtime_module_t = null;
        const err = c.wasmtime_module_new(@ptrCast(engine), bytes.ptr, bytes.len, &module);
        if (maybeSetError(err)) return error.wasm;
        return @ptrCast(module.?);
    }

    pub fn deinit(module: *Module) void {
        c.wasmtime_module_delete(@ptrCast(module));
    }
};

pub const WasiConfig = opaque {
    pub fn init() !*WasiConfig {
        return @ptrCast(c.wasi_config_new() orelse return error.wasm);
    }

    pub fn deinit(config: *WasiConfig) void {
        c.wasi_config_delete(@ptrCast(config));
    }

    pub fn inheritArgv(config: *WasiConfig) void {
        c.wasi_config_inherit_argv(@ptrCast(config));
    }

    pub fn inheritEnv(config: *WasiConfig) void {
        c.wasi_config_inherit_env(@ptrCast(config));
    }

    pub fn inheritStdin(config: *WasiConfig) void {
        c.wasi_config_inherit_stdin(@ptrCast(config));
    }

    pub fn inheritStdout(config: *WasiConfig) void {
        c.wasi_config_inherit_stdout(@ptrCast(config));
    }

    pub fn inheritStderr(config: *WasiConfig) void {
        c.wasi_config_inherit_stderr(@ptrCast(config));
    }
};

pub const Valkind = enum(u8) {
    i32 = c.WASM_I32,
    i64 = c.WASM_I64,
    f32 = c.WASM_F32,
    f64 = c.WASM_F64,
    externref = c.WASM_EXTERNREF,
    funcref = c.WASM_FUNCREF,

    pub fn isNum(kind: Valkind) bool {
        return c.wasm_valkind_is_num(@intFromEnum(kind));
    }

    pub fn isRef(kind: Valkind) bool {
        return c.wasm_valkind_is_ref(@intFromEnum(kind));
    }
};

pub const Valunion = extern union {
    i32: i32,
    i64: i64,
    f32: f32,
    f64: f64,
    anyref: Anyref,
    externref: Externref,
    funcref: Func,
    v128: v128,
};

pub const Anyref = extern struct {
    store_id: u64,
    __private1: u32,
    __private2: u32,
};

pub const Externref = extern struct {
    store_id: u64,
    __private1: u32,
    __private2: u32,
};

pub const v128 = [16]u8;

pub const Val = extern struct {
    kind: Valkind,
    of: Valunion,

    pub fn deinit(val: *Val) void {
        c.wasm_val_delete(@ptrCast(val));
    }

    pub fn newI32(v: i32) Val {
        return Val{
            .kind = .i32,
            .of = .{ .i32 = v },
        };
    }

    pub fn newI64(v: i64) Val {
        return Val{
            .kind = .i64,
            .of = .{ .i64 = v },
        };
    }

    pub fn newF32(v: f32) Val {
        return Val{
            .kind = .f32,
            .of = .{ .f32 = v },
        };
    }

    pub fn newF64(v: f64) Val {
        return Val{
            .kind = .f64,
            .of = .{ .f64 = v },
        };
    }

    pub fn newExternref(v: Externref) Val {
        return Val{
            .kind = .externref,
            .of = .{ .externref = v },
        };
    }

    pub fn newFuncref(v: Func) Val {
        return Val{
            .kind = .funcref,
            .of = .{ .funcref = v },
        };
    }
};

pub const Valtype = opaque {
    pub fn init(kind: Valkind) *Valtype {
        return @ptrCast(c.wasm_valtype_new(@intFromEnum(kind)).?);
    }

    pub fn deinit(val: *Valtype) void {
        c.wasm_valtype_delete(@ptrCast(val));
    }

    pub fn newI32() *Valtype {
        return @ptrCast(c.wasm_valtype_new_i32().?);
    }

    pub fn newI64() *Valtype {
        return @ptrCast(c.wasm_valtype_new_i64().?);
    }

    pub fn newF32() *Valtype {
        return @ptrCast(c.wasm_valtype_new_f32().?);
    }

    pub fn newF64() *Valtype {
        return @ptrCast(c.wasm_valtype_new_f64().?);
    }

    pub fn newExternref() *Valtype {
        return @ptrCast(c.wasm_valtype_new_externref().?);
    }

    pub fn newFuncref() *Valtype {
        return @ptrCast(c.wasm_valtype_new_funcref().?);
    }

    pub fn isNum(val: *const Valtype) bool {
        return c.wasm_valtype_is_num(val);
    }

    pub fn isRef(val: *const Valtype) bool {
        return c.wasm_valtype_is_ref(val);
    }

    pub fn getKind(val: *const Valtype) Valkind {
        return @enumFromInt(c.wasm_valtype_kind(val));
    }

    pub fn copy(val: *const Valtype) *Valtype {
        return @ptrCast(c.wasm_valtype_copy(@ptrCast(val)).?);
    }
};

pub const ValtypeVec = extern struct {
    size: usize,
    data: [*]*Valtype,

    pub fn init(vals: []const *Valtype) ValtypeVec {
        var vec: c.wasm_valtype_vec_t = undefined;
        c.wasm_valtype_vec_new(&vec, vals.len, @ptrCast(vals.ptr));
        return @bitCast(vec);
    }

    pub fn initEmpty() ValtypeVec {
        var vec: c.wasm_valtype_vec_t = undefined;
        c.wasm_valtype_vec_new_empty(&vec);
        return @bitCast(vec);
    }

    pub fn initUninitialized(size: usize) ValtypeVec {
        var vec: c.wasm_valtype_vec_t = undefined;
        c.wasm_valtype_vec_new_uninitialized(&vec, size);
        return @bitCast(vec);
    }

    pub fn deinit(vec: *ValtypeVec) void {
        c.wasm_valtype_vec_delete(&vec);
    }

    pub fn copy(vec: *ValtypeVec) ValtypeVec {
        var new: c.wasm_valtype_vec_t = undefined;
        c.wasm_valtype_vec_copy(&vec, &new);
        return @bitCast(new);
    }
};

pub const Functype = opaque {
    /// Takes ownership of params and results
    pub fn init(params: *ValtypeVec, results: *ValtypeVec) *Functype {
        return @ptrCast(c.wasm_functype_new(@ptrCast(params), @ptrCast(results)).?);
    }

    pub fn init_0_0() *Functype {
        return @ptrCast(c.wasm_functype_new_0_0().?);
    }

    pub fn init_1_0(arg_p: *Valtype) *Functype {
        return @ptrCast(c.wasm_functype_new_1_0(@ptrCast(arg_p)).?);
    }

    pub fn init_2_0(arg_p1: *Valtype, arg_p2: *Valtype) *Functype {
        return @ptrCast(c.wasm_functype_new_2_0(@ptrCast(arg_p1), @ptrCast(arg_p2)).?);
    }

    pub fn init_3_0(arg_p1: *Valtype, arg_p2: *Valtype, arg_p3: *Valtype) *Functype {
        return @ptrCast(c.wasm_functype_new_3_0(@ptrCast(arg_p1), @ptrCast(arg_p2), @ptrCast(arg_p3)).?);
    }

    pub fn init_0_1(arg_r: *Valtype) *Functype {
        return @ptrCast(c.wasm_functype_new_0_1(@ptrCast(arg_r)).?);
    }

    pub fn init_1_1(arg_p: *Valtype, arg_r: *Valtype) *Functype {
        return @ptrCast(c.wasm_functype_new_1_1(@ptrCast(arg_p), @ptrCast(arg_r)).?);
    }

    pub fn init_2_1(arg_p1: *Valtype, arg_p2: *Valtype, arg_r: *Valtype) *Functype {
        return @ptrCast(c.wasm_functype_new_2_1(@ptrCast(arg_p1), @ptrCast(arg_p2), @ptrCast(arg_r)).?);
    }

    pub fn init_3_1(arg_p1: *Valtype, arg_p2: *Valtype, arg_p3: *Valtype, arg_r: *Valtype) *Functype {
        return @ptrCast(c.wasm_functype_new_3_1(@ptrCast(arg_p1), @ptrCast(arg_p2), @ptrCast(arg_p3), @ptrCast(arg_r)).?);
    }

    pub fn init_0_2(arg_r1: *Valtype, arg_r2: *Valtype) *Functype {
        return @ptrCast(c.wasm_functype_new_0_2(@ptrCast(arg_r1), @ptrCast(arg_r2)).?);
    }

    pub fn init_1_2(arg_p: *Valtype, arg_r1: *Valtype, arg_r2: *Valtype) *Functype {
        return @ptrCast(c.wasm_functype_new_1_2(@ptrCast(arg_p), @ptrCast(arg_r1), @ptrCast(arg_r2)).?);
    }

    pub fn init_2_2(arg_p1: *Valtype, arg_p2: *Valtype, arg_r1: *Valtype, arg_r2: *Valtype) *Functype {
        return @ptrCast(c.wasm_functype_new_2_2(@ptrCast(arg_p1), @ptrCast(arg_p2), @ptrCast(arg_r1), @ptrCast(arg_r2)).?);
    }

    pub fn init_3_2(arg_p1: *Valtype, arg_p2: *Valtype, arg_p3: *Valtype, arg_r1: *Valtype, arg_r2: *Valtype) *Functype {
        return @ptrCast(c.wasm_functype_new_3_2(@ptrCast(arg_p1), @ptrCast(arg_p2), @ptrCast(arg_p3), @ptrCast(arg_r1), @ptrCast(arg_r2)).?);
    }

    pub fn init_0_3(arg_r1: *Valtype, arg_r2: *Valtype, arg_r3: *Valtype) *Functype {
        return @ptrCast(c.wasm_functype_new_0_3(@ptrCast(arg_r1), @ptrCast(arg_r2), @ptrCast(arg_r3)).?);
    }

    pub fn init_1_3(arg_p: *Valtype, arg_r1: *Valtype, arg_r2: *Valtype, arg_r3: *Valtype) *Functype {
        return @ptrCast(c.wasm_functype_new_1_3(@ptrCast(arg_p), @ptrCast(arg_r1), @ptrCast(arg_r2), @ptrCast(arg_r3)).?);
    }

    pub fn init_2_3(arg_p1: *Valtype, arg_p2: *Valtype, arg_r1: *Valtype, arg_r2: *Valtype, arg_r3: *Valtype) *Functype {
        return @ptrCast(c.wasm_functype_new_2_3(@ptrCast(arg_p1), @ptrCast(arg_p2), @ptrCast(arg_r1), @ptrCast(arg_r2), @ptrCast(arg_r3)).?);
    }

    pub fn init_3_3(arg_p1: *Valtype, arg_p2: *Valtype, arg_p3: *Valtype, arg_r1: *Valtype, arg_r2: *Valtype, arg_r3: *Valtype) *Functype {
        return @ptrCast(c.wasm_functype_new_3_3(@ptrCast(arg_p1), @ptrCast(arg_p2), @ptrCast(arg_p3), @ptrCast(arg_r1), @ptrCast(arg_r2), @ptrCast(arg_r3)).?);
    }

    pub fn deinit(functype: *Functype) void {
        c.wasm_functype_delete(@ptrCast(functype));
    }
};

pub const Caller = opaque {
    pub fn exportGet(caller: *Caller, name: []const u8) ?Extern {
        var ext: c.wasmtime_extern_t = undefined;
        const ok = c.wasmtime_caller_export_get(@ptrCast(caller), name.ptr, name.len, &ext);
        if (!ok) return null;
        return @bitCast(ext);
    }

    pub fn context(caller: *Caller) *Context {
        return @ptrCast(c.wasmtime_caller_context(@ptrCast(caller)));
    }

    pub fn getMemory(caller: *Caller) ?Memory {
        var ext = caller.exportGet("memory") orelse return null;
        defer ext.deinit();
        assert(ext.kind == .memory);
        return ext.of.memory;
    }

    pub fn getMemoryData(caller: *Caller) ?[*]u8 {
        const memory = caller.getMemory() orelse return null;
        const ctx = caller.context();
        return memory.data(ctx);
    }
};
