// 캐릭터 만화풍 재질(셀 셰이딩)의 공통 부분. toon.gdshader(불투명)와 toon_alpha.gdshader(반투명)가 함께 쓴다.
// 원본 게임처럼 빛을 받는 정도를 색 띠(ramp) 텍스처의 색으로 바꿔 칠한다. 띠의 왼쪽(그늘)은 회색이라 그늘도
// 너무 어둡지 않고, 가운데 경계는 살구색이라 피부 그늘 경계가 따뜻하다.
// 빛을 받는 쪽 윤곽에는 테두리 빛(림)을, 빛나는 부분 마스크가 있으면 그 부분을 빛나게 한다.

uniform sampler2D albedo_texture : source_color, hint_default_white, filter_linear_mipmap_anisotropic;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform sampler2D ramp : source_color, hint_default_white, filter_linear, repeat_disable;
// 0보다 크면 알파가 이보다 낮은 곳을 그리지 않는다(바이저처럼 구멍 난 재질). 0이면 불투명. (불투명 재질만)
uniform float alpha_scissor = 0.0;
uniform sampler2D emission_mask : hint_default_black, filter_linear_mipmap;
uniform float emission_energy = 0.0;
// 주름 법선 지도. 원본은 두 채널(빨강 X, 초록 Y)만 쓰므로 Z는 계산한다.
uniform sampler2D normal_texture : hint_default_black, filter_linear_mipmap_anisotropic;
uniform bool use_normal_map = false;
uniform float normal_strength = 0.7;
// 테두리 빛의 세기와 두께(0~1)
uniform float rim_strength = 0.4;
uniform float rim_width = 0.28;
// 얼굴: 굴곡을 얼마나 지우고 얼굴이 보는 방향으로 고르게 비출지 (0이면 보통 법선)
uniform float flatness = 0.0;
// 얼굴이 보는 방향(세상 기준). PlayerBody가 매 프레임 머리 방향으로 넣는다.
instance uniform vec3 face_forward = vec3(0.0, 0.0, -1.0);
// 얼굴 그림자 지도(SDF)의 파란 채널: 빛이 얼굴 정면에서 얼마나 돌았을 때(0 정면, 1 뒤) 이 자리가 그늘이 되는지.
// 쓰면 얼굴의 굴곡 대신 이 지도로 코와 볼에 만화풍 그림자를 만든다. 지도는 얼굴 오른쪽에서 오는 빛 기준이라
// 빛이 왼쪽에서 오면 좌우를 뒤집어 읽는다.
uniform sampler2D face_shadow_map : hint_default_white, filter_linear;
uniform bool use_face_shadow = false;
uniform float face_shadow_softness = 0.04;
// 얼굴의 오른쪽(세상 기준). PlayerBody가 매 프레임 머리 방향으로 넣는다.
instance uniform vec3 face_right = vec3(1.0, 0.0, 0.0);
// 머리카락 광택: 빛과 시선의 가운데 방향을 향한 곳에 경계가 또렷한 밝은 띠를 그린다(만화풍 머리카락의 고리 광택).
uniform float gloss_strength = 0.0;
uniform float gloss_sharpness = 48.0;
// 카메라 쪽으로 당겨 그리는 거리(m). 눈썹을 앞머리 위에 보이게 한다(원본 게임처럼). 뒤통수처럼 이보다 멀리
// 떨어진 것은 뚫고 보이지 않는다.
uniform float depth_bias = 0.0;

void vertex() {
	// POSITION을 쓰면 엔진이 그 재질의 기본 변환을 건너뛰므로, 정점 자체를 카메라 쪽으로 옮긴다.
	if (depth_bias > 0.0) {
		vec3 camera_local = (inverse(MODEL_MATRIX) * vec4(CAMERA_POSITION_WORLD, 1.0)).xyz;
		VERTEX += normalize(camera_local - VERTEX) * depth_bias;
	}
}

void fragment() {
	vec4 color = texture(albedo_texture, UV) * albedo_color;
	ALBEDO = color.rgb;
	ALPHA = color.a;
#ifndef TOON_ALPHA
	ALPHA_SCISSOR_THRESHOLD = alpha_scissor;
#endif
	if (use_normal_map) {
		vec2 xy = texture(normal_texture, UV).rg * 2.0 - 1.0;
		NORMAL_MAP = vec3(xy, sqrt(max(1.0 - dot(xy, xy), 0.0))) * 0.5 + 0.5;
		NORMAL_MAP_DEPTH = normal_strength;
	}
	if (flatness > 0.0) {
		vec3 flat_normal = normalize((VIEW_MATRIX * vec4(face_forward, 0.0)).xyz);
		NORMAL = normalize(mix(NORMAL, flat_normal, flatness));
	}
	EMISSION = color.rgb * texture(emission_mask, UV).r * emission_energy;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float shade = ndl * 0.5 + 0.5;
	if (use_face_shadow) {
		// 빛을 얼굴의 앞·옆 평면에 눕혀, 정면에서 돈 각도(0: 정면, 1: 뒤)를 지도 값과 비교한다.
		vec3 front = normalize((VIEW_MATRIX * vec4(face_forward, 0.0)).xyz);
		vec3 side = normalize((VIEW_MATRIX * vec4(face_right, 0.0)).xyz);
		vec2 flat_light = vec2(dot(LIGHT, side), dot(LIGHT, front));
		float turned = acos(clamp(flat_light.y / max(length(flat_light), 0.0001), -1.0, 1.0)) / PI;
		vec2 map_uv = flat_light.x > 0.0 ? UV : vec2(1.0 - UV.x, UV.y);
		float threshold = texture(face_shadow_map, map_uv).b;
		shade = mix(0.02, 0.98, smoothstep(turned - face_shadow_softness, turned + face_shadow_softness, threshold));
	}
	vec3 band = texture(ramp, vec2(clamp(shade, 0.01, 0.99), 0.5)).rgb;
	DIFFUSE_LIGHT += band * ATTENUATION * LIGHT_COLOR / PI;
	if (gloss_strength > 0.0) {
		float facing = pow(clamp(dot(NORMAL, normalize(LIGHT + VIEW)), 0.0, 1.0), gloss_sharpness);
		SPECULAR_LIGHT += smoothstep(0.3, 0.45, facing) * gloss_strength * ATTENUATION * LIGHT_COLOR / PI;
	}
	float edge = smoothstep(1.0 - rim_width, 1.0, 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0));
	SPECULAR_LIGHT += edge * clamp(ndl + 0.3, 0.0, 1.0) * rim_strength * ATTENUATION * LIGHT_COLOR / PI;
}
