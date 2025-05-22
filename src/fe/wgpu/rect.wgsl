/*
 * Rectangle drawing
 */

//= types

struct RectInstance {
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

struct FragmentInput {
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

//= rect pass

@vertex
fn vsMain(in: RectInstance) -> FragmentInput {
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

    let ndc = (2 * dst_pos / surface_size_px) - 1;
    let flipped_ndc = vec2f(ndc.x, -ndc.y); // flip y

    //- position texture
    let tex_half_size = (in.tex_p1 - in.tex_p0) * 0.5;
    let tex_center = (in.tex_p1 + in.tex_p0) * 0.5;
    let tex_pos = corners[in.index] * tex_half_size + tex_center;

    let atlas_dims = textureDimensions(atlas_texture).xy;
    let atlas_size = vec2f(f32(atlas_dims.x), f32(atlas_dims.y));
    let tex_uv = tex_pos / atlas_size;

    //- fill output
    var out: FragmentInput;

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

@fragment
fn fsMain(in: FragmentInput) -> @location(0) vec4f {
    // Calculate pixel size in object space for precise AA
    let pixel_size = length(vec2f(
        dpdx(in.dst_pos.x),
        dpdy(in.dst_pos.y)
    ));
    
    // We'll use a much simpler approach: single-pixel AA with no softness
    // This produces crisp edges at all object sizes
    
    // Calculate SDF without softness padding
    let dist = roundedRectSDF(
        in.dst_pos,
        in.dst_center,
        in.dst_half_size,
        in.corner_radius
    );
    
    // Single-pixel antialiasing
    // This is all we need for crisp UI rendering at all scales
    let edge_width = pixel_size;
    var rounding_factor = 1.0 - smoothstep(-0.5 * edge_width, 0.5 * edge_width, dist);
    
    // Only apply softness if explicitly requested and above a threshold
    if (in.edge_softness > 0.1) {
        // Calculate softness effect
        let soft_dist = smoothstep(0.0, in.edge_softness * 2.0, dist);
        
        // Gradually blend in softness based on object size 
        // (larger objects can handle more softness)
        let obj_size = min(in.dst_half_size.x, in.dst_half_size.y) * 2.0;
        let size_ratio = obj_size / pixel_size;
        let soft_blend = saturate((size_ratio - 8.0) / 24.0);
        
        // Blend between crisp AA and soft edges based on object size
        rounding_factor = mix(rounding_factor, 1.0 - soft_dist, soft_blend * in.edge_softness);
    }
    
    // Border handling
    var border_factor = 1.0;
    if (in.border_thickness > 0.0) {
        let adjusted_thickness = max(in.border_thickness, pixel_size);
        let interior_half_size = in.dst_half_size - vec2f(adjusted_thickness);
        
        // Skip border rendering if interior would be too small
        if (all(interior_half_size > vec2f(pixel_size))) {
            let interior_radius = max(0.0, in.corner_radius - adjusted_thickness);
            
            let inside_dist = roundedRectSDF(
                in.dst_pos,
                in.dst_center,
                interior_half_size,
                interior_radius
            );
            
            // Single-pixel AA for border
            border_factor = smoothstep(-0.5 * pixel_size, 0.5 * pixel_size, inside_dist);
        }
    }
    
    // Color and texture
    let font_sample = textureSample(atlas_texture, atlas_sampler, in.uv);
    let font_c = font_sample.r;
    
    // Sharper text edges (critical for small UI)
    let text_smoothing = 1.0 / 32.0;
    let font_alpha = smoothstep(0.5 - text_smoothing, 0.5 + text_smoothing, font_c);
    
    let in_rgb = in.color.rgb;
    let in_a = in.color.a;
    
    // Gamma correction
    let linear_in_rgb = pow(in_rgb, vec3f(2.2));
    
    let out_rgb = linear_in_rgb;
    let out_a = in_a * font_alpha;
    
    let out_color = vec4f(out_rgb, out_a) * rounding_factor * border_factor;
    return out_color;
}

//= util

fn roundedRectSDF(
    sample_pos: vec2f,
    rect_center: vec2f,
    rect_half_size: vec2f,
    r: f32,
) -> f32 {
    let offset = abs(rect_center - sample_pos) - rect_half_size + vec2f(r, r);
    let outer_dist = length(max(offset, vec2f(0f, 0f)));
    let inner_dist = min(max(offset.x, offset.y), 0f);
    return outer_dist + inner_dist - r;
}
