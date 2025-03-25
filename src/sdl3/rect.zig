pub const Rect = extern struct {
    x: c_int,
    y: c_int,
    w: c_int,
    h: c_int,
};

pub const FRect = extern struct {
    x: f32,
    y: f32,
    w: f32,
    h: f32,
};
