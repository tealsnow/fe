struct Globals { // fields are 16 bit aligned
    surface_size_px: vec2f, // 8 // px
    // _padding: vec2u, // 8
};

@group(0) @binding(0) var<uniform> globals: Globals;

struct Cpu2Vertex {
    @builtin(vertex_index) index: u32,
    // @builtin(instance_index) index: u32,

    @location(0) p0: vec2f,
    @location(1) p1: vec2f,
    @location(2) color: vec4f,
}

struct Vertex2Fragment {
    @builtin(position) position: vec4f,

    // fragment input
    @location(0) color: vec4f,
}

@vertex
fn vsMain(in: Cpu2Vertex) -> Vertex2Fragment {
    var vertices = array<vec2f, 4>(
        vec2f(-1, -1),
        vec2f(-1, 1),
        vec2f(1, -1),
        vec2f(1, 1),
    );

    // dst => destination
    let dst_half_size = (in.p1 - in.p0) / 2;
    let dst_center = (in.p1 + in.p0) / 2;
    let dst_pos = vertices[in.index] * dst_half_size + dst_center;

    var out: Vertex2Fragment;
    out.position = vec4f(
        2 * dst_pos.x / globals.surface_size_px.x - 1,
        -(2 * dst_pos.y / globals.surface_size_px.y - 1),
        0,
        1,
    );
    out.color = in.color;
    return out;
}

@fragment
fn fsMain(in: Vertex2Fragment) -> @location(0) vec4f {
    let rgb = in.color.rgb;
    let a = in.color.a;

    // gamma correction
    // this is an approximation
    let linear_rgb = pow(rgb, vec3f(2.2));

    return vec4f(linear_rgb, a);
}
