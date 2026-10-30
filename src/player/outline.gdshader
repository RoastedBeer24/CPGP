// 캐릭터 외곽선(뒤집은 껍질). 메시를 법선 방향으로 조금 부풀려 뒷면만 바탕색보다 어둡게 그린다.
// 굵기는 카메라와의 거리에 비례해 키워서 화면에서 비슷한 굵기로 보이게 한다(가까이 0.5m ~ 멀리 8m까지).
shader_type spatial;
render_mode cull_front, unshaded, shadows_disabled;

uniform sampler2D albedo_texture : source_color, hint_default_white, filter_linear_mipmap;
// 1m 떨어졌을 때의 굵기(m)
uniform float width = 0.0012;
// 외곽선 색 = 바탕색 × darkness
uniform float darkness = 0.3;
uniform float alpha_scissor = 0.0;

void vertex() {
	float distance = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
	VERTEX += normalize(NORMAL) * width * clamp(distance, 0.5, 8.0);
}

void fragment() {
	vec4 color = texture(albedo_texture, UV);
	ALBEDO = color.rgb * darkness;
	ALPHA = color.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_scissor;
}
