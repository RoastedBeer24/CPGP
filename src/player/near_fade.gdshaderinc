// 1인칭에서 보이는 팔(PlayerBody의 팔 사본): 카메라에 near_fade_to(m)보다 가까우면 점점이 지우기 시작해
// near_fade_from에서 다 지운다. 팔을 휘두를 때 카메라를 스치는 소매가 화면을 덮지 않게 한다. near_fade_to가 0이면 끈다.
uniform float near_fade_from = 0.0;
uniform float near_fade_to = 0.0;

// 이 조각을 지울지. 픽셀마다 다른 문턱(흩뿌린 점 무늬)과 비교해, 반쯤 지울 곳은 점점이 지운다.
bool near_faded(vec3 view_position, vec2 frag_coord) {
	if (near_fade_to <= 0.0) {
		return false;
	}
	float seen = smoothstep(near_fade_from, near_fade_to, length(view_position));
	return seen < fract(52.9829189 * fract(dot(frag_coord, vec2(0.06711056, 0.00583715))));
}
