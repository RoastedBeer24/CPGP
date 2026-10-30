class_name DamageNumber
extends Label3D
## 맞힌 자리에 떠오르는 피해 숫자. 때린 사람에게만 보인다.
## 원석 결정을 깨뜨린 타격은 주황색으로 크게, 경직을 일으킨 타격은 노란색으로 보인다.

const LIFETIME := 0.9
const RISE_SPEED := 1.1
const SHATTER_COLOR := Color(1, 0.55, 0.1)
const BREAK_COLOR := Color(1, 0.88, 0.25)

var _age := 0.0


static func spawn(parent: Node, position: Vector3, amount: float, flags: int) -> void:
	var number := DamageNumber.new()
	number.text = str(roundi(amount))
	number.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	number.no_depth_test = true
	number.fixed_size = true
	number.pixel_size = 0.0012
	number.outline_size = 10
	number.font_size = 30
	number.modulate = Color(1, 1, 1)
	if flags & Player.HIT_SHATTER:
		number.font_size = 44
		number.modulate = SHATTER_COLOR
	elif flags & Player.HIT_BREAK:
		number.font_size = 38
		number.modulate = BREAK_COLOR
	number.top_level = true
	parent.add_child(number)
	number.global_position = position + Vector3(randf_range(-0.2, 0.2), 0.3, randf_range(-0.2, 0.2))


func _process(delta: float) -> void:
	_age += delta
	global_position.y += RISE_SPEED * delta
	modulate.a = 1.0 - clampf((_age - LIFETIME * 0.5) / (LIFETIME * 0.5), 0.0, 1.0)
	if _age >= LIFETIME:
		queue_free()
