// 캐릭터 얼굴(얼굴, 눈썹, 눈동자). 원본 게임은 얼굴 그림자를 따로 그린 그림(SDF)으로 정하는데, 여기서는
// 얼굴 전체를 얼굴이 보는 방향의 판처럼 비춘다. 보통 조명은 코와 볼의 굴곡을 따라 얼굴 절반이 시커멓게 갈라진다.
shader_type spatial;
render_mode cull_back, diffuse_lambert_wrap, specular_disabled;

uniform sampler2D albedo_texture : source_color, hint_default_white, filter_linear_mipmap_anisotropic;
uniform vec4 albedo_color : source_color = vec4(1.0);
// 얼굴 굴곡을 얼마나 지울지 (1이면 완전히 판처럼)
uniform float flatness = 0.85;
// 얼굴이 보는 방향(세상 기준). PlayerBody가 매 프레임 머리 방향으로 넣는다.
instance uniform vec3 face_forward = vec3(0.0, 0.0, -1.0);

void fragment() {
	ALBEDO = (texture(albedo_texture, UV) * albedo_color).rgb;
	vec3 flat_normal = normalize((VIEW_MATRIX * vec4(face_forward, 0.0)).xyz);
	NORMAL = normalize(mix(NORMAL, flat_normal, flatness));
	ROUGHNESS = 1.0;
}
