const c = @cImport({
    @cInclude("SDL3/SDL_pixels.h");
});

pub const Color = extern struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8,
};

pub const PixelFormat = enum(c_uint) {
    unknown = c.SDL_PIXELFORMAT_UNKNOWN,
    index1lsb = c.SDL_PIXELFORMAT_INDEX1LSB,
    index1msb = c.SDL_PIXELFORMAT_INDEX1MSB,
    index2lsb = c.SDL_PIXELFORMAT_INDEX2LSB,
    index2msb = c.SDL_PIXELFORMAT_INDEX2MSB,
    index4lsb = c.SDL_PIXELFORMAT_INDEX4LSB,
    index4msb = c.SDL_PIXELFORMAT_INDEX4MSB,
    index8 = c.SDL_PIXELFORMAT_INDEX8,
    rgb332 = c.SDL_PIXELFORMAT_RGB332,
    xrgb4444 = c.SDL_PIXELFORMAT_XRGB4444,
    xbgr4444 = c.SDL_PIXELFORMAT_XBGR4444,
    xrgb1555 = c.SDL_PIXELFORMAT_XRGB1555,
    xbgr1555 = c.SDL_PIXELFORMAT_XBGR1555,
    argb4444 = c.SDL_PIXELFORMAT_ARGB4444,
    rgba4444 = c.SDL_PIXELFORMAT_RGBA4444,
    abgr4444 = c.SDL_PIXELFORMAT_ABGR4444,
    bgra4444 = c.SDL_PIXELFORMAT_BGRA4444,
    argb1555 = c.SDL_PIXELFORMAT_ARGB1555,
    rgba5551 = c.SDL_PIXELFORMAT_RGBA5551,
    abgr1555 = c.SDL_PIXELFORMAT_ABGR1555,
    bgra5551 = c.SDL_PIXELFORMAT_BGRA5551,
    rgb565 = c.SDL_PIXELFORMAT_RGB565,
    bgr565 = c.SDL_PIXELFORMAT_BGR565,
    rgb24 = c.SDL_PIXELFORMAT_RGB24,
    bgr24 = c.SDL_PIXELFORMAT_BGR24,
    xrgb8888 = c.SDL_PIXELFORMAT_XRGB8888,
    rgbx8888 = c.SDL_PIXELFORMAT_RGBX8888,
    xbgr8888 = c.SDL_PIXELFORMAT_XBGR8888,
    bgrx8888 = c.SDL_PIXELFORMAT_BGRX8888,
    argb8888 = c.SDL_PIXELFORMAT_ARGB8888,
    rgba8888 = c.SDL_PIXELFORMAT_RGBA8888,
    abgr8888 = c.SDL_PIXELFORMAT_ABGR8888,
    bgra8888 = c.SDL_PIXELFORMAT_BGRA8888,
    argb2101010 = c.SDL_PIXELFORMAT_ARGB2101010,
    // rgba32 = c.SDL_PIXELFORMAT_RGBA32,
    // argb32 = c.SDL_PIXELFORMAT_ARGB32,
    // bgra32 = c.SDL_PIXELFORMAT_BGRA32,
    // abgr32 = c.SDL_PIXELFORMAT_ABGR32,
    // rgbx32 = c.SDL_PIXELFORMAT_RGBX32,
    // xrgb32 = c.SDL_PIXELFORMAT_XRGB32,
    // bgrx32 = c.SDL_PIXELFORMAT_BGRX32,
    // xbgr32 = c.SDL_PIXELFORMAT_XBGR32,
    yv12 = c.SDL_PIXELFORMAT_YV12,
    iyuv = c.SDL_PIXELFORMAT_IYUV,
    yuy2 = c.SDL_PIXELFORMAT_YUY2,
    uyvy = c.SDL_PIXELFORMAT_UYVY,
    yvyu = c.SDL_PIXELFORMAT_YVYU,
    nv12 = c.SDL_PIXELFORMAT_NV12,
    nv21 = c.SDL_PIXELFORMAT_NV21,
    external_oes = c.SDL_PIXELFORMAT_EXTERNAL_OES,

    pub fn pixelType(self: PixelFormat) PixelType {
        return @enumFromInt(c.SDL_PIXELTYPE(@intFromEnum(self)));
    }

    pub fn pixelOrder(self: PixelFormat) PixelOrder {
        return @bitCast(c.SDL_PIXELORDER(@intFromEnum(self)));
    }

    pub fn pixelLayout(self: PixelFormat) PackedLayout {
        return @enumFromInt(c.SDL_PIXELLAYOUT(@intFromEnum(self)));
    }

    pub fn bitsPerPixel(self: PixelFormat) c_int {
        return c.SDL_BITSPERPIXEL(@intFromEnum(self));
    }

    pub fn bytesPerPixel(self: PixelFormat) c_int {
        return c.SDL_BYTESPERPIXEL(@intFromEnum(self));
    }

    pub fn isIndexed(self: PixelFormat) bool {
        return c.SDL_ISPIXELFORMAT_INDEXED(@intFromEnum(self));
    }

    pub fn isAlpha(self: PixelFormat) bool {
        return c.SDL_ISPIXELFORMAT_ALPHA(@intFromEnum(self));
    }

    pub fn isFourcc(self: PixelFormat) bool {
        return c.SDL_ISPIXELFORMAT_FOURCC(@intFromEnum(self));
    }
};

pub const PixelType = enum(c_uint) {
    unknown = c.SDL_PIXELTYPE_UNKNOWN,
    index1 = c.SDL_PIXELTYPE_INDEX1,
    index4 = c.SDL_PIXELTYPE_INDEX4,
    index8 = c.SDL_PIXELTYPE_INDEX8,
    packed8 = c.SDL_PIXELTYPE_PACKED8,
    packed16 = c.SDL_PIXELTYPE_PACKED16,
    packed32 = c.SDL_PIXELTYPE_PACKED32,
    arrayu8 = c.SDL_PIXELTYPE_ARRAYU8,
    arrayu16 = c.SDL_PIXELTYPE_ARRAYU16,
    arrayu32 = c.SDL_PIXELTYPE_ARRAYU32,
    arrayf16 = c.SDL_PIXELTYPE_ARRAYF16,
    arrayf32 = c.SDL_PIXELTYPE_ARRAYF32,
    index2 = c.SDL_PIXELTYPE_INDEX2,
};

pub const BitmapPixelOrder = enum(c_uint) {
    none = c.SDL_BITMAPORDER_NONE,
    @"4321" = c.SDL_BITMAPORDER_4321,
    @"1234" = c.SDL_BITMAPORDER_1234,
};

pub const PackedPixelOrder = enum(c_uint) {
    none = c.SDL_PACKEDORDER_NONE,
    xrgb = c.SDL_PACKEDORDER_XRGB,
    rgbx = c.SDL_PACKEDORDER_RGBX,
    argb = c.SDL_PACKEDORDER_ARGB,
    rgba = c.SDL_PACKEDORDER_RGBA,
    xbgr = c.SDL_PACKEDORDER_XBGR,
    bgrx = c.SDL_PACKEDORDER_BGRX,
    abgr = c.SDL_PACKEDORDER_ABGR,
    bgra = c.SDL_PACKEDORDER_BGRA,
};

pub const ArrayPixelOrder = enum(c_uint) {
    none = c.SDL_ARRAYORDER_NONE,
    rgb = c.SDL_ARRAYORDER_RGB,
    rgba = c.SDL_ARRAYORDER_RGBA,
    argb = c.SDL_ARRAYORDER_ARGB,
    bgr = c.SDL_ARRAYORDER_BGR,
    bgra = c.SDL_ARRAYORDER_BGRA,
    abgr = c.SDL_ARRAYORDER_ABGR,
};

pub const PixelOrder = extern union {
    bitmap: BitmapPixelOrder,
    @"packed": PackedPixelOrder,
    array: ArrayPixelOrder,
};

pub const PackedLayout = enum(c_uint) {
    none = c.SDL_PACKEDLAYOUT_NONE,
    @"332" = c.SDL_PACKEDLAYOUT_332,
    @"4444" = c.SDL_PACKEDLAYOUT_4444,
    @"1555" = c.SDL_PACKEDLAYOUT_1555,
    @"5551" = c.SDL_PACKEDLAYOUT_5551,
    @"565" = c.SDL_PACKEDLAYOUT_565,
    @"8888" = c.SDL_PACKEDLAYOUT_8888,
    @"2101010" = c.SDL_PACKEDLAYOUT_2101010,
    @"1010102" = c.SDL_PACKEDLAYOUT_1010102,
};

pub const TextureAccess = enum(c_uint) {
    static = c.SDL_TEXTUREACCESS_STATIC,
    streaming = c.SDL_TEXTUREACCESS_STREAMING,
    target = c.SDL_TEXTUREACCESS_TARGET,
};
