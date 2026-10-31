class_name Enemy
extends CharacterBody3D
## 적. 판단·이동·피해 판정은 호스트가 하고, 상태와 체력은 동기화로 모두에게 퍼진다.
##
## 흐름: 가까운 플레이어를 쫓는다 → 공격 거리에 들면 예고(땅에 맞을 자리가 차오른다) → 예고가 끝나면 맞힌다
## → 잠깐 쉰다. 플레이어는 예고 동안 회피한다. 예고가 끝나는 순간 회피 무적이면 완벽한 회피다.
## 맞으면 경직 게이지가 쌓이고, 다 차면 경직된다(움직이지 못하고 받는 피해 증가, 처형 가능).
## 배틀 스킬에 맞으면 원석 결정이 붙고, 궁극기가 그 결정을 깨뜨리면 큰 추가 피해를 입는다.

signal staggered
signal defeated

enum State { IDLE, CHASE, WIND_UP, RECOVER, HURT, STAGGERED, DEAD }

const GROUP := &"enemies"
const TEAM := &"enemy"
## 경직 중에 받는 피해 배율
const STAGGERED_DAMAGE := 1.3
## 원석 결정이 붙어 있는 시간(초)과, 깨뜨릴 때의 추가 피해(공격력 배율)·경직
const CRYSTAL_TIME := 15.0
const SHATTER_BONUS := 4.0
const SHATTER_STAGGER := 50.0
## 움찔하는 시간(초)
const HURT_TIME := 0.35
## 맞지 않은 채 이 시간(초)이 지나면 경직 게이지가 줄기 시작한다(초당 줄어드는 비율).
const STAGGER_DECAY_DELAY := 3.0
const STAGGER_DECAY_RATE := 0.15
## 쓰러진 뒤 몸이 사라질 때까지(초). 원작 모델은 쓰러지는 동작(3초 남짓)을 보이고 땅으로 가라앉는다(EnemyBody).
const CORPSE_TIME := 4.0
## 플레이어가 적의 공격에 맞을 때 얻는 궁극기 에너지
const ENERGY_ON_HURT := 3.0
## 적끼리 떨어지려는 거리(m)
const SEPARATION := 1.3
## 밀려남(과 원작 이동 곡선이 없는 공격의 내디딤)이 줄어드는 빠르기(m/s²). 예전 18은 맞는 순간 확 밀렸다가 0.3초 만에
## 멈춰서 순간이동처럼 보였다. 같은 거리를 조금 더 길게 밀린다.
const KNOCKBACK_DECAY := 10.0
## 격노하면 예고 시간과 이동 속도에 곱하는 값
const ENRAGED_WIND_UP := 0.75
const ENRAGED_SPEED := 1.25

## 맞힌 결과 (호스트가 공격한 플레이어에게 돌려준다)
class HitOutcome:
	var amount := 0.0
	var flags := 0

@export var data: EnemyData
## false면 생각하지 않고 서 있다(허수아비). 맞고 경직되고 쓰러지는 것은 그대로다.
@export var ai_enabled := true

# ---- 동기화되는 값 (호스트가 정한다) ----
var state := State.IDLE
## 지금(또는 마지막) 공격 이름과, 공격 예고를 시작할 때마다 1씩 느는 번호. 몸이 이 변화를 보고 예고를 보여 준다.
var attack_id := &""
var attack_count := 0
var hurt_count := 0
var stagger := 0.0
## 원석 결정이 남은 시간(초). 0이면 없다.
var crystal_left := 0.0
## 격노했는지 (보스가 체력이 줄면)
var enraged := false

# ---- 호스트만 쓰는 값 ----
var target: Player
var _attack: EnemyAttackData
var _state_time := 0.0
var _cooldowns: Dictionary[StringName, float] = {}
var _knockback := Vector3.ZERO
## 이번 공격에서 원작 이동 곡선(EnemyAttackData.travel)대로 나아간 거리(m)
var _traveled := 0.0
var _since_hit := 100.0
var _repath := 0.0
## 이번 공격을 이미 피한 플레이어 (완벽한 회피를 한 번만 알린다)
var _dodged: Array[Player] = []
## 이번 돌진 공격에 이미 맞은 플레이어
var _struck: Array[Player] = []

@onready var collision: CollisionShape3D = $CollisionShape3D
@onready var body: EnemyBody = $Body
@onready var health: Health = $Health
@onready var hitbox: Hitbox = $Hitbox
@onready var agent: NavigationAgent3D = $NavigationAgent3D


func _ready() -> void:
	add_to_group(GROUP)
	if data == null:
		data = load("res://data/enemies/grunt.tres") as EnemyData
	health.max_health = data.max_health
	health.current = data.max_health
	var capsule := (collision.shape as CapsuleShape3D).duplicate() as CapsuleShape3D
	capsule.radius = data.radius
	capsule.height = data.height
	collision.shape = capsule
	collision.position.y = data.height * 0.5
	var hit_shape := hitbox.get_node("Shape") as CollisionShape3D
	var hit_capsule := CapsuleShape3D.new()
	hit_capsule.radius = data.radius + 0.1
	hit_capsule.height = data.height
	hit_shape.shape = hit_capsule
	hitbox.position.y = data.height * 0.5
	agent.radius = data.radius
	agent.height = data.height
	health.died.connect(_on_died)
	body.setup(self)


func is_alive() -> bool:
	return health.is_alive() and state != State.DEAD


func is_staggered() -> bool:
	return state == State.STAGGERED


func has_crystal() -> bool:
	return crystal_left > 0.0


func radius() -> float:
	return data.radius


## 머리 위 정보(체력 막대)를 띄울 높이
func top() -> Vector3:
	return global_position + Vector3.UP * (data.height + 0.35)


func current_attack() -> EnemyAttackData:
	return find_attack(attack_id)


func find_attack(id: StringName) -> EnemyAttackData:
	for attack in data.attacks:
		if attack.id == id:
			return attack
	return null


func state_time() -> float:
	return _state_time


## 지금 예고 시간(격노하면 짧다)
func wind_up_time(attack: EnemyAttackData) -> float:
	return attack.wind_up * (ENRAGED_WIND_UP if enraged else 1.0)


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	_state_time += delta
	_since_hit += delta
	crystal_left = maxf(crystal_left - delta, 0.0)
	for id: StringName in _cooldowns:
		_cooldowns[id] = maxf(_cooldowns[id] - delta, 0.0)
	if data.enrage_below > 0.0 and not enraged and health.ratio() < data.enrage_below:
		enraged = true
	if _since_hit > STAGGER_DECAY_DELAY and state != State.STAGGERED:
		stagger = maxf(stagger - data.stagger_max * STAGGER_DECAY_RATE * delta, 0.0)
	var move := Vector3.ZERO
	match state:
		State.IDLE:
			if ai_enabled:
				_find_target()
				if target != null:
					_set_state(State.CHASE)
		State.CHASE:
			if ai_enabled:
				move = _process_chase(delta)
			else:
				_set_state(State.IDLE)
		State.WIND_UP:
			_process_wind_up(delta)
			move = _attack_move(delta)
		State.RECOVER:
			if _attack.sweep_time > 0.0 and _state_time <= _attack.sweep_time:
				_sweep_strike(_attack)
			if _state_time >= _attack.recovery:
				_set_state(State.CHASE)
			else:
				move = _attack_move(delta)
		State.HURT:
			if _state_time >= HURT_TIME:
				_set_state(State.CHASE)
		State.STAGGERED:
			if _state_time >= data.stagger_duration:
				stagger = 0.0
				_set_state(State.CHASE)
		State.DEAD:
			if _state_time >= CORPSE_TIME:
				queue_free()
			return
	_knockback = _knockback.move_toward(Vector3.ZERO, KNOCKBACK_DECAY * delta)
	velocity.x = move.x + _knockback.x
	velocity.z = move.z + _knockback.z
	velocity.y = 0.0 if is_on_floor() else velocity.y - 18.0 * delta
	move_and_slide()


func _set_state(next: State) -> void:
	state = next
	_state_time = 0.0


## 가장 가까운 살아 있는 플레이어를 목표로 한다.
func _find_target() -> void:
	var best: Player = null
	var best_distance := data.aggro_range
	for player in Roster.players(self):
		if not player.is_alive():
			continue
		var distance := _flat_distance(player.global_position)
		if distance < best_distance:
			best_distance = distance
			best = player
	target = best


func _process_chase(delta: float) -> Vector3:
	if target == null or not is_instance_valid(target) or not target.is_alive():
		_find_target()
		if target == null:
			_set_state(State.IDLE)
			return Vector3.ZERO
	var distance := _flat_distance(target.global_position) - data.radius - 0.35
	_face_toward(target.global_position, data.turn_speed * delta)
	# 쓸 수 있는 공격이 있으면 예고를 시작한다.
	for attack in data.attacks:
		if _cooldowns.get(attack.id, 0.0) > 0.0:
			continue
		if distance >= attack.min_range and distance <= attack.max_range:
			_start_attack(attack)
			return Vector3.ZERO
	# 다가가거나(근접), 거리를 유지한다(원거리).
	var direction := Vector3.ZERO
	if data.preferred_range > 0.0:
		if distance < data.preferred_range - 2.0:
			direction = (global_position - target.global_position)
		elif distance > data.preferred_range + 1.5:
			direction = _path_direction(target.global_position, delta)
	elif distance > _closest_range() * 0.8:
		direction = _path_direction(target.global_position, delta)
	direction.y = 0.0
	var speed := data.move_speed * (ENRAGED_SPEED if enraged else 1.0)
	var move := direction.normalized() * speed if direction.length() > 0.01 else Vector3.ZERO
	return move + _separation() * speed * 0.6


func _closest_range() -> float:
	var reach := 1.5
	for attack in data.attacks:
		reach = maxf(reach, attack.max_range) if attack.projectile_speed <= 0.0 else reach
	return reach


## 길찾기 지도가 있으면 그 길을 따라, 없으면 곧장 간다.
func _path_direction(destination: Vector3, delta: float) -> Vector3:
	_repath -= delta
	if _repath <= 0.0:
		_repath = 0.25
		agent.target_position = destination
	if NavigationServer3D.map_get_iteration_id(agent.get_navigation_map()) > 0 and not agent.is_navigation_finished():
		var next := agent.get_next_path_position()
		var to_next := next - global_position
		to_next.y = 0.0
		if to_next.length() > 0.05:
			return to_next
	return destination - global_position


## 다른 적과 너무 붙지 않게 밀어내는 방향
func _separation() -> Vector3:
	var push := Vector3.ZERO
	for other in Roster.enemies(self):
		if other == self or not other.is_alive():
			continue
		var away := global_position - other.global_position
		away.y = 0.0
		var distance := away.length()
		if distance < SEPARATION and distance > 0.01:
			push += away / distance * (1.0 - distance / SEPARATION)
	return push


func _start_attack(attack: EnemyAttackData) -> void:
	_attack = attack
	attack_id = attack.id
	attack_count += 1
	_dodged.clear()
	_struck.clear()
	_cooldowns[attack.id] = attack.cooldown
	_traveled = attack.travel_at(attack.clip_time(0.0, wind_up_time(attack), false), _attack_end_time(attack))
	_set_state(State.WIND_UP)


## 공격 동작의 재생 위치를 따라 원작 이동 곡선대로 나아가는 속도. 예고 동안에도 원작처럼 다가서거나 뛰어든다.
func _attack_move(delta: float) -> Vector3:
	if _attack == null or _attack.travel.is_empty() or delta <= 0.0:
		return Vector3.ZERO
	var time := _attack.clip_time(_state_time, wind_up_time(_attack), state == State.RECOVER)
	var distance := _attack.travel_at(time, _attack_end_time(_attack))
	var step := distance - _traveled
	_traveled = distance
	return facing() * (step / delta)


## 공격 동작이 끝나는(맞힌 뒤 쉬기가 끝나는) 동작 시각
static func _attack_end_time(attack: EnemyAttackData) -> float:
	return maxf(attack.clip_hit, attack.clip_from) + attack.recovery


func _process_wind_up(delta: float) -> void:
	# 예고 앞부분에는 목표를 따라 돌고, 끝 무렵에는 방향을 굳힌다(그래야 피할 수 있다).
	var wind_up := wind_up_time(_attack)
	if target != null and is_instance_valid(target) and _state_time < wind_up * 0.6:
		_face_toward(target.global_position, data.turn_speed * delta)
	if _state_time < wind_up:
		return
	_execute_attack(_attack)
	_set_state(State.RECOVER)


func _execute_attack(attack: EnemyAttackData) -> void:
	if attack.lunge > 0.0 and attack.travel.is_empty():
		# 원작 이동 곡선이 없으면 한꺼번에 내디딘다. 줄어드는 빠르기가 일정하므로, lunge(m)만큼 가려면 처음 속도는
		# sqrt(2 × 줄어드는 빠르기 × 거리)다.
		_knockback = facing() * sqrt(2.0 * KNOCKBACK_DECAY * attack.lunge)
	if attack.sweep_time > 0.0:
		_sweep_strike(attack)
		return
	if attack.projectile_speed > 0.0:
		var aim_at := target.global_position + Vector3.UP * 1.0 if target != null and is_instance_valid(target) else global_position + facing() * 10.0
		var origin := global_position + Vector3.UP * (data.height * 0.7) + facing() * (data.radius + 0.2)
		_fire_projectile.rpc(origin, (aim_at - origin).normalized() * attack.projectile_speed, attack.id)
		return
	for player in Roster.players(self):
		if not player.is_alive():
			continue
		var to_player := player.global_position - global_position
		to_player.y = 0.0
		if to_player.length() > attack.reach + 0.35:
			continue
		if attack.arc < 180.0 and to_player.length() > 0.3 and rad_to_deg(facing().angle_to(to_player)) > attack.arc:
			continue
		strike(player, attack)


## 돌진 공격: 내디디는 동안 지금 자리에서 닿는 플레이어를 한 번씩 맞힌다.
func _sweep_strike(attack: EnemyAttackData) -> void:
	for player in Roster.players(self):
		if _struck.has(player) or not player.is_alive():
			continue
		var to_player := player.global_position - global_position
		to_player.y = 0.0
		if to_player.length() > attack.reach + 0.35:
			continue
		if to_player.length() > 0.3 and rad_to_deg(facing().angle_to(to_player)) > attack.arc:
			continue
		_struck.append(player)
		strike(player, attack)


## 플레이어 한 명을 이 공격으로 맞힌다(호스트). 회피 무적이면 완벽한 회피로 알린다.
func strike(player: Player, attack: EnemyAttackData) -> bool:
	if player.invulnerable:
		if player.state == Player.State.DODGE and not _dodged.has(player):
			_dodged.append(player)
			player.notify_perfect_dodge()
		return false
	var info := DamageInfo.create(attack.damage, 0, player.global_position + Vector3.UP, attack.id)
	if player.health.apply_damage(info) > 0.0:
		player.notify_hit(attack.heavy, global_position, ENERGY_ON_HURT)
	return true


@rpc("authority", "call_local", "reliable")
func _fire_projectile(origin: Vector3, launch_velocity: Vector3, id: StringName) -> void:
	var projectile := EnemyProjectile.new()
	projectile.velocity = launch_velocity
	projectile.attack = find_attack(id)
	projectile.source = self
	projectile.authoritative = multiplayer.is_server()
	get_parent().add_child(projectile)
	projectile.global_position = origin


## 플레이어의 공격에 맞았다(호스트). 피해·경직·원석 결정·밀려남을 처리하고 결과를 돌려준다.
## stagger_scale과 shatter_scale은 공격한 플레이어의 보상(경직 증가, 결정 파쇄 피해 증가)이다.
func receive_hit(attacker_peer: int, hit: HitData, attack_power: float, from: Vector3, stagger_scale: float = 1.0, shatter_scale: float = 1.0) -> HitOutcome:
	var outcome := HitOutcome.new()
	if not multiplayer.is_server() or not is_alive():
		return outcome
	_since_hit = 0.0
	var amount := attack_power * hit.damage
	var stagger_gain := hit.stagger * stagger_scale
	if is_staggered():
		amount *= STAGGERED_DAMAGE
	match hit.effect:
		HitData.Effect.APPLY_CRYSTAL:
			crystal_left = CRYSTAL_TIME
		HitData.Effect.SHATTER_CRYSTAL:
			if has_crystal():
				amount += attack_power * SHATTER_BONUS * shatter_scale
				stagger_gain += SHATTER_STAGGER
				crystal_left = 0.0
				outcome.flags |= Player.HIT_SHATTER
	outcome.amount = health.apply_damage(DamageInfo.create(amount, attacker_peer, top(), &"player"))
	if not health.is_alive():
		outcome.flags |= Player.HIT_KILL
		return outcome
	# 때린 플레이어에게 덤빈다.
	var attacker := _player_of(attacker_peer)
	if attacker != null and attacker.is_alive():
		target = attacker
	# 밀려남: knockback² (m)만큼 (knockback 1이면 1m, 0.3이면 9cm). 처음 속도는 sqrt(2 × 줄어드는 빠르기 × 거리).
	var away := global_position - from
	away.y = 0.0
	if away.length() > 0.01 and data.knockback_scale > 0.0:
		_knockback = away.normalized() * hit.knockback * data.knockback_scale * sqrt(2.0 * KNOCKBACK_DECAY)
	if not is_staggered():
		stagger = minf(stagger + stagger_gain, data.stagger_max)
		if stagger >= data.stagger_max:
			_set_state(State.STAGGERED)
			outcome.flags |= Player.HIT_BREAK
			staggered.emit()
			return outcome
		if data.flinches and state != State.HURT:
			hurt_count += 1
			_set_state(State.HURT)
	return outcome


func _player_of(peer: int) -> Player:
	for player in Roster.players(self):
		if player.get_multiplayer_authority() == peer:
			return player
	return null


func _on_died(_info: DamageInfo) -> void:
	state = State.DEAD
	_state_time = 0.0
	crystal_left = 0.0
	hitbox.set_deferred("collision_layer", 0)
	# 쓰러진 몸에 걸리지 않게 몸 충돌도 끈다(바닥에 붙여 두므로 떨어지지 않는다).
	set_deferred("collision_layer", 0)
	defeated.emit()


func facing() -> Vector3:
	return -global_basis.z


func _face_toward(point: Vector3, max_step: float) -> void:
	var to_point := point - global_position
	to_point.y = 0.0
	if to_point.length() < 0.05:
		return
	rotation.y = rotate_toward(rotation.y, atan2(-to_point.x, -to_point.z), max_step)


func _flat_distance(point: Vector3) -> float:
	return Vector2(point.x - global_position.x, point.z - global_position.z).length()
