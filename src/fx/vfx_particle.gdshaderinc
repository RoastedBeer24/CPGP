// 원작 이펙트 파티클의 정점 단계. 파티클 하나가 MultiMesh 인스턴스 하나이고, 인스턴스 변환 자리에 그리기 정보를 담는다(FxSystem).
//   그리기 0 (메시·축 판): 기둥 0~2 = 세 축(크기·회전 포함), 원점 = 중심
//   그리기 1 (화면 정면 판): 기둥 0 = (가로, 세로, 회전), 원점 = 중심
//   그리기 2 (늘어나는 판): 기둥 0 = (폭, 크기), 기둥 1 = 속도, 원점 = 중심
//   COLOR = 파티클 색(메시의 정점 색이 곱해진다), INSTANCE_CUSTOM = 커스텀 데이터(x 메인 텍스처 밀기, y 샘플 슬롯 밀기,
//   z 녹아 사라지기, w 텍스처 시트의 칸 번호)
// 원작 재질(vfx_base), 화면 왜곡(vfx_refract), 방사 흐림(vfx_blur)이 함께 쓴다.

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
// 가장 밝은 값. 원작 강도(최대 100)는 원작 화면에서 하얗게 날아가도록 만든 값이다. 이 값까지는 빛 번짐(글로)으로
// 빛나게 두고 그 위는 자른다.
uniform float max_brightness = 4.0;

varying vec2 uv_main;
varying vec4 particle_custom;
varying vec4 particle_color;
// 파티클 중심(보기 좌표). 방사 흐림이 쓴다.
varying vec3 particle_centre;

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
	particle_centre = (VIEW_MATRIX * vec4(centre, 1.0)).xyz;
	particle_color = COLOR;
}

