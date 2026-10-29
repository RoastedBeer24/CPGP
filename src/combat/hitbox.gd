class_name Hitbox
extends Area3D
## 피격 판정 영역. 사격과 근접 공격은 이 영역을 맞혀서 연결된 Health에 피해를 준다.
## 머리, 몸통처럼 부위마다 Hitbox를 따로 두고 배율을 다르게 준다.

enum Part { BODY, HEAD, LIMB }

const LAYER := 4  # 물리 레이어 3번 "hitbox"의 비트 값

@export var part := Part.BODY
@export var health_path: NodePath
## 같은 편끼리는 피해를 주지 않는다. 플레이어끼리는 "player", 적은 "enemy".
@export var team := &"enemy"

var health: Health


func _ready() -> void:
	collision_layer = LAYER
	collision_mask = 0
	monitoring = false
	health = get_node(health_path) as Health


func multiplier(headshot_multiplier: float) -> float:
	match part:
		Part.HEAD:
			return headshot_multiplier
		Part.LIMB:
			return 0.75
		_:
			return 1.0
