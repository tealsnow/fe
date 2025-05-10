/*
 * Rectangle drawing
 */

//= Type definitions

struct Cpu2Vertex {
    //- instance data
    @location(0) dst_p0: vec2f, // top left corner on screen
    @location(1) dst_p1: vec2f, // bottom right corner on screen

    @location(2) tex_p0: vec2f, // top left corner on texture
    @location(3) tex_p1: vec2f, // bottom right corner on texture

    @location(4) color: vec4f,

    //- vertex data
    @builtin(vertex_index) index: u32,
}

struct Vertex2Fragment {
    @builtin(position) position: vec4f,

    // fragment input
    @location(0) uv: vec2f,
    @location(1) color: vec4f,
}

//= bindings

@group(0) @binding(0) var<uniform> surface_size_px: vec2f;
@group(0) @binding(1) var atlas_texture: texture_2d<f32>;
@group(0) @binding(2) var atlas_sampler: sampler;

//= vertex

@vertex
fn vsMain(in: Cpu2Vertex) -> Vertex2Fragment {
    // This could easily be provided by the vertex buffer
    // This is a var to allow for runtime indexing
    var corners = array<vec2f, 4>(
        vec2f(-1, -1),
        vec2f(-1, 1),
        vec2f(1, -1),
        vec2f(1, 1),
    );

    //- position rect

    let dst_half_size = (in.dst_p1 - in.dst_p0) * 0.5;
    let dst_center = (in.dst_p1 + in.dst_p0) * 0.5;
    let dst_pos = corners[in.index] * dst_half_size + dst_center;

    let ndc = (dst_pos / surface_size_px) - 1;
    let flipped_ndc = vec2f(ndc.x, -ndc.y); // flip y

    //- position texture

    let tex_half_size = (in.tex_p1 - in.tex_p0) * 0.5;
    let tex_center = (in.tex_p1 + in.tex_p0) * 0.5;
    let tex_pos = corners[in.index] * tex_half_size + tex_center;

    let atlas_dims = textureDimensions(atlas_texture).xy;
    let atlas_size = vec2f(f32(atlas_dims.x), f32(atlas_dims.y));
    let tex_uv = tex_pos / atlas_size;

    //- fill output

    var out: Vertex2Fragment;

    out.position = vec4f(flipped_ndc, 0, 1);
    out.uv = tex_uv;
    out.color = in.color;

    return out;
}

//= fragment

@fragment
fn fsMain(in: Vertex2Fragment) -> @location(0) vec4f {
    let sample = textureSample(atlas_texture, atlas_sampler, in.uv);

    let srgb = in.color.rgb;
    let a = in.color.a;

    // gamma correction
    // this is an approximation
    let linear_rgb = pow(srgb, vec3f(2.2));

    return vec4f(linear_rgb * sample.rgb, a * sample.a);
}
