/*
 * Rectangle drawing
 */

//= types 

struct Cpu2Vertex {
    //- instance data
    @location(0) dst_p0: vec2f, // top left corner on screen
    @location(1) dst_p1: vec2f, // bottom right corner on screen

    @location(2) tex_p0: vec2f, // top left corner on texture
    @location(3) tex_p1: vec2f, // bottom right corner on texture

    @location(4) color: vec4f,

    @location(5) corner_radius: f32,
    @location(6) edge_softness: f32,

    @location(7) border_thickness: f32,

    //- vertex data
    @builtin(vertex_index) index: u32,
}

struct Vertex2Fragment {
    @builtin(position) position: vec4f,

    // fragment input
    @location(0) uv: vec2f,
    @location(1) color: vec4f,

    @location(2) dst_pos: vec2f,
    @location(3) dst_center: vec2f,
    @location(4) dst_half_size: vec2f,

    @location(5) corner_radius: f32,
    @location(6) edge_softness: f32,

    @location(7) border_thickness: f32,
}

//= bindings

@group(0) @binding(0) var<uniform> surface_size_px: vec2f;

@group(1) @binding(0) var atlas_texture: texture_2d<f32>;
@group(1) @binding(1) var atlas_sampler: sampler;

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

    out.dst_pos = dst_pos;
    out.dst_center = dst_center;
    out.dst_half_size = dst_half_size;

    out.corner_radius = in.corner_radius;
    out.edge_softness = in.edge_softness;

    out.border_thickness = in.border_thickness;

    return out;
}

//= fragment

@fragment
fn fsMain(in: Vertex2Fragment) -> @location(0) vec4f {
    //- rounding / drop shadows

    // we need to shrink the rectangle's half-size
    // that is used for distance calculations with
    // the edge softness - otherwise the underlying
    // primitive will cut off the falloff too early.
    let softness = in.edge_softness;
    let softness_padding = vec2f(
        max(0f, softness * 2f - 1f),
        max(0f, softness * 2f - 1f),
    );

    // sample distance
    let dist = roundedRectSDF(
        in.dst_pos,
        in.dst_center,
        in.dst_half_size - softness_padding,
        in.corner_radius,
    );

    // map distance => a blend color
    let sdf_factor = 1f - smoothstep(0f, 2f * softness, dist);

    //- hollow rects / border thickness
    var border_factor = 1f;
    if (in.border_thickness != 0f) {
        let interior_half_size =
            in.dst_half_size - vec2f(in.border_thickness);

        // reduction factor for the internal corner
        // radius. not 100% sure the best way to go
        // about this, but this is the best thing I've
        // found so far!
        //
        // this is necessary because otherwise it looks
        // weird
        let interior_radius_reduce_f = min(
            interior_half_size.x / in.dst_half_size.x,
            interior_half_size.y / in.dst_half_size.y
        );

        let interior_corner_radius =
            in.corner_radius *
            interior_radius_reduce_f *
            interior_radius_reduce_f;

        let inside_d = roundedRectSDF(
            in.dst_pos,
            in.dst_center,
            interior_half_size - softness_padding,
            interior_corner_radius,
        );

        let inside_f = smoothstep(0f, 2f * softness, inside_d);
        border_factor = inside_f;
    }

    //- color / texture

    let font_sample = textureSample(atlas_texture, atlas_sampler, in.uv);
    let font_c = font_sample.r;

    let smoothing = 1f / 16f;
    let font_alpha = smoothstep(0.5 - smoothing, 0.5 + smoothing, font_c);

    let in_rgb = in.color.rgb;
    let in_a = in.color.a;

    // gamma correction
    // this is an approximation
    let linear_in_rgb = pow(in_rgb, vec3f(2.2));

    let out_rgb = linear_in_rgb;
    let out_a = in_a * font_alpha;

    let out_color = vec4f(out_rgb, out_a) * sdf_factor * border_factor;
    return out_color;
}

//= util

fn roundedRectSDF(
    sample_pos: vec2f,
    rect_center: vec2f,
    rect_half_size: vec2f,
    r: f32,
) -> f32 {
    let d2 = 
        abs(rect_center - sample_pos) -
        rect_half_size + 
        vec2f(r, r);
    return min(max(d2.x, d2.y), 0f) + length(max(d2, vec2f(0f, 0f))) - r;
}

