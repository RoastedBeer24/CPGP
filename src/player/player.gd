class_name Player
extends CharacterBody3D
## 1인칭 플레이어. 걷기, 달리기, 웅크리기, 슬라이딩, 점프, 턱 오르기를 처리한다.
##
## 네트워크: 이 플레이어를 조종하는 피어(멀티플레이 권한자)만 이동을 계산한다.
## 다른 피어에서는 MultiplayerSynchronizer가 위치와 시점을 받아 보여 주기만 한다.
## 이동은 반응성을 위해 각자 계산하고, 피해·AI 같은 결과 판정은 호스트가 맡는다.

signal mantled

enum State { GROUND, AIR, SLIDE, MANTLE }

@export var config: MovementConfig = preload("res://data/player/default_movement.tres")
## false면 키보드·마우스를 읽지 않는다. 테스트나 원격 플레이어용.
@export var use_device_input := true

var state := State.GROUND
var crouched := false
## 0이면 선 자세, 1이면 웅크린 자세. 원격 피어에도 동기화된다.
var crouch_blend := 0.0
## 테스트에서 입력을 직접 넣을 때 쓴다. 설정되어 있으면 장치 입력 대신 이것을 읽는다.
var intent_override: PlayerIntent

var _time_since_floor := 0.0
var _jump_buffer := 0.0
var _slide_time := 0.0
var _mantle_from := Vector3.ZERO
var _mantle_to := Vector3.ZERO
var _mantle_elapsed := 0.0
var _mantle_duration := 0.0

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var collision: CollisionShape3D = $CollisionShape3D
@onready var body_mesh: Node3D = $Body
@onready var _capsule: CapsuleShape3D = collision.shape


func _ready() -> void:
	var local := is_multiplayer_authority()
	camera.current = local and use_device_input
	# 1인칭이므로 자기 몸은 안 보이게 하고, 다른 사람 눈에만 보이게 한다.
	body_mesh.visible = not local
	camera.fov = config.base_fov
	_apply_crouch_shape()


func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority() or not use_device_input:
		return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	var motion := event as InputEventMouseMotion
	if motion != null:
		look(motion.relative * config.mouse_sensitivity)


## 시점을 돌린다. x는 좌우(라디안), y는 상하(라디안).
func look(delta_radians: Vector2) -> void:
	rotate_y(-delta_radians.x)
	head.rotation.x = clampf(head.rotation.x - delta_radians.y, deg_to_rad(-89.0), deg_to_rad(89.0))


func _process(_delta: float) -> void:
	if not is_multiplayer_authority():
		# 원격 플레이어는 동기화된 crouch_blend로 몸 높이만 맞춘다.
		_apply_crouch_shape()


func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return
	var intent := _read_intent()

	if state == State.MANTLE:
		_process_mantle(delta)
		return

	_update_timers(delta, intent)
	_update_crouch(intent, delta)

	match state:
		State.SLIDE:
			_process_slide(delta, intent)
		_:
			_process_walk(delta, intent)

	move_and_slide()

	if state != State.SLIDE:
		state = State.GROUND if is_on_floor() else State.AIR
	if state == State.AIR and intent.jump_held and intent.move.y > 0.3:
		_try_mantle()

	_update_fov(delta, intent)


func horizontal_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()


## 지금 선 자세로 일어설 공간이 있는지.
func can_stand() -> bool:
	if crouch_blend <= 0.0:
		return true
	var shape := CapsuleShape3D.new()
	shape.radius = _capsule.radius
	shape.height = config.stand_height
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis(), global_position + Vector3.UP * (config.stand_height * 0.5 + 0.02))
	query.exclude = [get_rid()]
	query.collision_mask = collision_mask
	return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


func _read_intent() -> PlayerIntent:
	if intent_override != null:
		var copy := PlayerIntent.new()
		copy.move = intent_override.move
		copy.sprint = intent_override.sprint
		copy.jump_held = intent_override.jump_held
		copy.jump_pressed = intent_override.jump_pressed
		copy.crouch_held = intent_override.crouch_held
		copy.crouch_pressed = intent_override.crouch_pressed
		intent_override.consume_edges()
		return copy
	if use_device_input:
		return PlayerIntent.from_device()
	return PlayerIntent.new()


func _update_timers(delta: float, intent: PlayerIntent) -> void:
	_time_since_floor = 0.0 if is_on_floor() else _time_since_floor + delta
	_jump_buffer = config.jump_buffer_time if intent.jump_pressed else maxf(_jump_buffer - delta, 0.0)


func _update_crouch(intent: PlayerIntent, delta: float) -> void:
	var want_crouch := crouched
	if config.crouch_toggle:
		if intent.crouch_pressed:
			want_crouch = not crouched
	else:
		want_crouch = intent.crouch_held
	# 사이버펑크 2077처럼 달리기를 누르면 웅크린 자세에서 일어난다.
	if intent.sprint and intent.move.y > 0.3 and state != State.SLIDE:
		want_crouch = false

	var can_slide := (
		intent.crouch_pressed
		and not crouched
		and is_on_floor()
		and state == State.GROUND
		and horizontal_speed() >= config.slide_min_entry_speed
	)
	if can_slide:
		_start_slide()
		want_crouch = true

	if want_crouch:
		crouched = true
	elif crouched and can_stand():
		crouched = false

	var target := 1.0 if crouched else 0.0
	crouch_blend = move_toward(crouch_blend, target, config.crouch_transition_speed * delta)
	_apply_crouch_shape()


func _apply_crouch_shape() -> void:
	var height := lerpf(config.stand_height, config.crouch_height, crouch_blend)
	_capsule.height = height
	collision.position.y = height * 0.5
	head.position.y = lerpf(config.stand_eye_height, config.crouch_eye_height, crouch_blend)
	body_mesh.scale.y = height / config.stand_height
	body_mesh.position.y = height * 0.5


func _process_walk(delta: float, intent: PlayerIntent) -> void:
	var on_floor := is_on_floor()
	if not on_floor:
		velocity.y -= config.gravity * delta

	var wish_dir := _wish_direction(intent)
	var target_speed := _target_speed(intent)
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var target := wish_dir * target_speed
	var rate: float
	if not on_floor:
		rate = config.air_acceleration
	elif wish_dir == Vector3.ZERO:
		rate = config.ground_deceleration
	else:
		rate = config.ground_acceleration
	horizontal = horizontal.move_toward(target, rate * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z

	var can_jump := on_floor or _time_since_floor <= config.coyote_time
	if _jump_buffer > 0.0 and can_jump:
		_jump()


func _process_slide(delta: float, intent: PlayerIntent) -> void:
	_slide_time += delta
	if not is_on_floor():
		velocity.y -= config.gravity * delta
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	horizontal = horizontal.move_toward(Vector3.ZERO, config.slide_friction * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z

	if _jump_buffer > 0.0 and is_on_floor():
		# 슬라이딩 점프: 속도를 유지한 채 뛰어오른다.
		state = State.AIR
		_jump()
		if config.crouch_toggle and can_stand():
			crouched = false
		return

	var finished := _slide_time >= config.slide_max_duration or horizontal.length() <= config.slide_exit_speed
	if finished or not is_on_floor():
		state = State.GROUND if is_on_floor() else State.AIR
		if not config.crouch_toggle and not intent.crouch_held and can_stand():
			crouched = false


func _start_slide() -> void:
	state = State.SLIDE
	_slide_time = 0.0
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var direction := horizontal.normalized()
	var speed := maxf(horizontal.length(), config.slide_boost_speed)
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed


func _jump() -> void:
	velocity.y = config.jump_velocity()
	_jump_buffer = 0.0
	_time_since_floor = config.coyote_time + 1.0
	if crouched and can_stand():
		crouched = false


func _wish_direction(intent: PlayerIntent) -> Vector3:
	if intent.move == Vector2.ZERO:
		return Vector3.ZERO
	var local := Vector3(intent.move.x, 0.0, -intent.move.y)
	return (global_basis * local).normalized() * minf(intent.move.length(), 1.0)


func _target_speed(intent: PlayerIntent) -> float:
	if crouched:
		return config.crouch_speed
	if intent.sprint and intent.move.y > 0.3:
		return config.sprint_speed
	return config.walk_speed


## 앞쪽에 오를 수 있는 턱이 있으면 턱 오르기를 시작한다.
func _try_mantle() -> bool:
	var space := get_world_3d().direct_space_state
	var forward := -global_basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var feet := global_position

	# 1) 가슴 높이에서 앞쪽 벽 찾기
	var chest := feet + Vector3.UP * (config.stand_height * 0.45)
	var wall := _raycast(space, chest, chest + forward * (_capsule.radius + config.mantle_reach))
	if wall.is_empty():
		return false
	var wall_normal: Vector3 = wall["normal"]
	if absf(wall_normal.y) > 0.3:
		return false

	# 2) 벽 너머 위에서 아래로 쏴서 턱 윗면 찾기
	var wall_point: Vector3 = wall["position"]
	var probe := wall_point + forward * (_capsule.radius + 0.1)
	var top_from := Vector3(probe.x, feet.y + config.mantle_max_height + 0.05, probe.z)
	var top_to := Vector3(probe.x, feet.y + config.mantle_min_height, probe.z)
	var top := _raycast(space, top_from, top_to)
	if top.is_empty():
		return false
	var top_normal: Vector3 = top["normal"]
	if top_normal.y < 0.7:
		return false
	var top_point: Vector3 = top["position"]

	# 3) 턱 위에 선 자세로 설 공간이 있는지
	var target := Vector3(probe.x, top_point.y + 0.02, probe.z)
	var shape := CapsuleShape3D.new()
	shape.radius = _capsule.radius
	shape.height = config.stand_height
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis(), target + Vector3.UP * (config.stand_height * 0.5 + 0.02))
	query.exclude = [get_rid()]
	query.collision_mask = collision_mask
	if not space.intersect_shape(query, 1).is_empty():
		return false

	var climb := target.y - feet.y
	state = State.MANTLE
	crouched = false
	_mantle_from = feet
	_mantle_to = target
	_mantle_elapsed = 0.0
	_mantle_duration = config.mantle_base_duration + config.mantle_duration_per_meter * climb
	velocity = Vector3.ZERO
	return true


func _process_mantle(delta: float) -> void:
	_mantle_elapsed += delta
	var t := clampf(_mantle_elapsed / _mantle_duration, 0.0, 1.0)
	# 앞부분 70%는 위로 오르고, 나머지 30%에 앞으로 넘어간다. 벽을 파고들지 않게 하기 위함.
	var rise := clampf(t / 0.7, 0.0, 1.0)
	var advance := clampf((t - 0.7) / 0.3, 0.0, 1.0)
	var y := lerpf(_mantle_from.y, _mantle_to.y, ease(rise, 0.6))
	var xz := Vector2(_mantle_from.x, _mantle_from.z).lerp(Vector2(_mantle_to.x, _mantle_to.z), advance)
	global_position = Vector3(xz.x, y, xz.y)
	if t >= 1.0:
		state = State.GROUND
		velocity = Vector3.ZERO
		mantled.emit()


func _raycast(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to, collision_mask, [get_rid()])
	return space.intersect_ray(query)


func _update_fov(delta: float, intent: PlayerIntent) -> void:
	var target := config.base_fov
	if state == State.SLIDE:
		target += config.slide_fov_bonus
	elif intent.sprint and horizontal_speed() > config.walk_speed + 0.5:
		target += config.sprint_fov_bonus
	camera.fov = lerpf(camera.fov, target, minf(config.fov_transition_speed * delta, 1.0))
