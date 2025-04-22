struct Globals { // fields are 16 bit aligned
    surface_size_px: vec2f, // 8 // px
    // _padding: vec2u, // 8
};

@group(0) @binding(0) var<uniform> globals: Globals;

struct Cpu2Vertex {
    // instance data
    @location(0) p0: vec2f,
    @location(1) p1: vec2f,
    @location(2) color: vec4f,

    // vertex data
    @builtin(vertex_index) index: u32,
}

struct Vertex2Fragment {
    @builtin(position) position: vec4f,

    // fragment input
    @location(0) color: vec4f,
}

@vertex
// fn vsMain(in: Cpu2Vertex) -> Vertex2Fragment {
fn vsMain(in: Cpu2Vertex) -> Vertex2Fragment {
    // This could easily be provided by the vertex buffer
    var corners = array<vec2f, 4>(
        vec2f(-1, -1),
        vec2f(-1, 1),
        vec2f(1, -1),
        vec2f(1, 1),
    );

    let dst_center = (in.p0 + in.p1) * 0.5;
    let dst_half_size = (in.p1 - in.p0) * 0.5;
    let corner = corners[in.index];
    let dst_pos = dst_center + corner * dst_half_size;

    let ndc = (dst_pos / globals.surface_size_px) - 1;
    let flipped_ndc = vec2f(ndc.x, -ndc.y); // flip y

    var out: Vertex2Fragment;
    out.position = vec4f(flipped_ndc, 0, 1);
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
