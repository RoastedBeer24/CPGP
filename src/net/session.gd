class_name Session
extends Node
## 한 판의 게임. 구역을 불러오고, 참가한 피어마다 플레이어를 스폰한다.
##
## 싱글 플레이는 OfflineMultiplayerPeer로 "혼자 호스트하는 코옵"처럼 돌아가므로,
## 싱글·호스트·참여가 모두 같은 코드 경로를 탄다.
## 플레이어 스폰과 제거는 호스트만 하고, MultiplayerSpawner가 다른 피어에 복제한다.

signal started
signal ended(reason: String)
signal player_spawned(player: Player)

enum Mode { NONE, SINGLE, HOST, CLIENT }

const DEFAULT_PORT := 47820
const MAX_PLAYERS := 3
const PLAYER_SCENE := preload("res://src/player/player.tscn")

@export var zone_scene: PackedScene = preload("res://src/zones/test_range/test_range.tscn")
## false면 플레이어가 키보드·마우스를 읽지 않는다. 테스트용.
@export var use_device_input := true

var mode := Mode.NONE

@onready var world: Node3D = $World
@onready var players: Node3D = $Players
@onready var spawner: MultiplayerSpawner = $PlayerSpawner


func _ready() -> void:
	spawner.spawn_function = _spawn_player
	spawner.spawned.connect(_on_spawned)


func start_single() -> Error:
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	mode = Mode.SINGLE
	_load_zone()
	_spawn_for(multiplayer.get_unique_id())
	started.emit()
	return OK


func host(port: int = DEFAULT_PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_server(port, MAX_PLAYERS - 1)
	if error != OK:
		return error
	multiplayer.multiplayer_peer = peer
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	mode = Mode.HOST
	_load_zone()
	_spawn_for(multiplayer.get_unique_id())
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
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_end.bind("호스트에 연결하지 못했습니다."))
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


func _load_zone() -> void:
	world.add_child(zone_scene.instantiate())


func _spawn_for(peer_id: int) -> void:
	# 호스트 쪽에서는 spawned 시그널이 오지 않으므로 직접 알린다.
	var player := spawner.spawn({"peer_id": peer_id, "position": _next_spawn_position()}) as Player
	player_spawned.emit(player)


func _next_spawn_position() -> Vector3:
	var points := world.get_child(0).get_node_or_null("SpawnPoints")
	if points == null or points.get_child_count() == 0:
		return Vector3.ZERO
	var marker := points.get_child(players.get_child_count() % points.get_child_count()) as Node3D
	return marker.global_position


func _spawn_player(data: Variant) -> Node:
	var info: Dictionary = data
	var peer_id: int = info["peer_id"]
	var player := PLAYER_SCENE.instantiate() as Player
	player.name = str(peer_id)
	player.set_multiplayer_authority(peer_id)
	player.position = info["position"]
	player.use_device_input = use_device_input
	return player


func _on_spawned(node: Node) -> void:
	player_spawned.emit(node as Player)


func _on_peer_connected(peer_id: int) -> void:
	print("[세션] 참가: 피어 %d" % peer_id)
	_spawn_for(peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	print("[세션] 퇴장: 피어 %d" % peer_id)
	var player := get_player(peer_id)
	if player != null:
		player.queue_free()


func _on_connected_to_server() -> void:
	print("[세션] 호스트에 접속함 (내 피어 %d)" % multiplayer.get_unique_id())
	started.emit()


func _end(reason: String) -> void:
	# 연결이 끊긴 피어로는 더 이상 멀티플레이 함수를 부를 수 없으므로 바로 정리한다.
	# 복제 시스템이 이벤트를 처리하는 도중이므로, 정리는 이번 프레임 끝으로 미룬다.
	_finish.call_deferred(reason)


func _finish(reason: String) -> void:
	print("[세션] 종료: %s" % reason)
	leave()
	ended.emit(reason)
