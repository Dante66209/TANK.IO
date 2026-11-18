shader_type canvas_item;

uniform vec2 player_screen_pos = vec2(650.0, 400.0);
uniform vec2 viewport_size = vec2(1300.0, 800.0);
uniform float sight_radius_px = 560.0;
uniform float feather_px = 90.0;
uniform vec4 fog_color : source_color = vec4(0.05, 0.06, 0.09, 0.86);

void fragment() {
	vec2 frag_pos = UV * viewport_size;
	float dist = distance(frag_pos, player_screen_pos);
	float alpha = smoothstep(sight_radius_px - feather_px, sight_radius_px, dist);
	COLOR = vec4(fog_color.rgb, fog_color.a * alpha);
}
