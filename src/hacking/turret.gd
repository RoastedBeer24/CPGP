class_name Turret
extends StaticBody3D
## 자동 포탑. 시야에 들어온 플레이어를 빠르게 알아채고 연사한다.
## 장치 해킹 "포탑 장악"을 받으면 한동안 플레이어 편이 되어 적을 쏜다. 총으로 부술 수도 있다.
## 판단과 사격 판정은 호스트가 하고, 상태와 머리 방향은 동기화된다.

enum State { HOSTILE, FRIENDLY, DESTROYED }

@export var sight_range := 22.0
@export var sight_half_angle := 75.0
@export var detect_rate := 2.0
@export var fire_interval := 0.25
@export var damage := 3.5
@export var spread_degrees := 3.0

# 동기화되는 상태
var state := State.HOSTILE
var detection := 0.0

var head: Node3D
var _light: MeshInstance3D
var _health: Health
var _cooldown := 0.0
var _friendly_left := 0.0


func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.8, 1.2, 0.8)
	shape.shape = box
	shape.position = Vector3(0, 0.6, 0)
	add_child(shape)
	DeviceParts.box(self, Vector3(0.8, 1.0, 0.8), Vector3(0, 0.5, 0), Color(0.25, 0.25, 0.28))
	head = Node3D.new()
	head.name = "Head"
	head.position = Vector3(0, 1.25, 0)
	add_child(head)
	DeviceParts.box(head, Vector3(0.6, 0.35, 0.7), Vector3.ZERO, Color(0.3, 0.3, 0.33))
	DeviceParts.box(head, Vector3(0.1, 0.1, 0.7), Vector3(0.12, 0, -0.6), Color(0.15, 0.15, 0.17))
	DeviceParts.box(head, Vector3(0.1, 0.1, 0.7), Vector3(-0.12, 0, -0.6), Color(0.15, 0.15, 0.17))
	_light = DeviceParts.box(head, Vector3(0.4, 0.06, 0.02), Vector3(0, 0.12, -0.36), Color(1, 0.2, 0.2), 3.0)
	_health = DeviceParts.health(self, 150.0, 40.0)
	_health.died.connect(_on_destroyed)
	DeviceParts.hitbox(self, _health, 0.75, Vector3(0, 1.0, 0))
	DeviceParts.hackable(self, "포탑", ["res://data/hacking/turret_takeover.tres"], Vector3(0, 1.3, 0))
	DeviceParts.sync(self, [".:state", ".:detection", "Head:rotation", "Health:current"])


func is_hackable() -> bool:
	return state == State.HOSTILE


func scan_lines() -> PackedStringArray:
	var text: String = ["적대", "아군 (%d초)" % ceili(_friendly_left), "부서짐"][state]
	return PackedStringArray(["포탑", "상태: %s" % text, "체력 %d   장갑 40" % ceili(_health.current), "장악하면 적을 쏜다"])


func apply_quickhack(hack: QuickhackData, _hacker: Player) -> void:
	if not multiplayer.is_server() or hack.effect != QuickhackData.Effect.TURRET_TAKEOVER or not is_hackable():
		return
	state = State.FRIENDLY
	_friendly_left = hack.duration
	detection = 0.0


func is_friendly() -> bool:
	return state == State.FRIENDLY


func _on_destroyed(_info: DamageInfo) -> void:
	if multiplayer.is_server():
		state = State.DESTROYED


# ---- 판단 (호스트) ----

func _physics_process(delta: float) -> void:
	if not multiplayer.is_server() or state == State.DESTROYED:
		return
	_cooldown = maxf(_cooldown - delta, 0.0)
	if state == State.FRIENDLY:
		_friendly_left -= delta
		if _friendly_left <= 0.0:
			state = State.HOSTILE
	var target := _pick_target()
	if target == Vector3.INF:
		detection = maxf(detection - 0.5 * delta, 0.0)
		return
	var local := to_local(target)
	head.rotation.y = rotate_toward(head.rotation.y, atan2(-local.x, -local.z), 4.0 * delta)
	if state == State.HOSTILE and detection < 1.0:
		detection = minf(detection + detect_rate * delta, 1.0)
		return
	var facing := absf(angle_difference(head.rotation.y, atan2(-local.x, -local.z))) < deg_to_rad(10.0)
	if facing and _cooldown <= 0.0:
		_cooldown = fire_interval
		_shoot(target)


## 쏠 곳. 적대 중이면 보이는 플레이어, 장악당했으면 보이는 적. 없으면 Vector3.INF.
func _pick_target() -> Vector3:
	var space := get_world_3d().direct_space_state
	var eye := head.global_position
	var forward := -global_basis.z
	var best := Vector3.INF
	var best_distance := INF
	var group := Enemy.GROUP if state == State.FRIENDLY else Player.GROUP
	for node in get_tree().get_nodes_in_group(group):
		var body := node as Node3D
		if body == null or body.get_viewport().find_world_3d() != get_world_3d():
			continue
		if body is Player and not (body as Player).health.is_alive():
			continue
		if body is Enemy and not (body as Enemy).is_active():
			continue
		var point := body.global_position + Vector3.UP * 1.1
		var points := PackedVector3Array([point])
		if Senses.point_visibility(space, eye, forward, sight_range, sight_half_angle, sight_range, points) <= 0.0:
			continue
		var distance := eye.distance_to(point)
		if distance < best_distance:
			best = point
			best_distance = distance
	return best


func _shoot(target: Vector3) -> void:
	var origin := head.global_position - head.global_basis.z * 0.9
	var direction := CombatQuery.pellet_directions(target - origin, 1, spread_degrees, randi())[0]
	# 장악당하면 플레이어 편이라 플레이어는 통과하고 적을 맞힌다.
	var team := WeaponHolder.TEAM if state == State.FRIENDLY else Enemy.TEAM
	var hit := CombatQuery.trace(get_world_3d().direct_space_state, origin, direction, sight_range * 1.5, team)
	var end := origin + direction * sight_range * 1.5
	if hit != null:
		end = hit.position
		if hit.hitbox != null and hit.hitbox.health != null and hit.hitbox.health != _health:
			hit.hitbox.health.apply_damage(DamageInfo.create(damage, 0, hit.position, &"turret", false))
	_show_shot.rpc(origin, end)
	StealthNoise.emit(self, origin, StealthNoise.GUNSHOT_RADIUS * 0.6, StealthNoise.Kind.GUNSHOT)


@rpc("authority", "call_local", "unreliable")
func _show_shot(from: Vector3, to: Vector3) -> void:
	Tracer.spawn(self, from, to)


func _process(_delta: float) -> void:
	var material := _light.mesh.surface_get_material(0) as StandardMaterial3D
	var color: Color
	match state:
		State.FRIENDLY:
			color = Color(0.2, 1, 0.4)
		State.DESTROYED:
			color = Color(0.05, 0.05, 0.05)
		_:
			color = Color(1, 0.8, 0.1).lerp(Color(1, 0.15, 0.15), detection)
	material.albedo_color = color
	material.emission = color
