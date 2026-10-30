// 원작 이펙트 재질(HGRP/Effect/VFXBaseV2)을 Godot로 다시 만든 것. 파티클(FxSystem)이 MultiMesh로 그린다.
// 섞는 방식·뒷면·깊이 비교는 재질마다 달라서 FxMaterial이 render_mode 줄을 붙여 셰이더를 만든다.
//
// 정점: 파티클 하나가 인스턴스 하나다. 인스턴스 변환 자리에 그리기 정보를 담는다(FxSystem).
//   그리기 0 (메시·축 판): 기둥 0~2 = 세 축(크기·회전 포함), 원점 = 중심
//   그리기 1 (화면 정면 판): 기둥 0 = (가로, 세로, 회전), 원점 = 중심
//   그리기 2 (늘어나는 판): 기둥 0 = (폭, 크기), 기둥 1 = 속도, 원점 = 중심
//   COLOR = 파티클 색, INSTANCE_CUSTOM = 커스텀 데이터(x 메인 텍스처 밀기, y 샘플 슬롯 밀기, z 녹아 사라지기,
//   w 텍스처 시트의 칸 번호)
// 조각: 메인 텍스처와 샘플 슬롯(최대 4개, 슬롯마다 왜곡·가중치·마스크·섞기·녹이기 역할)을 원작 계산대로 합친다.
// UV는 원작(유니티) 방식(v가 위)으로 계산하고 그림을 읽을 때만 뒤집는다.

uniform int draw_mode = 0;
uniform bool is_mesh = true;
uniform vec3 pivot = vec3(0.0);
uniform float min_size = 0.0;
uniform float max_size = 0.5;
uniform float length_scale = 2.0;
uniform float velocity_scale = 0.0;
uniform float vert_camera_offset = 0.0;
uniform vec2 sheet_tiles = vec2(1.0);
uniform bool use_second_uv = false;
// 가장 밝은 값. 원작 강도(최대 100)는 원작 화면에서 하얗게 날아가도록 만든 값이라 너무 밝지 않게 자른다.
uniform float max_brightness = 1.5;

uniform vec4 tint_color = vec4(1.0);
uniform float tint_intensity = 1.0;
uniform float tint_alpha = 1.0;
uniform float disable_vert_color = 0.0;

uniform sampler2D main_tex : source_color, repeat_enable, filter_linear_mipmap;
uniform vec4 main_weights = vec4(1.0, 0.0, 0.0, 0.0);
uniform vec4 main_speed = vec4(0.0);
uniform vec4 main_rot = vec4(1.0, 0.0, 0.0, 1.0);
uniform vec4 main_st = vec4(1.0, 1.0, 0.0, 0.0);
uniform float main_as_alpha = 0.0;
uniform float main_use_disturb = 0.0;
uniform bool main_clamp = false;

uniform int slot_count = 0;
uniform sampler2D slot0 : source_color, repeat_enable, filter_linear_mipmap;
uniform sampler2D slot1 : source_color, repeat_enable, filter_linear_mipmap;
uniform sampler2D slot2 : source_color, repeat_enable, filter_linear_mipmap;
uniform sampler2D slot3 : source_color, repeat_enable, filter_linear_mipmap;
uniform vec4 slot_weights[4];
uniform vec4 slot_speed[4];
uniform vec4 slot_rot[4];
uniform vec4 slot_st[4];
// 슬롯 역할: (왜곡, 가중치, 마스크, 섞기)와 녹이기
uniform vec4 slot_roles[4];
uniform float slot_dissolve[4];
uniform float slot_as_alpha[4];
uniform float slot_use_disturb[4];
uniform float slot_clamp[4];

uniform float use_disturb = 0.0;
uniform float use_disturb2 = 0.0;
uniform float bi_disturb = 0.0;
uniform float disturb1_normal = 0.0;
uniform float disturb2_normal = 0.0;
uniform vec4 disturb_intensity = vec4(0.0);
uniform float use_weight_tex = 0.0;
uniform float weight_tex_intensity = 1.0;
uniform float disturb_use_weight = 0.0;
uniform float use_mask = 0.0;
uniform vec4 blend_tint = vec4(1.0);
uniform float use_dissolve = 0.0;
uniform float dissolve_use_weight = 0.0;
uniform float dissolve_schedule_offset = 0.0;
uniform float dissolve_emissive_edge = 0.0;
uniform float dissolve_edge_sharp = 1.0;
uniform vec4 dissolve_emissive_color = vec4(0.0);
uniform float exp_threshold = 1.0;
uniform float exp_intensity = 0.0;
uniform bool soft_enabled = false;
uniform float soft_bias = 0.0;
uniform float soft_distance = 1.0;
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;

varying vec2 uv_main;
varying vec4 particle_custom;
varying vec4 particle_color;

void vertex() {
	mat4 data = MODEL_MATRIX;
	vec3 centre = data[3].xyz;
	vec2 corner = vec2(0.0);
	vec3 view_pos;
	if (draw_mode == 1) {
		// 화면 정면 판: 카메라 쪽을 보고 시계 방향으로 돈다. 크기는 화면 폭 비율로 자른다.
		vec3 info = data[0].xyz;
		float depth = max(-(VIEW_MATRIX * vec4(centre, 1.0)).z, 0.001);
		float frustum = 2.0 * depth / PROJECTION_MATRIX[0][0];
		float w = clamp(info.x, min_size * frustum, max_size * frustum);
		float h = clamp(info.y, min_size * frustum, max_size * frustum);
		vec2 q = VERTEX.xy;
		vec2 c = (q - pivot.xy) * vec2(w, h);
		float ca = cos(info.z);
		float sa = sin(info.z);
		c = vec2(c.x * ca + c.y * sa, -c.x * sa + c.y * ca);
		vec3 world = centre + INV_VIEW_MATRIX[0].xyz * c.x + INV_VIEW_MATRIX[1].xyz * c.y - INV_VIEW_MATRIX[2].xyz * pivot.z * w;
		view_pos = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
		corner = q + 0.5;
		NORMAL = vec3(0.0, 0.0, 1.0);
	} else if (draw_mode == 2) {
		// 늘어나는 판: 머리(중심)에서 속도 반대쪽으로 꼬리를 늘인다. 속도가 0이면 보이지 않는다.
		vec3 info = data[0].xyz;
		float depth = max(-(VIEW_MATRIX * vec4(centre, 1.0)).z, 0.001);
		float frustum = 2.0 * depth / PROJECTION_MATRIX[0][0];
		float width = clamp(info.x, min_size * frustum, max_size * frustum);
		vec3 head = (VIEW_MATRIX * vec4(centre, 1.0)).xyz;
		vec3 velocity = (VIEW_MATRIX * vec4(data[1].xyz, 0.0)).xyz;
		float speed = length(velocity);
		vec3 tail = head - velocity * velocity_scale - (speed > 0.0 ? velocity / speed : vec3(0.0)) * length_scale * info.y;
		vec2 side = vec2(head.z * tail.y - head.y * tail.z, head.x * tail.z - head.z * tail.x);
		side = length(side) > 0.000001 ? normalize(side) : vec2(1.0, 0.0);
		vec2 q = VERTEX.xy;
		view_pos = mix(head, tail, q.x + 0.5) + vec3(side, 0.0) * (q.y * width);
		corner = q + 0.5;
		NORMAL = vec3(0.0, 0.0, 1.0);
	} else {
		// 메시·축 판: 세 축(FxSystem이 크기·회전·좌표 뒤집기까지 계산)으로 정점을 놓는다.
		mat3 axes = mat3(data[0].xyz, data[1].xyz, data[2].xyz);
		vec3 world = centre + axes * (VERTEX - pivot);
		view_pos = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
		corner = is_mesh ? vec2(UV.x, 1.0 - UV.y) : VERTEX.xy + 0.5;
		NORMAL = normalize(mat3(VIEW_MATRIX) * (axes * NORMAL));
	}
	// 카메라 쪽으로 조금 당긴다(겹친 판끼리 깜빡이지 않게).
	float dist = length(view_pos);
	view_pos += -view_pos / max(dist, 0.0001) * (min(max(dist - 1.0, 0.0), vert_camera_offset) + 0.001);
	VERTEX = view_pos;
	vec4 rect = vec4(0.0, 0.0, 1.0, 1.0);
	if (sheet_tiles.x * sheet_tiles.y > 1.0) {
		float index = INSTANCE_CUSTOM.w;
		float column = mod(index, sheet_tiles.x);
		float row = floor(index / sheet_tiles.x);
		rect = vec4(column / sheet_tiles.x, 1.0 - (row + 1.0) / sheet_tiles.y, 1.0 / sheet_tiles.x, 1.0 / sheet_tiles.y);
	}
	uv_main = rect.xy + corner * rect.zw;
	particle_custom = INSTANCE_CUSTOM;
	particle_color = COLOR;
}

vec2 uv_transform(vec2 uv0, vec2 uv1, vec4 weights, vec4 speed, vec4 rot, vec4 st, float shift) {
	vec2 p = weights.x * uv0 + weights.y * uv1 + speed.xy * TIME + speed.zw * shift - 0.5;
	p = vec2(p.x * rot.x + p.y * rot.z, p.x * rot.y + p.y * rot.w) + 0.5;
	return p * st.xy + st.zw;
}

vec4 read(sampler2D image, vec2 p, float clamp_uv, float as_alpha) {
	vec2 uv = vec2(p.x, 1.0 - p.y);
	if (clamp_uv > 0.5) {
		vec2 half_texel = 0.5 / vec2(textureSize(image, 0));
		uv = clamp(uv, half_texel, 1.0 - half_texel);
	}
	vec4 c = texture(image, uv);
	return as_alpha > 0.5 ? vec4(1.0, 1.0, 1.0, c.r) : c;
}

vec2 disturb(vec4 d, float normal_map, float u_intensity, float v_intensity) {
	float s = d.x * (1.0 + bi_disturb) - bi_disturb;
	return normal_map > 0.5 ? (vec2(s * d.w, d.y) * 2.0 - 1.0) * u_intensity : s * vec2(u_intensity, v_intensity);
}

vec4 read_slot(int index, vec2 p) {
	if (index == 0) {
		return read(slot0, p, slot_clamp[0], slot_as_alpha[0]);
	} else if (index == 1) {
		return read(slot1, p, slot_clamp[1], slot_as_alpha[1]);
	} else if (index == 2) {
		return read(slot2, p, slot_clamp[2], slot_as_alpha[2]);
	}
	return read(slot3, p, slot_clamp[3], slot_as_alpha[3]);
}

void fragment() {
	vec2 uv0 = uv_main;
	vec2 uv1 = use_second_uv ? uv_main : vec2(0.0);
	vec4 custom = particle_custom;
	vec4 vertex_color = disable_vert_color > 0.5 ? vec4(1.0) : particle_color;
	vec4 col = vertex_color * tint_color * vec4(vec3(tint_intensity), tint_alpha);
	vec2 dist = vec2(0.0);
	float weight = 1.0 - use_weight_tex;
	vec4 mask = vec4(1.0 - use_mask);
	vec4 blend = vec4(0.0);
	float dissolve_value = 0.0;
	for (int b = 0; b < 4; b++) {
		if (b >= slot_count) {
			break;
		}
		vec2 p = uv_transform(uv0, uv1, slot_weights[b], slot_speed[b], slot_rot[b], slot_st[b], custom.y);
		if (b > 0) {
			p += dist * slot_use_disturb[b];
		}
		vec4 s = read_slot(b, p);
		vec4 role = slot_roles[b];
		if (b == 0 && role.x != 0.0) {
			dist = disturb(vec4(s.x * role.x, s.y * role.x, 0.0, s.w * role.x) + (1.0 - use_disturb), disturb1_normal, disturb_intensity.x, disturb_intensity.y);
		}
		if (b == 1 && role.x != 0.0) {
			dist += disturb(vec4(s.x * role.x, s.y * role.x, 0.0, s.w * role.x) + (1.0 - use_disturb * use_disturb2), disturb2_normal, disturb_intensity.z, disturb_intensity.w);
		}
		weight += s.x * role.y;
		mask += s * role.z;
		blend += s * role.w;
		dissolve_value += s.x * slot_dissolve[b];
		if (b > 0) {
			dist *= mix(1.0, weight, role.y * weight_tex_intensity * disturb_use_weight);
		}
	}
	vec2 main_uv = uv_transform(uv0, uv1, main_weights, main_speed, main_rot, main_st, custom.x) + dist * main_use_disturb;
	col *= read(main_tex, main_uv, main_clamp ? 1.0 : 0.0, main_as_alpha);
	vec4 c = col * mask;
	vec3 rgb = c.rgb + clamp((col.a * mask.a + blend.a) * blend_tint.a, 0.0, 1.0) * blend.rgb * blend_tint.rgb;
	float a = c.a;
	if (use_dissolve != 0.0) {
		float k = weight_tex_intensity * dissolve_use_weight;
		float progress = (custom.z + dissolve_schedule_offset) * 2.02 - 0.01;
		float d = dissolve_value - ((weight * k + 1.0 - k) * progress - 1.0);
		float edge = clamp((dissolve_emissive_edge - d) * dissolve_edge_sharp, 0.0, 1.0);
		rgb = mix(rgb, edge * dissolve_emissive_color.rgb * tint_intensity, edge);
		a = clamp(d * dissolve_edge_sharp, 0.0, 1.0) * c.a;
	}
	rgb += max(rgb - exp_threshold, vec3(0.0)) * exp_intensity;
	if (soft_enabled) {
		// 부드러운 파티클: 뒤에 있는 물체에 가까울수록 흐려져 판이 땅·벽에 박힌 선이 보이지 않는다.
		float depth = texture(depth_texture, SCREEN_UV).r;
		vec4 scene = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
		float scene_depth = -scene.z / scene.w;
		a *= clamp((scene_depth + VERTEX.z + soft_bias) / max(soft_distance, 0.0001), 0.0, 1.0);
	}
	ALBEDO = clamp(rgb, vec3(0.0), vec3(max_brightness));
	ALPHA = clamp(a, 0.0, 1.0);
}
