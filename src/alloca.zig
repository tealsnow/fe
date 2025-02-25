/// This is just my attempts to understand allocators a little better
const std = @import("std");

pub const FixedSizeArena = struct {
    buffer: []align(std.mem.page_size) u8,
    pos: usize,

    pub fn init(cap: u64) !FixedSizeArena {
        const page = try std.posix.mmap(
            null,
            cap,
            std.posix.PROT.READ | std.posix.PROT.WRITE,
            .{ .TYPE = .PRIVATE, .ANONYMOUS = true },
            -1,
            0,
        );

        return .{
            .buffer = page[0..cap],
            .pos = 0,
        };
    }

    pub fn deinit(self: *FixedSizeArena) void {
        std.posix.munmap(self.buffer);

        self.* = undefined;
    }

    // pub fn setAutoAlign(self: *FixedSizeArena, alignment: u29) void {
    //     _ = self;
    //     _ = alignment;
    // }

    pub fn pushAligned(self: *FixedSizeArena, comptime T: type, comptime alignment: u64) !*align(alignment) T {
        // @REMARK(ketanr): I don't fully understand the what, how and why of this.
        //  I understand that `log2_int` gives us a power of two for the alignment,
        //  but the left shift I don't get
        //  it may have something to do with what `alignPointerOffset` wants
        const log2_ptr_align = std.math.log2_int(usize, @as(usize, alignment));
        const ptr_align = @as(usize, 1) << @as(std.mem.Allocator.Log2Align, @intCast(log2_ptr_align));

        const adjust_off = std.mem.alignPointerOffset(
            self.buffer.ptr + self.pos,
            ptr_align,
        ) orelse return error.oom;

        const adjusted_pos = self.pos + adjust_off;

        const size = @sizeOf(T);
        const new_pos = adjusted_pos + size;
        if (new_pos > self.buffer.len) return error.oom;
        self.pos = new_pos;

        const ptr: *align(alignment) T = @ptrCast(@alignCast(self.buffer.ptr + adjusted_pos));
        ptr.* = undefined;
        // ptr.* = std.mem.zeroes(T);
        return ptr;
    }

    pub fn push(self: *FixedSizeArena, comptime T: type) !*T {
        return self.pushAligned(T, @alignOf(T));
    }

    // // undefined
    // pub fn pushNoZero(self: *FixedSizeArena, T: type) *T {
    //     _ = self;
    //     unreachable;
    // }

    pub fn popTo(self: *FixedSizeArena, pos: usize) void {
        self.pos = pos;
    }

    pub fn clear(self: *FixedSizeArena) void {
        self.pos = 0;
    }
};

pub fn fixedSizeArenaTest() !void {
    const Foo = struct {
        a: u32,
        b: f64,
        c: bool,
    };

    var fsa = try FixedSizeArena.init(1024);
    defer fsa.deinit();

    std.debug.print("pos: {d}\n", .{fsa.pos});

    std.debug.print("sizeof(Foo): {d}\n", .{@sizeOf(Foo)});
    std.debug.print("alignof(Foo): {d}\n", .{@alignOf(Foo)});

    const foo = try fsa.pushAligned(Foo, 64);
    foo.* = .{
        .a = 42,
        .b = 36.3,
        .c = true,
    };

    std.debug.print("pos: {d} -- after foo\n", .{fsa.pos});

    std.debug.print("sizeof([5]u8): {d}\n", .{@sizeOf([5]u8)});
    std.debug.print("alignof([5]u8): {d}\n", .{@alignOf([5]u8)});

    // const str = try fsa.push([5]u8);
    const str = try fsa.pushAligned([5]u8, 16);
    str.* = "hello".*;

    std.debug.print("pos: {d} -- after str\n", .{fsa.pos});

    std.debug.print("{d} {d} {}\n", .{ foo.a, foo.b, foo.c });

    std.debug.print("{s}\n", .{str});

    std.debug.print("pos: {d}\n", .{fsa.pos});
    fsa.clear();
    std.debug.print("pos: {d}\n", .{fsa.pos});
}

pub const ChainingAllocator = struct {
    metadata: FixedSizeArena,

    first: *Node,
    current: *Node,
    index: usize = 0,

    const Page = []align(std.mem.page_size) u8;

    const Node = struct {
        page: Page,
        next: ?*Node = null,
    };

    const Marker = struct {
        node: *Node,
        index: usize,
    };

    pub fn init() !ChainingAllocator {
        var metadata = try FixedSizeArena.init(std.mem.page_size);
        const first = try metadata.push(Node);

        const page = try makePage();
        first.* = .{ .page = page };

        return .{
            .metadata = metadata,
            .first = first,
            .current = first,
        };
    }

    pub fn deinit(self: *ChainingAllocator) void {
        var next: ?*Node = self.first;
        while (next) |node| : (next = node.next) {
            std.posix.munmap(node.page);
        }
        self.metadata.deinit();
        self.* = undefined;
    }

    fn makePage() !Page {
        return std.posix.mmap(
            null,
            std.mem.page_size,
            std.posix.PROT.READ | std.posix.PROT.WRITE,
            .{ .TYPE = .PRIVATE, .ANONYMOUS = true },
            -1,
            0,
        );
    }

    pub fn push(self: *ChainingAllocator, comptime T: type) !*T {
        std.log.debug(
            "ChainingAllocator.push(T: {s}) -- start -- index: {d} ; sizeof(T): {d} ; page_size: {d}",
            .{ @typeName(T), self.index, @sizeOf(T), std.mem.page_size },
        );
        defer std.log.debug("ChainingAllocator.push(T: {s}) -- end", .{@typeName(T)});

        const log2_ptr_align = std.math.log2_int(usize, @as(usize, @alignOf(T)));
        const ptr_align = @as(usize, 1) << @as(std.mem.Allocator.Log2Align, @intCast(log2_ptr_align));
        const adjust_off = std.mem.alignPointerOffset(
            self.current.page.ptr + self.index,
            ptr_align,
        ) orelse return error.oom;
        const adjusted_index = self.index + adjust_off;

        const size = @sizeOf(T);
        const new_index = adjusted_index + size;

        if (new_index > self.current.page.len) {
            std.log.debug(
                "  -- too big for current page -- new_index: {d}",
                .{new_index},
            );

            if (self.current.next) |next| {
                std.log.debug(
                    "  -- already have a next node",
                    .{},
                );

                self.current = next;
            } else {
                std.log.debug(
                    "  -- don't have next node; making one",
                    .{},
                );

                const next_node = try self.metadata.push(Node);
                const page = try makePage();
                next_node.* = .{ .page = page };

                self.current.next = next_node;
                self.current = next_node;
            }

            self.index = 0;

            const offset = std.mem.alignPointerOffset(
                self.current.page.ptr,
                ptr_align,
            ) orelse return error.oom;

            const ptr: *T = @ptrCast(@alignCast(self.current.page.ptr + offset));
            ptr.* = undefined;
            return ptr;
        } else {
            std.log.debug(
                "  -- fits in current page",
                .{},
            );

            self.index = new_index;

            const ptr: *T = @ptrCast(@alignCast(self.current.page.ptr + adjusted_index));
            ptr.* = undefined;
            return ptr;
        }
    }

    pub fn getMarker(self: *ChainingAllocator) Marker {
        return .{
            .node = self.current,
            .index = self.index,
        };
    }

    pub fn clearTo(self: *ChainingAllocator, marker: Marker) void {
        std.log.debug("ChainingAllocator.clearTo(...)", .{});

        var next: ?*Node = self.first;
        while (next) |node| : (next = node.next) {
            if (node == marker.node) {
                self.current = node;
                self.index = marker.index;
                break;
            }
        }
    }

    pub fn clear(self: *ChainingAllocator) void {
        std.log.debug("ChainingAllocator.clear()", .{});

        self.current = self.first;
        self.index = 0;
    }
};

pub fn chainingAllocatorTest() !void {
    const Foo = struct {
        a: u32,
        b: f64,
        c: bool,
    };

    var ca = try ChainingAllocator.init();
    defer ca.deinit();

    const foo = try ca.push(Foo);
    foo.* = .{
        .a = 42,
        .b = 36.3,
        .c = true,
    };

    std.debug.print("-- print foo: {d} {d} {}\n", .{ foo.a, foo.b, foo.c });

    ca.clear();

    const str = try ca.push([5]u8);
    str.* = "hello".*;

    std.debug.print("-- print str: {s}\n", .{str});

    ca.clear();
    std.debug.print("\n\n", .{});

    const half_a_page = std.mem.page_size / 2;
    const HalfPage = [half_a_page]u8;

    _ = try ca.push(HalfPage);
    _ = try ca.push(HalfPage);
    _ = try ca.push(HalfPage);

    ca.clear();
    std.debug.print("\n\n", .{});

    _ = try ca.push(HalfPage);
    _ = try ca.push(HalfPage);
    _ = try ca.push(HalfPage);

    ca.clear();
    std.debug.print("\n\n", .{});

    _ = try ca.push(HalfPage);
    _ = try ca.push(HalfPage);
    const marker = ca.getMarker();
    _ = try ca.push(HalfPage);

    ca.clearTo(marker);

    _ = try ca.push(HalfPage);
}

// std.heap.MemoryPool(comptime Item: type)

pub const PoolAllocator = struct {
    //
};
