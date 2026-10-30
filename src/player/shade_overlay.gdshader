// 캐릭터 얼굴에 겹쳐 그리는 그림자 메시(눈 흰자 위 그림자, 앞머리 그림자). 아래 색에 곱해서 어둡게 한다.
// 원본은 마스크 텍스처의 빨간 채널에 그림자 세기를 넣어 두었다(초록·파랑은 흰색이라 그대로 칠하면 하늘색이 된다).
shader_type spatial;
render_mode blend_mul, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform sampler2D mask : hint_default_white, filter_linear_mipmap;
// 마스크가 없으면 이 값으로 곱한다 (1이면 그대로)
uniform float shade = 0.85;
uniform bool use_mask = true;
// 0이면 그림자 없음, 1이면 마스크 값 그대로 곱함
uniform float strength = 0.55;

void fragment() {
	float value = use_mask ? texture(mask, UV).r : shade;
	ALBEDO = vec3(mix(1.0, value, strength));
}
