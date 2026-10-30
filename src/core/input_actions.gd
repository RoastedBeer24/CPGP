extends Node
## 게임 입력 동작을 등록한다. 기본 키 배치는 사이버펑크 2077을 따른다.
## 키 재설정(설정 메뉴)은 이 기본값 위에 덮어쓰는 방식으로 나중에 추가한다.

const MOVE_FORWARD := &"move_forward"
const MOVE_BACK := &"move_back"
const MOVE_LEFT := &"move_left"
const MOVE_RIGHT := &"move_right"
const JUMP := &"jump"
const SPRINT := &"sprint"
const CROUCH := &"crouch"
const PAUSE := &"pause"
const DEBUG_OVERLAY := &"debug_overlay"
const FIRE := &"fire"
const AIM := &"aim"
const RELOAD := &"reload"
const WEAPON_1 := &"weapon_1"
const WEAPON_2 := &"weapon_2"
const WEAPON_3 := &"weapon_3"
const WEAPON_NEXT := &"weapon_next"
const WEAPON_PREV := &"weapon_prev"
const CAMERA_TOGGLE := &"camera_toggle"
const INTERACT := &"interact"
const FREE_LOOK := &"free_look"

const DEFAULT_KEYS := {
	MOVE_FORWARD: [KEY_W],
	MOVE_BACK: [KEY_S],
	MOVE_LEFT: [KEY_A],
	MOVE_RIGHT: [KEY_D],
	JUMP: [KEY_SPACE],
	SPRINT: [KEY_SHIFT],
	CROUCH: [KEY_CTRL, KEY_C],
	PAUSE: [KEY_ESCAPE],
	DEBUG_OVERLAY: [KEY_F3],
	RELOAD: [KEY_R],
	WEAPON_1: [KEY_1],
	WEAPON_2: [KEY_2],
	WEAPON_3: [KEY_3],
	# 사이버펑크 2077은 걸어 다닐 때 3인칭이 없어서, 차량 시점 전환 키(V)를 따른다.
	CAMERA_TOGGLE: [KEY_V],
	INTERACT: [KEY_F],
	# 누르고 있는 동안 캐릭터 주변을 둘러본다 (휠로 확대·축소)
	FREE_LOOK: [KEY_QUOTELEFT],
}

const DEFAULT_MOUSE_BUTTONS := {
	FIRE: [MOUSE_BUTTON_LEFT],
	AIM: [MOUSE_BUTTON_RIGHT],
	WEAPON_NEXT: [MOUSE_BUTTON_WHEEL_DOWN],
	WEAPON_PREV: [MOUSE_BUTTON_WHEEL_UP],
}


func _enter_tree() -> void:
	register_defaults()


## 아직 없는 동작만 기본 키로 등록한다. 여러 번 불러도 안전하다.
static func register_defaults() -> void:
	for action: StringName in DEFAULT_KEYS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for keycode: Key in DEFAULT_KEYS[action]:
			var event := InputEventKey.new()
			event.physical_keycode = keycode
			InputMap.action_add_event(action, event)
	for action: StringName in DEFAULT_MOUSE_BUTTONS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for button: MouseButton in DEFAULT_MOUSE_BUTTONS[action]:
			var event := InputEventMouseButton.new()
			event.button_index = button
			InputMap.action_add_event(action, event)
