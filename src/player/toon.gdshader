// 캐릭터 만화풍 재질(셀 셰이딩). 원본 게임처럼 빛을 받는 정도를 색 띠(ramp) 텍스처의 색으로 바꿔 칠한다.
// 띠의 왼쪽(그늘)은 회색이라 그늘도 너무 어둡지 않고, 가운데 경계는 살구색이라 피부 그늘 경계가 따뜻하다.
// 빛을 받는 쪽 윤곽에는 테두리 빛(림)을, 빛나는 부분 마스크가 있으면 그 부분을 빛나게 한다.
shader_type spatial;
render_mode cull_back;

uniform sampler2D albedo_texture : source_color, hint_default_white, filter_linear_mipmap_anisotropic;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform sampler2D ramp : source_color, hint_default_white, filter_linear, repeat_disable;
// 0보다 크면 알파가 이보다 낮은 곳을 그리지 않는다(바이저처럼 구멍 난 재질). 0이면 불투명.
uniform float alpha_scissor = 0.0;
uniform sampler2D emission_mask : hint_default_black, filter_linear_mipmap;
uniform float emission_energy = 0.0;
// 테두리 빛의 세기와 두께(0~1)
uniform float rim_strength = 0.4;
uniform float rim_width = 0.28;
// 얼굴: 굴곡을 얼마나 지우고 얼굴이 보는 방향으로 고르게 비출지 (0이면 보통 법선)
uniform float flatness = 0.0;
// 얼굴이 보는 방향(세상 기준). PlayerBody가 매 프레임 머리 방향으로 넣는다.
instance uniform vec3 face_forward = vec3(0.0, 0.0, -1.0);
// 카메라 쪽으로 당겨 그리는 거리(m). 눈썹을 앞머리 위에 보이게 한다(원본 게임처럼). 뒤통수처럼 이보다 멀리
// 떨어진 것은 뚫고 보이지 않는다.
uniform float depth_bias = 0.0;

void vertex() {
	// POSITION을 쓰면 엔진이 모든 재질의 기본 변환을 건너뛰므로, 정점 자체를 카메라 쪽으로 옮긴다.
	if (depth_bias > 0.0) {
		vec3 camera_local = (inverse(MODEL_MATRIX) * vec4(CAMERA_POSITION_WORLD, 1.0)).xyz;
		VERTEX += normalize(camera_local - VERTEX) * depth_bias;
	}
}

void fragment() {
	vec4 color = texture(albedo_texture, UV) * albedo_color;
	ALBEDO = color.rgb;
	ALPHA = color.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_scissor;
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
	vec3 band = texture(ramp, vec2(clamp(ndl * 0.5 + 0.5, 0.01, 0.99), 0.5)).rgb;
	DIFFUSE_LIGHT += band * ATTENUATION * LIGHT_COLOR / PI;
	float edge = smoothstep(1.0 - rim_width, 1.0, 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0));
	SPECULAR_LIGHT += edge * clamp(ndl + 0.3, 0.0, 1.0) * rim_strength * ATTENUATION * LIGHT_COLOR / PI;
}
