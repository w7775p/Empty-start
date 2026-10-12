shader_type canvas_item;

uniform float melt_amount : hint_range(0.0, 1.0) = 0.0;
uniform float wobble_amount : hint_range(0.0, 1.0) = 0.0;
uniform float melt_pull_pixels = 30.0;
uniform float wave_pixels = 12.0;
uniform float wobble_speed = 24.0;

void vertex() {
	float side_mask = sin(UV.x * PI);
	float lower_body = smoothstep(0.04, 0.96, UV.y);
	float melt_wave = sin(UV.y * 19.0 + TIME * 7.0) * melt_amount * wave_pixels * lower_body;
	VERTEX.x += melt_wave * side_mask;
	VERTEX.y += pow(UV.y, 1.8) * melt_amount * melt_pull_pixels;

	float upper_mask = 1.0 - smoothstep(0.22, 0.88, UV.y);
	float leg_mask = smoothstep(0.35, 0.92, UV.y);
	float wings = sin(UV.y * 16.0 + TIME * wobble_speed) * upper_mask;
	float legs = cos(UV.x * 17.0 - TIME * wobble_speed * 1.17) * leg_mask;
	VERTEX.x += (wings + legs) * side_mask * wobble_amount * wave_pixels;
	VERTEX.y += (wings - legs) * wobble_amount * wave_pixels * 0.28;
}
