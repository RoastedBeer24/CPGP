class_name Senses
extends RefCounted
## 적의 시야 계산. 감지 게이지가 얼마나 빨리 차는지(0~1)를 돌려준다.
## 거리, 시야 원뿔, 가림(벽), 웅크림을 따진다. 결과가 0이면 보이지 않는 것이다.

## 이 거리(수평, m) 안이면 뒤에 있어도 느낀다.
const BUMP_DISTANCE := 0.7


## eye(눈 위치)와 forward(앞 방향)를 가진 적이 player를 얼마나 잘 보는지. 0이면 못 본다.
static func player_visibility(space: PhysicsDirectSpaceState3D, eye: Vector3, forward: Vector3, data: EnemyData, player: Player) -> float:
	if not player.health.is_alive():
		return 0.0
	var points := PackedVector3Array([player.head.global_position, player.global_position + Vector3.UP * 0.5])
	var amount := point_visibility(space, eye, forward, data.sight_range, data.sight_half_angle, data.close_range, points)
	if amount <= 0.0:
		return 0.0
	# 웅크리면 덜 보인다.
	return amount * lerpf(1.0, data.crouch_visibility, player.crouch_blend)


## points 중 하나라도 시야 안에서 가리지 않고 보이면, 거리에 따른 비율(가까우면 1)을 돌려준다.
static func point_visibility(space: PhysicsDirectSpaceState3D, eye: Vector3, forward: Vector3, sight_range: float,
		half_angle_degrees: float, close_range: float, points: PackedVector3Array) -> float:
	var flat_forward := Vector3(forward.x, 0.0, forward.z).normalized()
	for point in points:
		var to_point := point - eye
		var distance := to_point.length()
		if distance > sight_range or distance < 0.01:
			continue
		# 위아래보다 좌우가 중요하므로 수평 방향으로 원뿔을 잰다. 몸이 닿을 만큼(BUMP_DISTANCE) 가까우면
		# 각도와 관계없이 느낀다. 더 넓히면 뒤에서 다가가 제압할 수 없게 된다(제압 거리 1.8m).
		var flat := Vector3(to_point.x, 0.0, to_point.z)
		if flat.length() > BUMP_DISTANCE:
			var angle := rad_to_deg(flat_forward.angle_to(flat.normalized()))
			if angle > half_angle_degrees:
				continue
		if not has_line_of_sight(space, eye, point):
			continue
		if distance <= close_range:
			return 1.0
		# 멀수록 천천히 알아챈다. 시야 끝에서는 가까울 때의 1/4.
		return lerpf(1.0, 0.25, (distance - close_range) / maxf(sight_range - close_range, 0.01))
	return 0.0


## 두 점 사이를 벽(world 레이어)이 가리지 않는지
static func has_line_of_sight(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(from, to, CombatQuery.WORLD_MASK)
	return space.intersect_ray(query).is_empty()
