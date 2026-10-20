shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled;

uniform sampler2D reflection_texture : source_color, filter_linear;
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform mat4 reflection_view;
uniform mat4 reflection_projection;
uniform vec3 pond_center = vec3(0.0);
uniform vec2 pond_extent = vec2(8.0, 5.0);
uniform vec3 camera_world_position = vec3(0.0, 5.0, 10.0);
uniform vec3 water_tint : source_color = vec3(0.20, 0.55, 0.54);
uniform float wave_speed = 0.8;
uniform float wave_scale = 1.0;
uniform float transparency = 0.82;

varying vec3 world_position;

float water_height(vec2 position) {
	float broad = sin(position.x * 0.72 + TIME * wave_speed) * cos(position.y * 0.58 - TIME * wave_speed * 0.73);
	float ripple_a = sin(length(position - pond_center.xz - vec2(TIME * 0.42, 0.0)) * 4.2 - TIME * 3.4);
	float ripple_b = sin(length(position - pond_center.xz + vec2(0.0, TIME * 0.31)) * 3.1 - TIME * 2.7);
	return (broad * 0.035 + ripple_a * 0.012 + ripple_b * 0.009) * wave_scale;
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	 vec2 pond_uv = (world_position.xz - pond_center.xz) / pond_extent;
	float edge_distance = length(pond_uv);
	if (edge_distance > 1.0) {
		discard;
	}
	float height = water_height(world_position.xz);
	vec3 normal = normalize(vec3(-dFdx(height) * 5.0, 1.0, -dFdy(height) * 5.0));
	vec2 distortion = normal.xz * 0.018;
	vec3 refracted = texture(screen_texture, SCREEN_UV + distortion).rgb;
	vec4 reflected_clip = reflection_projection * reflection_view * vec4(world_position, 1.0);
	vec2 reflection_uv = reflected_clip.xy / reflected_clip.w * 0.5 + 0.5;
	reflection_uv.y = 1.0 - reflection_uv.y;
	vec3 reflected = texture(reflection_texture, clamp(reflection_uv + distortion, vec2(0.001), vec2(0.999))).rgb;
	vec3 view_direction = normalize(camera_world_position - world_position);
	float fresnel = 0.02 + 0.98 * pow(1.0 - abs(dot(normal, view_direction)), 5.0);
	ALBEDO = mix(refracted * water_tint, reflected, fresnel);
	ALPHA = transparency * (1.0 - smoothstep(0.88, 1.0, edge_distance));
	ROUGHNESS = 0.12 + (1.0 - fresnel) * 0.22;
}