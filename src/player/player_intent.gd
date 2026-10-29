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
	return intent


func consume_edges() -> void:
	jump_pressed = false
	crouch_pressed = false
