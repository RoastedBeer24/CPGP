class_name HideSpot
extends Node3D
## 시체를 숨길 수 있는 곳(컨테이너 등). 몸을 들고 radius 안에서 상호작용 키를 누르면 숨긴다.

const GROUP := &"hide_spots"

@export var radius := 2.2


func _ready() -> void:
	add_to_group(GROUP)


## position에서 가장 가까운, 닿을 수 있는 숨길 곳. 없으면 null.
static func near(from: Node3D, position: Vector3) -> HideSpot:
	var best: HideSpot
	var best_distance := INF
	for node in from.get_tree().get_nodes_in_group(GROUP):
		var spot := node as HideSpot
		if spot == null or spot.get_viewport().find_world_3d() != from.get_viewport().find_world_3d():
			continue
		var distance := spot.global_position.distance_to(position)
		if distance <= spot.radius and distance < best_distance:
			best = spot
			best_distance = distance
	return best
