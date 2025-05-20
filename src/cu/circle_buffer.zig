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
