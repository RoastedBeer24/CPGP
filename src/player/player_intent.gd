class_name PlayerIntent
extends RefCounted
## 한 물리 프레임 동안 플레이어가 하려는 것. 키보드에서 읽거나, 테스트에서 직접 채운다.

## x: 오른쪽(+), y: 앞(+). 길이는 1 이하.
var move := Vector2.ZERO
var sprint := false
var jump_held := false
## 이번 프레임에 새로 눌렸는지. 플레이어가 읽은 뒤 false로 되돌린다.
var jump_pressed := false
var crouch_held := false
var crouch_pressed := false
## 회피(대시) 방향. x: 오른쪽(+), y: 앞(+). 0이면 회피하지 않음.
var dodge := Vector2.ZERO

var fire_held := false
var fire_pressed := false
var aim_held := false
var reload_pressed := false
## 1~3이면 그 번호의 무기로 바꾼다. 0이면 그대로.
var weapon_slot := 0
## +1이면 다음 무기, -1이면 이전 무기.
var weapon_cycle := 0
## 스캔 모드(누르고 있는 동안). 이때 1~3 키는 무기 대신 퀵핵을 고른다.
var scan_held := false
## 바이저를 벗거나 쓴다 (눌림)
var visor_pressed := false


static func from_device() -> PlayerIntent:
	var intent := PlayerIntent.new()
	var raw := Input.get_vector(
		InputActions.MOVE_LEFT, InputActions.MOVE_RIGHT, InputActions.MOVE_BACK, InputActions.MOVE_FORWARD
	)
	intent.move = raw
	intent.sprint = Input.is_action_pressed(InputActions.SPRINT)
	intent.jump_held = Input.is_action_pressed(InputActions.JUMP)
	intent.jump_pressed = Input.is_action_just_pressed(InputActions.JUMP)
	intent.crouch_held = Input.is_action_pressed(InputActions.CROUCH)
	intent.crouch_pressed = Input.is_action_just_pressed(InputActions.CROUCH)
	intent.fire_held = Input.is_action_pressed(InputActions.FIRE)
	intent.fire_pressed = Input.is_action_just_pressed(InputActions.FIRE)
	intent.aim_held = Input.is_action_pressed(InputActions.AIM)
	intent.reload_pressed = Input.is_action_just_pressed(InputActions.RELOAD)
	intent.scan_held = Input.is_action_pressed(InputActions.SCAN)
	intent.visor_pressed = Input.is_action_just_pressed(InputActions.TOGGLE_VISOR)
	for slot in 3:
		if Input.is_action_just_pressed(StringName("weapon_%d" % (slot + 1))):
			intent.weapon_slot = slot + 1
	return intent


func copy() -> PlayerIntent:
	var other := PlayerIntent.new()
	other.move = move
	other.sprint = sprint
	other.jump_held = jump_held
	other.jump_pressed = jump_pressed
	other.crouch_held = crouch_held
	other.crouch_pressed = crouch_pressed
	other.dodge = dodge
	other.fire_held = fire_held
	other.fire_pressed = fire_pressed
	other.aim_held = aim_held
	other.reload_pressed = reload_pressed
	other.weapon_slot = weapon_slot
	other.weapon_cycle = weapon_cycle
	other.scan_held = scan_held
	other.visor_pressed = visor_pressed
	return other


## 한 번만 처리해야 하는 입력(눌림)을 지운다.
func consume_edges() -> void:
	jump_pressed = false
	crouch_pressed = false
	dodge = Vector2.ZERO
	fire_pressed = false
	reload_pressed = false
	weapon_slot = 0
	weapon_cycle = 0
	visor_pressed = false
