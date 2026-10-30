// 무기 재질. 원작처럼 무기가 나타날 때는 손잡이 쪽에서 칼끝 쪽으로 차오르고, 사라질 때는 칼끝부터 지워지며
// 잘린 자리가 밝게 빛난다. 색은 무기 모델의 원래 색 그림(albedo)을 그대로 쓴다.
shader_type spatial;
render_mode cull_back;

uniform sampler2D albedo_texture : source_color, hint_default_white, filter_linear_mipmap_anisotropic;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform float roughness = 0.8;
uniform float metallic = 0.0;
uniform vec4 emission_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float emission_energy = 0.0;
// 나타난 정도(0: 안 보임, 1: 다 보임). 메시 기준 축(cut_axis)을 따라 cut_from에서 cut_to까지 차오른다.
uniform float reveal = 1.0;
uniform vec3 cut_axis = vec3(0.0, 1.0, 0.0);
uniform float cut_from = 0.0;
uniform float cut_to = 1.0;
// 잘린 자리에 빛나는 띠의 두께(m), 색, 세기
uniform float edge_width = 0.06;
uniform vec4 edge_color : source_color = vec4(1.0, 0.93, 0.75, 1.0);
uniform float edge_energy = 6.0;

varying float along;

void vertex() {
	along = dot(VERTEX, cut_axis);
}

void fragment() {
	float cut = mix(cut_from - edge_width, cut_to + edge_width, reveal);
	if (along > cut) {
		discard;
	}
	float edge = 1.0 - smoothstep(0.0, edge_width, cut - along);
	vec4 color = texture(albedo_texture, UV) * albedo_color;
	ALBEDO = mix(color.rgb, edge_color.rgb, edge);
	ROUGHNESS = roughness;
	METALLIC = metallic;
	EMISSION = emission_color.rgb * emission_energy + edge_color.rgb * edge * edge_energy;
}
