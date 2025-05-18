/// Will be faster (if only marginal) with a power of 2 Size
///
/// This has no checking for overwriting
pub fn EventQueueCircleBuffer(comptime size: usize, comptime T: type) type {
    return struct {
        buffer: [size]T,
        head: usize,
        tail: usize,

        const Self = @This();

        pub const empty = Self{
            .buffer = undefined,
            .head = 0,
            .tail = 0,
        };

        pub fn queue(self: *Self, item: T) void {
            self.buffer[self.head] = item;
            self.head = (self.head + 1) % size;
        }

        pub fn dequeue(self: *Self) ?T {
            if (self.tail == self.head) return null;

            const item = self.buffer[self.tail];
            self.tail = (self.tail + 1) % size;
            return item;
        }

        pub fn indexBack(self: *const Self, i: usize) ?T {
            const tail = (self.tail + i) % size;
            if (tail == self.head) return null;
            return self.buffer[tail];
        }

        pub fn count(self: *Self) usize {
            return (self.head -% self.tail +% size) % size;
        }
    };
}

pub fn CircleBuffer(comptime size: usize, Elem: type) type {
    return struct {
        buffer: [size]Elem,
        head: usize,
        count: usize,

        const Self = @This();

        pub const empty = Self{
            .buffer = undefined,
            .head = 0,
            .count = 0,
        };

        pub fn push(self: *Self, value: Elem) void {
            self.buffer[self.head] = value;
            self.head = (self.head + 1) % size;
            self.count = @min(self.count + 1, size);
        }

        pub fn indexBack(self: Self, idx: usize) ?Elem {
            if (idx >= self.count) {
                @branchHint(.unlikely);
                return null;
            }

            const pos = (self.head + size - 1 - idx) % size;
            return self.buffer[pos];
        }

        pub fn slice(self: *Self) []Elem {
            return self.buffer[0..self.count];
        }
    };
}
