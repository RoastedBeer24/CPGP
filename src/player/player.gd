class_name Player
extends CharacterBody3D
## 플레이어. 걷기, 달리기, 웅크리기, 슬라이딩, 점프, 턱 오르기, 회피를 처리하고,
## 무기(WeaponHolder)와 체력(Health)을 가진다. 체력은 호스트가 관리한다.
## 기본은 1인칭이고, V로 어깨 너머 3인칭과 바꿀 수 있다. 시점은 각자 화면에만 적용된다.
## ` 키를 누르고 있으면 자유 시야: 카메라만 캐릭터 주변을 어느 방향으로든 돈다(휠로 크게 확대·축소).
## 자유 시야 중에도 움직이고 조준하고 쏠 수 있다. 공격은 캐릭터가 보는 방향(머리 방향)으로 나간다.
##
## 네트워크: 이 플레이어를 조종하는 피어(멀티플레이 권한자)만 이동을 계산한다.
## 다른 피어에서는 MultiplayerSynchronizer가 위치와 시점을 받아 보여 주기만 한다.
## 이동은 반응성을 위해 각자 계산하고, 피해·AI 같은 결과 판정은 호스트가 맡는다.

signal mantled
signal dodged
signal camera_mode_changed(third_person: bool)

enum State { GROUND, AIR, SLIDE, MANTLE, DODGE }

## 모든 플레이어가 들어가는 그룹. 적이 목표를 찾을 때 쓴다.
const GROUP := &"players"

const MOVE_ACTIONS := {
	&"move_forward": Vector2(0, 1),
	&"move_back": Vector2(0, -1),
	&"move_left": Vector2(-1, 0),
	&"move_right": Vector2(1, 0),
}

## 마지막으로 쏜 뒤 이 프레임 수(물리 60fps 기준 2초) 동안은 전투 자세를 유지한다.
const COMBAT_READY_FRAMES := 120

## 자유 시야에서 휠 한 칸에 카메라 거리가 바뀌는 배율과 그 범위(m)
const ZOOM_FACTOR := 1.2
const MIN_CAMERA_DISTANCE := 0.6
const MAX_CAMERA_DISTANCE := 30.0
## 자유 시야에서 위아래로 돌릴 수 있는 한계(라디안). 바로 위·아래 직전까지.
const FREE_LOOK_PITCH_LIMIT := 1.48

## 3인칭 조준점을 찾을 때 카메라에서 쏘는 광선의 길이(m)
const AIM_PROBE_RANGE := 200.0

@export var config: MovementConfig = preload("res://data/player/default_movement.tres")
## false면 키보드·마우스를 읽지 않는다. 테스트나 원격 플레이어용.
@export var use_device_input := true

## 이동 상태. 원격 피어에도 동기화되어 몸 애니메이션(점프, 슬라이딩 등)에 쓰인다.
var state := State.GROUND
## 점프·회피를 할 때마다 1씩 는다. 원격 피어의 몸이 이 값의 변화를 보고 점프·회피 동작을 튼다.
var jump_count := 0
var dodge_count := 0
var crouched := false
## 0이면 선 자세, 1이면 웅크린 자세. 원격 피어에도 동기화된다.
var crouch_blend := 0.0
## 조준 중이거나 방금 쐈으면 true. 3인칭 몸이 조준 방향을 보고 총을 겨눈다. 원격 피어에도 동기화된다.
var combat_ready := false
## true면 어깨 너머 3인칭. 조종하는 피어의 화면에만 영향을 주므로 동기화하지 않는다.
var third_person := false
## 0이면 1인칭, 1이면 3인칭 카메라 위치. 전환할 때 부드럽게 움직인다.
var camera_blend := 0.0
## 자유 시야 중인지. 카메라가 캐릭터를 중심으로 돈다. 움직이고 쏘는 것은 평소처럼 된다.
var free_look := false
## 3인칭과 자유 시야의 카메라 거리. 자유 시야에서 휠로 바꾸면 3인칭에도 그대로 쓴다.
var camera_distance := 0.0
## 테스트에서 입력을 직접 넣을 때 쓴다. 설정되어 있으면 장치 입력 대신 이것을 읽는다.
var intent_override: PlayerIntent

var _time_since_floor := 0.0
var _jump_buffer := 0.0
var _slide_time := 0.0
var _mantle_from := Vector3.ZERO
var _mantle_to := Vector3.ZERO
var _mantle_elapsed := 0.0
var _mantle_duration := 0.0
var _dodge_time := 0.0
var _dodge_cooldown := 0.0
var _last_tap_msec: Dictionary = {}
var _pending_dodge := Vector2.ZERO
var _pending_cycle := 0
var _last_fire_frame := -100000
# 자유 시야의 카메라 회전 (머리 기준). 목표값과, 부드럽게 따라가는 지금 값.
var _free_yaw := 0.0
var _free_pitch := 0.0
var _free_amount := 0.0
## 화면에 쓰는 카메라 거리. camera_distance를 부드럽게 따라간다.
var _shown_distance := 0.0
# 토글로 설정한 달리기와 조준의 지금 상태
var _sprint_toggled := false
var _aim_toggled := false
# 발소리 (호스트에서 모든 플레이어의 움직임을 보고 적에게 들려준다)
var _noise_last_position := Vector3.ZERO
var _step_left := 0.0

@onready var head: Node3D = $Head
@onready var camera_arm: SpringArm3D = $Head/CameraArm
@onready var camera: Camera3D = $Head/CameraArm/Camera3D
@onready var collision: CollisionShape3D = $CollisionShape3D
@onready var body: PlayerBody = $Body
@onready var interactor: Interactor = $Interactor
@onready var cyberdeck: Cyberdeck = $Cyberdeck
@onready var _capsule: CapsuleShape3D = collision.shape
@onready var health: Health = $Health
@onready var weapons: WeaponHolder = $Head/WeaponHolder
@onready var head_hitbox: Hitbox = $HeadHitbox
@onready var body_hitbox: Hitbox = $BodyHitbox
@onready var _body_hitbox_shape: CapsuleShape3D = ($BodyHitbox/Shape as CollisionShape3D).shape


func _ready() -> void:
	add_to_group(GROUP)
	var local := is_multiplayer_authority()
	camera.current = local and use_device_input
	camera.fov = GameSettings.fov
	camera_distance = config.third_person_distance
	_shown_distance = camera_distance
	# 3인칭 카메라가 내 몸에 걸려 당겨지지 않게 한다.
	camera_arm.add_excluded_object(get_rid())
	health.died.connect(_on_died)
	weapons.fired.connect(func(_weapon: WeaponData) -> void: _last_fire_frame = Engine.get_physics_frames())
	health.revived.connect(_on_revived)
	_apply_crouch_shape()
	_apply_view()


func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority() or not use_device_input:
		return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event.is_action(InputActions.FREE_LOOK) and not event.is_echo():
		if GameSettings.free_look_toggle:
			if event.is_pressed():
				set_free_look(not free_look)
		else:
			set_free_look(event.is_pressed())
		return
	var motion := event as InputEventMouseMotion
	if motion != null:
		if free_look:
			orbit(GameSettings.look_delta(motion.relative))
		else:
			look(GameSettings.look_delta(motion.relative))
		return
	# 자유 시야 중의 휠은 무기를 바꾸지 않고 확대·축소한다.
	var wheel := event as InputEventMouseButton
	if free_look and wheel != null and wheel.pressed:
		if wheel.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom(-1)
			return
		if wheel.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom(1)
			return
	if event.is_action_pressed(InputActions.CAMERA_TOGGLE):
		set_third_person(not third_person)
		return
	if event.is_action_pressed(InputActions.WEAPON_NEXT):
		_pending_cycle += 1
	elif event.is_action_pressed(InputActions.WEAPON_PREV):
		_pending_cycle -= 1
	_detect_double_tap(event)


## 같은 방향키를 짧은 간격으로 두 번 누르면 그 방향으로 회피한다 (사이버펑크 2077 방식).
func _detect_double_tap(event: InputEvent) -> void:
	if event.is_echo() or not event.is_pressed():
		return
	for action: StringName in MOVE_ACTIONS:
		if not event.is_action(action):
			continue
		var now := Time.get_ticks_msec()
		var last: int = _last_tap_msec.get(action, -100000)
		if now - last <= int(config.dodge_double_tap_window * 1000.0):
			_pending_dodge = MOVE_ACTIONS[action]
			_last_tap_msec[action] = -100000
		else:
			_last_tap_msec[action] = now


## 시점을 돌린다. x는 좌우(라디안), y는 상하(라디안).
func look(delta_radians: Vector2) -> void:
	rotate_y(-delta_radians.x)
	head.rotation.x = clampf(head.rotation.x - delta_radians.y, deg_to_rad(-89.0), deg_to_rad(89.0))


## 움직임을 보고 발소리를 낸다. 호스트에서 모든 플레이어에 대해 돈다(다른 피어의 플레이어는 속도가
## 동기화되지 않으므로 위치 변화로 잰다). 웅크려 걸으면 소리가 나지 않는다.
func _emit_footsteps(delta: float) -> void:
	var moved := global_position - _noise_last_position
	_noise_last_position = global_position
	# 한 프레임에 2m 넘게 움직였으면 걸은 게 아니라 옮겨진 것이다(스폰, 부활).
	if delta <= 0.0 or not health.is_alive() or moved.length() > 2.0:
		return
	var speed := minf(Vector2(moved.x, moved.z).length() / delta, 15.0)
	_step_left -= delta
	if _step_left > 0.0 or crouch_blend > 0.5 or speed < 1.0:
		return
	if speed > config.walk_speed + 0.8:
		_step_left = 0.3
		StealthNoise.emit(self, global_position, StealthNoise.SPRINT_STEP_RADIUS, StealthNoise.Kind.FOOTSTEP)
	else:
		_step_left = 0.45
		StealthNoise.emit(self, global_position, StealthNoise.WALK_STEP_RADIUS, StealthNoise.Kind.FOOTSTEP)


## 1인칭과 3인칭을 바꾼다. 내 화면에서만 바뀌고 다른 사람에게는 영향이 없다.
func set_third_person(enabled: bool) -> void:
	if third_person == enabled:
		return
	third_person = enabled
	_apply_view()
	camera_mode_changed.emit(third_person)


## 자유 시야를 켜거나 끈다. 끄면 카메라가 원래 시점으로 부드럽게 돌아온다.
func set_free_look(enabled: bool) -> void:
	if free_look == enabled:
		return
	free_look = enabled
	if enabled:
		# 지금 보던 방향에서 시작한다.
		_free_yaw = 0.0
		_free_pitch = head.rotation.x
	_apply_view()


## 자유 시야에서 카메라를 돌린다. x는 좌우(제한 없음), y는 상하(라디안). 캐릭터는 돌지 않는다.
func orbit(delta_radians: Vector2) -> void:
	_free_yaw = wrapf(_free_yaw - delta_radians.x, -PI, PI)
	_free_pitch = clampf(_free_pitch - delta_radians.y, -FREE_LOOK_PITCH_LIMIT, FREE_LOOK_PITCH_LIMIT)


## 카메라를 당기거나(-) 민다(+). 휠 한 칸이 1이다. 가까울수록 조금씩, 멀수록 크게 바뀐다.
func zoom(steps: int) -> void:
	camera_distance = clampf(camera_distance * pow(ZOOM_FACTOR, steps), MIN_CAMERA_DISTANCE, MAX_CAMERA_DISTANCE)


## 공격 판정의 시작점. 시점과 관계없이 눈에서 쏜다. 3인칭 카메라 위치에서 쏘면
## 캐릭터 뒤의 물체에 맞거나, 캐릭터가 볼 수 없는 곳을 맞히게 되기 때문이다.
func aim_origin() -> Vector3:
	return head.global_position


## 공격 방향. 1인칭은 카메라가 보는 방향이고, 3인칭은 화면 가운데 조준점이 가리키는 곳을 향한다.
## 자유 시야 중에는 카메라가 딴 곳을 볼 수 있으므로 캐릭터가 보는 방향(머리 방향)이다.
func aim_direction() -> Vector3:
	if free_look:
		return -head.global_basis.z
	var forward := -camera.global_basis.z
	if camera_blend <= 0.0:
		return forward
	# 카메라와 머리 사이에 있는 물체는 무시하도록, 광선을 머리 옆에서부터 쏜다.
	var cam := camera.global_position
	var start := cam + forward * maxf(forward.dot(head.global_position - cam), 0.0)
	var hit := CombatQuery.trace(get_world_3d().direct_space_state, start, forward, AIM_PROBE_RANGE, WeaponHolder.TEAM)
	var target := hit.position if hit != null else start + forward * AIM_PROBE_RANGE
	var to_target := target - aim_origin()
	# 조준점이 눈보다 뒤나 바로 앞이면(벽에 붙어 있을 때) 카메라 방향을 그대로 쓴다.
	if to_target.length() < 0.5 or to_target.normalized().dot(forward) < 0.5:
		return forward
	return to_target.normalized()


func _process(delta: float) -> void:
	if multiplayer.is_server():
		_emit_footsteps(delta)
	if not is_multiplayer_authority():
		# 원격 플레이어는 동기화된 crouch_blend로 몸 높이만 맞춘다.
		_apply_crouch_shape()
		return
	_update_camera_arm(delta)


func _update_camera_arm(delta: float) -> void:
	var target := 1.0 if third_person or free_look else 0.0
	camera_blend = move_toward(camera_blend, target, config.camera_switch_speed * delta)
	_free_amount = move_toward(_free_amount, 1.0 if free_look else 0.0, config.camera_switch_speed * delta)
	_shown_distance = lerpf(_shown_distance, camera_distance, minf(delta * 10.0, 1.0))
	var t := ease(camera_blend, -2.0)
	# 자유 시야는 어깨가 아니라 머리를 중심으로 돈다.
	var shoulder := Vector3(config.third_person_shoulder.x, config.third_person_shoulder.y, 0.0) * t * (1.0 - _free_amount)
	camera_arm.spring_length = _shown_distance * t
	camera_arm.position = shoulder
	# 자유 시야의 회전은 머리(조준 높이)와 상관없이 세상 기준으로 정한다. 그래야 위아래 어디로든 돌 수 있다.
	# 평소에는 머리를 그대로 따라가고, 켜고 끌 때는 두 방향 사이를 부드럽게 오간다.
	var follow := head.global_basis.get_rotation_quaternion()
	var orbiting := Basis.from_euler(Vector3(_free_pitch, rotation.y + _free_yaw, 0.0)).get_rotation_quaternion()
	camera_arm.global_basis = Basis(follow.slerp(orbiting, ease(_free_amount, -2.0)))


## 시점과 생사에 따라 몸과 1인칭 무기 모델을 보이거나 숨긴다.
func _apply_view() -> void:
	var local := is_multiplayer_authority()
	if not health.is_alive():
		body.set_view_mode(PlayerBody.ViewMode.HIDDEN)
	elif local and not third_person and not free_look:
		# 1인칭에서는 내 몸이 카메라를 가리지 않게 그림자만 남긴다.
		body.set_view_mode(PlayerBody.ViewMode.SHADOW_ONLY)
	else:
		body.set_view_mode(PlayerBody.ViewMode.VISIBLE)
	weapons.viewmodel.visible = local and not third_person and not free_look


func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return
	var intent := _read_intent()
	if not health.is_alive():
		intent = PlayerIntent.new()
	# 쏘거나 조준하면 달리기가 풀린다.
	if intent.fire_held or intent.aim_held:
		intent.sprint = false

	if state == State.MANTLE:
		_process_mantle(delta)
		weapons.tick(delta, intent, false)
		return

	_update_timers(delta, intent)
	_update_crouch(intent, delta)
	if intent.dodge != Vector2.ZERO:
		_try_dodge(intent.dodge)

	match state:
		State.SLIDE:
			_process_slide(delta, intent)
		State.DODGE:
			_process_dodge(delta)
		_:
			_process_walk(delta, intent)

	move_and_slide()

	if state != State.SLIDE and state != State.DODGE:
		state = State.GROUND if is_on_floor() else State.AIR
	if state == State.AIR and intent.jump_held and intent.move.y > 0.3:
		_try_mantle()

	var sprinting := intent.sprint and intent.move.y > 0.3 and not crouched
	# 스캔 중에는 1~3 키가 무기 대신 퀵핵을 고른다.
	cyberdeck.update_scan(intent.scan_held)
	if cyberdeck.scanning and intent.weapon_slot > 0:
		cyberdeck.request_hack(intent.weapon_slot)
		intent.weapon_slot = 0
	# 몸을 들고 있으면 쏠 수 없다.
	# 몸을 들고 있거나 스캔 중에는 쏠 수 없다.
	weapons.tick(delta, intent, health.is_alive() and not sprinting and interactor.carrying == null and not cyberdeck.scanning)
	combat_ready = weapons.aiming or Engine.get_physics_frames() - _last_fire_frame < COMBAT_READY_FRAMES
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
		var copied := intent_override.copy()
		intent_override.consume_edges()
		return copied
	if not use_device_input:
		return PlayerIntent.new()
	var intent := PlayerIntent.from_device()
	apply_toggles(intent, Input.is_action_just_pressed(InputActions.SPRINT), Input.is_action_just_pressed(InputActions.AIM))
	intent.dodge = _pending_dodge
	intent.weapon_cycle = signi(_pending_cycle)
	_pending_dodge = Vector2.ZERO
	_pending_cycle = 0
	return intent


## 달리기·조준을 토글로 설정했으면 누를 때마다 켜고 끈다(웅크리기 토글은 _update_crouch가 맡는다).
## 달리기 토글은 앞으로 가지 않으면 풀리고, 조준 토글은 달리면 풀린다.
func apply_toggles(intent: PlayerIntent, sprint_pressed: bool, aim_pressed: bool) -> void:
	if GameSettings.sprint_toggle:
		if sprint_pressed:
			_sprint_toggled = not _sprint_toggled
		if intent.move.y <= 0.3:
			_sprint_toggled = false
		intent.sprint = _sprint_toggled
	if GameSettings.aim_toggle:
		if aim_pressed:
			_aim_toggled = not _aim_toggled
		if intent.sprint or not health.is_alive():
			_aim_toggled = false
		intent.aim_held = _aim_toggled


func _update_timers(delta: float, intent: PlayerIntent) -> void:
	_dodge_cooldown = maxf(_dodge_cooldown - delta, 0.0)
	_time_since_floor = 0.0 if is_on_floor() else _time_since_floor + delta
	_jump_buffer = config.jump_buffer_time if intent.jump_pressed else maxf(_jump_buffer - delta, 0.0)


func _update_crouch(intent: PlayerIntent, delta: float) -> void:
	var want_crouch := crouched
	if GameSettings.crouch_toggle:
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
	# 피격 판정: 머리는 눈높이에, 몸통은 머리 아래를 채운다.
	head_hitbox.position.y = head.position.y
	var body_height := maxf(head.position.y - 0.15, 0.6)
	_body_hitbox_shape.height = body_height
	body_hitbox.position.y = body_height * 0.5


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
		if GameSettings.crouch_toggle and can_stand():
			crouched = false
		return

	var finished := _slide_time >= config.slide_max_duration or horizontal.length() <= config.slide_exit_speed
	if finished or not is_on_floor():
		state = State.GROUND if is_on_floor() else State.AIR
		if not GameSettings.crouch_toggle and not intent.crouch_held and can_stand():
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
	jump_count += 1
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
	var speed := config.walk_speed
	if crouched:
		speed = config.crouch_speed
	elif intent.sprint and intent.move.y > 0.3:
		speed = config.sprint_speed
	if weapons.aiming:
		speed *= config.aim_speed_multiplier
	if interactor.carrying != null:
		speed = minf(speed, config.walk_speed) * Interactor.CARRY_SPEED_MULTIPLIER
	return speed


## 지면에서 지정한 방향(로컬, 앞이 +y)으로 짧게 돌진한다.
func _try_dodge(direction: Vector2) -> bool:
	if _dodge_cooldown > 0.0 or not is_on_floor() or state == State.SLIDE or state == State.DODGE:
		return false
	var world_direction := (global_basis * Vector3(direction.x, 0.0, -direction.y)).normalized()
	velocity.x = world_direction.x * config.dodge_speed
	velocity.z = world_direction.z * config.dodge_speed
	state = State.DODGE
	_dodge_time = 0.0
	_dodge_cooldown = config.dodge_cooldown
	dodge_count += 1
	dodged.emit()
	return true


func _process_dodge(delta: float) -> void:
	_dodge_time += delta
	if not is_on_floor():
		velocity.y -= config.gravity * delta
	if _dodge_time >= config.dodge_duration:
		state = State.GROUND if is_on_floor() else State.AIR
		var horizontal := Vector3(velocity.x, 0.0, velocity.z).limit_length(config.walk_speed)
		velocity.x = horizontal.x
		velocity.z = horizontal.z


## 호스트가 부활 위치로 옮길 때 부른다.
@rpc("any_peer", "call_local", "reliable")
func respawn_at(spawn_position: Vector3) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	global_position = spawn_position
	velocity = Vector3.ZERO
	state = State.GROUND
	crouched = false


func _on_died(_info: DamageInfo) -> void:
	_apply_view()
	# 죽은 뒤에는 맞지 않는다. 몸 충돌은 남겨 둬야 바닥 아래로 떨어지지 않는다.
	head_hitbox.set_deferred("collision_layer", 0)
	body_hitbox.set_deferred("collision_layer", 0)


func _on_revived() -> void:
	_apply_view()
	head_hitbox.set_deferred("collision_layer", Hitbox.LAYER)
	body_hitbox.set_deferred("collision_layer", Hitbox.LAYER)


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
	var target := GameSettings.fov
	if weapons.aiming:
		target = weapons.current_weapon().aim_fov
	elif state == State.SLIDE:
		target += config.slide_fov_bonus
	elif intent.sprint and horizontal_speed() > config.walk_speed + 0.5:
		target += config.sprint_fov_bonus
	camera.fov = lerpf(camera.fov, target, minf(config.fov_transition_speed * delta, 1.0))
