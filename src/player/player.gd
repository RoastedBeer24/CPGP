class_name Player
extends CharacterBody3D
## 플레이어. 3인칭 액션 조작이다.
##   - 카메라: 마우스로 캐릭터 주위를 돈다(휠로 거리). 대상 고정(가운데 클릭) 중에는 대상 쪽으로 돌아간다.
##   - 이동: 카메라가 보는 방향 기준으로 움직이고, 몸은 가는 쪽으로 돈다.
##   - 전투: 기본 공격 연속(5단계), 회피 직후 대시 공격, 경직된 적 처형, 배틀 스킬(SP), 궁극기(에너지).
##     공격 동작은 원본 동작의 내디딤 거리만큼 앞으로 나가고(AttackData.advance), 정해진 시각에 앞쪽 부채꼴을 맞힌다.
##   - 회피: 이동 방향으로 내닫거나(입력이 없으면 뒤로 물러남) 잠깐 무적이다. 적의 공격을 무적으로 피하면
##     완벽한 회피(SP 회복, 혼자 할 때는 잠깐 느려짐). 회피한 뒤 회피 키를 누르고 있으면 질주한다.
##
## 네트워크: 이 플레이어를 조종하는 피어(멀티플레이 권한자)가 이동과 동작을 계산한다. 다른 피어는
## MultiplayerSynchronizer로 위치와 동작 번호를 받아 같은 동작을 보여 준다.
## 타격 판정과 피해는 호스트가 한다: 타격 시각이 되면 조종하는 피어가 호스트에 요청을 보내고(_request_hit),
## 호스트가 적을 맞힌 결과(피해 숫자, 얻은 에너지)를 돌려준다. 맞힌 느낌(멈춤, 흔들림, 불꽃)은 조종하는 피어가
## 미리 계산해 바로 보여 준다. SP와 궁극기 에너지는 조종하는 피어가 관리한다(가족끼리 하는 게임이라
## 부정 행위 방지는 하지 않는다).

signal action_started(attack: AttackData)
## 내 공격이 적을 맞힌 결과가 돌아왔을 때 (조종하는 피어에서만)
signal hit_confirmed(position: Vector3, amount: float, flags: int)
signal perfect_dodged
## 적에게 맞았을 때 (조종하는 피어에서만). heavy면 몸이 휘청인다.
signal got_hit(heavy: bool)
## SP나 에너지가 모자라 스킬을 못 쓸 때
signal skill_denied(reason: String)

enum State { GROUND, AIR, DODGE, ACTION, HURT, DOWN }

## 모든 플레이어가 들어가는 그룹. 적이 목표를 찾을 때 쓴다.
const GROUP := &"players"
const TEAM := &"player"

## 피해 결과 표시(hit_confirmed의 flags)
const HIT_SHATTER := 1
const HIT_BREAK := 2
const HIT_KILL := 4

## 강하게 맞았을 때 휘청이는 시간(초)
const HURT_TIME := 0.6
## 공격이나 피격 뒤 이 시간(초) 동안 전투 자세(전투 대기 동작)를 유지한다.
const COMBAT_TIME := 6.0
## 이 거리(m) 안의 적이 나를 알아채고 다가오면 전투 자세로 무기를 꺼낸다(원작처럼). 적이 잠잠해져도 이 시간(초)은 유지한다.
const ALERT_RANGE := 16.0
const ALERT_COMBAT_TIME := 2.0
## 가볍게 맞은 쪽 (flinch_side): 앞, 뒤, 왼쪽, 오른쪽
enum HitSide { FRONT, BACK, LEFT, RIGHT }
## 미리 누른 공격을 기억하는 시간(초)
const ATTACK_BUFFER := 0.45
## 공격이 끝난 뒤 이 시간(초) 안에 다시 누르면 연속 공격이 이어진다.
const CHAIN_GRACE := 0.35
## 쓰러진 동료를 일으키는 거리(m)와 시간(초), 일으킨 뒤의 체력 비율
const REVIVE_RANGE := 2.2
const REVIVE_TIME := 2.5
const REVIVE_HEALTH := 0.3
## 완벽한 회피의 느린 시간: 배속과 실제 시간(초). 혼자 할 때만 쓴다.
const SLOW_MOTION_SCALE := 0.3
const SLOW_MOTION_TIME := 0.4
## 3인칭에서 카메라가 벽에 밀려 이보다 중심에 가까워지면 몸을 숨긴다(머리 속이 화면을 가리지 않게, m).
## 자유 시점은 얼굴을 가까이 보는 것이 목적이라 카메라가 정말 머리 속에 들어갔을 때만 숨긴다.
const CAMERA_INSIDE_DISTANCE := 0.35
const FREE_INSIDE_DISTANCE := 0.1
## 휠 한 칸에 카메라 거리가 바뀌는 배율. 가까울수록 조금씩, 멀수록 크게 바뀐다.
const ZOOM_FACTOR := 1.15
## 카메라 방식: 기본 시점(3인칭·1인칭, V로 바꾼다)과 자유 시점(`로 켜고 끈다, 휠로 확대·축소)
enum CameraMode { THIRD_PERSON, FIRST_PERSON, FREE }

@export var config: MovementConfig = preload("res://data/player/default_movement.tres")
## 비워 두면 고른 캐릭터(character_id)의 전투 구성. 스크립트끼리 서로 참조하는 중에 리소스를 미리 불러오면
## 깨지므로 실행 시점에 불러온다.
@export var kit: KitData
## false면 키보드·마우스를 읽지 않는다. 테스트나 원격 플레이어용.
@export var use_device_input := true

## 고른 캐릭터. 호스트가 스폰할 때 정하고, 스폰 정보로 모든 피어에 같이 간다.
var character_id := Characters.DEFAULT_ID

# ---- 동기화되는 값 (조종하는 피어가 정한다) ----
var state := State.GROUND
## 지금(또는 마지막) 동작 이름과, 동작을 시작할 때마다 1씩 느는 번호. 원격 피어의 몸이 이 변화를 보고 동작을 튼다.
var action_id := &""
var action_count := 0
var jump_count := 0
var dodge_count := 0
## 마지막 회피가 뒤로 물러나기였는지
var dodge_back := false
var hurt_count := 0
## 가볍게 맞을 때마다 1씩 느는 번호와 맞은 쪽(HitSide). 몸이 윗몸만 움찔한다(움직임은 막지 않는다).
var flinch_count := 0
var flinch_side := HitSide.FRONT
## 머리 장비(바이저)를 쓰고 있는지. 내 플레이어는 설정에 저장된 값으로 시작한다.
var visor_on := true
## 무적(회피 직후, 궁극기·처형 중). 호스트가 적의 공격을 판정할 때 본다.
var invulnerable := false
## 전투 중이면 몸이 전투 대기 동작을 한다.
var in_combat := false
## 쓰러진 동료를 일으키는 중인지 (F를 누르고 있음)
var reviving := false
## 이번 작전에서 고른 보상(RewardData.id). 조종하는 피어가 고르고, 호스트는 피해 계산과 최대 체력에 쓴다.
var rewards := PackedStringArray():
	set(value):
		rewards = value
		_bonus_cache.clear()
		_apply_reward_health()

# ---- 조종하는 피어만 쓰는 값 ----
var sp := 100.0
var energy := 0.0
## 카메라 방향(라디안). 몸의 방향과 따로 돈다.
var camera_yaw := 0.0
var camera_pitch := deg_to_rad(-12.0)
## 자유 시점(과 캐릭터 화면)의 카메라 거리(m). 기본 시점은 정해진 거리를 쓴다.
var camera_distance := 4.2
## 지금 카메라 방식
var camera_mode := CameraMode.THIRD_PERSON
## 대상 고정 중인 적. 없으면 null.
var lock_target: Enemy
## 테스트에서 입력을 직접 넣을 때 쓴다. 설정되어 있으면 장치 입력 대신 이것을 읽는다.
var intent_override: PlayerIntent
## true면 키보드·마우스 입력을 받지 않는다(보상 고르기, 캐릭터 화면이 열렸을 때).
var input_blocked := false
## 캐릭터 화면: 카메라가 캐릭터를 앞에서 비춘다. showcase_yaw만큼 둘레를 돈다.
var showcase := false:
	set(value):
		if value == showcase:
			return
		showcase = value
		if value:
			# 캐릭터 화면은 지금 보이는 거리에서 시작해 휠로 얼굴까지 당길 수 있다.
			camera_distance = clampf(maxf(_arm_length, config.camera_distance), config.camera_min_distance, config.camera_max_distance)
		if is_node_ready():
			_apply_view()
var showcase_yaw := 0.0
## 캐릭터 화면에서 무기를 보는 중인지(캐릭터가 왼손에 무기를 들고 보여 준다), 캐릭터를 누른 횟수(누를 때마다 반응한다)
var showcase_weapon := false
var showcase_pokes := 0

var _action: AttackData
var _action_time := 0.0
var _action_hit := 0
var _action_advanced := 0.0
var _action_target: Enemy
## 기본 공격 연속에서 마지막으로 낸 단계(0부터). -1이면 처음부터.
var _chain_index := -1
var _chain_grace := 0.0
var _attack_buffer := 0.0
var _dodge_time := 0.0
var _dodge_cooldown := 0.0
var _dodge_direction := Vector3.ZERO
var _since_dodge := 100.0
var _sprinting := false
var _hurt_left := 0.0
var _hit_stop := 0.0
var _skill_hold := -1.0
var _combat_left := 0.0
var _time_since_floor := 0.0
var _jump_buffer := 0.0
var _shake := 0.0
var _shake_time := 0.0
var _camera_inside := false
## 자유 시점을 끄면 돌아갈 기본 시점
var _base_camera := CameraMode.THIRD_PERSON
## 지금 카메라 거리(벽에 막혀 당긴 것 포함)와 카메라 중심(부드럽게 따라간다)
var _arm_length := 4.2
var _pivot := Vector3.ZERO
var _pivot_ready := false
## 벽에 막혔던 뒤로 남은 시간(초). 그동안은 천천히 되돌린다.
var _blocked_time := 0.0
## 싸우는 중 물러나는 정도(0~1)
var _combat_view := 0.0
var _probe := SphereShape3D.new()
var _was_alive := true
## 호스트에서: 쓰러진 이 플레이어를 일으킨 정도(초)
var _revive_elapsed := 0.0
## 보상 수치 합(수치 이름 → 값). 보상이 바뀌면 다시 센다.
var _bonus_cache: Dictionary[StringName, float] = {}
## 호스트에서: 체력에 반영한 보상 수 (새 보상의 회복을 한 번만 준다)
var _rewards_applied := 0

@onready var collision: CollisionShape3D = $CollisionShape3D
@onready var body: PlayerBody = $Body
@onready var health: Health = $Health
@onready var camera_rig: Node3D = $CameraRig
@onready var camera_arm: SpringArm3D = $CameraRig/CameraArm
@onready var camera: Camera3D = $CameraRig/CameraArm/Camera3D


func _ready() -> void:
	add_to_group(GROUP)
	if kit == null:
		kit = Characters.find(character_id).kit()
	health.max_health = kit.max_health
	health.current = kit.max_health
	var local := is_multiplayer_authority()
	camera.current = local and use_device_input
	camera.fov = GameSettings.fov
	camera_distance = config.camera_distance
	_arm_length = config.camera_distance
	camera_yaw = rotation.y
	camera_rig.top_level = true
	if local and use_device_input and GameSettings.first_person:
		camera_mode = CameraMode.FIRST_PERSON
		_base_camera = CameraMode.FIRST_PERSON
	if local and use_device_input:
		visor_on = GameSettings.visor_on
		# 내 화면에서만 캐릭터(나와 동료)를 카메라 쪽에서 약하게 비춘다.
		camera.add_child(PlayerBody.make_character_light())
	# 카메라 팔의 길이는 직접 정한다(_update_camera: 벽에 막히면 바로 당기고 풀리면 천천히 되돌린다).
	camera_arm.collision_mask = 0
	camera_arm.spring_length = _arm_length
	health.died.connect(_on_died)
	health.revived.connect(_on_revived)
	_apply_view()
	_update_camera(0.0)


func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority() or not use_device_input or input_blocked:
		return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event.is_action_pressed(InputActions.TOGGLE_VIEW) and not event.is_echo():
		toggle_first_person()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(InputActions.FREE_VIEW) and not event.is_echo():
		toggle_free_view()
		get_viewport().set_input_as_handled()
		return
	var motion := event as InputEventMouseMotion
	if motion != null:
		look(GameSettings.look_delta(motion.relative))
		return
	var wheel := event as InputEventMouseButton
	if wheel != null and wheel.pressed:
		if wheel.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom(-1)
		elif wheel.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom(1)


## 카메라를 돌린다. x는 좌우(라디안), y는 상하(라디안). 몸은 돌지 않는다.
func look(delta_radians: Vector2) -> void:
	camera_yaw = wrapf(camera_yaw - delta_radians.x, -PI, PI)
	camera_pitch = clampf(camera_pitch - delta_radians.y, deg_to_rad(config.camera_min_pitch), deg_to_rad(config.camera_max_pitch))


## 자유 시점(과 캐릭터 화면)에서 카메라를 당기거나(-) 민다(+). 휠 한 칸이 1이다. 기본 시점에서는 거리가 정해져 있다.
func zoom(steps: int) -> void:
	if camera_mode != CameraMode.FREE and not showcase:
		return
	camera_distance = clampf(camera_distance * pow(ZOOM_FACTOR, steps), config.camera_min_distance, config.camera_max_distance)


## 기본 시점을 1인칭 ↔ 3인칭으로 바꾼다. 자유 시점이었으면 자유 시점을 끄고 바꾼다. 다음에 켜도 기억한다.
func toggle_first_person() -> void:
	set_camera_mode(CameraMode.THIRD_PERSON if _base_camera == CameraMode.FIRST_PERSON else CameraMode.FIRST_PERSON)


## 자유 시점을 켜거나 끈다(끄면 기본 시점으로 돌아간다).
func toggle_free_view() -> void:
	set_camera_mode(_base_camera if camera_mode == CameraMode.FREE else CameraMode.FREE)


## 카메라 방식을 바꾼다. remember면 기본 시점(1인칭·3인칭)을 설정에 저장한다(화면 확인용 시작 옵션은 저장하지 않는다).
func set_camera_mode(mode: CameraMode, remember := true) -> void:
	if mode == camera_mode:
		return
	if mode == CameraMode.FREE:
		# 지금 보이는 거리에서 시작한다.
		camera_distance = clampf(maxf(_arm_length, config.camera_distance), config.camera_min_distance, config.camera_max_distance)
	else:
		_base_camera = mode
		if remember and use_device_input and is_multiplayer_authority():
			GameSettings.first_person = mode == CameraMode.FIRST_PERSON
			GameSettings.save()
	camera_mode = mode
	_apply_view()


## 몸이 보는 방향 (수평, 길이 1)
func facing() -> Vector3:
	return -global_basis.z


func horizontal_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()


func is_alive() -> bool:
	return health.is_alive()


## 지금 하고 있는 공격 동작. 없으면 null.
func current_action() -> AttackData:
	return _action if state == State.ACTION else null


func action_time() -> float:
	return _action_time


func is_sprinting() -> bool:
	return _sprinting


## 맞힌 순간 잠깐 멈추는 중인지 (몸 동작도 함께 멈춘다)
func is_hit_stopped() -> bool:
	return _hit_stop > 0.0


func ultimate_ready() -> bool:
	return energy >= kit.max_energy


## 고른 보상이 올려 준 수치 합 (예: attack 0.3이면 공격력 +30%)
func bonus(stat: StringName) -> float:
	if not _bonus_cache.has(stat):
		var total := 0.0
		var pool := _reward_pool()
		for reward_id in rewards:
			var reward := pool.find(StringName(reward_id)) if pool != null else null
			if reward != null and reward.stat == stat:
				total += reward.value
		_bonus_cache[stat] = total
	return _bonus_cache[stat]


## 보상을 하나 고른다 (조종하는 피어). 동기화로 호스트에 간다.
func add_reward(reward_id: StringName) -> void:
	var next := rewards.duplicate()
	next.append(String(reward_id))
	rewards = next


## 호스트가 작전을 시작하거나 끝낼 때 부른다: 보상을 비우고 SP와 에너지를 처음으로 되돌린다.
@rpc("any_peer", "call_local", "reliable")
func reset_for_run() -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	rewards = PackedStringArray()
	sp = 100.0
	energy = 0.0


static var _pool: RewardPool


static func _reward_pool() -> RewardPool:
	if _pool == null:
		_pool = load(Run.REWARD_POOL) as RewardPool
	return _pool


## 호스트: 보상에 따라 최대 체력을 바꾸고, 새로 고른 보상의 회복을 준다.
func _apply_reward_health() -> void:
	if not is_inside_tree() or not multiplayer.is_server() or kit == null:
		return
	var before := health.max_health
	health.max_health = kit.max_health * (1.0 + bonus(&"max_health"))
	if health.is_alive() and health.max_health > before:
		health.current = minf(health.current + health.max_health - before, health.max_health)
	var pool := _reward_pool()
	while _rewards_applied < rewards.size():
		var reward := pool.find(StringName(rewards[_rewards_applied])) if pool != null else null
		if reward != null and reward.heal > 0.0:
			health.heal(health.max_health * reward.heal)
		_rewards_applied += 1
	if rewards.is_empty():
		_rewards_applied = 0
		health.current = minf(health.current, health.max_health)


# ---- 매 프레임 ----

func _process(delta: float) -> void:
	if not is_multiplayer_authority():
		return
	_update_camera(delta)


func _physics_process(delta: float) -> void:
	if multiplayer.is_server():
		_update_revive(delta)
	if not is_multiplayer_authority():
		return
	var intent := _read_intent()
	if intent.visor_pressed:
		set_visor(not visor_on)
	if not is_alive():
		intent = PlayerIntent.new()
		if state != State.DOWN:
			_enter_down()
	if intent.lock_on_pressed:
		toggle_lock_on()
	_validate_lock_target()

	_timers(delta, intent)
	reviving = intent.interact_held and is_alive() and _downed_teammate_nearby() != null
	if _hit_stop > 0.0:
		# 맞힌 순간: 동작을 잠깐 멈춘다. 떨어지는 것만 계속한다.
		_hit_stop = maxf(_hit_stop - delta, 0.0)
		velocity = Vector3(0.0, velocity.y - config.gravity * delta if not is_on_floor() else 0.0, 0.0)
		move_and_slide()
		return

	match state:
		State.DOWN:
			_process_down(delta)
		State.HURT:
			_process_hurt(delta)
		State.DODGE:
			_process_dodge(delta, intent)
		State.ACTION:
			_process_action(delta, intent)
		_:
			_process_free(delta, intent)
	move_and_slide()
	if state == State.GROUND or state == State.AIR:
		state = State.GROUND if is_on_floor() else State.AIR
	sp = minf(sp + kit.sp_regen * (1.0 + bonus(&"sp_regen")) * delta, kit.max_sp)
	if _enemy_alerted_nearby():
		_combat_left = maxf(_combat_left, ALERT_COMBAT_TIME)
	in_combat = _combat_left > 0.0
	_update_fov(delta)


func _timers(delta: float, intent: PlayerIntent) -> void:
	_dodge_cooldown = maxf(_dodge_cooldown - delta, 0.0)
	_since_dodge += delta
	_chain_grace = maxf(_chain_grace - delta, 0.0)
	_combat_left = maxf(_combat_left - delta, 0.0)
	_attack_buffer = ATTACK_BUFFER if intent.attack_pressed else maxf(_attack_buffer - delta, 0.0)
	_time_since_floor = 0.0 if is_on_floor() else _time_since_floor + delta
	_jump_buffer = config.jump_buffer_time if intent.jump_pressed else maxf(_jump_buffer - delta, 0.0)
	if state != State.DODGE and current_action() == null:
		invulnerable = false


## 걷기·달리기·점프 중. 공격, 스킬, 회피를 시작할 수 있다.
func _process_free(delta: float, intent: PlayerIntent) -> void:
	var on_floor := is_on_floor()
	if not on_floor:
		velocity.y -= config.gravity * delta
	var wish := _wish_direction(intent)
	if _sprinting and (not intent.dodge_held or wish == Vector3.ZERO):
		_sprinting = false
	var speed := config.sprint_speed if _sprinting else config.run_speed
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var rate := config.air_acceleration
	if on_floor:
		rate = config.ground_deceleration if wish == Vector3.ZERO else config.ground_acceleration
	horizontal = horizontal.move_toward(wish * speed, rate * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	if wish != Vector3.ZERO:
		_turn_toward(wish, config.turn_speed * delta)
	if _jump_buffer > 0.0 and (on_floor or _time_since_floor <= config.coyote_time):
		_jump()
		return
	if _handle_combat_input(intent):
		return


## 공격·스킬·회피 입력을 처리한다. 무언가 시작했으면 true.
func _handle_combat_input(intent: PlayerIntent) -> bool:
	if intent.dodge_pressed and _try_dodge(intent):
		return true
	if _handle_skill_input(intent):
		return true
	if _attack_buffer > 0.0 and is_on_floor():
		_attack_buffer = 0.0
		return _attack(intent)
	return false


## 배틀 스킬 키: 궁극기 에너지가 차 있으면 길게 눌렀는지 보고 궁극기, 아니면 배틀 스킬.
func _handle_skill_input(intent: PlayerIntent) -> bool:
	if intent.ultimate_pressed:
		return _try_skill(kit.ultimate, intent)
	if intent.skill_pressed:
		if not ultimate_ready():
			return _try_skill(kit.battle_skill, intent)
		_skill_hold = 0.0
		return false
	if _skill_hold < 0.0:
		return false
	if intent.skill_held:
		_skill_hold += get_physics_process_delta_time()
		if _skill_hold >= config.ultimate_hold_time:
			_skill_hold = -1.0
			return _try_skill(kit.ultimate, intent)
		return false
	# 짧게 눌렀다 뗐다: 배틀 스킬
	_skill_hold = -1.0
	return _try_skill(kit.battle_skill, intent)


func _try_skill(attack: AttackData, intent: PlayerIntent) -> bool:
	if attack == null or not is_on_floor():
		return false
	if sp < attack.sp_cost:
		skill_denied.emit("SP가 부족합니다")
		return false
	if attack.energy_cost > 0.0 and energy < attack.energy_cost:
		skill_denied.emit("궁극기 에너지가 부족합니다")
		return false
	sp -= attack.sp_cost
	if attack.energy_cost > 0.0:
		energy = 0.0
	energy = minf(energy + attack.energy_gain, kit.max_energy)
	_start_action(attack, _pick_target(intent, config.auto_target_range * 1.4), intent)
	return true


## 공격 키: 경직된 적이 가까우면 처형, 회피 직후면 대시 공격, 아니면 기본 공격 다음 단계.
func _attack(intent: PlayerIntent) -> bool:
	var staggered := _staggered_enemy_nearby()
	if staggered != null and kit.finisher != null:
		_chain_index = -1
		_start_action(kit.finisher, staggered, intent)
		return true
	if _since_dodge <= config.dash_attack_window and kit.dash_attack != null:
		_chain_index = -1
		_start_action(kit.dash_attack, _pick_target(intent, config.auto_target_range * 1.5), intent)
		return true
	if kit.basic_chain.is_empty():
		return false
	var next := 0
	if _chain_grace > 0.0 or (state == State.ACTION and kit.basic_chain.has(_action)):
		next = (_chain_index + 1) % kit.basic_chain.size()
	_chain_index = next
	_start_action(kit.basic_chain[next], _pick_target(intent, config.auto_target_range), intent)
	return true


func _start_action(attack: AttackData, target: Enemy, intent: PlayerIntent) -> void:
	_action = attack
	_action_time = 0.0
	_action_hit = 0
	_action_advanced = 0.0
	_action_target = target
	_sprinting = false
	_skill_hold = -1.0
	_combat_left = COMBAT_TIME
	state = State.ACTION
	action_id = attack.id
	action_count += 1
	invulnerable = attack.invulnerable_until > 0.0
	velocity.x = 0.0
	velocity.z = 0.0
	# 목표가 있으면 그쪽을, 없으면 입력한 방향을 바로 본다.
	var aim := Vector3.ZERO
	if target != null:
		aim = target.global_position - global_position
	elif intent != null:
		aim = _wish_direction(intent)
	aim.y = 0.0
	if aim.length() > 0.05:
		_face(aim)
	action_started.emit(attack)


func _process_action(delta: float, intent: PlayerIntent) -> void:
	var attack := _action
	_action_time += delta
	if not is_on_floor():
		velocity.y -= config.gravity * delta
	else:
		velocity.y = 0.0
	# 목표 쪽으로 몸 돌리기 (동작 앞부분만)
	if _action_time <= attack.turn_until and _action_target != null and is_instance_valid(_action_target):
		var to_target := _action_target.global_position - global_position
		to_target.y = 0.0
		if to_target.length() > 0.1:
			_turn_toward(to_target, 20.0 * delta)
	# 원본 동작의 내디딤만큼 앞으로 나아간다. 목표 바로 앞에서는 멈춘다.
	var step := attack.advance_at(_action_time) - _action_advanced
	_action_advanced += step
	step = maxf(step, 0.0)
	if step > 0.0 and attack.stop_short > 0.0:
		step = minf(step, _room_ahead(attack.stop_short))
	velocity.x = facing().x * step / delta
	velocity.z = facing().z * step / delta
	# 타격
	while _action_hit < attack.hits.size() and _action_time >= attack.hits[_action_hit].time:
		_perform_hit(attack, _action_hit)
		_action_hit += 1
	if _action_time >= attack.invulnerable_until:
		invulnerable = false
	# 끊기: 회피, 이어지는 공격, 스킬, 이동
	if intent.dodge_pressed and _action_time >= attack.dodge_cancel_from and _try_dodge(intent):
		return
	var is_basic := kit.basic_chain.has(attack) or attack == kit.dash_attack
	if is_basic and _action_hit > 0 and _handle_skill_input(intent):
		return
	if _action_time >= attack.chain_from:
		if _handle_skill_input(intent):
			return
		if _attack_buffer > 0.0:
			_attack_buffer = 0.0
			_attack(intent)
			return
	if _action_time >= attack.move_cancel_from and intent.move != Vector2.ZERO:
		_end_action()
		return
	if _action_time >= attack.duration:
		_end_action()


func _end_action() -> void:
	if _action != null and kit.basic_chain.has(_action):
		_chain_grace = CHAIN_GRACE
	else:
		_chain_index = -1
	_action = null
	_action_target = null
	invulnerable = false
	state = State.GROUND if is_on_floor() else State.AIR


## 타격 한 번: 맞힌 느낌은 바로 보여 주고, 판정은 호스트에 맡긴다.
func _perform_hit(attack: AttackData, index: int) -> void:
	var hit := attack.hits[index]
	var origin := global_position + Vector3.UP * 1.0
	var forward := facing()
	var predicted := CombatQuery.melee(get_world_3d().direct_space_state, origin, forward, hit.reach, hit.arc, TEAM)
	if not predicted.is_empty():
		_hit_stop = hit.hit_stop
		add_shake(hit.shake)
		for target in predicted:
			HitSpark.spawn(self, target.global_position, hit.effect)
	if multiplayer.is_server():
		_resolve_hit(multiplayer.get_unique_id(), attack.id, index, origin, forward)
	else:
		_request_hit.rpc_id(1, attack.id, index, origin, forward)


## 조종하는 피어가 타격 판정을 요청한다 (호스트에서 실행).
@rpc("any_peer", "call_remote", "reliable")
func _request_hit(attack_id: StringName, index: int, origin: Vector3, forward: Vector3) -> void:
	if not multiplayer.is_server() or multiplayer.get_remote_sender_id() != get_multiplayer_authority():
		return
	_resolve_hit(get_multiplayer_authority(), attack_id, index, origin, forward)


## 호스트: 타격을 판정해 적에게 피해를 주고, 결과를 공격한 피어에 알린다.
func _resolve_hit(peer: int, attack_id: StringName, index: int, origin: Vector3, forward: Vector3) -> void:
	var attack := kit.find_attack(attack_id)
	if attack == null or index < 0 or index >= attack.hits.size():
		return
	var hit := attack.hits[index]
	var positions := PackedVector3Array()
	var amounts := PackedFloat32Array()
	var flags := PackedInt32Array()
	var energy_gain := 0.0
	var sp_gain := 0.0
	var power := kit.attack_power * (1.0 + bonus(&"attack")) * (1.0 + bonus(_damage_stat(attack)))
	var stagger_scale := 1.0 + bonus(&"stagger")
	var shatter_scale := 1.0 + bonus(&"shatter_damage")
	for target in CombatQuery.melee(get_world_3d().direct_space_state, origin, forward, hit.reach, hit.arc, TEAM):
		var enemy := target.owner as Enemy
		if enemy == null or not enemy.is_alive():
			continue
		var outcome := enemy.receive_hit(peer, hit, power, origin, stagger_scale, shatter_scale)
		positions.append(target.global_position)
		amounts.append(outcome.amount)
		flags.append(outcome.flags)
		energy_gain += attack.energy_per_hit
		sp_gain += attack.sp_per_hit
	if positions.is_empty():
		return
	if peer == multiplayer.get_unique_id():
		_apply_hit_results(positions, amounts, flags, energy_gain, sp_gain)
	else:
		_hit_results.rpc_id(peer, positions, amounts, flags, energy_gain, sp_gain)


## 이 동작의 피해를 올리는 보상 수치
func _damage_stat(attack: AttackData) -> StringName:
	if attack == kit.battle_skill:
		return &"skill_damage"
	if attack == kit.ultimate:
		return &"ultimate_damage"
	if attack == kit.finisher:
		return &"finisher_damage"
	return &"basic_damage"


@rpc("any_peer", "call_remote", "reliable")
func _hit_results(positions: PackedVector3Array, amounts: PackedFloat32Array, flags: PackedInt32Array, energy_gain: float, sp_gain: float) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	_apply_hit_results(positions, amounts, flags, energy_gain, sp_gain)


func _apply_hit_results(positions: PackedVector3Array, amounts: PackedFloat32Array, flags: PackedInt32Array, energy_gain: float, sp_gain: float) -> void:
	energy = minf(energy + energy_gain * (1.0 + bonus(&"energy_gain")), kit.max_energy)
	sp = minf(sp + sp_gain, kit.max_sp)
	_combat_left = COMBAT_TIME
	for i in positions.size():
		if use_device_input:
			DamageNumber.spawn(self, positions[i], amounts[i], flags[i])
		hit_confirmed.emit(positions[i], amounts[i], flags[i])


## 회피: 이동 입력이 있으면 그쪽으로 내닫고, 없으면 뒤로 물러난다.
func _try_dodge(intent: PlayerIntent) -> bool:
	if _dodge_cooldown > 0.0 or not is_on_floor() or state == State.DOWN or state == State.HURT:
		return false
	var wish := _wish_direction(intent)
	dodge_back = wish == Vector3.ZERO
	_dodge_direction = -facing() if dodge_back else wish.normalized()
	if not dodge_back:
		_face(_dodge_direction)
	if state == State.ACTION:
		_end_action()
		_chain_index = -1
	state = State.DODGE
	_dodge_time = 0.0
	_sprinting = false
	invulnerable = true
	dodge_count += 1
	return true


func _process_dodge(delta: float, intent: PlayerIntent) -> void:
	_dodge_time += delta
	var speed := config.backstep_speed if dodge_back else config.dodge_speed
	# 끝으로 갈수록 조금 느려진다.
	var t := clampf(_dodge_time / config.dodge_duration, 0.0, 1.0)
	speed *= lerpf(1.0, 0.6, t * t)
	velocity.x = _dodge_direction.x * speed
	velocity.z = _dodge_direction.z * speed
	velocity.y = 0.0 if is_on_floor() else velocity.y - config.gravity * delta
	if _dodge_time >= config.dodge_invulnerable + bonus(&"dodge_invulnerable"):
		invulnerable = false
	if _dodge_time < config.dodge_duration:
		return
	invulnerable = false
	_since_dodge = 0.0
	_dodge_cooldown = config.dodge_cooldown
	state = State.GROUND if is_on_floor() else State.AIR
	var wish := _wish_direction(intent)
	_sprinting = intent.dodge_held and wish != Vector3.ZERO and not dodge_back
	var keep := config.sprint_speed if _sprinting else config.run_speed
	var horizontal := Vector3(velocity.x, 0.0, velocity.z).limit_length(keep)
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	# 회피 중에 누른 공격은 대시 공격으로 이어진다.
	_handle_combat_input(intent)


func _process_hurt(delta: float) -> void:
	_hurt_left -= delta
	velocity.y = 0.0 if is_on_floor() else velocity.y - config.gravity * delta
	var horizontal := Vector3(velocity.x, 0.0, velocity.z).move_toward(Vector3.ZERO, 12.0 * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	if _hurt_left <= 0.0:
		state = State.GROUND


func _process_down(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, 20.0 * delta)
	velocity.z = move_toward(velocity.z, 0.0, 20.0 * delta)
	velocity.y = 0.0 if is_on_floor() else velocity.y - config.gravity * delta


func _enter_down() -> void:
	if state == State.ACTION:
		_end_action()
	state = State.DOWN
	_sprinting = false
	invulnerable = false
	lock_target = null


func _jump() -> void:
	velocity.y = config.jump_velocity()
	jump_count += 1
	_jump_buffer = 0.0
	_time_since_floor = config.coyote_time + 1.0
	state = State.AIR


# ---- 맞기 (호스트가 부른다) ----

## 호스트가 적의 공격을 이 플레이어에게 맞혔을 때 조종하는 피어에 알린다.
func notify_hit(heavy: bool, from: Vector3, energy_gain: float) -> void:
	_take_hit.rpc_id(get_multiplayer_authority(), heavy, from, energy_gain)


@rpc("any_peer", "call_local", "reliable")
func _take_hit(heavy: bool, from: Vector3, energy_gain: float) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	energy = minf(energy + energy_gain, kit.max_energy)
	_combat_left = COMBAT_TIME
	add_shake(0.5 if heavy else 0.2)
	got_hit.emit(heavy)
	if not is_alive() or state == State.DOWN:
		return
	var action := current_action()
	if not heavy or (action != null and action.super_armor):
		_flinch(from)
		return
	if state == State.ACTION:
		_end_action()
		_chain_index = -1
	state = State.HURT
	_hurt_left = HURT_TIME
	_sprinting = false
	hurt_count += 1
	var away := global_position - from
	away.y = 0.0
	if away.length() > 0.01:
		var push := away.normalized() * 4.0
		velocity.x = push.x
		velocity.z = push.z
		_face(-away)


## 가볍게 맞았다: 맞은 쪽을 정하고 번호를 올린다(몸이 윗몸만 움찔한다).
func _flinch(from: Vector3) -> void:
	var toward := from - global_position
	toward.y = 0.0
	var forward := toward.dot(facing())
	var right := toward.dot(global_basis.x)
	if absf(forward) >= absf(right):
		flinch_side = HitSide.FRONT if forward >= 0.0 else HitSide.BACK
	else:
		flinch_side = HitSide.RIGHT if right > 0.0 else HitSide.LEFT
	flinch_count += 1


## 가까운 적이 나를 알아채고 싸우려 드는지 (적 상태는 호스트가 정해 모든 피어에 동기화된다)
func _enemy_alerted_nearby() -> bool:
	for enemy in Roster.enemies(self):
		if not enemy.is_alive() or enemy.state == Enemy.State.IDLE:
			continue
		if enemy.global_position.distance_squared_to(global_position) <= ALERT_RANGE * ALERT_RANGE:
			return true
	return false


## 호스트가 적의 공격을 무적으로 피한 것을 알린다: 완벽한 회피.
func notify_perfect_dodge() -> void:
	_perfect_dodge.rpc_id(get_multiplayer_authority())


@rpc("any_peer", "call_local", "reliable")
func _perfect_dodge() -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	sp = minf(sp + kit.perfect_dodge_sp, kit.max_sp)
	perfect_dodged.emit()
	if use_device_input and _is_solo():
		_slow_motion()


func _is_solo() -> bool:
	return multiplayer.multiplayer_peer is OfflineMultiplayerPeer


## 완벽한 회피의 느린 시간. 혼자 할 때만 쓴다(코옵에서는 남의 시간까지 늦출 수 없다).
func _slow_motion() -> void:
	Engine.time_scale = SLOW_MOTION_SCALE
	await get_tree().create_timer(SLOW_MOTION_TIME, true, false, true).timeout
	Engine.time_scale = 1.0


## 호스트가 시작 위치로 옮길 때 부른다 (방을 다시 시작할 때 등).
@rpc("any_peer", "call_local", "reliable")
func respawn_at(spawn_position: Vector3, reset_resources: bool) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	global_position = spawn_position
	velocity = Vector3.ZERO
	if state == State.ACTION:
		_end_action()
	state = State.GROUND
	lock_target = null
	if reset_resources:
		sp = 100.0
		energy = 0.0


func _on_died(_info: DamageInfo) -> void:
	_apply_view()


func _on_revived() -> void:
	_apply_view()
	if is_multiplayer_authority() and state == State.DOWN:
		state = State.GROUND


# ---- 동료 일으키기 (호스트) ----

func _update_revive(delta: float) -> void:
	if is_alive():
		_revive_elapsed = 0.0
		health.revive_progress = 0.0
		return
	var helped := false
	for other: Node in get_tree().get_nodes_in_group(GROUP):
		var mate := other as Player
		if mate == self or mate == null or not mate.is_alive() or not mate.reviving:
			continue
		if mate.global_position.distance_to(global_position) <= REVIVE_RANGE:
			helped = true
	_revive_elapsed = _revive_elapsed + delta if helped else maxf(_revive_elapsed - delta, 0.0)
	health.revive_progress = _revive_elapsed / REVIVE_TIME
	if _revive_elapsed >= REVIVE_TIME:
		_revive_elapsed = 0.0
		health.revive(REVIVE_HEALTH)


func _downed_teammate_nearby() -> Player:
	for other: Node in get_tree().get_nodes_in_group(GROUP):
		var mate := other as Player
		if mate != self and mate != null and not mate.is_alive() and mate.global_position.distance_to(global_position) <= REVIVE_RANGE:
			return mate
	return null


# ---- 목표 찾기 ----

## 대상 고정을 켜거나 끈다. 켤 때는 화면 가운데에 가까운 적을 고른다.
func toggle_lock_on() -> void:
	if lock_target != null:
		lock_target = null
		return
	var best: Enemy = null
	var best_score := INF
	var view := -camera.global_basis.z
	for node: Node in get_tree().get_nodes_in_group(Enemy.GROUP):
		var enemy := node as Enemy
		if enemy == null or not enemy.is_alive():
			continue
		var to_enemy := enemy.global_position - global_position
		var distance := to_enemy.length()
		if distance > config.lock_on_range:
			continue
		var angle := view.angle_to(enemy.global_position - camera.global_position)
		if angle > deg_to_rad(60.0):
			continue
		var score := angle * 10.0 + distance * 0.1
		if score < best_score:
			best_score = score
			best = enemy
	lock_target = best


func _validate_lock_target() -> void:
	if lock_target == null:
		return
	if not is_instance_valid(lock_target) or not lock_target.is_alive() or lock_target.global_position.distance_to(global_position) > config.lock_on_range * 1.2:
		lock_target = null


## 공격할 적: 대상 고정이 있으면 그 적, 없으면 가까운 적 중 입력 방향(없으면 카메라 방향)에 가까운 적.
func _pick_target(intent: PlayerIntent, max_range: float) -> Enemy:
	if lock_target != null and lock_target.global_position.distance_to(global_position) <= max_range * 2.0:
		return lock_target
	var wish := _wish_direction(intent) if intent != null else Vector3.ZERO
	var preferred := wish.normalized() if wish != Vector3.ZERO else _camera_forward()
	var best: Enemy = null
	var best_score := INF
	for node: Node in get_tree().get_nodes_in_group(Enemy.GROUP):
		var enemy := node as Enemy
		if enemy == null or not enemy.is_alive():
			continue
		var to_enemy := enemy.global_position - global_position
		to_enemy.y = 0.0
		var distance := to_enemy.length()
		if distance > max_range + enemy.radius():
			continue
		var angle := preferred.angle_to(to_enemy) if distance > 0.01 else 0.0
		if angle > deg_to_rad(110.0):
			continue
		var score := distance + angle * 2.5
		if score < best_score:
			best_score = score
			best = enemy
	return best


func _staggered_enemy_nearby() -> Enemy:
	var best: Enemy = null
	var best_distance := config.finisher_range
	for node: Node in get_tree().get_nodes_in_group(Enemy.GROUP):
		var enemy := node as Enemy
		if enemy == null or not enemy.is_alive() or not enemy.is_staggered():
			continue
		var distance := enemy.global_position.distance_to(global_position) - enemy.radius()
		if distance <= best_distance:
			best_distance = distance
			best = enemy
	return best


## 앞으로 더 나아가도 되는 거리: 앞에 있는 목표 바로 앞(stop_short)까지.
func _room_ahead(stop_short: float) -> float:
	var target := _action_target
	if target == null or not is_instance_valid(target) or not target.is_alive():
		return INF
	var to_target := target.global_position - global_position
	to_target.y = 0.0
	var along := to_target.dot(facing())
	if along <= 0.0:
		return INF
	return maxf(along - target.radius() - stop_short, 0.0)


# ---- 도우미 ----

func _camera_forward() -> Vector3:
	return Vector3(-sin(camera_yaw), 0.0, -cos(camera_yaw))


## 카메라 기준 이동 입력을 세상 방향으로 바꾼다 (수평, 길이 0~1).
func _wish_direction(intent: PlayerIntent) -> Vector3:
	if intent == null or intent.move == Vector2.ZERO:
		return Vector3.ZERO
	var local := Vector3(intent.move.x, 0.0, -intent.move.y)
	return (Basis(Vector3.UP, camera_yaw) * local).normalized() * minf(intent.move.length(), 1.0)


## 몸을 그 방향으로 바로 돌린다.
func _face(direction: Vector3) -> void:
	rotation.y = atan2(-direction.x, -direction.z)


func _turn_toward(direction: Vector3, max_step: float) -> void:
	var target := atan2(-direction.x, -direction.z)
	rotation.y = rotate_toward(rotation.y, target, max_step)


func add_shake(amount: float) -> void:
	_shake = maxf(_shake, amount)


func set_visor(on: bool) -> void:
	visor_on = on
	if use_device_input:
		GameSettings.visor_on = on
		GameSettings.save()


func _read_intent() -> PlayerIntent:
	if intent_override != null:
		var copied := intent_override.copy()
		intent_override.consume_edges()
		return copied
	if not use_device_input or input_blocked:
		return PlayerIntent.new()
	return PlayerIntent.from_device()


# ---- 카메라 ----

func _update_camera(delta: float) -> void:
	# 캐릭터 화면: 캐릭터 앞에서 온몸이 보이게 비춘다.
	if showcase and delta > 0.0:
		camera_yaw = lerp_angle(camera_yaw, rotation.y + PI + showcase_yaw, minf(6.0 * delta, 1.0))
		camera_pitch = lerpf(camera_pitch, deg_to_rad(-4.0), minf(6.0 * delta, 1.0))
	# 대상 고정 중에는 카메라가 대상 쪽으로 돌아간다.
	if lock_target != null and is_instance_valid(lock_target) and delta > 0.0:
		var to_target := lock_target.global_position - global_position
		to_target.y = 0.0
		if to_target.length() > 1.0:
			var wanted := atan2(-to_target.x, -to_target.z)
			camera_yaw = lerp_angle(camera_yaw, wanted, minf(config.lock_on_turn_speed * delta, 1.0))
			camera_pitch = lerpf(camera_pitch, deg_to_rad(-14.0), minf(2.0 * delta, 1.0))
	var free := camera_mode == CameraMode.FREE or showcase
	var first := camera_mode == CameraMode.FIRST_PERSON and not showcase
	# 방식마다 카메라 중심과 거리:
	#   1인칭: 눈 위치, 거리 0
	#   자유 시점·캐릭터 화면: 멀면 몸 가운데, 가까이 당길수록 얼굴(눈)로 옮겨 간다. 휠로 정한 거리
	#   3인칭: 어깨 높이, 정해진 거리. 싸우는 중에는 조금 물러나 주변 적이 보이게 한다.
	var target_distance := config.camera_distance
	var target_pivot := global_position + Vector3.UP * config.camera_pivot_height
	if first:
		target_distance = 0.0
		target_pivot = body.eye_position()
	elif free:
		target_distance = camera_distance
		var body_center := global_position + Vector3.UP * (1.0 if showcase else config.camera_pivot_height)
		var face := clampf((config.camera_body_distance - camera_distance) / maxf(config.camera_body_distance - config.camera_face_distance, 0.01), 0.0, 1.0)
		target_pivot = body_center.lerp(body.eye_position(), smoothstep(0.0, 1.0, face))
	else:
		_combat_view = move_toward(_combat_view, 1.0 if in_combat else 0.0, delta * 0.8)
		target_distance = lerpf(config.camera_distance, config.camera_combat_distance, smoothstep(0.0, 1.0, _combat_view))
	# 중심을 따라가기: 3인칭은 수평은 바로(달릴 때 뒤처지지 않게), 높이는 부드럽게(계단·점프에서 화면이 덜 흔들리게).
	# 1인칭과 자유 시점은 동작으로 흔들리는 눈·얼굴을 조금 늦게 따라간다.
	if not _pivot_ready or delta <= 0.0:
		_pivot = target_pivot
		_pivot_ready = true
	elif first or free:
		_pivot = _pivot.lerp(target_pivot, minf(config.first_person_follow * delta, 1.0))
	else:
		_pivot = Vector3(target_pivot.x, lerpf(_pivot.y, target_pivot.y, minf(12.0 * delta, 1.0)), target_pivot.z)
	camera_rig.global_position = _pivot
	camera_rig.global_basis = Basis.from_euler(Vector3(camera_pitch, camera_yaw, 0.0))
	# 거리: 벽·바닥·기둥에 막히면 바로 당기고, 막힌 것이 풀리면 천천히 되돌린다(덜컹이지 않게).
	# 방식을 바꿀 때(1인칭 ↔ 3인칭 등)는 부드럽게 옮겨 간다.
	var allowed := _camera_clearance(target_distance, free)
	var wanted_length := minf(target_distance, allowed)
	if allowed < target_distance - 0.05:
		_blocked_time = 0.6
	_blocked_time = maxf(_blocked_time - delta, 0.0)
	if delta <= 0.0:
		_arm_length = wanted_length
	elif wanted_length < _arm_length:
		_arm_length = minf(lerpf(_arm_length, wanted_length, minf(25.0 * delta, 1.0)), allowed)
	elif _blocked_time > 0.0:
		_arm_length = move_toward(_arm_length, wanted_length, config.camera_return_speed * delta)
	else:
		_arm_length = lerpf(_arm_length, wanted_length, minf(8.0 * delta, 1.0))
	camera_arm.spring_length = _arm_length
	# 가까이 볼 때는 앞쪽 자르는 거리를 줄여 얼굴·칼이 잘리지 않게 한다.
	camera.near = 0.02 if first or _arm_length < 0.8 else 0.05
	# 흔들림: 세게 맞힐수록 크게, 빠르게 잦아든다.
	_shake = move_toward(_shake, 0.0, delta * 2.5)
	_shake_time += delta * 40.0
	# 카메라 위치는 카메라 팔(SpringArm3D)이 정하므로 흔들림은 화면 어긋남(offset)으로 준다.
	var amount := _shake * _shake * 0.12
	camera.h_offset = sin(_shake_time * 1.3) * amount
	camera.v_offset = cos(_shake_time * 1.7) * amount
	# 카메라가 벽에 밀려 머리에 붙으면 몸을 숨긴다(자유 시점은 정말 머리 속에 들어갔을 때만).
	var inside := not first and _arm_length < (FREE_INSIDE_DISTANCE if free else CAMERA_INSIDE_DISTANCE)
	if inside != _camera_inside:
		_camera_inside = inside
		_apply_view()


## 카메라 중심에서 뒤로 distance만큼 갈 때 벽·바닥(world 레이어)에 막히지 않는 거리
func _camera_clearance(distance: float, fine: bool) -> float:
	if distance <= 0.01 or not is_inside_tree():
		return distance
	_probe.radius = 0.06 if fine and distance < 1.5 else config.camera_probe_radius
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _probe
	query.transform = Transform3D(Basis.IDENTITY, _pivot)
	query.motion = camera_rig.global_basis.z * distance
	query.collision_mask = 1
	query.exclude = [get_rid()]
	var result := get_world_3d().direct_space_state.cast_motion(query)
	return distance * result[0]


## 카메라의 지금 거리(m, 벽에 막혀 당긴 것 포함). 테스트와 디버그용.
func camera_length() -> float:
	return _arm_length


func _update_fov(delta: float) -> void:
	var target := GameSettings.fov
	if _sprinting:
		target += config.sprint_fov_bonus
	camera.fov = lerpf(camera.fov, target, minf(config.fov_transition_speed * delta, 1.0))


## 내 화면에서 내 몸을 어떻게 그릴지: 1인칭이면 머리만 숨기고(팔·칼·몸은 보인다), 3인칭 카메라가 벽에 밀려
## 머리에 붙었으면 몸 전체를 그림자만 남긴다.
func _apply_view() -> void:
	var mine := is_multiplayer_authority()
	body.set_first_person(mine and camera_mode == CameraMode.FIRST_PERSON and not showcase)
	if mine and _camera_inside:
		body.set_view_mode(PlayerBody.ViewMode.SHADOW_ONLY)
	else:
		body.set_view_mode(PlayerBody.ViewMode.VISIBLE)
