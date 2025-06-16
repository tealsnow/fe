const MenuBar = @This();

context: *anyopaque,
root: []const MenuList,

pub const MenuItem = union(enum) {
    button: MenuButton,
    list: MenuList,
};

pub const MenuButton = struct {
    name: []const u8,
    action: *const fn (*anyopaque) void,
};

pub const MenuList = struct {
    name: []const u8,
    items: []const MenuItem,
};
