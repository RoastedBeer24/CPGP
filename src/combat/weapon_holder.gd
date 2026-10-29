class_name WeaponHolder
extends Node3D
## 플레이어가 든 무기들. 발사, 근접 공격, 재장전, 반동, 조준, 무기 교체를 맡는다.
##
## 네트워크 흐름:
##   1) 조종하는 피어가 쏘면 반동·탄약·화면 효과를 바로 처리하고, 호스트에 발사 요청을 보낸다.
##   2) 호스트가 같은 시드로 탄 방향을 다시 계산해 판정하고 피해를 준다.
##   3) 호스트가 다른 피어에 탄 궤적을, 쏜 사람에게 명중 결과(피해 숫자, 명중 표시)를 보낸다.
## 탄약은 쏘는 피어가 관리한다(가족끼리 하는 게임이라 부정 행위 방지는 하지 않는다).

signal weapon_changed(weapon: WeaponData)
signal ammo_changed(in_magazine: int, magazine_size: int)
signal fired(weapon: WeaponData)
signal reload_started(duration: float)
## 내가 쏜 공격이 무언가를 맞혔을 때 (쏜 사람의 피어에서만)
signal hit_confirmed(position: Vector3, amount: float, headshot: bool, killed: bool)

const TEAM := &"player"
const RECOIL_RETURN_SPEED := 0.12  # 라디안/초

## 기본 장비. 스크립트끼리 서로 참조하는 중에 리소스를 미리 불러오면 깨지므로, 실행 시점에 불러온다.
const DEFAULT_LOADOUT: Array[String] = [
	"res://data/weapons/pistol.tres",
	"res://data/weapons/shotgun.tres",
	"res://data/weapons/arm_blade.tres",
]

## 비워 두면 DEFAULT_LOADOUT을 쓴다.
@export var loadout: Array[WeaponData] = []

var current_index := 0
var aiming := false
var reloading := false

var _ammo: Array[int] = []
var _cooldown := 0.0
var _reload_left := 0.0
var _recoil_return := 0.0
var _host_last_fire_frame: Dictionary = {}
var _shot_counter := 0

@onready var player: Player = owner as Player
@onready var viewmodel: Viewmodel = $Viewmodel


func _ready() -> void:
	if loadout.is_empty():
		for path in DEFAULT_LOADOUT:
			loadout.append(load(path) as WeaponData)
	for weapon in loadout:
		_ammo.append(weapon.magazine_size)
	viewmodel.visible = is_multiplayer_authority()
	viewmodel.show_weapon(current_weapon())


func current_weapon() -> WeaponData:
	return loadout[current_index]


func ammo_in_magazine() -> int:
	return _ammo[current_index]


## 조종하는 피어에서 매 물리 프레임 호출된다.
func tick(delta: float, intent: PlayerIntent, can_attack: bool) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	_return_recoil(delta)

	if intent.weapon_slot > 0:
		select(intent.weapon_slot - 1)
	elif intent.weapon_cycle != 0:
		select(wrapi(current_index + intent.weapon_cycle, 0, loadout.size()))

	var weapon := current_weapon()
	aiming = intent.aim_held and can_attack and not weapon.is_melee()

	if reloading:
		_reload_left -= delta
		if _reload_left <= 0.0:
			reloading = false
			_ammo[current_index] = weapon.magazine_size
			ammo_changed.emit(_ammo[current_index], weapon.magazine_size)
		return

	if intent.reload_pressed:
		start_reload()
		return

	var wants_fire := intent.fire_held if weapon.automatic else intent.fire_pressed
	if wants_fire and can_attack and _cooldown <= 0.0:
		if weapon.is_melee():
			_attack_melee(weapon)
		elif _ammo[current_index] > 0:
			_fire(weapon)
		else:
			start_reload()


func select(index: int) -> void:
	if index < 0 or index >= loadout.size() or index == current_index:
		return
	current_index = index
	reloading = false
	_cooldown = 0.25
	viewmodel.show_weapon(current_weapon())
	weapon_changed.emit(current_weapon())
	ammo_changed.emit(_ammo[current_index], current_weapon().magazine_size)


func start_reload() -> void:
	var weapon := current_weapon()
	if weapon.is_melee() or reloading or _ammo[current_index] >= weapon.magazine_size:
		return
	reloading = true
	_reload_left = weapon.reload_time
	reload_started.emit(weapon.reload_time)
	viewmodel.play_reload(weapon.reload_time)


func _fire(weapon: WeaponData) -> void:
	_cooldown = weapon.fire_interval
	_ammo[current_index] -= 1
	ammo_changed.emit(_ammo[current_index], weapon.magazine_size)

	var origin := player.aim_origin()
	var direction := player.aim_direction()
	var spread := weapon.spread_degrees * (weapon.aim_spread_ratio if aiming else 1.0)
	_shot_counter += 1
	var shot_seed := hash([multiplayer.get_unique_id(), _shot_counter, Time.get_ticks_usec()])

	# 효과는 바로 보여 주고, 판정은 호스트에 맡긴다.
	var ends := _trace_pellets(origin, direction, weapon, spread, shot_seed)
	viewmodel.play_fire(weapon)
	_spawn_tracers(viewmodel.muzzle_position() if viewmodel.visible else muzzle_for_others(origin, direction), ends)
	_kick(weapon)
	fired.emit(weapon)
	_host_fire.rpc_id(1, current_index, origin, direction, spread, shot_seed)


func _attack_melee(weapon: WeaponData) -> void:
	_cooldown = weapon.fire_interval
	viewmodel.play_swing()
	fired.emit(weapon)
	_host_melee.rpc_id(1, current_index, player.aim_origin(), player.aim_direction())


func _kick(weapon: WeaponData) -> void:
	var pitch := deg_to_rad(weapon.recoil_pitch) * (0.6 if aiming else 1.0)
	var yaw := deg_to_rad(randf_range(-weapon.recoil_yaw, weapon.recoil_yaw))
	player.look(Vector2(yaw, -pitch))
	_recoil_return += pitch * weapon.recoil_recovery


func _return_recoil(delta: float) -> void:
	if _recoil_return <= 0.0:
		return
	var step := minf(_recoil_return, maxf(RECOIL_RETURN_SPEED, _recoil_return * 8.0) * delta)
	_recoil_return -= step
	player.look(Vector2(0.0, step))


func _trace_pellets(origin: Vector3, direction: Vector3, weapon: WeaponData, spread: float, shot_seed: int) -> PackedVector3Array:
	var space := get_world_3d().direct_space_state
	var ends := PackedVector3Array()
	for pellet in CombatQuery.pellet_directions(direction, weapon.pellets, spread, shot_seed):
		var hit := CombatQuery.trace(space, origin, pellet, weapon.max_range, TEAM)
		ends.append(hit.position if hit != null else origin + pellet * weapon.max_range)
	return ends


# ---- 호스트에서 실행되는 판정 ----

@rpc("any_peer", "call_local", "reliable")
func _host_fire(index: int, origin: Vector3, direction: Vector3, spread: float, shot_seed: int) -> void:
	if not multiplayer.is_server() or not _sender_is_owner() or not _host_can_attack(index):
		return
	var weapon := loadout[index]
	var space := get_world_3d().direct_space_state
	var ends := PackedVector3Array()
	var results: Array[Dictionary] = []
	var per_health: Dictionary = {}
	for pellet in CombatQuery.pellet_directions(direction, weapon.pellets, spread, shot_seed):
		var hit := CombatQuery.trace(space, origin, pellet, weapon.max_range, TEAM)
		if hit == null:
			ends.append(origin + pellet * weapon.max_range)
			continue
		ends.append(hit.position)
		if hit.hitbox == null or hit.hitbox.health == null:
			continue
		var headshot := hit.hitbox.part == Hitbox.Part.HEAD
		var amount := weapon.damage * hit.hitbox.multiplier(weapon.headshot_multiplier) * weapon.falloff(hit.distance)
		var key := hit.hitbox.health.get_instance_id()
		# 산탄은 대상마다 합쳐서 숫자 하나로 보여 준다.
		if not per_health.has(key):
			per_health[key] = {"health": hit.hitbox.health, "amount": 0.0, "headshot": false, "position": hit.position}
		var entry: Dictionary = per_health[key]
		entry["amount"] = float(entry["amount"]) + amount
		entry["headshot"] = bool(entry["headshot"]) or headshot

	for entry: Dictionary in per_health.values():
		results.append(_apply(entry["health"], entry["amount"], entry["position"], weapon.id, entry["headshot"]))
	var tracer_start := muzzle_for_others(origin, direction)
	_show_tracers.rpc(tracer_start, ends)
	if not is_multiplayer_authority():
		_spawn_tracers(tracer_start, ends)
	_send_confirmations(results)


@rpc("any_peer", "call_local", "reliable")
func _host_melee(index: int, origin: Vector3, direction: Vector3) -> void:
	if not multiplayer.is_server() or not _sender_is_owner() or not _host_can_attack(index):
		return
	var weapon := loadout[index]
	if not weapon.is_melee():
		return
	var space := get_world_3d().direct_space_state
	var results: Array[Dictionary] = []
	for hitbox in CombatQuery.melee(space, origin, direction, weapon.melee_reach, weapon.melee_arc_degrees, TEAM):
		var amount := weapon.damage * hitbox.multiplier(weapon.headshot_multiplier)
		results.append(_apply(hitbox.health, amount, hitbox.global_position, weapon.id, hitbox.part == Hitbox.Part.HEAD))
	_send_confirmations(results)


func _apply(health: Health, amount: float, position: Vector3, weapon_id: StringName, headshot: bool) -> Dictionary:
	var info := DamageInfo.create(amount, get_multiplayer_authority(), position, weapon_id, headshot)
	var dealt := health.apply_damage(info)
	return {"position": position, "amount": dealt, "headshot": headshot, "killed": not health.is_alive() and dealt > 0.0}


func _send_confirmations(results: Array[Dictionary]) -> void:
	for result in results:
		if float(result["amount"]) <= 0.0:
			continue
		_confirm_hit.rpc_id(get_multiplayer_authority(), result["position"], result["amount"], result["headshot"], result["killed"])


## 연사 속도를 넘는 요청은 무시한다. 네트워크 지연을 감안해 약간 여유를 둔다.
func _host_can_attack(index: int) -> bool:
	if index < 0 or index >= loadout.size():
		return false
	if player.health != null and not player.health.is_alive():
		return false
	# 실제 시간이 아니라 물리 프레임으로 잰다. 시간 배율이나 테스트의 고정 프레임에도 맞게 동작한다.
	var now := Engine.get_physics_frames()
	var last: int = _host_last_fire_frame.get(index, -100000)
	var min_frames := int(loadout[index].fire_interval * Engine.physics_ticks_per_second * 0.7)
	if now - last < min_frames:
		return false
	_host_last_fire_frame[index] = now
	return true


func _sender_is_owner() -> bool:
	var sender := multiplayer.get_remote_sender_id()
	# call_local로 자기 자신에게 보낸 경우 sender는 0이 아니라 자기 피어 번호다.
	return sender == get_multiplayer_authority()


## 다른 피어와 3인칭에서 보이는 탄 궤적의 시작점. 몸 모델이 든 총의 총구에서 시작하고,
## 몸 모델이 없으면(캡슐 몸) 눈앞에서 시작한다. 1인칭 무기 모델은 본인에게만 있다.
func muzzle_for_others(origin: Vector3, direction: Vector3) -> Vector3:
	if player.body.has_muzzle():
		return player.body.muzzle_position()
	return origin + direction * 0.6 + Vector3.DOWN * 0.25


# ---- 모든 피어에서 실행되는 효과 ----

@rpc("any_peer", "call_remote", "unreliable")
func _show_tracers(from: Vector3, ends: PackedVector3Array) -> void:
	if multiplayer.get_remote_sender_id() != 1 or is_multiplayer_authority():
		return
	_spawn_tracers(from, ends)


@rpc("any_peer", "call_local", "reliable")
func _confirm_hit(position: Vector3, amount: float, headshot: bool, killed: bool) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	hit_confirmed.emit(position, amount, headshot, killed)
	DamageNumber.spawn(self, position, amount, headshot)


func _spawn_tracers(from: Vector3, ends: PackedVector3Array) -> void:
	for end in ends:
		Tracer.spawn(self, from, end)
