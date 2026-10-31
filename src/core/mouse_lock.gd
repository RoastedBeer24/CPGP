class_name MouseLock
extends RefCounted
## 게임 중 마우스를 창에 가둔다(카메라를 돌리려고). 화면 확인용으로 도는 중(tools/screenshot.sh, tools/capture.sh)에는
## 가두지 않는다: 창이 화면 밖에 떠 있어서, 가두면 PC를 쓰고 있는 사람의 커서가 화면 밖으로 끌려간다.

## true면 마우스를 가두지 않는다 (main.gd가 화면 확인용으로 켜졌을 때 정한다)
static var disabled := false


static func capture() -> void:
	if not disabled:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
