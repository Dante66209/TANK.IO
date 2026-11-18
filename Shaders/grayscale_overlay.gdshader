shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;
uniform float intensity : hint_range(0.0, 1.0) = 1.0;
uniform float dim_amount : hint_range(0.0, 1.0) = 0.22;

void fragment() {
	vec4 src = texture(screen_texture, SCREEN_UV);
	float lum = dot(src.rgb, vec3(0.299, 0.587, 0.114));
	vec3 gray = vec3(lum);
	vec3 tinted = mix(gray, vec3(0.16, 0.18, 0.21), dim_amount);
	COLOR = vec4(mix(src.rgb, tinted, intensity), intensity);
}
