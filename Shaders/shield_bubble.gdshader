shader_type canvas_item;

uniform vec4 shield_color : source_color = vec4(0.2, 0.8, 1.0, 0.4);
uniform float pulse_speed = 3.0;

void fragment() {
	vec2 uv = UV - vec2(0.5);
	float dist = length(uv);
	float rim = smoothstep(0.35, 0.5, dist) * (1.0 - smoothstep(0.48, 0.5, dist));
	float pulse = 0.8 + 0.2 * sin(TIME * pulse_speed);
	COLOR = vec4(shield_color.rgb, (shield_color.a + rim * 0.5) * pulse);
}
