const std = @import("std");
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const assert = std.debug.assert;

const fontconfig = @import("../fontconfig.zig");
const sdl = @import("../sdl/sdl.zig");

pub const layout = @import("layout.zig");

pub const GlobalState = struct {
    current_frame_index: u64 = 0,

    renderer: *sdl.Renderer,
    font: *sdl.ttf.Font,

    alloc_temp: Allocator,
    // widget_alloc: Allocator,
    alloc_persistent: Allocator,

    widget_pool: WidgetPool,
    widget_stack: WidgetStack = .{},
    widget_map: WidgetMap = .{},

    pub const MaxWidgets = 1024 * 4;

    pub const WidgetPool = std.heap.MemoryPoolExtra(Widget, .{ .growable = false });
    pub const WidgetStack = std.ArrayListUnmanaged(*Widget);
    pub const WidgetMap = std.ArrayHashMapUnmanaged(
        Key,
        *Widget,
        Key.KeyContext,
        false,
    );

    // widget_map: std.HashMapUnmanaged(
    //     Key,
    //     *Widget,
    //     Key.KeyContext,
    //     80,
    // ) = .{},

    // pub fn deinit(self: *GlobalState) void {
    //     var it = self.widget_map.valueIterator();
    //     while (it.next()) |widget| {
    //         freeWidgetWithChildrenAndPrevHashes(widget.*);
    //     }

    //     self.parent_stack.deinit(self.widget_alloc);
    //     self.widget_map.deinit(self.persistent_alloc);
    // }

    inline fn allocWidget(self: *GlobalState) *Widget {
        return self.widget_pool.create() catch @panic("oom");
    }

    inline fn pushParent(self: *GlobalState, widget: *Widget) void {
        self.widget_stack.append(self.alloc_persistent, widget) catch @panic("oom");
    }

    inline fn popParent(self: *GlobalState) *Widget {
        return self.widget_stack.pop();
    }

    inline fn currentParent(self: *GlobalState) ?*Widget {
        return self.widget_stack.getLastOrNull();
    }
};

pub var gs: GlobalState = undefined;

pub fn Vec2(comptime T: type) type {
    return extern union {
        vec: extern struct {
            x: T,
            y: T,
        },
        arr: [2]T,

        pub const Zero = std.mem.zeroes(@This());
    };
}

pub fn vec2(comptime T: type, x: T, y: T) Vec2(T) {
    return .{ .arr = .{ x, y } };
}

pub const AxisKind = enum(u2) {
    x = 0,
    y,
    none = std.math.maxInt(u2),

    pub const Array = [2]AxisKind{ .x, .y };
};

pub fn Axis2(comptime T: type) type {
    return extern union {
        vec: extern struct {
            x: T,
            y: T,
        },
        sz: extern struct {
            w: T,
            h: T,
        },
        arr: [2]T,

        pub const Zero = std.mem.zeroes(@This());
    };
}

pub fn axis2(comptime T: type, x: T, y: T) Axis2(T) {
    return .{ .arr = .{ x, y } };
}

pub fn Range2(comptime T: type) type {
    return extern union {
        minmax: extern struct {
            min: Vec2(T),
            max: Vec2(T),
        },
        pt: extern struct {
            p0: Vec2(T),
            p1: Vec2(T),
        },
        vec: extern struct {
            x0: T,
            y0: T,
            x1: T,
            y1: T,
        },
        arr: [2]Vec2(T),
        // parr: [4]T,
        // pmat: [2][2]T,

        pub const Zero = std.mem.zeroes(@This());
    };
}

pub fn range2(comptime T: type, p0: Vec2(T), p1: Vec2(T)) Range2(T) {
    return .{ .arr = .{ p0, p1 } };
}

pub const SizeKind = enum(u8) {
    none,
    pixels, // value px
    percent_of_parent, // value %
    text_content,
    children_sum,
};

pub const Size = extern struct {
    kind: SizeKind = .none,
    /// pixels* px, percents_of_parent* %, children_sum!, text_content!
    value: f32 = 0,
    /// what percent of final size do we refuse to give up
    strictness: f32 = 0,

    /// kind: percent_of_parent
    /// value: 1
    /// strictness: 0
    pub const grow = percent_relaxed(1);

    /// kind: children_sum
    pub const sum = Size{ .kind = .children_sum };

    /// kind: text_content
    pub const text = Size{ .kind = .text_content };

    /// kind: pixels
    /// value: pxs
    /// strictness: 1
    pub fn px(pxs: f32) Size {
        return .{
            .kind = .pixels,
            .value = pxs,
            .strictness = 1,
        };
    }

    /// kind: pixels
    /// value: px
    /// strictness: 0
    pub fn px_relaxed(pxs: f32) Size {
        return .{
            .kind = .pixels,
            .value = pxs,
            .strictness = 0,
        };
    }

    /// kind: percent_of_parent
    /// value: pct
    /// strictness: 1
    pub fn percent(pct: f32) Size {
        return .{
            .kind = .percent_of_parent,
            .value = pct,
            .strictness = 1,
        };
    }

    /// kind: percent_of_parent
    /// value: pct
    /// strictness: 0
    pub fn percent_relaxed(pct: f32) Size {
        return .{
            .kind = .percent_of_parent,
            .value = pct,
            .strictness = 0,
        };
    }
};

pub const Key = enum(u32) {
    _,

    pub const Zero: Key = @enumFromInt(0);

    pub const KeyContext = struct {
        pub fn hash(self: @This(), key: Key) u32 {
            _ = self;
            return @intFromEnum(key);
        }

        // pub fn eql(self: @This(), left: Key, right: Key) bool {
        //     _ = self;
        //     return Key.eql(left, right);
        // }
        pub fn eql(self: @This(), a: Key, b: Key, b_index: usize) bool {
            _ = self;
            _ = b_index;
            return Key.eql(a, b);
        }
    };

    pub fn eql(left: Key, right: Key) bool {
        return @intFromEnum(left) == @intFromEnum(right);
    }

    pub fn processString(
        string: []const u8,
    ) struct {
        string: []const u8,
        key: Key,
    } {
        // hash whole string, only display before '##'
        const two_hash = "##";
        // only hash after '###', only display before '###'
        const three_hash = "###";
        // or just hash the string

        return if (std.mem.indexOf(u8, string, two_hash)) |index| blk: {
            const hash = std.array_hash_map.hashString(string);

            const str = string[0..index];
            break :blk .{
                .string = str,
                .key = @enumFromInt(hash),
            };
        } else if (std.mem.indexOf(u8, string, three_hash)) |index| blk: {
            const slice = string[(index + three_hash.len)..];
            const hash = std.array_hash_map.hashString(slice);

            const str = string[0..index];
            break :blk .{
                .string = str,
                .key = @enumFromInt(hash),
            };
        } else blk: {
            const hash = std.array_hash_map.hashString(string);

            break :blk .{
                .string = string,
                .key = @enumFromInt(hash),
            };
        };
    }
};

pub const Widget = struct {
    // tree links
    children: ?struct {
        first: *Widget,
        last: *Widget,
        count: u32,
    } = null,
    siblings: struct {
        next: ?*Widget = null,
        prev: ?*Widget = null,
    } = .{},
    parent: ?*Widget = null,

    // // hash links
    // hash_next: ?*Widget = null,
    // hash_prev: ?*Widget = null,

    // key+generation info
    key: Key,
    first_frame_touched: u64,
    last_frame_touched: u64,

    string: []const u8, // not guaranteed to be valid across frames
    text_data: ?TextData = null, // not guaranteed to be valid across frames
    color: sdl.Color = .{},

    layout_axis: AxisKind = .none,
    size: Axis2(Size) = Axis2(Size).Zero,

    // recomputed every frame
    fixed_size: Axis2(f32) = Axis2(f32).Zero,
    rel_position: Axis2(f32) = Axis2(f32).Zero,
    rect: Range2(f32) = Range2(f32).Zero,
    view_bounds: Axis2(f32) = Axis2(f32).Zero,

    // // @FIXME: not sure if this is the right thing for the moment
    // pub fn deinit(self: *Widget) void {
    //     self.hash_prev = null;
    //     // if (self.children) |children| {
    //     //     var maybe_child: ?*Widget = children.first;
    //     //     while (maybe_child) |child| : (maybe_child = child.siblings.next)
    //     //         child.deinit();
    //     // }

    //     if (self.text_data) |data| data.deinit();
    // }

    // pub const Nil = Widget{
    //     .key = Key.Zero,
    //     .last_frame_touched = 0,
    //     .string = "",
    // };

    // pub fn isNil(self: *Widget) bool {
    //     return self.key == Key.Zero and
    //         self.last_frame_touched == 0 and
    //         self.string.len == 0;
    // }
};

pub const TextData = struct {
    zstring: [:0]const u8, // @Icky
    surface: *sdl.Surface,
    texture: *sdl.Texture,
    size: Axis2(f32),

    pub fn init(text: []const u8) !TextData {
        const zstring = try gs.alloc_persistent.allocSentinel(u8, text.len, 0);
        @memcpy(zstring[0..text.len], text[0..]);

        const font_color = sdl.Color{ .r = 255, .g = 255, .b = 255, .a = 255 };
        const surface = try gs.font.renderTextSolid(zstring, font_color);
        defer surface.deinit();

        const texture = try gs.renderer.createTextureFromSurface(surface);
        defer texture.deinit();

        var w: c_int = 0;
        var h: c_int = 0;
        try texture.query(null, null, &w, &h);

        const size = axis2(f32, @floatFromInt(w), @floatFromInt(h));

        return .{
            .zstring = zstring,
            .surface = surface,
            .texture = texture,
            .size = size,
        };
    }

    pub fn deinit(self: TextData) void {
        defer gs.alloc_persistent.free(self.zstring);
        defer self.surface.deinit();
        defer self.texture.deinit();
    }
};

// pub fn widgetMakeF(comptime fmt: []const u8, args: anytype) *Widget {
//     const string = std.fmt.allocPrint(gs.widget_alloc, fmt, args) catch @panic("oom");
//     return widgetMake(string);
// }

// fn doHash(widget: *Widget) void {
//     const prev_hash = gs.widget_map.fetchPut(
//         gs.persistent_alloc,
//         widget.key,
//         widget,
//     ) catch @panic("oom");

//     if (prev_hash) |prev_kv| {
//         const prev = prev_kv.value;
//         widget.hash_prev = prev;
//         prev.hash_next = widget;
//     }
// }

pub fn widgetFromKey(key: Key) ?*Widget {
    if (!key.eql(Key.Zero)) {
        if (gs.widget_map.get(key)) |widget| {
            return widget;
        }
    }
    return null;
}

pub fn buildWidgetFromKey(key: Key) *Widget {
    // gs.build_widget_count +%= 1; // wrapping add

    const widget = if (widgetFromKey(key)) |widget|
        widget
    else blk: {
        const widget = gs.allocWidget();
        widget.first_frame_touched = gs.current_frame_index;

        gs.widget_map.put(gs.alloc_persistent, key, widget) catch @panic("oom");

        break :blk widget;
    };

    widget.parent = null;
    widget.siblings.next = null;
    widget.siblings.prev = null;
    widget.children = null;

    if (gs.currentParent()) |parent| {
        widget.parent = parent;

        if (parent.children) |*children| {
            const last = children.last;
            last.siblings.next = widget;
            widget.siblings.prev = last;

            children.last = widget;

            children.count += 1;
        } else {
            parent.children = .{
                .first = widget,
                .last = widget,
                .count = 1,
            };
        }
    }

    widget.key = key;
    widget.last_frame_touched = gs.current_frame_index;

    return widget;
}

pub fn buildWidgetFromString(string: []const u8) *Widget {
    const key_str = Key.processString(string);

    const widget = buildWidgetFromKey(key_str.key);
    const str = gs.alloc_persistent.dupe(u8, key_str.string) catch @panic("oom");
    widget.string = str;

    return widget;
}

pub fn buildWidgetFromStringF(comptime fmt: []const u8, args: anytype) *Widget {
    const string = std.fmt.allocPrint(gs.alloc_persistent, fmt, args) catch @panic("oom");
    defer gs.alloc_persistent.free(string);

    return buildWidgetFromString(string);
}

// // @TODO: add flags
// pub fn widgetMake(string: []const u8) *Widget {
//     const parent = gs.currentParent();
//     const key_str = Key.processString(string);

//     const widget = if (gs.widget_map.get(key_str.key)) |widget| blk: {
//         widget.last_frame_touched = gs.current_frame_index;
//         widget.parent = parent;
//         widget.siblings.next = null;
//         widget.siblings.prev = null;
//         widget.children = null;
//         break :blk widget;
//     } else blk: {
//         const widget = gs.allocWidget();
//         widget.* = .{
//             .parent = parent,
//             .key = key_str.key,
//             .last_frame_touched = gs.current_frame_index,
//             .first_frame_touched = gs.current_frame_index,
//             .string = key_str.string,
//         };
//         break :blk widget;
//     };

//     if (parent.children) |*children| {
//         const last = children.last;
//         last.siblings.next = widget;
//         widget.siblings.prev = last;

//         children.last = widget;

//         children.count += 1;
//     } else {
//         parent.children = .{
//             .first = widget,
//             .last = widget,
//             .count = 1,
//         };
//     }

//     return widget;
// }

pub fn start(window: *sdl.Window) void {
    const root = buildWidgetFromStringF("###root-window-id-{x}", .{window.getID()});

    const window_size = window.size();
    root.size.sz = .{
        .w = Size.px(@floatFromInt(window_size.w)),
        .h = Size.px(@floatFromInt(window_size.h)),
    };
    root.rect.pt = .{
        .p0 = vec2(f32, 0, 0),
        .p1 = vec2(f32, @floatFromInt(window_size.w), @floatFromInt(window_size.h)),
    };
    root.layout_axis = .x;

    gs.pushParent(root);
}

// fn freeWidgetWithChildrenAndPrevHashes(widget: *Widget) void {
//     var maybe_prev: ?*Widget = widget.hash_prev;
//     while (maybe_prev) |prev| : (maybe_prev = prev.hash_prev) {
//         // prev.deinit();
//         gs.widget_alloc.destroy(prev);
//     }

//     widget.deinit();
//     gs.widget_alloc.destroy(widget);
// }

pub fn end() !*Widget {
    // var it = gs.widget_map.valueIterator();
    // while (it.next()) |widget_ref| {
    //     const widget = widget_ref.*;
    //     if (widget.last_frame_touched < gs.current_frame_index) {
    //         freeWidgetWithChildrenAndPrevHashes(widget);
    //     }
    // }

    // const buffer = gs.alloc_temp.alloc(*Widget, 1024 * 4) catch @panic("oom");
    // defer gs.alloc_temp.free(buffer); // @FIXME: is this needed
    // const free_list = std.ArrayListUnmanaged(*Widget).initBuffer(buffer);

    // var it = gs.widget_map.valueIterator();
    // while (it.next()) |widget_ref| {
    //     const widget = widget_ref.*;
    //     if (widget.last_frame_touched < gs.current_frame_index) {
    //         free_list.appendAssumeCapacity(widget);
    //     }
    // }

    // for (free_list.items) |wdg| {
    //     gs.widget_map.remove(wdg.key);
    //     gs.widget_pool.destroy(wdg);
    // }

    gs.widget_map.lockPointers();
    defer gs.widget_map.unlockPointers();

    for (gs.widget_map.values()) |widget| {
        if (widget.last_frame_touched < gs.current_frame_index or widget.key.eql(Key.Zero)) {
            assert(gs.widget_map.swapRemove(widget.key));

            if (widget.text_data) |data|
                data.deinit();
            if (widget.string.len != 0)
                gs.alloc_persistent.free(widget.string);

            gs.widget_pool.destroy(widget);
        }
    }

    const root = gs.popParent();
    assert(gs.widget_stack.items.len == 0);

    try layout.layout(root);

    gs.current_frame_index +%= 1; // wrapping add

    return root;
}

// pub const OpenHandle = struct {
//     widget: *Widget,

//     pub fn close(self: *const OpenHandle) void {
//         const widget = gs.popParent();
//         assert(std.mem.eql(u8, widget.string, self.widget.string));
//     }
// };

pub const OpenOpts = struct {
    layout_axis: AxisKind = .none,
    color: sdl.Color = .{ .r = 255, .g = 255, .b = 255, .a = 255 },
    size: Axis2(Size),
};

// pub fn open(string: []const u8, opts: OpenOpts) ?OpenHandle {
//     const widget = widgetMake(string);

//     widget.layout_axis = opts.layout_axis;
//     widget.color = opts.color;
//     widget.size = opts.size;

//     gs.pushParent(widget);

//     return OpenHandle{ .widget = widget };
// }

pub inline fn ui(string: []const u8) ConfigFn {
    gs.pushParent(buildWidgetFromString(string));
    return _config;
}

pub inline fn uif(comptime fmt: []const u8, args: anytype) ConfigFn {
    gs.pushParent(buildWidgetFromStringF(fmt, args));
    return _config;
}

const ConfigFn = fn (OpenOpts) callconv(.Inline) BodyFn;
pub inline fn _config(opts: OpenOpts) BodyFn {
    const widget = gs.currentParent().?;
    widget.layout_axis = opts.layout_axis;
    widget.color = opts.color;
    widget.size = opts.size;
    return _body;
}

const BodyFn = fn (void) callconv(.Inline) void;
pub inline fn _body(_: void) void {
    _ = gs.popParent();
}
