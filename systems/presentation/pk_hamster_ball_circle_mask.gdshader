shader_type canvas_item;

uniform float circle_radius : hint_range(0.90, 1.0, 0.005) = 0.96;
uniform float edge_softness : hint_range(0.005, 0.08, 0.005) = 0.015;


void fragment() {
	vec4 texel = texture(TEXTURE, UV) * COLOR;
	float radial_distance = length((UV - vec2(0.5)) * 2.0);
	float circular_alpha = 1.0 - smoothstep(circle_radius - edge_softness, circle_radius, radial_distance);
	COLOR = vec4(texel.rgb, texel.a * circular_alpha);
}
