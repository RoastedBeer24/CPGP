class_name SecurityCamera
extends Node3D
## 감시 카메라. 좌우로 훑다가 플레이어를 알아채면(감지 게이지가 차면) 근처 경비를 부른다.
## 퀵핵 "카메라 차단"으로 잠시 끌 수 있고, 총으로 쏘면 부서진다.
## 판단은 호스트가 하고, 상태와 머리 방향은 동기화된다. 시야는 반투명 원뿔로 보여 준다.

enum State { ACTIVE, ALARM, DISABLED, DESTROYED }

@export var sight_range := 18.0
## 시야 원뿔의 반각(도)
@export var sight_half_angle := 28.0
## 좌우로 훑는 각도(도)와 속도(라디안/초)
@export var sweep_degrees := 45.0
@export var sweep_speed := 0.5
## 가까이 정면으로 보일 때 감지 게이지가 차는 속도(초당)
@export var detect_rate := 1.2
## 경보를 울리면 이 거리 안의 적을 부른다.
@export var alarm_radius := 35.0
## 경보를 울린 뒤 다시 훑기 시작하기까지의 시간
@export var alarm_time := 6.0

# 동기화되는 상태
var state := State.ACTIVE
var detection := 0.0

var head: Node3D
var _lens: MeshInstance3D
var _cone: MeshInstance3D
var _cone_material: StandardMaterial3D
var _health: Health
var _time := 0.0
var _state_left := 0.0
var _tracking: Player


func _ready() -> void:
	DeviceParts.box(self, Vector3(0.15, 0.4, 0.15), Vector3(0, 0.2, 0), Color(0.25, 0.25, 0.3))
	head = Node3D.new()
	head.name = "Head"
	head.position = Vector3(0, -0.05, 0)
	add_child(head)
	DeviceParts.box(head, Vector3(0.25, 0.22, 0.45), Vector3(0, 0, -0.1), Color(0.3, 0.3, 0.35))
	_lens = DeviceParts.box(head, Vector3(0.12, 0.12, 0.04), Vector3(0, 0, -0.34), Color(1, 0.2, 0.2), 3.0)
	_build_cone()
	_health = DeviceParts.health(self, 40.0, 0.0)
	_health.died.connect(_on_destroyed)
	DeviceParts.hitbox(head, _health, 0.32, Vector3(0, 0, -0.1))
	DeviceParts.hackable(self, "감시 카메라", ["res://data/hacking/camera_shutdown.tres"], Vector3(0, -0.05, 0))
	DeviceParts.sync(self, [".:state", ".:detection", "Head:rotation", "Health:current"])


func _build_cone() -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.0
	mesh.bottom_radius = tan(deg_to_rad(sight_half_angle)) * sight_range * 0.35
	mesh.height = sight_range * 0.35
	_cone_material = StandardMaterial3D.new()
	_cone_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_cone_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# 바깥 면만 그린다. 원뿔 안(카메라에 보이는 자리)에 서면 화면 전체가 물들어 앞이 잘 안 보인다.
	_cone_material.cull_mode = BaseMaterial3D.CULL_BACK
	mesh.material = _cone_material
	_cone = MeshInstance3D.new()
	_cone.mesh = mesh
	_cone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# 원뿔 꼭짓점(원기둥의 위, +Y)을 렌즈에 두고 넓은 쪽이 앞(-Z)으로 가게 눕힌다(X축으로 +90도 돌리면 +Y가 +Z로 간다).
	# 보기 좋게 실제 시야의 1/3 길이만 그린다.
	_cone.rotation.x = PI * 0.5
	_cone.position = Vector3(0, 0, -0.36 - mesh.height * 0.5)
	head.add_child(_cone)


# ---- 해킹 ----

func is_hackable() -> bool:
	return state == State.ACTIVE or state == State.ALARM


func scan_lines() -> PackedStringArray:
	var text: String = ["작동 중", "경보!", "꺼짐", "부서짐"][state]
	return PackedStringArray(["감시 카메라", "상태: %s" % text, "보이면 근처 경비를 부른다"])


func apply_quickhack(hack: QuickhackData, _hacker: Player) -> void:
	if not multiplayer.is_server() or hack.effect != QuickhackData.Effect.CAMERA_SHUTDOWN or not is_hackable():
		return
	state = State.DISABLED
	detection = 0.0
	_state_left = hack.duration
	_tracking = null


func _on_destroyed(_info: DamageInfo) -> void:
	if multiplayer.is_server():
		state = State.DESTROYED


# ---- 판단 (호스트) ----

func _physics_process(delta: float) -> void:
	if not multiplayer.is_server() or state == State.DESTROYED:
		return
	_time += delta
	if state == State.DISABLED:
		_state_left -= delta
		if _state_left <= 0.0:
			state = State.ACTIVE
		return
	if state == State.ALARM:
		_state_left -= delta
		if _tracking != null and is_instance_valid(_tracking):
			_turn_toward(_tracking.global_position, delta)
		if _state_left <= 0.0:
			state = State.ACTIVE
			detection = 0.0
			_tracking = null
		return

	var space := get_world_3d().direct_space_state
	var eye := head.global_position
	var forward := -head.global_basis.z
	var best: Player
	var best_amount := 0.0
	for node in get_tree().get_nodes_in_group(Player.GROUP):
		var player := node as Player
		if player == null or player.get_world_3d() != get_world_3d() or not player.health.is_alive():
			continue
		var points := PackedVector3Array([player.head.global_position, player.global_position + Vector3.UP * 0.5])
		var amount := Senses.point_visibility(space, eye, forward, sight_range, sight_half_angle, 4.0, points)
		amount *= lerpf(1.0, 0.6, player.crouch_blend)
		if amount > best_amount:
			best = player
			best_amount = amount
	if best != null:
		detection = minf(detection + best_amount * detect_rate * delta, 1.0)
		_turn_toward(best.global_position, delta * 0.5)
		if detection >= 1.0:
			_raise_alarm(best)
	else:
		detection = maxf(detection - 0.3 * delta, 0.0)
		head.rotation.y = sin(_time * sweep_speed) * deg_to_rad(sweep_degrees)


func _turn_toward(point: Vector3, delta: float) -> void:
	var local := to_local(point)
	var yaw := atan2(-local.x, -local.z)
	head.rotation.y = rotate_toward(head.rotation.y, clampf(yaw, -PI * 0.75, PI * 0.75), 2.5 * delta)


func _raise_alarm(player: Player) -> void:
	state = State.ALARM
	_state_left = alarm_time
	_tracking = player
	for node in get_tree().get_nodes_in_group(Enemy.GROUP):
		var enemy := node as Enemy
		if enemy != null and enemy.get_world_3d() == get_world_3d() and enemy.global_position.distance_to(global_position) <= alarm_radius:
			enemy.notify_alarm(player.global_position)


# ---- 모든 피어: 겉모습 ----

func _process(_delta: float) -> void:
	var lens := _lens.mesh.surface_get_material(0) as StandardMaterial3D
	var color: Color
	match state:
		State.ALARM:
			color = Color(1, 0.1, 0.1)
		State.DISABLED:
			color = Color(0.2, 0.2, 0.25)
		State.DESTROYED:
			color = Color(0.05, 0.05, 0.05)
		_:
			# 감지 게이지가 차오를수록 흰색에서 노란색으로 바뀐다.
			color = Color(0.9, 0.95, 1.0).lerp(Color(1, 0.8, 0.1), detection)
	lens.albedo_color = color
	lens.emission = color
	_cone.visible = state == State.ACTIVE or state == State.ALARM
	_cone_material.albedo_color = Color(color.r, color.g, color.b, 0.07 + detection * 0.08)
