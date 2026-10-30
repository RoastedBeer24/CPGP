class_name StealthNoise
extends RefCounted
## 적이 들을 수 있는 소리. 호스트에서만 퍼뜨린다(적의 판단은 호스트가 하므로).
## 소리가 난 곳에서 radius 안에 있는 적이 hear()로 받는다. 벽은 소리를 막지 않는다.

enum Kind { FOOTSTEP, GUNSHOT, MELEE }

## 소리 크기(들리는 거리, m). 조정은 여기서 한다.
const GUNSHOT_RADIUS := 35.0
const MELEE_RADIUS := 5.0
const SPRINT_STEP_RADIUS := 9.0
const WALK_STEP_RADIUS := 4.0


static func emit(source: Node, position: Vector3, radius: float, kind: Kind) -> void:
	if radius <= 0.0 or not source.is_inside_tree() or not source.multiplayer.is_server():
		return
	var world := source.get_viewport().find_world_3d()
	for node in source.get_tree().get_nodes_in_group(Enemy.GROUP):
		var enemy := node as Enemy
		if enemy == null or enemy.get_viewport().find_world_3d() != world:
			continue
		if enemy.global_position.distance_to(position) <= radius:
			enemy.hear(position, kind)
