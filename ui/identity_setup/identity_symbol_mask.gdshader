shader_type canvas_item;

// The identity artwork includes a beige card backing.
// Key out the paper so only the printed identity symbol sits on our larger detail card.
void fragment() {
	vec4 ink = texture(TEXTURE, UV);
	float paper = smoothstep(0.55, 0.68, ink.r)
		* smoothstep(0.41, 0.57, ink.g)
		* smoothstep(0.32, 0.46, ink.b);
	COLOR = vec4(ink.rgb, ink.a * (1.0 - paper));
}
