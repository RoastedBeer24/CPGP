class_name Enemy
extends CharacterBody3D
## 적(경비, 중장갑병). 순찰하다가 보거나 들으면 의심 → 수색 → 전투로 경계를 높인다.
##
## 경계 단계:
##   무경계: 순찰 경로를 돈다(경로가 없으면 제자리를 지킨다).
##   의심: 감지 게이지가 조금 찼거나 발소리를 들었다. 그쪽을 돌아보고 확인하러 간다.
##   수색: 총성을 들었거나, 시체를 봤거나, 동료가 불렀거나, 대상을 놓쳤다. 그곳과 주변을 뒤진다.
##   전투: 감지 게이지가 다 찼거나 공격받았다. 엄폐 지점으로 움직이며 쏘고, 근처 동료를 부른다.
## 쓰러지면(사망, 기절) 몸이 남고, 플레이어가 들어 옮기거나 컨테이너에 숨길 수 있다.
## 퀵핵(주의 분산, 과열, 무기 오작동)을 받을 수 있고, 넷러너는 총 대신 플레이어에게 역해킹을 올린다.
##
## 판단과 이동은 호스트만 하고, 위치·경계 단계·감지 게이지·쓰러짐 상태는 StateSync로 모두에게 퍼진다.
## 머리 위 표시("?", "!")와 쓰러진 모습은 동기화된 값으로 각 피어가 그린다.

enum Alert { UNAWARE, SUSPICIOUS, SEARCHING, COMBAT }
enum Condition { ACTIVE, DEAD, KNOCKED_OUT }

## 모든 적이 들어가는 그룹. 소리와 동료 호출에 쓴다.
const GROUP := &"enemies"
const COVER_GROUP := &"cover_points"
const TEAM := &"enemy"
const AIM_HEIGHT := 1.1
const GRAVITY := 18.0
## 이 거리 안에서 뒤로 다가가면 제압할 수 있다.
const TAKEDOWN_RANGE := 1.8
## 쓰러진 몸을 들 수 있는 거리
const BODY_REACH := 2.2
const ARRIVE_DISTANCE := 0.6
const DEFAULT_DATA := "res://data/enemies/guard.tres"

## 비워 두면 일반 경비 수치를 쓴다.
@export var data: EnemyData
## 순찰 경로. Marker3D 자식들을 차례로 돈다. 비워 두면 제자리를 지킨다.
@export var patrol_route: NodePath
## 0이면 되살아나지 않는다. 시험장에서는 반복 연습을 위해 되살린다.
@export var respawn_delay := 0.0

# ---- 동기화되는 상태 ----
var alert := Alert.UNAWARE
## 0~1. 1이 되면 전투.
var detection := 0.0
var condition := Condition.ACTIVE
## 컨테이너에 숨겨졌는지
var stashed := false
## 이 몸을 들고 있는 플레이어의 피어 번호. 0이면 아무도 들지 않음.
var carrier_peer := 0

# ---- 호스트 전용 ----
var target: Player
var last_known_position := Vector3.ZERO
## 이 몸을 다른 적이 이미 발견했는지 (같은 시체로 경보가 반복되지 않게)
var body_discovered := false

var _waypoints: Array[Vector3] = []
var _waypoint_index := 0
var _wait_left := 0.0
var _state_time := 0.0
var _cooldown := 0.0
var _since_seen := 0.0
var _investigate_point := Vector3.ZERO
var _search_points: Array[Vector3] = []
var _cover_point := Vector3.ZERO
var _has_cover := false
var _cover_repick_left := 0.0
var _move_target := Vector3.ZERO
var _has_move_target := false
var _move_speed := 0.0
var _face_point := Vector3.ZERO
var _has_face_point := false
var _respawn_left := 0.0
var _home: Transform3D
var _applied_condition := Condition.ACTIVE
# 퀵핵 효과 (호스트)
var _glitch_left := 0.0
var _burn_left := 0.0
var _burn_dps := 0.0
# 넷러너의 역해킹 (호스트)
var _netrun_target: Player
var _netrun_left := 0.0
var _applied_stashed := false

@onready var health: Health = $Health
@onready var body_mesh: Node3D = $Body
@onready var health_label: Label3D = $HealthLabel
@onready var alert_label: Label3D = $AlertLabel
@onready var agent: NavigationAgent3D = $NavigationAgent3D
@onready var collision: CollisionShape3D = $CollisionShape3D
@onready var hitboxes: Array[Hitbox] = [$HeadHitbox, $BodyHitbox]
@onready var hackable: Hackable = $Hackable


func _ready() -> void:
	if data == null:
		# Enemy와 서로 참조하는 스크립트가 많아 리소스는 실행 시점에 불러온다.
		data = load(DEFAULT_DATA) as EnemyData
	add_to_group(GROUP)
	health.max_health = data.max_health
	health.armor = data.armor
	health.current = data.max_health
	health.died.connect(_on_died)
	health.damaged.connect(_on_damaged)
	hackable.display_name = data.display_name
	_apply_look()
	_home = global_transform
	var route := get_node_or_null(patrol_route)
	if route != null:
		for marker in route.get_children():
			if marker is Node3D:
				_waypoints.append((marker as Node3D).global_position)


func is_active() -> bool:
	return condition == Condition.ACTIVE


## 쓰러진 몸이 아직 바닥에 보이는지 (숨겨지거나 들려 있지 않음)
func is_visible_body() -> bool:
	return condition != Condition.ACTIVE and not stashed and carrier_peer == 0


func eye_position() -> Vector3:
	return global_position + Vector3.UP * data.eye_height


func forward() -> Vector3:
	return -global_basis.z


# ---- 플레이어와의 상호작용 (판정은 호스트) ----

## player가 지금 이 적을 제압할 수 있는지. 전투 중이 아니고, 뒤에 있거나 아직 못 알아챘을 때.
## 프롬프트 표시용으로 모든 피어에서 부르고, 실제 판정은 호스트에서 다시 한다.
func can_be_taken_down_by(player: Player) -> bool:
	if not is_active() or alert == Alert.COMBAT or not player.health.is_alive():
		return false
	var to_player := player.global_position - global_position
	to_player.y = 0.0
	if to_player.length() > TAKEDOWN_RANGE:
		return false
	var behind := forward().dot(to_player.normalized()) < 0.0
	return behind or detection < data.suspicion_threshold


func try_takedown(player: Player) -> bool:
	if not multiplayer.is_server() or not can_be_taken_down_by(player):
		return false
	_go_down(Condition.KNOCKED_OUT)
	return true


func can_be_picked_up_by(player: Player) -> bool:
	if not is_visible_body():
		return false
	return global_position.distance_to(player.global_position) <= BODY_REACH


func pick_up(player: Player) -> bool:
	if not multiplayer.is_server() or not can_be_picked_up_by(player):
		return false
	carrier_peer = player.get_multiplayer_authority()
	return true


## 들고 있던 몸을 내려놓는다. 바닥까지 떨어뜨린다.
func drop() -> void:
	if not multiplayer.is_server():
		return
	carrier_peer = 0
	var space := get_world_3d().direct_space_state
	var from := global_position + Vector3.UP * 0.5
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 6.0, CombatQuery.WORLD_MASK)
	var hit := space.intersect_ray(query)
	if not hit.is_empty():
		global_position = hit["position"]


## 컨테이너에 숨긴다. 숨긴 몸은 다른 적이 발견하지 못한다.
func stash() -> void:
	if not multiplayer.is_server():
		return
	carrier_peer = 0
	stashed = true


# ---- 해킹 (판정은 호스트) ----

func is_hackable() -> bool:
	return is_active()


## 스캔 화면에 보여 줄 정보
func scan_lines() -> PackedStringArray:
	var state: String = ["무경계", "의심", "수색", "전투"][alert]
	var lines := PackedStringArray([
		data.display_name,
		"상태: %s" % state,
		"체력 %d / %d   장갑 %d" % [ceili(health.current), int(data.max_health), int(data.armor)],
	])
	if data.netrunner:
		lines.append("넷러너: 보이면 역해킹을 올린다")
	if data.armor >= 50.0:
		lines.append("약점: 과열(장갑 무시)")
	return lines


func apply_quickhack(hack: QuickhackData, hacker: Player) -> void:
	if not multiplayer.is_server() or not is_active():
		return
	match hack.effect:
		QuickhackData.Effect.DISTRACT:
			# 해커 반대쪽 6m에서 소리가 난 것처럼 그쪽을 확인하러 간다(해커에게서 멀어지게 꾄다).
			# 전투 중이면 넘어가지 않는다.
			if alert != Alert.COMBAT:
				var away := global_position - hacker.global_position
				away.y = 0.0
				away = away.normalized() if away.length() > 0.1 else global_basis.z
				_investigate(_closest_walkable(global_position + away * 6.0))
		QuickhackData.Effect.OVERHEAT:
			_burn_left = hack.duration
			_burn_dps = hack.damage_per_second
			# 누가 했는지는 모르므로 자기 주변을 수색한다.
			if alert != Alert.COMBAT:
				_start_search(global_position)
		QuickhackData.Effect.WEAPON_GLITCH:
			_glitch_left = hack.duration
			_cancel_netrun()


func is_weapon_glitched() -> bool:
	return _glitch_left > 0.0


func _tick_hacks(delta: float) -> void:
	_glitch_left = maxf(_glitch_left - delta, 0.0)
	if _burn_left > 0.0:
		_burn_left -= delta
		health.apply_damage(DamageInfo.hack(_burn_dps * delta, 0, global_position, &"overheat"))


## 넷러너: 보이는 대상에게 역해킹을 올린다. 시야를 끊거나 맞으면 처음부터 다시 해야 한다.
func _netrun(delta: float, sees_target: bool) -> void:
	var in_range := sees_target and _flat_distance(global_position, target.global_position) <= data.hack_range
	if not in_range or _glitch_left > 0.0 or _cooldown > 0.0:
		_cancel_netrun()
		return
	if _netrun_target != target:
		_cancel_netrun()
		_netrun_target = target
		_netrun_left = data.hack_upload_time
	_netrun_left -= delta
	_netrun_target.cyberdeck.incoming_progress = clampf(1.0 - _netrun_left / data.hack_upload_time, 0.0, 1.0)
	if _netrun_left <= 0.0:
		_netrun_target.cyberdeck.apply_overheat(data.hack_damage_per_second, data.hack_duration)
		_cancel_netrun()
		_cooldown = data.hack_cooldown


func _cancel_netrun() -> void:
	if _netrun_target != null and is_instance_valid(_netrun_target):
		_netrun_target.cyberdeck.incoming_progress = 0.0
	_netrun_target = null
	_netrun_left = 0.0


# ---- 감각 입력 (호스트) ----

## 소리를 들었다. StealthNoise.emit이 부른다.
func hear(position: Vector3, kind: StealthNoise.Kind) -> void:
	if not is_active() or not multiplayer.is_server():
		return
	match alert:
		Alert.COMBAT:
			if _since_seen > 0.5:
				last_known_position = position
		Alert.SEARCHING:
			_start_search(position)
		_:
			if kind == StealthNoise.Kind.FOOTSTEP:
				_investigate(position)
			else:
				_start_search(position)


## 동료가 불렀다. 그곳을 수색한다.
func notify_alarm(position: Vector3) -> void:
	if not is_active() or alert == Alert.COMBAT:
		return
	_start_search(position)


# ---- 판단 (호스트) ----

func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	if not is_active():
		_tick_down(delta)
		return
	_state_time += delta
	_cooldown = maxf(_cooldown - delta, 0.0)
	_tick_hacks(delta)
	if not is_active():
		return
	_has_move_target = false
	_has_face_point = false
	_perceive(delta)
	match alert:
		Alert.UNAWARE:
			_patrol(delta)
		Alert.SUSPICIOUS:
			_suspicious()
		Alert.SEARCHING:
			_search()
		Alert.COMBAT:
			_fight(delta)
	_move(delta)


func _perceive(delta: float) -> void:
	var space := get_world_3d().direct_space_state
	var eye := eye_position()
	var best: Player
	var best_visibility := 0.0
	for node in get_tree().get_nodes_in_group(Player.GROUP):
		var player := node as Player
		if player == null or player.get_world_3d() != get_world_3d():
			continue
		var amount := Senses.player_visibility(space, eye, forward(), data, player)
		if amount > best_visibility:
			best = player
			best_visibility = amount

	if best != null:
		last_known_position = best.global_position
		if alert == Alert.COMBAT:
			target = best
			_since_seen = 0.0
			detection = 1.0
		else:
			var rate := data.detect_rate * (1.0 if alert == Alert.UNAWARE else data.alert_detect_multiplier)
			detection = minf(detection + best_visibility * rate * delta, 1.0)
			if detection >= 1.0:
				_enter_combat(best)
			elif detection >= data.suspicion_threshold and alert == Alert.UNAWARE:
				_investigate(best.global_position)
			elif alert == Alert.SUSPICIOUS:
				_investigate_point = best.global_position
	elif alert == Alert.COMBAT:
		_since_seen += delta
		if _since_seen >= data.lose_target_time:
			target = null
			_start_search(last_known_position)
	else:
		detection = maxf(detection - data.detect_decay * delta, 0.0)

	if alert != Alert.COMBAT:
		_look_for_bodies(space, eye)


func _look_for_bodies(space: PhysicsDirectSpaceState3D, eye: Vector3) -> void:
	for node in get_tree().get_nodes_in_group(GROUP):
		var other := node as Enemy
		if other == null or other == self or other.body_discovered or not other.is_visible_body():
			continue
		if other.get_world_3d() != get_world_3d():
			continue
		var point := PackedVector3Array([other.global_position + Vector3.UP * 0.3])
		if Senses.point_visibility(space, eye, forward(), data.body_sight_range, data.sight_half_angle, data.close_range, point) <= 0.0:
			continue
		other.body_discovered = true
		_start_search(other.global_position)
		_call_allies(other.global_position, data.alert_radius * 0.6)
		return


func _enter_combat(player: Player) -> void:
	var was_combat := alert == Alert.COMBAT
	target = player
	detection = 1.0
	_since_seen = 0.0
	last_known_position = player.global_position
	if was_combat:
		return
	_set_alert(Alert.COMBAT)
	_cooldown = data.reaction_time
	_has_cover = false
	_cover_repick_left = 0.0
	_call_allies(global_position, data.alert_radius)


func _investigate(position: Vector3) -> void:
	_investigate_point = position
	detection = maxf(detection, data.suspicion_threshold)
	if alert != Alert.SUSPICIOUS:
		_set_alert(Alert.SUSPICIOUS)


func _start_search(position: Vector3) -> void:
	last_known_position = position
	detection = maxf(detection, data.suspicion_threshold)
	_search_points.clear()
	_search_points.append(position)
	# 소리가 난 곳 주변 몇 군데를 더 둘러본다.
	for i in 3:
		var offset := Vector3(randf_range(-6.0, 6.0), 0.0, randf_range(-6.0, 6.0))
		_search_points.append(_closest_walkable(position + offset))
	_set_alert(Alert.SEARCHING)


func _call_allies(position: Vector3, radius: float) -> void:
	for node in get_tree().get_nodes_in_group(GROUP):
		var other := node as Enemy
		if other == null or other == self or other.get_world_3d() != get_world_3d():
			continue
		if other.global_position.distance_to(global_position) <= radius:
			other.notify_alarm(position)


func _set_alert(new_alert: Alert) -> void:
	alert = new_alert
	_state_time = 0.0
	_wait_left = 0.0


# ---- 단계별 행동 ----

func _patrol(delta: float) -> void:
	if _waypoints.is_empty():
		# 제자리를 지킨다. 밀려났으면 돌아가고, 원래 방향을 본다.
		if _flat_distance(global_position, _home.origin) > ARRIVE_DISTANCE:
			_go(_home.origin, data.walk_speed)
		else:
			_face(global_position - _home.basis.z)
		return
	var point := _waypoints[_waypoint_index]
	if _flat_distance(global_position, point) > ARRIVE_DISTANCE:
		_go(point, data.walk_speed)
		return
	# 지점에 닿으면 잠시 멈춰 둘러보고 다음 지점으로 간다.
	_wait_left += delta
	if _wait_left >= 1.5:
		_wait_left = 0.0
		_waypoint_index = (_waypoint_index + 1) % _waypoints.size()


func _suspicious() -> void:
	# 처음 1초는 멈춰서 그쪽을 본다. 그다음 천천히 확인하러 간다.
	_face(_investigate_point)
	if _state_time > 1.0 and _flat_distance(global_position, _investigate_point) > 1.5:
		_go(_investigate_point, data.walk_speed)
	if _state_time >= data.investigate_time:
		detection = 0.0
		_set_alert(Alert.UNAWARE)


func _search() -> void:
	if _state_time >= data.search_time:
		detection = 0.0
		_set_alert(Alert.UNAWARE)
		return
	if _search_points.is_empty():
		_face(global_position + forward().rotated(Vector3.UP, _state_time * 0.8))
		return
	var point := _search_points[0]
	if _flat_distance(global_position, point) > 1.0:
		_go(point, lerpf(data.walk_speed, data.run_speed, 0.6))
	else:
		_search_points.remove_at(0)


func _fight(delta: float) -> void:
	var sees_target := target != null and _since_seen <= 0.05
	if data.netrunner:
		_netrun(delta, sees_target)
	if not sees_target:
		# 마지막으로 본 곳으로 뛰어간다.
		_go(last_known_position, data.run_speed)
		_face(last_known_position)
		return

	var aim := target.global_position + Vector3.UP * AIM_HEIGHT
	_face(aim)
	_cover_repick_left -= delta
	if _cover_repick_left <= 0.0:
		_cover_repick_left = 6.0
		_has_cover = _pick_cover()
	var distance := _flat_distance(global_position, target.global_position)
	if _has_cover and _flat_distance(global_position, _cover_point) > ARRIVE_DISTANCE:
		_go(_cover_point, data.run_speed)
	elif distance > data.engage_distance:
		_go(target.global_position, data.run_speed)

	var facing := absf(angle_difference(rotation.y, _yaw_to(aim))) < deg_to_rad(12.0)
	# 넷러너는 총을 쏘지 않고, 무기 오작동 중에는 아무도 쏘지 못한다.
	if facing and _cooldown <= 0.0 and not data.netrunner and _glitch_left <= 0.0:
		_cooldown = data.fire_interval
		_shoot(aim)


## 가까운 엄폐 지점 중 대상과 적당히 떨어져 있고, 다른 적이 쓰지 않는 곳을 고른다.
func _pick_cover() -> bool:
	var best_score := INF
	var found := false
	for node in get_tree().get_nodes_in_group(COVER_GROUP):
		var marker := node as Node3D
		if marker == null or marker.get_viewport().find_world_3d() != get_world_3d():
			continue
		var point := marker.global_position
		var from_me := _flat_distance(global_position, point)
		if from_me > data.cover_search_radius:
			continue
		var from_target := _flat_distance(point, target.global_position)
		if from_target < 5.0 or from_target > data.engage_distance:
			continue
		if _cover_taken(point):
			continue
		if from_me < best_score:
			best_score = from_me
			_cover_point = point
			found = true
	return found


func _cover_taken(point: Vector3) -> bool:
	for node in get_tree().get_nodes_in_group(GROUP):
		var other := node as Enemy
		if other != null and other != self and other.is_active() and other._has_cover and other._cover_point.distance_to(point) < 1.0:
			return true
	return false


func _shoot(aim: Vector3) -> void:
	var origin := eye_position() - global_basis.z * 0.4
	var direction := CombatQuery.pellet_directions(aim - origin, 1, data.spread_degrees, randi())[0]
	var space := get_world_3d().direct_space_state
	var shot_range := data.sight_range * 1.5
	var hit := CombatQuery.trace(space, origin, direction, shot_range, TEAM)
	var end := origin + direction * shot_range
	if hit != null:
		end = hit.position
		if hit.hitbox != null and hit.hitbox.health != null:
			var amount := data.damage * hit.hitbox.multiplier(1.5)
			hit.hitbox.health.apply_damage(DamageInfo.create(amount, 0, hit.position, &"enemy_rifle", hit.hitbox.part == Hitbox.Part.HEAD))
	_show_shot.rpc(origin, end)
	# 총성은 다른 적도 듣는다.
	StealthNoise.emit(self, origin, StealthNoise.GUNSHOT_RADIUS, StealthNoise.Kind.GUNSHOT)


@rpc("authority", "call_local", "unreliable")
func _show_shot(from: Vector3, to: Vector3) -> void:
	Tracer.spawn(self, from, to)


# ---- 이동 (호스트) ----

func _go(point: Vector3, speed: float) -> void:
	_move_target = point
	_has_move_target = true
	_move_speed = speed


func _face(point: Vector3) -> void:
	_face_point = point
	_has_face_point = true


func _move(delta: float) -> void:
	var horizontal := Vector3.ZERO
	if _has_move_target and _flat_distance(global_position, _move_target) > ARRIVE_DISTANCE * 0.5:
		if agent.target_position.distance_to(_move_target) > 0.3:
			agent.target_position = _move_target
		var next := agent.get_next_path_position()
		var step := next - global_position
		step.y = 0.0
		# 길찾기 지도가 없거나 길을 못 찾으면 곧장 간다.
		if step.length() < 0.05:
			step = _move_target - global_position
			step.y = 0.0
		horizontal = step.normalized() * _move_speed
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	velocity.y = 0.0 if is_on_floor() else velocity.y - GRAVITY * delta
	move_and_slide()

	var look_at_point := _face_point if _has_face_point else global_position + horizontal
	if _has_face_point or horizontal.length() > 0.1:
		rotation.y = rotate_toward(rotation.y, _yaw_to(look_at_point), data.turn_speed * delta)


func _yaw_to(point: Vector3) -> float:
	var to_point := point - global_position
	return atan2(-to_point.x, -to_point.z)


func _closest_walkable(point: Vector3) -> Vector3:
	var map := get_world_3d().navigation_map
	# 길찾기 지도가 없으면(지역이 하나도 없으면) 가장 가까운 점이 원점으로 나오므로 그대로 쓴다.
	if NavigationServer3D.map_get_iteration_id(map) == 0 or NavigationServer3D.map_get_regions(map).is_empty():
		return point
	return NavigationServer3D.map_get_closest_point(map, point)


static func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


# ---- 쓰러짐과 부활 (호스트) ----

func _on_damaged(info: DamageInfo, _amount: float) -> void:
	if not multiplayer.is_server() or not is_active() or not health.is_alive():
		return
	# 맞으면 역해킹이 끊긴다. 과열 피해는 매 프레임 들어오므로 반응은 퀵핵을 받을 때 한 번만 한다.
	_cancel_netrun()
	if info.weapon_id == &"overheat":
		return
	# 맞으면 쏜 사람을 바로 알아챈다. 쏜 사람을 찾지 못하면 맞은 곳을 수색한다.
	for node in get_tree().get_nodes_in_group(Player.GROUP):
		var player := node as Player
		if player != null and player.get_multiplayer_authority() == info.attacker_peer and player.get_world_3d() == get_world_3d():
			_enter_combat(player)
			return
	if alert != Alert.COMBAT:
		_start_search(info.hit_position)


func _on_died(_info: DamageInfo) -> void:
	if multiplayer.is_server():
		_go_down(Condition.DEAD)


func _go_down(new_condition: Condition) -> void:
	_cancel_netrun()
	_burn_left = 0.0
	_glitch_left = 0.0
	condition = new_condition
	target = null
	detection = 0.0
	alert = Alert.UNAWARE
	body_discovered = false
	velocity = Vector3.ZERO
	_respawn_left = respawn_delay


func _tick_down(delta: float) -> void:
	if carrier_peer != 0:
		_follow_carrier()
	elif not is_on_floor() and not stashed:
		velocity = Vector3(0.0, velocity.y - GRAVITY * delta, 0.0)
		move_and_slide()
	if respawn_delay <= 0.0:
		return
	_respawn_left -= delta
	if _respawn_left <= 0.0:
		_respawn()


func _follow_carrier() -> void:
	for node in get_tree().get_nodes_in_group(Player.GROUP):
		var player := node as Player
		if player != null and player.get_multiplayer_authority() == carrier_peer and player.get_world_3d() == get_world_3d():
			if not player.health.is_alive():
				break
			# 어깨에 걸쳐 멘 모습
			global_position = player.global_position + Vector3.UP * 1.1 - player.global_basis.z * 0.1
			rotation.y = player.rotation.y + PI * 0.5
			return
	drop()


func _respawn() -> void:
	carrier_peer = 0
	stashed = false
	global_transform = _home
	velocity = Vector3.ZERO
	_waypoint_index = 0
	health.revive()
	condition = Condition.ACTIVE
	_set_alert(Alert.UNAWARE)


# ---- 모든 피어: 겉모습 ----

func _process(_delta: float) -> void:
	if condition != _applied_condition or stashed != _applied_stashed:
		_apply_condition()
	health_label.text = "%d" % ceili(health.current)
	health_label.visible = is_active() and health.current < data.max_health
	_update_alert_label()


func _apply_condition() -> void:
	_applied_condition = condition
	_applied_stashed = stashed
	var down := condition != Condition.ACTIVE
	# 쓰러진 몸은 눕혀 보이고, 길을 막거나 총알을 받지 않는다.
	collision.set_deferred("disabled", down)
	for hitbox in hitboxes:
		hitbox.set_deferred("collision_layer", 0 if down else Hitbox.LAYER)
	body_mesh.visible = not stashed
	if down:
		body_mesh.position = Vector3(0, 0.25, 0)
		body_mesh.rotation = Vector3(-PI * 0.5, 0, 0)
	else:
		body_mesh.position = Vector3(0, 0.9, 0)
		body_mesh.rotation = Vector3.ZERO


func _update_alert_label() -> void:
	if not is_active():
		alert_label.visible = condition == Condition.KNOCKED_OUT and not stashed and carrier_peer == 0
		alert_label.text = "기절"
		alert_label.modulate = Color(0.7, 0.7, 0.8, 0.8)
		return
	match alert:
		Alert.COMBAT:
			alert_label.text = "!"
			alert_label.modulate = Color(1, 0.2, 0.2)
		Alert.SEARCHING:
			alert_label.text = "!"
			alert_label.modulate = Color(1, 0.6, 0.1)
		Alert.SUSPICIOUS:
			alert_label.text = "?"
			alert_label.modulate = Color(1, 0.85, 0.2)
		_:
			alert_label.text = "?"
			# 무경계일 때는 감지 게이지만큼 흐린 물음표로 "들킬 것 같다"를 알린다.
			alert_label.modulate = Color(1, 1, 1, clampf(detection * 3.0, 0.0, 1.0))
	alert_label.visible = alert != Alert.UNAWARE or detection > 0.02


## 종류마다 다른 색과 크기 (중장갑병은 크고 주황색 바이저)
func _apply_look() -> void:
	# 씬의 재질은 모든 적이 함께 쓰므로, 복사본을 덮어씌워 이 적만 바꾼다.
	body_mesh.scale = Vector3.ONE * data.body_scale
	var body := body_mesh as MeshInstance3D
	var material := (body.mesh.surface_get_material(0) as StandardMaterial3D).duplicate() as StandardMaterial3D
	material.albedo_color = data.body_color
	body.set_surface_override_material(0, material)
	var visor := body_mesh.get_node("Visor") as MeshInstance3D
	var visor_material := (visor.mesh.surface_get_material(0) as StandardMaterial3D).duplicate() as StandardMaterial3D
	visor_material.albedo_color = data.visor_color
	visor_material.emission = data.visor_color
	visor.set_surface_override_material(0, visor_material)
