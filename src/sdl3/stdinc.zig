const c = @cImport({
    @cInclude("SDL3/SDL_stdinc.h");
});

pub const MemoryFunctions = struct {
    malloc: c.SDL_malloc_func,
    calloc: c.SDL_calloc_func,
    realloc: c.SDL_realloc_func,
    free: c.SDL_free_func,
};

pub fn setMemoryFunctions(funcs: MemoryFunctions) !void {
    if (c.SDL_SetMemoryFunctions(
        funcs.malloc,
        funcs.calloc,
        funcs.realloc,
        funcs.free,
    ) != 0)
        return error.Sdl;
}

pub fn getMemoryFunctions() MemoryFunctions {
    var funcs: MemoryFunctions = undefined;
    c.SDL_GetMemoryFunctions(
        &funcs.malloc,
        &funcs.calloc,
        &funcs.realloc,
        &funcs.free,
    );
    return funcs;
}

// pub const SDLMEM = struct {
//     pub fn init(allocator: std.mem.Allocator) void {
//         // state.mutex.lock();
//         // defer state.mutex.unlock();

//         state.allocations_list = std.AutoHashMap(usize, usize).init(allocator);
//     }

//     pub fn deinit() void {
//         // state.mutex.lock();
//         // defer state.mutex.unlock();

//         state.allocations_list.?.deinit();
//         state.allocations_list = null;
//     }

//     pub fn setAllocator(allocator: std.mem.Allocator) !void {
//         state.mutex.lock();
//         defer state.mutex.unlock();

//         state.allocator = allocator;
//         try setMemoryFunctions(.{
//             .malloc = sdlMalloc,
//             .calloc = sdlCalloc,
//             .realloc = sdlRealloc,
//             .free = sdlFree,
//         });
//     }

//     const State = struct {
//         allocator: ?std.mem.Allocator = null,
//         allocations_list: ?std.AutoHashMap(usize, usize) = null,
//         mutex: std.Thread.Mutex = .{},
//     };

//     pub var state = State{};

//     const sdl_mem_alignment = 16;

//     pub export fn sdlMalloc(size: usize) callconv(.C) ?*anyopaque {
//         state.mutex.lock();
//         defer state.mutex.unlock();

//         const mem = state.allocator.?.alignedAlloc(
//             u8,
//             sdl_mem_alignment,
//             size,
//         ) catch @panic("sdl alloc: out of memory");

//         state.allocations_list.?.put(@intFromPtr(mem.ptr), size) catch
//             @panic("sdl alloc: out of memory");

//         return mem.ptr;
//     }

//     pub export fn sdlCalloc(count: usize, size: usize) callconv(.C) ?*anyopaque {
//         state.mutex.lock();
//         defer state.mutex.unlock();

//         const total_size = count * size;
//         const mem = state.allocator.?.alignedAlloc(
//             u8,
//             sdl_mem_alignment,
//             total_size,
//         ) catch @panic("sdl alloc: out of memory");

//         @memset(mem, 0);

//         state.allocations_list.?.put(@intFromPtr(mem.ptr), total_size) catch
//             @panic("sdl alloc: out of memory");

//         return mem.ptr;
//     }

//     pub export fn sdlRealloc(ptr: ?*anyopaque, size: usize) callconv(.C) ?*anyopaque {
//         state.mutex.lock();
//         defer state.mutex.unlock();

//         const old_size = if (ptr != null)
//             state.allocations_list.?.get(@intFromPtr(ptr.?)).?
//         else
//             0;
//         const old_mem = if (old_size > 0)
//             @as([*]align(sdl_mem_alignment) u8, @ptrCast(@alignCast(ptr)))[0..old_size]
//         else
//             @as([*]align(sdl_mem_alignment) u8, undefined)[0..0];

//         const new_mem = state.allocator.?.realloc(old_mem, size) catch
//             @panic("sdl alloc: out of memory");

//         if (ptr != null) {
//             const removed = state.allocations_list.?.remove(@intFromPtr(ptr.?));
//             std.debug.assert(removed);
//         }

//         state.allocations_list.?.put(@intFromPtr(new_mem.ptr), size) catch
//             @panic("sdl alloc: out of memory");

//         return new_mem.ptr;
//     }

//     pub export fn sdlFree(maybe_ptr: ?*anyopaque) callconv(.C) void {
//         if (maybe_ptr) |ptr| {
//             state.mutex.lock();
//             defer state.mutex.unlock();

//             const size = state.allocations_list.?.fetchRemove(@intFromPtr(ptr)).?.value;
//             const mem = @as([*]align(sdl_mem_alignment) u8, @ptrCast(@alignCast(ptr)))[0..size];
//             state.allocator.?.free(mem);
//         }
//     }
// };
