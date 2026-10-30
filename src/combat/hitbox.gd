class_name Hitbox
extends Area3D
## 피격 판정 영역. 근접 공격은 이 영역을 맞혀서 연결된 Health에 피해를 준다.

const LAYER := 4  # 물리 레이어 3번 "hitbox"의 비트 값

@export var health_path: NodePath
## 같은 편끼리는 피해를 주지 않는다. 플레이어는 "player", 적은 "enemy".
@export var team := &"enemy"

var health: Health


func _ready() -> void:
	collision_layer = LAYER
	collision_mask = 0
	monitoring = false
	health = get_node(health_path) as Health
