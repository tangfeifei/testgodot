shader_type spatial;
render_mode unshaded, cull_disabled;

uniform sampler2D reflection_texture : source_color, filter_linear;
uniform mat4 reflection_view;
uniform mat4 reflection_projection;
uniform vec3 camera_world_position = vec3(0.0);
uniform vec3 mirror_tint : source_color = vec3(0.92, 0.97, 0.96);

varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec4 reflected_clip = reflection_projection * reflection_view * vec4(world_position, 1.0);
	vec2 reflection_uv = reflected_clip.xy / reflected_clip.w * 0.5 + 0.5;
	reflection_uv.y = 1.0 - reflection_uv.y;
	vec3 reflected = texture(reflection_texture, clamp(reflection_uv, vec2(0.001), vec2(0.999))).rgb;
	float edge = smoothstep(0.0, 0.08, min(min(UV.x, 1.0 - UV.x), min(UV.y, 1.0 - UV.y)));
	ALBEDO = mix(mirror_tint * 0.42, reflected * mirror_tint, edge);
}