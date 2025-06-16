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
