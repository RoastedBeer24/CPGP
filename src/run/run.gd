class_name Run
extends Node
## 작전(한 판). 로비에서 방장이 출발하면 방들을 차례로 깬다(RunData). 방을 깰 때마다 각자 보상 하나를 고르고,
## 마지막 방(최종 보스)을 깨면 작전 완료, 모두 쓰러지면 작전 실패. 어느 쪽이든 잠시 뒤 로비로 돌아간다.
## 진행은 호스트가 정하고 동기화(RunSync)로 퍼진다. 보상 선택은 각자의 피어가 하고(Player.rewards), 호스트는
## 모두 골랐는지만 본다.

signal phase_changed(phase: Phase)

enum Phase { LOBBY, ROOM, REWARD, VICTORY, DEFEAT }

const DEFAULT_RUN := "res://data/runs/first_run.tres"
const REWARD_POOL := "res://data/rewards/pool.tres"
const LOBBY_SCENE := "res://src/zones/lobby/lobby.tscn"
## 보상을 고르는 데 기다려 주는 최대 시간(초). 넘으면 고르지 않은 사람 없이 다음 방으로 간다.
const REWARD_TIMEOUT := 40.0
## 작전이 끝나고 로비로 돌아가기까지(초)
const VICTORY_DELAY := 7.0
const DEFEAT_DELAY := 5.0
## 보상 후보 수
const OFFER_COUNT := 3

# ---- 동기화되는 값 (호스트가 정한다) ----
var phase := Phase.LOBBY:
	set(value):
		if phase != value:
			phase = value
			phase_changed.emit(value)
## 지금 방 번호(0부터)
var stage := 0
## 지금까지 연 보상 선택 횟수. 플레이어의 보상 수가 이보다 적으면 아직 고르는 중이다.
var reward_round := 0
## 보상 후보를 고르는 시드 (작전마다 바뀐다)
var run_seed := 0

var data: RunData
var pool: RewardPool

var _phase_time := 0.0

@onready var session: Session = get_parent() as Session


func _ready() -> void:
	data = load(DEFAULT_RUN) as RunData
	pool = load(REWARD_POOL) as RewardPool


func stage_count() -> int:
	return data.stages.size()


func current_stage() -> RunStage:
	return data.stages[clampi(stage, 0, data.stages.size() - 1)]


## 이 플레이어가 이번 선택에서 받을 보상 후보 (각자의 피어가 같은 시드로 고른다)
func offers_for(player: Player) -> Array[RewardData]:
	return pool.offer(hash([run_seed, reward_round, player.get_multiplayer_authority()]), OFFER_COUNT)


## 이 플레이어가 아직 보상을 고르는 중인지
func choosing(player: Player) -> bool:
	return phase == Phase.REWARD and player.rewards.size() < reward_round


## 호스트: 로비에서 작전을 시작한다.
func start() -> void:
	if not multiplayer.is_server() or phase != Phase.LOBBY:
		return
	run_seed = randi()
	reward_round = 0
	session.accepting_players = false
	for player in _players():
		player.reset_for_run.rpc_id(player.get_multiplayer_authority())
		player.health.revive(1.0)
	_enter_stage(0)


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	_phase_time += delta
	match phase:
		Phase.REWARD:
			var waiting := false
			for player in _players():
				waiting = waiting or player.rewards.size() < reward_round
			if not waiting or _phase_time >= REWARD_TIMEOUT:
				_enter_stage(stage + 1)
		Phase.VICTORY:
			if _phase_time >= VICTORY_DELAY:
				return_to_lobby()
		Phase.DEFEAT:
			if _phase_time >= DEFEAT_DELAY:
				return_to_lobby()


## 호스트: 로비로 돌아간다. 보상은 사라지고 모두 일어난다.
func return_to_lobby() -> void:
	if not multiplayer.is_server():
		return
	_set_phase(Phase.LOBBY)
	stage = 0
	reward_round = 0
	await _switch_zone(LOBBY_SCENE)
	for player in _players():
		player.reset_for_run.rpc_id(player.get_multiplayer_authority())
		player.health.revive(1.0)
	session.accepting_players = true


func _enter_stage(index: int) -> void:
	stage = index
	_set_phase(Phase.ROOM)
	var entry := data.stages[index]
	await _switch_zone(entry.scene_path)
	var room := session.zone() as CombatRoom
	if room == null:
		return
	room.waves = entry.waves
	room.auto_restart = false
	room.phase_changed.connect(_on_room_phase.bind(room))


func _on_room_phase(room_phase: CombatRoom.Phase, room: CombatRoom) -> void:
	if session.zone() != room or phase != Phase.ROOM:
		return
	match room_phase:
		CombatRoom.Phase.CLEARED:
			if stage >= data.stages.size() - 1:
				_set_phase(Phase.VICTORY)
			else:
				reward_round += 1
				_set_phase(Phase.REWARD)
		CombatRoom.Phase.FAILED:
			_set_phase(Phase.DEFEAT)


## 지금 방의 적을 먼저 치우고(복제된 적이 사라진 것을 모두 받게 잠깐 기다린다) 구역을 바꾼다.
func _switch_zone(scene_path: String) -> void:
	var room := session.zone() as CombatRoom
	if room != null:
		room.clear_enemies()
		await get_tree().create_timer(0.3, false).timeout
	session.change_zone(scene_path)


func _set_phase(next: Phase) -> void:
	phase = next
	_phase_time = 0.0


func _players() -> Array[Player]:
	var found: Array[Player] = []
	for node: Node in session.players.get_children():
		var player := node as Player
		if player != null:
			found.append(player)
	return found
