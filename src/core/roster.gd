class_name Roster
extends RefCounted
## 같은 판(같은 3D 세계)에 있는 플레이어와 적 목록.
## 그룹은 장면 트리 전체에 걸리므로, 한 프로세스에 여러 피어를 띄우는 코옵 테스트에서는 다른 피어의 노드까지
## 섞여 나온다. 3D 세계가 같은 것만 고른다.


static func players(of: Node3D) -> Array[Player]:
	var found: Array[Player] = []
	if not of.is_inside_tree():
		return found
	var world := of.get_world_3d()
	for node: Node in of.get_tree().get_nodes_in_group(Player.GROUP):
		var player := node as Player
		if player != null and player.is_inside_tree() and player.get_world_3d() == world:
			found.append(player)
	return found


static func enemies(of: Node3D) -> Array[Enemy]:
	var found: Array[Enemy] = []
	if not of.is_inside_tree():
		return found
	var world := of.get_world_3d()
	for node: Node in of.get_tree().get_nodes_in_group(Enemy.GROUP):
		var enemy := node as Enemy
		if enemy != null and enemy.is_inside_tree() and enemy.get_world_3d() == world:
			found.append(enemy)
	return found
