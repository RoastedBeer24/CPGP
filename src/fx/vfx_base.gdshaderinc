// 원작 이펙트 재질(HGRP/Effect/VFXBaseV2)을 Godot로 다시 만든 것. 파티클(FxSystem)이 MultiMesh로 그린다.
// 섞는 방식·뒷면·깊이 비교는 재질마다 달라서 FxMaterial이 render_mode 줄을 붙여 셰이더를 만든다.
//
// 정점 단계는 vfx_particle.gdshaderinc(그리기 정보 → 정점)를 함께 쓴다.
// 조각: 메인 텍스처와 샘플 슬롯(최대 4개, 슬롯마다 왜곡·가중치·마스크·섞기·녹이기 역할)을 원작 계산대로 합친다.
// UV는 원작(유니티) 방식(v가 위)으로 계산하고 그림을 읽을 때만 뒤집는다.

#include "res://src/fx/vfx_particle.gdshaderinc"

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
// 카메라 바로 앞의 판은 흐리게 한다(m, x에서 다 지우고 y부터 다 보인다): 얼굴까지 당긴 자유 시점에서 몸에 붙은
// 이펙트가 화면을 덮지 않게. 1인칭은 카메라가 이펙트 한가운데(몸)에 있어서 더 멀리서부터 흐린다(Player._apply_view).
global uniform vec2 fx_camera_fade;


// UV 만들기: 가중치(x 첫 UV, y 둘째 UV, z 극좌표, w 화면 UV)로 섞고, 흐르는 속도·커스텀 데이터로 밀고, 가운데를 축으로
// 돌린 뒤 타일링·오프셋을 마지막에 적용한다. 극좌표는 판의 가운데에서 잰 (각도, 거리)라서 띠 그림이 고리가 된다(충격파).
vec2 uv_transform(vec2 uv0, vec2 uv1, vec2 polar, vec2 screen, vec4 weights, vec4 speed, vec4 rot, vec4 st, float shift) {
	vec2 p = weights.x * uv0 + weights.y * uv1 + weights.z * polar + weights.w * screen + speed.xy * TIME + speed.zw * shift - 0.5;
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
	vec2 from_centre = uv0 - 0.5;
	vec2 polar = vec2(atan(from_centre.y, from_centre.x) / TAU + 0.5, length(from_centre) * 2.0);
	vec2 screen = vec2(SCREEN_UV.x, 1.0 - SCREEN_UV.y);
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
		vec2 p = uv_transform(uv0, uv1, polar, screen, slot_weights[b], slot_speed[b], slot_rot[b], slot_st[b], custom.y);
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
	vec2 main_uv = uv_transform(uv0, uv1, polar, screen, main_weights, main_speed, main_rot, main_st, custom.x) + dist * main_use_disturb;
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
	a *= smoothstep(fx_camera_fade.x, fx_camera_fade.y, length(VERTEX));
	ALBEDO = clamp(rgb, vec3(0.0), vec3(max_brightness));
	ALPHA = clamp(a, 0.0, 1.0);
}
