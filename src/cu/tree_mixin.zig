const std = @import("std");
const assert = std.debug.assert;

/// NOTE: field name for this must be `tree`
pub fn TreeMixin(comptime T: type) type {
    return struct {
        const Self = @This();

        children: struct {
            first: ?*T = null,
            last: ?*T = null,
            len: usize = 0,
        } = .{},
        siblings: struct {
            next: ?*T = null,
            prev: ?*T = null,
        } = .{},
        parent: ?*T = null,

        pub fn addChild(self: *Self, child: *T) void {
            const node: *T = @fieldParentPtr("tree", self);
            child.tree.parent = node;

            if (self.children.len == 0) {
                assert(self.children.first == null);
                assert(self.children.last == null);
                self.children = .{
                    .first = child,
                    .last = child,
                    .len = 1,
                };
            } else {
                const last = self.children.last.?;
                assert(last.tree.siblings.next == null);
                last.tree.siblings.next = child;

                child.tree.siblings.prev = last;
                child.tree.siblings.next = null;

                self.children.last = child;
                self.children.len += 1;
            }
        }

        pub fn recurseDepthFirstPreOrder(self: *Self) Recursion {
            const node: *T = @fieldParentPtr("tree", self);

            // if this node has children give the first
            if (node.tree.children.first) |first|
                return .{
                    .next = first,
                    .push_count = 1,
                    .pop_count = 0,
                };

            // otherwise, starting with this node
            // iterate up the tree
            // if the node has a sibling, give it
            var pop_count: u32 = 0;
            var maybe_parent: ?*T = node;
            while (maybe_parent) |parent| : ({
                maybe_parent = parent.tree.parent;
                pop_count += 1;
            }) {
                if (parent.tree.siblings.next) |next| {
                    return .{
                        .next = next,
                        .push_count = 0,
                        .pop_count = pop_count,
                    };
                }
            }

            return .empty;
        }

        pub const Recursion = struct {
            next: ?*T,
            push_count: u32,
            pop_count: u32,

            pub const empty = Recursion{
                .next = null,
                .push_count = 0,
                .pop_count = 0,
            };

            pub fn init(root: *T) Recursion {
                return .{ .next = root, .push_count = 0, .pop_count = 0 };
            }
        };

        pub fn depthFirstPreOrderIterator(self: *Self) DepthFirstPreOrderIterator {
            const node: *T = @fieldParentPtr("tree", self);
            return DepthFirstPreOrderIterator.init(node);
        }

        pub const DepthFirstPreOrderIterator = struct {
            root: *T,
            rec: Recursion = .empty,

            pub fn init(root: *T) DepthFirstPreOrderIterator {
                return .{
                    .root = root,
                    .rec = .init(root),
                };
            }

            pub fn next(self: *DepthFirstPreOrderIterator) ?*T {
                const result = self.rec.next orelse return null;
                self.rec = result.tree.recurseDepthFirstPreOrder();
                return result;
            }

            pub fn reset(self: *DepthFirstPreOrderIterator) void {
                self.* = .init(self.root);
            }
        };

        pub fn childIterator(self: *Self) ChildIterator {
            const node: *T = @fieldParentPtr("tree", self);
            return .init(node);
        }

        pub const ChildIterator = struct {
            parent: *T,
            next_child: ?*T,

            pub fn init(parent: *T) ChildIterator {
                return .{
                    .parent = parent,
                    .next_child = parent.tree.children.first,
                };
            }

            pub fn next(self: *ChildIterator) ?*T {
                if (self.next_child) |child| {
                    self.next_child = child.tree.siblings.next;
                    return child;
                }
                return null;
            }

            pub fn reset(self: *ChildIterator) void {
                self.* = .init(self.parent);
            }
        };

        pub fn parentIterator(self: *Self) ParentIterator {
            const node: *T = @fieldParentPtr("tree", self);
            return .init(node);
        }

        pub const ParentIterator = struct {
            start: *T,
            next_node: ?*T,

            pub fn init(start: *T) ParentIterator {
                return .{
                    .start = start,
                    .next_node = start,
                };
            }

            pub fn next(self: *ParentIterator) ?*T {
                if (self.next_node) |node| {
                    self.next_node = node.tree.parent;
                    return node;
                }
                return null;
            }

            pub fn reset(self: *ParentIterator) void {
                self.* = .init(self.start);
            }
        };
    };
}
