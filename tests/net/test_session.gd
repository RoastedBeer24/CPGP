extends TestCase
## 세션과 LAN 코옵을 한 프로세스 안에서 검증한다.
## 피어마다 별도의 SubViewport(독립된 3D 월드와 물리 공간)와 MultiplayerAPI를 주고,
## 실제 ENet으로 127.0.0.1에 접속시킨다.

const SESSION_SCENE := preload("res://src/net/session.tscn")
const CONNECT_TIMEOUT_FRAMES := 180

var _branches: Array[SubViewport] = []
var _port := 0


func before_each() -> void:
	_port = 47900 + randi() % 2000


func after_each() -> void:
	for branch in _branches:
		var path := branch.get_path()
		(branch.get_node("Session") as Session).leave()
		branch.get_parent().remove_child(branch)
		branch.free()
		tree.set_multiplayer(null, path)
	_branches.clear()


func test_single_spawns_one_local_player() -> void:
	var session := _new_peer("Solo")
	assert_eq(session.start_single(), OK)
	await tree.process_frame
	assert_eq(session.players.get_child_count(), 1)
	var player := session.get_local_player()
	assert_not_null(player)
	assert_true(player.is_multiplayer_authority())
	assert_true(session.can_pause())


func test_client_joins_and_both_see_two_players() -> void:
	var host := _new_peer("Host")
	var client := _new_peer("Client")
	assert_eq(host.host(_port), OK)
	assert_eq(client.join("127.0.0.1", _port), OK)
	assert_true(await _wait_until(func() -> bool: return _player_counts([host, client]) == [2, 2]), "양쪽 모두 2명")
	assert_false(host.can_pause(), "코옵 중에는 일시정지 불가")


func test_client_movement_replicates_to_host() -> void:
	var host := _new_peer("Host")
	var client := _new_peer("Client")
	host.host(_port)
	client.join("127.0.0.1", _port)
	await _wait_until(func() -> bool: return _player_counts([host, client]) == [2, 2])

	var client_id := client.multiplayer.get_unique_id()
	var own := client.get_player(client_id)
	var mirror := host.get_player(client_id)
	assert_true(own.is_multiplayer_authority(), "클라이언트가 자기 플레이어를 조종")
	assert_false(mirror.is_multiplayer_authority(), "호스트 쪽 사본은 조종하지 않음")

	var start := mirror.global_position
	var intent := PlayerIntent.new()
	intent.move = Vector2(0, 1)
	own.intent_override = intent
	await _physics_frames(40)
	intent.move = Vector2.ZERO
	await _physics_frames(20)

	assert_true(own.global_position.distance_to(start) > 1.0, "클라이언트 쪽에서 움직여야 함")
	assert_true(mirror.global_position.distance_to(own.global_position) < 0.05, "호스트 쪽 사본이 따라와야 함")


func test_host_movement_and_look_replicate_to_client() -> void:
	var host := _new_peer("Host")
	var client := _new_peer("Client")
	host.host(_port)
	client.join("127.0.0.1", _port)
	await _wait_until(func() -> bool: return _player_counts([host, client]) == [2, 2])

	var own := host.get_player(1)
	var mirror := client.get_player(1)
	own.look(Vector2(0.5, 0.3))
	var intent := PlayerIntent.new()
	intent.move = Vector2(1, 0)
	intent.crouch_pressed = true
	own.intent_override = intent
	await _physics_frames(40)
	intent.move = Vector2.ZERO
	await _physics_frames(20)

	assert_true(mirror.global_position.distance_to(own.global_position) < 0.05, "위치")
	assert_almost_eq(mirror.rotation.y, own.rotation.y, 0.001, "좌우 시점")
	assert_almost_eq(mirror.head.rotation.x, own.head.rotation.x, 0.001, "상하 시점")
	assert_almost_eq(mirror.crouch_blend, 1.0, 0.01, "웅크린 자세")


func test_three_players_can_play_together() -> void:
	var host := _new_peer("Host")
	var first := _new_peer("ClientA")
	var second := _new_peer("ClientB")
	host.host(_port)
	first.join("127.0.0.1", _port)
	second.join("127.0.0.1", _port)
	var ok := await _wait_until(func() -> bool: return _player_counts([host, first, second]) == [3, 3, 3])
	assert_true(ok, "세 명 모두 3명을 봐야 함: %s" % [_player_counts([host, first, second])])

	var positions: Array[Vector3] = []
	for player: Node in host.players.get_children():
		positions.append((player as Player).global_position)
	assert_true(positions[0].distance_to(positions[1]) > 0.5 and positions[1].distance_to(positions[2]) > 0.5, "서로 다른 자리에서 시작")


func test_fourth_player_is_rejected() -> void:
	var host := _new_peer("Host")
	var clients: Array[Session] = [_new_peer("ClientA"), _new_peer("ClientB"), _new_peer("ClientC")]
	host.host(_port)
	for client in clients:
		client.join("127.0.0.1", _port)
	await _physics_frames(CONNECT_TIMEOUT_FRAMES)
	assert_eq(host.players.get_child_count(), Session.MAX_PLAYERS)


func test_client_leaving_removes_its_player() -> void:
	var host := _new_peer("Host")
	var client := _new_peer("Client")
	host.host(_port)
	client.join("127.0.0.1", _port)
	await _wait_until(func() -> bool: return _player_counts([host, client]) == [2, 2])
	client.leave()
	assert_true(await _wait_until(func() -> bool: return host.players.get_child_count() == 1), "나간 플레이어 제거")


func test_host_leaving_ends_client_session() -> void:
	var host := _new_peer("Host")
	var client := _new_peer("Client")
	host.host(_port)
	client.join("127.0.0.1", _port)
	await _wait_until(func() -> bool: return _player_counts([host, client]) == [2, 2])
	var reasons: Array[String] = []
	client.ended.connect(func(reason: String) -> void: reasons.append(reason))
	host.leave()
	assert_true(await _wait_until(func() -> bool: return not reasons.is_empty()), "클라이언트 세션이 끝나야 함")


func test_join_without_host_fails() -> void:
	var client := _new_peer("Client")
	var reasons: Array[String] = []
	client.ended.connect(func(reason: String) -> void: reasons.append(reason))
	client.join("127.0.0.1", _port)
	# ENet 연결 시도 제한 시간이 길어서, 여기서는 시작되지 않았는지만 확인한다.
	await _physics_frames(60)
	assert_eq(client.players.get_child_count(), 0)


func _new_peer(peer_name: String) -> Session:
	var branch := SubViewport.new()
	branch.name = peer_name
	branch.own_world_3d = true
	branch.size = Vector2i(64, 64)
	branch.render_target_update_mode = SubViewport.UPDATE_DISABLED
	tree.root.add_child(branch)
	tree.set_multiplayer(SceneMultiplayer.new(), branch.get_path())
	var session := SESSION_SCENE.instantiate() as Session
	session.use_device_input = false
	branch.add_child(session)
	_branches.append(branch)
	return session


func _player_counts(sessions: Array[Session]) -> Array[int]:
	var counts: Array[int] = []
	for session in sessions:
		counts.append(session.players.get_child_count())
	return counts


func _wait_until(condition: Callable) -> bool:
	for i in CONNECT_TIMEOUT_FRAMES:
		if condition.call():
			return true
		await tree.physics_frame
	return condition.call()


func _physics_frames(count: int) -> void:
	for i in count:
		await tree.physics_frame
