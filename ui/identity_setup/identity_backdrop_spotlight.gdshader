shader_type canvas_item;

// Soft elliptical warm spotlight: the artwork stays untouched; vignette is entirely a UI layer.
uniform vec4 vignette_ink : source_color = vec4(0.20, 0.12, 0.085, 1.0);
uniform float edge_opacity : hint_range(0.0, 0.8) = 0.31;
uniform float center_opacity : hint_range(0.0, 0.8) = 0.055;
uniform vec2 light_center = vec2(0.51, 0.48);
uniform vec2 light_radius = vec2(0.62, 0.72);

void fragment() {
    vec2 offset = (UV - light_center) / light_radius;
    float spotlight = exp(-2.7 * dot(offset, offset));
    float darkening = mix(edge_opacity, center_opacity, spotlight);
    COLOR = vec4(vignette_ink.rgb, darkening);
}
