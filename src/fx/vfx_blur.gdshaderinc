// 원작의 방사 흐림 이펙트(HGRP/Effect/VFXRadialBlur, 큰 타격 순간 화면이 가운데로 빨려 드는 느낌)를 비슷하게 만든 것.
// 원작 재질 자료가 비어 있어서 계산은 직접 정했다: 파티클 판이 덮은 자리의 화면을 판의 가운데 쪽으로 여러 번 겹쳐 읽는다.
// 세기는 파티클 알파를 따르고, 판 가장자리로 갈수록 약해진다.

#include "res://src/fx/vfx_particle.gdshaderinc"

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
// 가운데 쪽으로 끌어당기는 정도(가운데까지 거리의 비율)
uniform float strength = 0.18;
const int SAMPLES = 8;

void fragment() {
	// 판 가운데의 화면 위치: 이 조각과 가운데의 화면 좌표 차이를 투영으로 구한다. 화면 위아래 방향은 미분으로 맞춘다.
	vec4 here_clip = PROJECTION_MATRIX * vec4(VERTEX, 1.0);
	vec4 centre_clip = PROJECTION_MATRIX * vec4(particle_centre, 1.0);
	vec2 here_ndc = here_clip.xy / here_clip.w;
	vec2 centre_ndc = centre_clip.xy / max(centre_clip.w, 0.0001);
	float flip = sign(dFdy(SCREEN_UV.y) * dFdy(here_ndc.y));
	vec2 centre_uv = SCREEN_UV + (centre_ndc - here_ndc) * vec2(0.5, 0.5 * (flip == 0.0 ? -1.0 : flip));
	float edge = 1.0 - smoothstep(0.2, 0.5, length(uv_main - 0.5));
	float amount = clamp(particle_color.a, 0.0, 1.0) * edge;
	vec3 sum = vec3(0.0);
	for (int i = 0; i < SAMPLES; i++) {
		float t = float(i) / float(SAMPLES - 1) * strength * amount;
		sum += texture(screen_texture, mix(SCREEN_UV, centre_uv, t)).rgb;
	}
	ALBEDO = sum / float(SAMPLES);
	ALPHA = amount;
}
