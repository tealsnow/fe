struct Globals { // fields are 16 bit aligned
    surface_size_px: vec2f, // 8 // px
    // _padding: vec2u, // 8
};

@group(0) @binding(0) var<uniform> globals: Globals;

// struct Cpu2Vertex {
//     @builtin(vertex_index) index: u32,
//     // @builtin(instance_index) index: u32,
//
//     @location(0) p0: vec2f,
//     @location(1) p1: vec2f,
//     @location(2) color: vec4f,
// }

struct RectInstance {
    @builtin(vertex_index) index: u32,
    @builtin(instance_index) i_index: u32,

    @location(0) p0: vec2f,
    @location(1) p1: vec2f,
    @location(2) color: vec4f,
}

struct Vertex2Fragment {
    @builtin(position) position: vec4f,

    // fragment input
    @location(0) color: vec4f,
}

// struct InstanceData {
//     // @builtin(instance_index) index: u32,
//
//     @location(3) _unused: u32,
// }

// @group(0) @binding(1) var<storage> instance_buffer: array<RectInstance>;

@vertex
// fn vsMain(in: Cpu2Vertex) -> Vertex2Fragment {
fn vsMain(
    // @builtin(vertex_index) vertex_index: u32,
    // @builtin(instance_index) instance_index: u32,
    in: RectInstance,
    @location(3) instance_data: u32,
    // @location(1) instance_data: InstanceData,
) -> Vertex2Fragment {
    var vertices = array<vec2f, 4>(
        vec2f(-1, -1),
        vec2f(-1, 1),
        vec2f(1, -1),
        vec2f(1, 1),
    );

    var colors = array<vec4f, 4>(
        vec4f(1.0, 0.0, 0.0, 1.0),
        vec4f(0.0, 1.0, 0.0, 1.0),
        vec4f(0.0, 0.0, 1.0, 1.0),
        vec4f(1.0, 1.0, 1.0, 1.0),
    );

    // let in = instance_buffer[vertex_index];

    // dst => destination
    let dst_half_size = (in.p1 - in.p0) / 2;
    let dst_center = (in.p1 + in.p0) / 2;
    // let dst_pos = vertices[in.index] * dst_half_size + dst_center;
    // let dst_pos = vertices[instance_index] * dst_half_size + dst_center;
    // let dst_pos = vertices[instance_data.index] * dst_half_size + dst_center;
    let dst_pos = vertices[instance_data] * dst_half_size + dst_center;

    var out: Vertex2Fragment;
    out.position = vec4f(
        2 * dst_pos.x / globals.surface_size_px.x - 1,
        -(2 * dst_pos.y / globals.surface_size_px.y - 1),
        0,
        1,
    );
    // out.color = in.color;
    // out.color = colors[in.index];
    // out.color = colors[in.i_index];
    out.color = colors[instance_data];
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
