class_name CombatQuery
extends RefCounted
## 사격과 근접 공격의 판정 계산. 호스트에서 실제 피해를 정할 때와,
## 조종하는 피어에서 효과(탄 궤적)를 미리 보여 줄 때 같은 계산을 쓴다.

const WORLD_MASK := 1
const HITBOX_MASK := Hitbox.LAYER


## 한 발의 탄이 맞은 결과
class Hit:
	var position := Vector3.ZERO
	var normal := Vector3.ZERO
	## 맞은 Hitbox. 벽이나 바닥이면 null.
	var hitbox: Hitbox
	var distance := 0.0


## 퍼짐을 적용한 탄 방향들. 같은 시드면 어느 피어에서 계산해도 같은 결과가 나온다.
static func pellet_directions(direction: Vector3, pellets: int, spread_degrees: float, rng_seed: int) -> Array[Vector3]:
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	var forward := direction.normalized()
	var up := Vector3.UP if absf(forward.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	var right := forward.cross(up).normalized()
	up = right.cross(forward).normalized()
	var result: Array[Vector3] = []
	var max_angle := deg_to_rad(spread_degrees)
	for i in pellets:
		# 원뿔 안에 고르게 퍼지도록 반지름에 제곱근을 쓴다.
		var radius := tan(max_angle) * sqrt(rng.randf())
		var angle := rng.randf() * TAU
		var offset := right * cos(angle) * radius + up * sin(angle) * radius
		result.append((forward + offset).normalized())
	return result


## 탄 한 발을 쏜다. 같은 팀의 Hitbox는 통과한다.
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


## 근접 공격 범위 안에서 맞은 Hitbox들. Health 하나당 가장 배율이 높은 부위 하나만 돌려준다.
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
		if rad_to_deg(forward.angle_to(to_target)) > arc_degrees:
			continue
		# 벽 너머는 베지 않는다.
		var wall := PhysicsRayQueryParameters3D.create(origin, hitbox.global_position, WORLD_MASK)
		if not space.intersect_ray(wall).is_empty():
			continue
		var key := hitbox.health.get_instance_id()
		var current := best.get(key) as Hitbox
		if current == null or hitbox.multiplier(2.0) > current.multiplier(2.0):
			best[key] = hitbox
	var hits: Array[Hitbox] = []
	for hitbox: Hitbox in best.values():
		hits.append(hitbox)
	return hits
