class_name PlayerIntent
extends RefCounted
## 한 물리 프레임 동안 플레이어가 하려는 것. 키보드·마우스에서 읽거나, 테스트에서 직접 채운다.
## "pressed"는 이번 프레임에 새로 눌렸는지다. 플레이어가 읽은 뒤 false로 되돌린다.

## x: 오른쪽(+), y: 앞(+). 길이는 1 이하. 카메라가 보는 방향 기준이다.
var move := Vector2.ZERO
var jump_pressed := false
var attack_pressed := false
var dodge_pressed := false
## 회피 키를 누르고 있는지. 회피한 뒤에도 누르고 있으면 질주한다.
var dodge_held := false
## 질주 키(Shift)를 누르고 있는지. 회피 없이 바로 질주한다.
var sprint_held := false
var skill_pressed := false
var skill_held := false
var ultimate_pressed := false
var lock_on_pressed := false
## 쓰러진 동료 곁에서 누르고 있으면 일으킨다.
var interact_held := false
var visor_pressed := false


static func from_device() -> PlayerIntent:
	var intent := PlayerIntent.new()
	intent.move = Input.get_vector(
		InputActions.MOVE_LEFT, InputActions.MOVE_RIGHT, InputActions.MOVE_BACK, InputActions.MOVE_FORWARD
	)
	intent.jump_pressed = Input.is_action_just_pressed(InputActions.JUMP)
	intent.attack_pressed = Input.is_action_just_pressed(InputActions.ATTACK)
	intent.dodge_pressed = Input.is_action_just_pressed(InputActions.DODGE)
	intent.dodge_held = Input.is_action_pressed(InputActions.DODGE)
	intent.sprint_held = Input.is_action_pressed(InputActions.SPRINT)
	intent.skill_pressed = Input.is_action_just_pressed(InputActions.SKILL)
	intent.skill_held = Input.is_action_pressed(InputActions.SKILL)
	intent.ultimate_pressed = Input.is_action_just_pressed(InputActions.ULTIMATE)
	intent.lock_on_pressed = Input.is_action_just_pressed(InputActions.LOCK_ON)
	intent.interact_held = Input.is_action_pressed(InputActions.INTERACT)
	intent.visor_pressed = Input.is_action_just_pressed(InputActions.TOGGLE_VISOR)
	return intent


func copy() -> PlayerIntent:
	var other := PlayerIntent.new()
	other.move = move
	other.jump_pressed = jump_pressed
	other.attack_pressed = attack_pressed
	other.dodge_pressed = dodge_pressed
	other.dodge_held = dodge_held
	other.sprint_held = sprint_held
	other.skill_pressed = skill_pressed
	other.skill_held = skill_held
	other.ultimate_pressed = ultimate_pressed
	other.lock_on_pressed = lock_on_pressed
	other.interact_held = interact_held
	other.visor_pressed = visor_pressed
	return other


## 한 번만 처리해야 하는 입력(눌림)을 지운다.
func consume_edges() -> void:
	jump_pressed = false
	attack_pressed = false
	dodge_pressed = false
	skill_pressed = false
	ultimate_pressed = false
	lock_on_pressed = false
	visor_pressed = false
