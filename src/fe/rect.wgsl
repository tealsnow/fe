struct Globals { // fields are 16 bit aligned
    color: vec4f, // 16
    res: vec2f, // 8

    // _padding: vec2f, // 8
};

@group(0) @binding(0) var<uniform> globals: Globals;

struct VertexInput {
    // @builtin(vertex_index) index: u32,
    @builtin(instance_index) index: u32,

    @location(0) p0: vec2f,
    @location(1) p1: vec2f,
    @location(2) color: vec4f,
}

struct VertexOutput {
    @builtin(position) position: vec4f,

    // fragment input
    @location(0) color: vec4f,
}

@vertex
fn vsMain(in: VertexInput) -> VertexOutput {
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

    var out: VertexOutput;
    out.position = vec4f(
        2 * dst_pos.x / globals.res.x - 1,
        2 * dst_pos.y / globals.res.y - 1,
        0,
        1,
    );
    out.color = in.color;
    return out;
}

@fragment
fn fsMain(in: VertexOutput) -> @location(0) vec4f {
    let color = in.color.rgb * globals.color.rgb;

    // gamma correction
    // this is an approximation
    let linear_color = pow(color, vec3f(2.2));

    let a = mix(globals.color.a, in.color.a, 0.5);
    // let a = in.color.a;

    return vec4f(linear_color, a);
}
