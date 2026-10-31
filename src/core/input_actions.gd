extends Node
## 게임 입력 동작을 등록한다. 기본 키 배치는 아크나이츠: 엔드필드 PC판을 따른다.
##   왼쪽 클릭 공격, 오른쪽 클릭·Shift 회피(누르고 있으면 질주), 1 배틀 스킬(길게 누르면 궁극기),
##   가운데 클릭 대상 고정, Space 점프. V 1인칭·3인칭, ` 자유 시점.
## 키 재설정(설정 메뉴)은 이 기본값 위에 덮어쓴다(GameSettings.key_overrides).

const MOVE_FORWARD := &"move_forward"
const MOVE_BACK := &"move_back"
const MOVE_LEFT := &"move_left"
const MOVE_RIGHT := &"move_right"
const JUMP := &"jump"
const ATTACK := &"attack"
## 회피. 회피한 뒤에도 누르고 있으면 질주한다.
const DODGE := &"dodge"
## 배틀 스킬. 궁극기 에너지가 차 있으면 길게 눌러 궁극기를 쓴다.
const SKILL := &"skill"
## 궁극기만 따로 쓰는 키. 엔드필드에는 없지만 캐릭터가 한 명이라 하나 더 둔다.
const ULTIMATE := &"ultimate"
const LOCK_ON := &"lock_on"
## 쓰러진 동료 곁에서 누르고 있으면 일으킨다.
const INTERACT := &"interact"
const TOGGLE_VISOR := &"toggle_visor"
## 기본 시점을 1인칭·3인칭으로 바꾼다.
const TOGGLE_VIEW := &"toggle_view"
## 자유 시점을 켜고 끈다(휠로 얼굴까지 가까이 당기거나 멀리 밀 수 있다).
const FREE_VIEW := &"free_view"
## 로비: 캐릭터 화면 열기, 작전 출발(방장)
const CHARACTER_MENU := &"character_menu"
const START_RUN := &"start_run"
const PAUSE := &"pause"
const DEBUG_OVERLAY := &"debug_overlay"

const DEFAULT_KEYS := {
	MOVE_FORWARD: [KEY_W],
	MOVE_BACK: [KEY_S],
	MOVE_LEFT: [KEY_A],
	MOVE_RIGHT: [KEY_D],
	JUMP: [KEY_SPACE],
	DODGE: [KEY_SHIFT],
	SKILL: [KEY_1],
	ULTIMATE: [KEY_Q],
	INTERACT: [KEY_F],
	# 머리 장비(바이저)를 벗거나 쓴다. 엔드필드에는 없는 키라 비어 있는 H(Head)를 쓴다.
	TOGGLE_VISOR: [KEY_H],
	TOGGLE_VIEW: [KEY_V],
	FREE_VIEW: [KEY_QUOTELEFT],
	CHARACTER_MENU: [KEY_C],
	START_RUN: [KEY_ENTER],
	PAUSE: [KEY_ESCAPE],
	DEBUG_OVERLAY: [KEY_F3],
}

const DEFAULT_MOUSE_BUTTONS := {
	ATTACK: [MOUSE_BUTTON_LEFT],
	DODGE: [MOUSE_BUTTON_RIGHT],
	LOCK_ON: [MOUSE_BUTTON_MIDDLE],
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
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		elif DEFAULT_KEYS.has(action):
			# 키와 마우스 버튼을 함께 쓰는 동작(회피)은 키를 넣은 뒤 버튼도 넣는다.
			var has_button := false
			for event in InputMap.action_get_events(action):
				has_button = has_button or event is InputEventMouseButton
			if has_button:
				continue
		else:
			continue
		for button: MouseButton in DEFAULT_MOUSE_BUTTONS[action]:
			var event := InputEventMouseButton.new()
			event.button_index = button
			InputMap.action_add_event(action, event)
