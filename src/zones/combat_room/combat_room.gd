class_name CombatRoom
extends Zone
## 전투 방. 웨이브마다 적을 불러내고, 다 쓰러뜨리면 다음 웨이브로 간다. 마지막 웨이브까지 깨면 방 정리.
## 플레이어가 모두 쓰러지면(전멸) 잠시 뒤 처음부터 다시 한다. 진행은 호스트가 정하고 동기화(RoomSync)로 퍼진다.
## 적은 이 방의 MultiplayerSpawner(EnemySpawner)가 모든 피어에 복제한다.

signal phase_changed(phase: Phase)

enum Phase { WAITING, FIGHTING, BETWEEN, CLEARED, FAILED }

const ENEMY_SCENE := preload("res://src/enemies/enemy.tscn")
const ENEMY_DATA := "res://data/enemies/%s.tres"
## 적이 나오는 자리는 플레이어와 이보다 멀어야 한다(m).
const SPAWN_CLEARANCE := 8.0

## 웨이브마다 나오는 적 종류(data/enemies의 파일 이름)
@export var waves: Array[PackedStringArray] = [
	PackedStringArray(["grunt", "grunt", "grunt"]),
	PackedStringArray(["grunt", "grunt", "shooter", "shooter"]),
	PackedStringArray(["heavy", "grunt", "grunt", "shooter"]),
]
## 들어와서 첫 웨이브까지, 웨이브 사이, 방 정리 뒤 다시 시작까지, 전멸 뒤 다시 시작까지(초)
@export var start_delay := 3.0
@export var between_delay := 3.0
@export var restart_delay := 8.0
@export var failed_delay := 5.0

# ---- 동기화되는 값 (호스트가 정한다) ----
var phase := Phase.WAITING:
	set(value):
		if phase != value:
			phase = value
			phase_changed.emit(value)
## 지금 웨이브 번호(1부터). 0이면 아직 시작 전.
var wave := 0
var enemies_left := 0

var _phase_time := 0.0
var _serial := 0

@onready var enemies: Node3D = $Enemies
@onready var spawner: MultiplayerSpawner = $EnemySpawner


func _ready() -> void:
	spawner.spawn_function = _spawn_enemy
	super._ready()


func wave_count() -> int:
	return waves.size()


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	var session := _session()
	if session != null and not session.waves_enabled:
		return
	_phase_time += delta
	match phase:
		Phase.WAITING:
			if _phase_time >= start_delay:
				_start_wave(1)
		Phase.FIGHTING:
			enemies_left = alive_enemies()
			if _everyone_down():
				_set_phase(Phase.FAILED)
			elif enemies_left == 0:
				_set_phase(Phase.CLEARED if wave >= waves.size() else Phase.BETWEEN)
		Phase.BETWEEN:
			if _phase_time >= between_delay:
				_start_wave(wave + 1)
		Phase.CLEARED:
			if _phase_time >= restart_delay:
				restart(true)
		Phase.FAILED:
			if _phase_time >= failed_delay:
				restart(true)


## 살아 있는 적의 수
func alive_enemies() -> int:
	var count := 0
	for node: Node in enemies.get_children():
		var enemy := node as Enemy
		if enemy != null and enemy.is_alive():
			count += 1
	return count


## 호스트: 적을 모두 치우고 플레이어를 일으켜 처음부터 다시 한다.
func restart(reset_resources: bool) -> void:
	if not multiplayer.is_server():
		return
	for node: Node in enemies.get_children():
		node.queue_free()
	var session := _session()
	if session != null:
		session.respawn_players(reset_resources)
	wave = 0
	enemies_left = 0
	_set_phase(Phase.WAITING)


## 호스트: 웨이브를 시작한다. 적은 플레이어에게서 먼 자리부터 나온다.
func _start_wave(number: int) -> void:
	wave = number
	var kinds := waves[number - 1]
	var points := _spawn_points_away_from_players()
	for i in kinds.size():
		var point := points[i % points.size()] if not points.is_empty() else Vector3(0, 0, -10)
		var jitter := Vector3(randf_range(-1.5, 1.5), 0.0, randf_range(-1.5, 1.5)) if i >= points.size() else Vector3.ZERO
		spawn_enemy(kinds[i], point + jitter)
	enemies_left = kinds.size()
	_set_phase(Phase.FIGHTING)


## 호스트: 적 하나를 불러낸다.
func spawn_enemy(kind: String, at: Vector3) -> Enemy:
	_serial += 1
	var to_center := -at
	to_center.y = 0.0
	var yaw := atan2(-to_center.x, -to_center.z) if to_center.length() > 0.1 else 0.0
	return spawner.spawn({"name": "Enemy%d" % _serial, "type": kind, "position": at, "yaw": yaw}) as Enemy


func _spawn_enemy(data: Variant) -> Node:
	var info: Dictionary = data
	var enemy := ENEMY_SCENE.instantiate() as Enemy
	enemy.name = str(info["name"])
	enemy.data = load(ENEMY_DATA % str(info["type"])) as EnemyData
	enemy.position = info["position"]
	enemy.rotation.y = float(info.get("yaw", 0.0))
	return enemy


func _spawn_points_away_from_players() -> Array[Vector3]:
	var far: Array[Vector3] = []
	var near: Array[Vector3] = []
	var markers := get_node_or_null("EnemySpawns")
	if markers == null:
		return far
	var players := Roster.players(self)
	for child: Node in markers.get_children():
		var point := (child as Node3D).global_position
		var clear := true
		for player in players:
			clear = clear and player.global_position.distance_to(point) >= SPAWN_CLEARANCE
		if clear:
			far.append(point)
		else:
			near.append(point)
	far.shuffle()
	far.append_array(near)
	return far


func _everyone_down() -> bool:
	var players := Roster.players(self)
	if players.is_empty():
		return false
	for player in players:
		if player.is_alive():
			return false
	return true


func _set_phase(next: Phase) -> void:
	phase = next
	_phase_time = 0.0
	if next == Phase.CLEARED:
		# 방을 정리하면 쓰러진 동료도 일어난다.
		for player in Roster.players(self):
			if not player.is_alive():
				player.health.revive(0.5)


func _session() -> Session:
	var node := get_parent()
	while node != null and not node is Session:
		node = node.get_parent()
	return node as Session
