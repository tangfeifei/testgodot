shader_type spatial;
render_mode blend_mix, depth_prepass_alpha, cull_disabled, unshaded;

uniform sampler2D foliage_texture : source_color;
uniform bool use_texture = false;
uniform bool billboard = false;
uniform int foliage_style = 0;
uniform vec3 foliage_tint : source_color = vec3(0.2, 0.4, 0.2);
uniform vec2 wind_direction = vec2(1.0, 0.0);
uniform float wind_strength = 0.12;
uniform float wind_speed = 1.0;
uniform float gust_factor = 1.0;

void vertex() {
	vec3 world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	if (billboard) {
		vec3 center = MODEL_MATRIX[3].xyz;
		float horizontal_scale = length(MODEL_MATRIX[0].xyz);
		float vertical_scale = length(MODEL_MATRIX[1].xyz);
		world_position = center + INV_VIEW_MATRIX[0].xyz * VERTEX.x * horizontal_scale + INV_VIEW_MATRIX[1].xyz * VERTEX.y * vertical_scale;
	}
	float height_factor = clamp(UV.y, 0.0, 1.0);
	float phase = TIME * wind_speed + dot(world_position.xz, vec2(0.071, 0.053)) + INSTANCE_CUSTOM.r * 6.28318;
	float wave = sin(phase) + 0.32 * sin(phase * 0.57 + 1.8);
	world_position.xz += wind_direction * wave * wind_strength * gust_factor * height_factor * height_factor;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world_position, 1.0);
}

void fragment() {
	vec4 texel = use_texture ? texture(foliage_texture, UV) : vec4(1.0);
	if (foliage_style < 3) {
		float width_limit = 0.47 * pow(max(sin(PI * (0.12 + UV.y * 0.86)), 0.0), 0.58);
		if (foliage_style == 1) {
			width_limit = 0.49 * (1.0 - UV.y) + 0.025;
		}
		if (abs(UV.x - 0.5) > width_limit) {
			discard;
		}
	} else if (foliage_style == 3) {
		float blade_width = 0.045 + 0.28 * UV.y * (1.0 - UV.y);
		float curved_center = 0.5 + 0.13 * sin(UV.y * PI);
		if (abs(UV.x - curved_center) > blade_width) {
			discard;
		}
	} else if (foliage_style >= 4) {
		if (UV.y < 0.61) {
			if (abs(UV.x - 0.5) > 0.035) {
				discard;
			}
		} else {
			vec2 petal_center = vec2(0.5, 0.78);
			vec2 petal_position = (UV - petal_center) * vec2(1.0, 1.25);
			float petal_angle = atan(petal_position.y, petal_position.x);
			float petal_radius = length(petal_position);
			float petal_edge = 0.18 + 0.09 * cos(petal_angle * 5.0);
			if (petal_radius > petal_edge) {
				discard;
			}
		}
	}
	ALBEDO = COLOR.rgb * foliage_tint * texel.rgb;
	ALPHA = COLOR.a * texel.a;
	ROUGHNESS = 0.92;
}