// 캐릭터 만화풍 재질(셀 셰이딩), 반투명(코트 겉감, 머리카락 끝). 양면을 그리고, 깊이를 먼저 그려 겹친 순서가
// 꼬이지 않게 한다. 내용은 toon_common.gdshaderinc에 있다.
shader_type spatial;
render_mode cull_disabled, depth_prepass_alpha;

#define TOON_ALPHA
#include "res://src/player/toon_common.gdshaderinc"
