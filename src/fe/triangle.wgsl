struct Globals { // fields are 16 bit aligned
    color: vec4f, // 16
    res: vec2f, // 8

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
    // let ratio = 1024.0 / 576.0;
    let ratio = globals.res.x / globals.res.y;
    out.position = vec4f(in.position.x, in.position.y * ratio, 0.0, 1.0);
    out.color = in.color;
    return out;
}

@fragment
fn fsMain(in: VertexOutput) -> @location(0) vec4f {
    let color = in.color.rgb * globals.color.rgb;

    // gamma correction
    // this is an approximation
    let linear_color = pow(color, vec3f(2.2));

    // let a = lerp(globals.color.a, in.color.a);
    let a = in.color.a;

    return vec4f(linear_color, a);
}
