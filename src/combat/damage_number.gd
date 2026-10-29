class_name DamageNumber
extends Label3D
## 맞힌 자리에 떠오르는 피해 숫자. 쏜 사람에게만 보인다. 머리를 맞히면 노란색으로 크게 보인다.

const LIFETIME := 0.8
const RISE_SPEED := 1.2

var _age := 0.0


static func spawn(parent: Node, position: Vector3, amount: float, headshot: bool) -> void:
	var number := DamageNumber.new()
	number.text = str(roundi(amount))
	number.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	number.no_depth_test = true
	number.fixed_size = true
	number.pixel_size = 0.0012
	number.font_size = 40 if headshot else 30
	number.outline_size = 10
	number.modulate = Color(1, 0.85, 0.2) if headshot else Color(1, 1, 1)
	number.top_level = true
	parent.add_child(number)
	number.global_position = position + Vector3(randf_range(-0.15, 0.15), 0.2, randf_range(-0.15, 0.15))


func _process(delta: float) -> void:
	_age += delta
	global_position.y += RISE_SPEED * delta
	modulate.a = 1.0 - clampf(_age / LIFETIME, 0.0, 1.0)
	if _age >= LIFETIME:
		queue_free()
