class_name Session
extends Node
## 한 판의 게임. 구역(전투 방)을 불러오고, 참가한 피어마다 그 사람이 고른 캐릭터로 플레이어를 스폰한다.
##
## 싱글 플레이는 OfflineMultiplayerPeer로 "혼자 호스트하는 코옵"처럼 돌아가므로,
## 싱글·호스트·참여가 모두 같은 코드 경로를 탄다.
## 플레이어 스폰과 제거는 호스트만 하고, MultiplayerSpawner가 다른 피어에 복제한다.
## 참여한 피어는 접속한 뒤 고른 캐릭터를 호스트에 알리고(_register), 호스트가 그 캐릭터로 스폰한다.
##
## 판은 로비에서 시작한다. 호스트가 구역을 바꾸면(change_zone) 모든 피어가 같은 구역을 불러오고 플레이어는 새 구역의
## 시작 자리로 간다. 구역 노드 이름(Zone1, Zone2, ...)은 호스트가 정해서 보낸다. 적 복제는 노드 경로로 찾으므로
## 나중에 들어온 피어도 이름이 같아야 한다.
## 작전(전투 방) 중에는 새로 들어오는 사람을 받지 않는다(적 복제가 로비에 있는 피어와 맞지 않는다).

signal started
signal ended(reason: String)
signal player_spawned(player: Player)
signal zone_changed(zone: Node)

enum Mode { NONE, SINGLE, HOST, CLIENT }

const DEFAULT_PORT := 47820
## 접속 인증에서 호스트가 보내는 답
const ACCEPTED := "crossfield:ok"
const REFUSED := "crossfield:refused"
const MAX_PLAYERS := 3
const PLAYER_SCENE := preload("res://src/player/player.tscn")

## 처음 불러올 구역 (로비)
@export var zone_scene: PackedScene = preload("res://src/zones/lobby/lobby.tscn")
## false면 플레이어가 키보드·마우스를 읽지 않는다. 테스트용.
@export var use_device_input := true
## false면 전투 방이 적을 불러내지 않는다. 테스트용.
@export var waves_enabled := true

## 내가 고른 캐릭터. 혼자 하거나 방을 만들면 바로 쓰고, 참여하면 접속한 뒤 호스트에 알린다.
var character_id := Characters.DEFAULT_ID
## false면 새로 들어오는 사람을 받지 않는다(작전 중). 호스트가 정한다. 접속 인증 단계에서 거절해서, 들어오려던
## 피어에 지금 방의 적이 복제되지 않게 한다(그 피어는 로비를 불러 놓은 상태라 경로가 맞지 않는다).
var accepting_players := true

var _zone_serial := 0

var mode := Mode.NONE

@onready var world: Node3D = $World
@onready var players: Node3D = $Players
@onready var spawner: MultiplayerSpawner = $PlayerSpawner
@onready var run: Run = $Run


func _ready() -> void:
	spawner.spawn_function = _spawn_player
	spawner.spawned.connect(_on_spawned)


func start_single() -> Error:
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	mode = Mode.SINGLE
	_load_zone()
	_spawn_for(multiplayer.get_unique_id(), character_id)
	started.emit()
	return OK


func host(port: int = DEFAULT_PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_server(port, MAX_PLAYERS - 1)
	if error != OK:
		return error
	multiplayer.multiplayer_peer = peer
	_use_authentication()
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	mode = Mode.HOST
	_load_zone()
	_spawn_for(multiplayer.get_unique_id(), character_id)
	started.emit()
	return OK


func join(address: String, port: int = DEFAULT_PORT) -> Error:
	if address.strip_edges().is_empty():
		return ERR_INVALID_PARAMETER
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_client(address, port)
	if error != OK:
		return error
	multiplayer.multiplayer_peer = peer
	_use_authentication()
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_end.bind("호스트에 연결하지 못했습니다. 작전 중이면 끝난 뒤에 다시 참여하세요."))
	multiplayer.server_disconnected.connect(_end.bind("호스트와의 연결이 끊어졌습니다."))
	mode = Mode.CLIENT
	# 스폰 메시지가 오기 전에 구역이 있어야 내 플레이어가 바닥 위에 선다.
	_load_zone()
	return OK


## 세션을 끝내고 연결을 닫는다. 세션 노드 해제는 호출한 쪽이 맡는다.
func leave() -> void:
	# 복제 중인 노드를 먼저 치워야 한다. 연결부터 바꾸면 복제 시스템이 이미 잊은 노드를
	# 다시 정리하려다 오류가 난다.
	for node: Node in players.get_children() + world.get_children():
		node.get_parent().remove_child(node)
		node.free()
	# 완벽한 회피의 느린 시간 중에 끝나도 다음 판은 제 속도로 시작한다.
	Engine.time_scale = 1.0
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	mode = Mode.NONE


## 일시정지는 혼자 할 때만 허용한다. 코옵 중에는 게임이 멈추지 않는다.
func can_pause() -> bool:
	return mode == Mode.SINGLE


## 같은 LAN의 다른 사람이 접속할 때 입력할 이 기기의 주소들.
static func lan_addresses() -> PackedStringArray:
	var found: PackedStringArray = []
	for address in IP.get_local_addresses():
		var parts := address.split(".")
		if parts.size() != 4:
			continue
		var second := parts[1].to_int()
		var private := (
			parts[0] == "10"
			or (parts[0] == "192" and parts[1] == "168")
			or (parts[0] == "172" and second >= 16 and second <= 31)
		)
		if private:
			found.append(address)
	return found


func get_player(peer_id: int) -> Player:
	return players.get_node_or_null(str(peer_id)) as Player


func get_local_player() -> Player:
	return get_player(multiplayer.get_unique_id())


## 지금 구역(전투 방). 아직 불러오지 않았으면 null.
func zone() -> Node:
	return world.get_child(0) if world.get_child_count() > 0 else null


## 호스트: 모든 플레이어를 일으켜 시작 위치로 옮긴다(방을 다시 시작할 때).
func respawn_players(reset_resources: bool) -> void:
	if not multiplayer.is_server():
		return
	var index := 0
	for node: Node in players.get_children():
		var player := node as Player
		if player == null:
			continue
		player.health.revive(1.0)
		player.respawn_at.rpc_id(player.get_multiplayer_authority(), _spawn_position(index), reset_resources)
		index += 1


func _load_zone() -> void:
	_set_zone(zone_scene, "Zone0")


## 호스트: 모든 피어를 다른 구역으로 옮긴다. 지금 구역의 적은 먼저 치워 둔다(Run이 맡는다).
func change_zone(scene_path: String) -> void:
	if not multiplayer.is_server():
		return
	_zone_serial += 1
	_change_zone.rpc(scene_path, "Zone%d" % _zone_serial)


@rpc("authority", "call_local", "reliable")
func _change_zone(scene_path: String, zone_name: String) -> void:
	var scene := load(scene_path) as PackedScene
	if scene == null:
		return
	_set_zone(scene, zone_name)
	if multiplayer.is_server():
		respawn_players(false)


func _set_zone(scene: PackedScene, zone_name: String) -> void:
	for node: Node in world.get_children():
		world.remove_child(node)
		node.queue_free()
	var next := scene.instantiate()
	next.name = zone_name
	world.add_child(next)
	GameSettings.apply_brightness(get_viewport())
	zone_changed.emit(next)


## 로비에서 캐릭터를 바꾼다. 내 플레이어를 새 캐릭터로 다시 스폰해 달라고 호스트에 부탁한다.
func request_character(chosen: StringName) -> void:
	character_id = chosen
	if multiplayer.is_server():
		change_character(multiplayer.get_unique_id(), chosen)
	else:
		_request_character.rpc_id(1, String(chosen))


@rpc("any_peer", "call_remote", "reliable")
func _request_character(chosen: String) -> void:
	if multiplayer.is_server():
		change_character(multiplayer.get_remote_sender_id(), StringName(chosen))


## 호스트: 플레이어를 그 자리에서 다른 캐릭터로 바꾼다(지우고 새로 스폰). 로비에서만 쓴다.
func change_character(peer_id: int, chosen: StringName) -> void:
	if not multiplayer.is_server() or not accepting_players:
		return
	var old := get_player(peer_id)
	if old == null or old.character_id == Characters.find(chosen).id:
		return
	var at := old.global_position
	var yaw := old.rotation.y
	players.remove_child(old)
	old.free()
	var player := spawner.spawn({"peer_id": peer_id, "position": at, "yaw": yaw, "character": String(chosen)}) as Player
	player_spawned.emit(player)


func _spawn_for(peer_id: int, chosen: StringName) -> void:
	# 호스트 쪽에서는 spawned 시그널이 오지 않으므로 직접 알린다.
	var info := {"peer_id": peer_id, "position": _spawn_position(players.get_child_count()), "character": String(chosen)}
	var player := spawner.spawn(info) as Player
	player_spawned.emit(player)


func _spawn_position(index: int) -> Vector3:
	var room := zone()
	var points := room.get_node_or_null("SpawnPoints") if room != null else null
	if points == null or points.get_child_count() == 0:
		return Vector3.ZERO
	var marker := points.get_child(index % points.get_child_count()) as Node3D
	return marker.global_position


## 참여한 피어가 고른 캐릭터를 알린다(호스트에서 실행). 호스트가 그 캐릭터로 플레이어를 스폰한다.
@rpc("any_peer", "call_remote", "reliable")
func _register(chosen: String) -> void:
	if not multiplayer.is_server():
		return
	var peer := multiplayer.get_remote_sender_id()
	if get_player(peer) != null or not accepting_players:
		return
	_spawn_for(peer, StringName(chosen))


func _spawn_player(data: Variant) -> Node:
	var info: Dictionary = data
	var peer_id: int = info["peer_id"]
	var player := PLAYER_SCENE.instantiate() as Player
	player.name = str(peer_id)
	player.set_multiplayer_authority(peer_id)
	# 체력은 호스트가 판정하므로, 체력과 그 동기화만 호스트 권한으로 되돌린다.
	player.get_node("Health").set_multiplayer_authority(1)
	player.get_node("HealthSync").set_multiplayer_authority(1)
	player.position = info["position"]
	player.rotation.y = float(info.get("yaw", 0.0))
	player.character_id = Characters.find(StringName(str(info.get("character", "")))).id
	player.use_device_input = use_device_input
	return player


func _on_spawned(node: Node) -> void:
	player_spawned.emit(node as Player)


func _on_peer_connected(peer_id: int) -> void:
	# 플레이어는 그 피어가 고른 캐릭터를 알려 오면(_register) 스폰한다.
	print("[세션] 참가: 피어 %d" % peer_id)


## 접속 인증: 호스트가 들어오는 피어에게 받을지 먼저 알린다. 인증이 끝나야 복제가 시작되므로, 작전 중에 거절하면
## 지금 방의 적이 그 피어에 복제되지 않는다.
func _use_authentication() -> void:
	var scene_multiplayer := multiplayer as SceneMultiplayer
	if scene_multiplayer == null:
		return
	scene_multiplayer.auth_callback = _on_auth
	scene_multiplayer.peer_authenticating.connect(_on_peer_authenticating)


func _on_peer_authenticating(peer_id: int) -> void:
	var scene_multiplayer := multiplayer as SceneMultiplayer
	if not multiplayer.is_server():
		return
	scene_multiplayer.send_auth(peer_id, (ACCEPTED if accepting_players else REFUSED).to_utf8_buffer())
	if accepting_players:
		scene_multiplayer.complete_auth(peer_id)
	else:
		# 거절한다는 답이 건너갈 틈을 두고 끊는다.
		get_tree().create_timer(0.5, true, false, true).timeout.connect(func() -> void:
			if multiplayer.multiplayer_peer != null:
				scene_multiplayer.disconnect_peer(peer_id))


## 참여하는 피어: 호스트의 답을 받는다.
func _on_auth(peer_id: int, data: PackedByteArray) -> void:
	if multiplayer.is_server():
		return
	if data.get_string_from_utf8() == ACCEPTED:
		(multiplayer as SceneMultiplayer).complete_auth(peer_id)
	else:
		_end("작전이 진행 중입니다. 방장이 로비로 돌아온 뒤에 참여해 주세요.")


func _on_peer_disconnected(peer_id: int) -> void:
	print("[세션] 퇴장: 피어 %d" % peer_id)
	var player := get_player(peer_id)
	if player != null:
		player.queue_free()


func _on_connected_to_server() -> void:
	print("[세션] 호스트에 접속함 (내 피어 %d)" % multiplayer.get_unique_id())
	_register.rpc_id(1, String(character_id))
	started.emit()


func _end(reason: String) -> void:
	# 연결이 끊긴 피어로는 더 이상 멀티플레이 함수를 부를 수 없으므로 바로 정리한다.
	# 복제 시스템이 이벤트를 처리하는 도중이므로, 정리는 이번 프레임 끝으로 미룬다.
	_finish.call_deferred(reason)


func _finish(reason: String) -> void:
	print("[세션] 종료: %s" % reason)
	leave()
	ended.emit(reason)
