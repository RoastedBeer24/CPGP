class_name CombatQuery
extends RefCounted
## 공격 판정 계산. 호스트에서 실제 피해를 정할 때와,
## 조종하는 피어에서 맞힌 느낌(멈춤, 불꽃)을 미리 보여 줄 때 같은 계산을 쓴다.

const WORLD_MASK := 1
const HITBOX_MASK := Hitbox.LAYER


## 광선이 맞은 결과
class Hit:
	var position := Vector3.ZERO
	var normal := Vector3.ZERO
	## 맞은 Hitbox. 벽이나 바닥이면 null.
	var hitbox: Hitbox
	var distance := 0.0


## 광선을 쏜다. 같은 팀의 Hitbox는 통과한다.
static func trace(space: PhysicsDirectSpaceState3D, origin: Vector3, direction: Vector3, max_range: float, shooter_team: StringName, exclude: Array[RID] = []) -> Hit:
	var excluded := exclude.duplicate()
	var target := origin + direction * max_range
	for attempt in 8:
		var query := PhysicsRayQueryParameters3D.create(origin, target, WORLD_MASK | HITBOX_MASK, excluded)
		query.collide_with_areas = true
		var result := space.intersect_ray(query)
		if result.is_empty():
			return null
		var hitbox := result["collider"] as Hitbox
		if hitbox != null and hitbox.team == shooter_team:
			excluded.append(result["rid"])
			continue
		var hit := Hit.new()
		hit.position = result["position"]
		hit.normal = result["normal"]
		hit.hitbox = hitbox
		hit.distance = origin.distance_to(hit.position)
		return hit
	return null


## 근접 공격 범위(origin에서 reach 안, direction에서 arc도 안) 안에서 맞은 Hitbox들. Health 하나당 하나만 돌려준다.
static func melee(space: PhysicsDirectSpaceState3D, origin: Vector3, direction: Vector3, reach: float, arc_degrees: float, shooter_team: StringName) -> Array[Hitbox]:
	var sphere := SphereShape3D.new()
	sphere.radius = reach
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform = Transform3D(Basis(), origin)
	query.collision_mask = HITBOX_MASK
	query.collide_with_areas = true
	query.collide_with_bodies = false

	var best: Dictionary = {}
	var forward := direction.normalized()
	for result in space.intersect_shape(query, 32):
		var hitbox := result["collider"] as Hitbox
		if hitbox == null or hitbox.team == shooter_team or hitbox.health == null:
			continue
		var to_target := hitbox.global_position - origin
		if to_target.length() > reach + 0.5:
			continue
		var flat := Vector3(to_target.x, 0.0, to_target.z)
		# arc가 180도 이상이면 둘레 전체다(바로 뒤는 각도가 180을 아주 조금 넘게 계산되어 빠졌다).
		if arc_degrees < 180.0 and flat.length() > 0.3 and rad_to_deg(Vector3(forward.x, 0.0, forward.z).angle_to(flat)) > arc_degrees:
			continue
		# 벽 너머는 베지 않는다.
		var wall := PhysicsRayQueryParameters3D.create(origin, hitbox.global_position, WORLD_MASK)
		if not space.intersect_ray(wall).is_empty():
			continue
		var key := hitbox.health.get_instance_id()
		if not best.has(key):
			best[key] = hitbox
	var hits: Array[Hitbox] = []
	for hitbox: Hitbox in best.values():
		hits.append(hitbox)
	return hits
