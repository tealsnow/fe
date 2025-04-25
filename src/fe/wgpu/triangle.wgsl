struct Globals { // fields are 16 bit aligned
    surface_size_px: vec2f, // 8
    // _padding: vec2f, // 8
};

@group(0) @binding(0) var<uniform> globals: Globals;

struct VertexInput {
    // @builtin(vertex_index) index: u32,

    @location(0) position: vec2f,
    @location(1) color: vec4f,
}

struct VertexOutput {
    @builtin(position) position: vec4f,

    // fragment input
    @location(0) color: vec4f,
}

@vertex
fn vsMain(in: VertexInput) -> VertexOutput {
    var out: VertexOutput;
    let ratio = globals.surface_size_px.x / globals.surface_size_px.y;
    out.position = vec4f(in.position.x, in.position.y * ratio, 0.0, 1.0);
    out.color = in.color;
    return out;
}

@fragment
fn fsMain(in: VertexOutput) -> @location(0) vec4f {
    let rgb = in.color.rgb;
    let a = in.color.a;

    // gamma correction
    // this is an approximation
    let linear_rgb = pow(rgb, vec3f(2.2));

    return vec4f(linear_rgb, a);
}
