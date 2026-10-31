// 원작의 화면 왜곡 이펙트(HGRP/Effect/VFXRefract, 칼빛을 따라가는 아지랑이)를 비슷하게 만든 것.
// 원작 재질 자료가 비어 있어서 계산은 직접 정했다: 파티클 메시가 덮은 자리의 화면을 잡음 그림만큼 비틀어 다시 그린다.
// 비트는 세기는 파티클 알파(수명에 따른 색 변화, 메시 가장자리의 정점 알파)를 따른다.

#include "res://src/fx/vfx_particle.gdshaderinc"

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D noise_texture : hint_default_black, repeat_enable, filter_linear_mipmap;
// 화면을 비트는 세기(화면 폭 비율)
uniform float strength = 0.035;

void fragment() {
	vec2 wobble = texture(noise_texture, uv_main * 1.5 + vec2(TIME * 0.4, TIME * 0.17)).rg * 2.0 - 1.0;
	float amount = clamp(particle_color.a, 0.0, 1.0);
	vec2 offset = wobble * strength * amount;
	ALBEDO = texture(screen_texture, SCREEN_UV + offset).rgb;
	ALPHA = amount;
}
