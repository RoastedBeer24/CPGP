extends NetTestCase
## 세션과 LAN 코옵을 한 프로세스 안에서 검증한다.

func test_single_spawns_one_local_player() -> void:
	var session := new_peer("Solo")
	assert_eq(session.start_single(), OK)
	await tree.process_frame
	assert_eq(session.players.get_child_count(), 1)
	var player := session.get_local_player()
	assert_not_null(player)
	assert_true(player.is_multiplayer_authority())
	assert_true(session.can_pause())


func test_client_joins_and_both_see_two_players() -> void:
	var host := new_peer("Host")
	var client := new_peer("Client")
	assert_eq(host.host(port), OK)
	assert_eq(client.join("127.0.0.1", port), OK)
	assert_true(await wait_until(func() -> bool: return player_counts([host, client]) == [2, 2]), "양쪽 모두 2명")
	assert_false(host.can_pause(), "코옵 중에는 일시정지 불가")


func test_client_movement_replicates_to_host() -> void:
	var host := new_peer("Host")
	var client := new_peer("Client")
	host.host(port)
	client.join("127.0.0.1", port)
	await wait_until(func() -> bool: return player_counts([host, client]) == [2, 2])

	var client_id := client.multiplayer.get_unique_id()
	var own := client.get_player(client_id)
	var mirror := host.get_player(client_id)
	assert_true(own.is_multiplayer_authority(), "클라이언트가 자기 플레이어를 조종")
	assert_false(mirror.is_multiplayer_authority(), "호스트 쪽 사본은 조종하지 않음")

	var start := mirror.global_position
	var intent := PlayerIntent.new()
	intent.move = Vector2(0, 1)
	own.intent_override = intent
	await physics_frames(40)
	intent.move = Vector2.ZERO
	await physics_frames(20)

	assert_true(own.global_position.distance_to(start) > 1.0, "클라이언트 쪽에서 움직여야 함")
	assert_true(mirror.global_position.distance_to(own.global_position) < 0.05, "호스트 쪽 사본이 따라와야 함")


func test_host_movement_and_look_replicate_to_client() -> void:
	var host := new_peer("Host")
	var client := new_peer("Client")
	host.host(port)
	client.join("127.0.0.1", port)
	await wait_until(func() -> bool: return player_counts([host, client]) == [2, 2])

	var own := host.get_player(1)
	var mirror := client.get_player(1)
	var intent := PlayerIntent.new()
	intent.move = Vector2(1, 0)
	own.intent_override = intent
	await physics_frames(40)
	intent.move = Vector2.ZERO
	await physics_frames(20)

	# 테스트는 실제 시간보다 빠르게 프레임을 돌리므로, 프레임 수가 아니라 값이 맞을 때까지 기다린다.
	assert_true(await wait_until(func() -> bool: return mirror.global_position.distance_to(own.global_position) < 0.05), "위치")
	assert_almost_eq(mirror.rotation.y, own.rotation.y, 0.001, "몸이 보는 방향")


func test_first_person_and_weapon_replicate_to_client() -> void:
	# 1인칭(시선 쪽을 보며 옆·뒤로 감)인지와 고른 무기가 다른 피어에도 가야 그 몸이 다리를 돌리고 같은 무기를 든다.
	var host := new_peer("Host")
	var client := new_peer("Client")
	host.host(port)
	client.join("127.0.0.1", port)
	await wait_until(func() -> bool: return player_counts([host, client]) == [2, 2])
	var own := host.get_player(1)
	var mirror := client.get_player(1)
	var other: WeaponData = null
	for weapon in Weapons.of_type(Characters.find(own.character_id).weapon_type):
		if weapon.id != own.weapon().id:
			other = weapon
	own.set_camera_mode(Player.CameraMode.FIRST_PERSON, false)
	assert_true(own.set_weapon(other.id), "같은 무기군의 다른 무기")
	assert_true(await wait_until(func() -> bool: return mirror.strafing), "1인칭인지")
	assert_true(await wait_until(func() -> bool: return mirror.weapon().id == other.id), "고른 무기")
	GameSettings.reset_to_defaults()


func test_three_players_can_play_together() -> void:
	var host := new_peer("Host")
	var first := new_peer("ClientA")
	var second := new_peer("ClientB")
	host.host(port)
	first.join("127.0.0.1", port)
	second.join("127.0.0.1", port)
	var ok := await wait_until(func() -> bool: return player_counts([host, first, second]) == [3, 3, 3])
	assert_true(ok, "세 명 모두 3명을 봐야 함: %s" % [player_counts([host, first, second])])

	var positions: Array[Vector3] = []
	for player: Node in host.players.get_children():
		positions.append((player as Player).global_position)
	assert_true(positions[0].distance_to(positions[1]) > 0.5 and positions[1].distance_to(positions[2]) > 0.5, "서로 다른 자리에서 시작")


func test_fourth_player_is_rejected() -> void:
	var host := new_peer("Host")
	var clients: Array[Session] = [new_peer("ClientA"), new_peer("ClientB"), new_peer("ClientC")]
	host.host(port)
	for client in clients:
		client.join("127.0.0.1", port)
	await physics_frames(CONNECT_TIMEOUT_FRAMES)
	assert_eq(host.players.get_child_count(), Session.MAX_PLAYERS)


func test_client_leaving_removes_its_player() -> void:
	var host := new_peer("Host")
	var client := new_peer("Client")
	host.host(port)
	client.join("127.0.0.1", port)
	await wait_until(func() -> bool: return player_counts([host, client]) == [2, 2])
	client.leave()
	assert_true(await wait_until(func() -> bool: return host.players.get_child_count() == 1), "나간 플레이어 제거")


func test_host_leaving_ends_client_session() -> void:
	var host := new_peer("Host")
	var client := new_peer("Client")
	host.host(port)
	client.join("127.0.0.1", port)
	await wait_until(func() -> bool: return player_counts([host, client]) == [2, 2])
	var reasons: Array[String] = []
	client.ended.connect(func(reason: String) -> void: reasons.append(reason))
	host.leave()
	assert_true(await wait_until(func() -> bool: return not reasons.is_empty()), "클라이언트 세션이 끝나야 함")


func test_join_without_host_fails() -> void:
	var client := new_peer("Client")
	var reasons: Array[String] = []
	client.ended.connect(func(reason: String) -> void: reasons.append(reason))
	client.join("127.0.0.1", port)
	# ENet 연결 시도 제한 시간이 길어서, 여기서는 시작되지 않았는지만 확인한다.
	await physics_frames(60)
	assert_eq(client.players.get_child_count(), 0)


func test_each_peer_plays_the_character_it_chose() -> void:
	var host := new_peer("Host")
	var client := new_peer("Client")
	host.character_id = &"endministrator_f"
	client.character_id = &"endministrator_m"
	host.host(port)
	client.join("127.0.0.1", port)
	assert_true(await wait_until(func() -> bool: return player_counts([host, client]) == [2, 2]), "둘 다 들어옴")
	var client_id := client.multiplayer.get_unique_id()
	for session: Session in [host, client]:
		assert_eq(session.get_player(1).character_id, &"endministrator_f", "호스트는 관리자(여)")
		assert_eq(session.get_player(client_id).character_id, &"endministrator_m", "참여한 사람은 관리자(남)")
	assert_eq(host.get_player(client_id).kit.id, &"endministrator_m", "전투 구성도 고른 캐릭터")


func test_unknown_character_falls_back_to_default() -> void:
	var session := new_peer("Solo")
	session.character_id = &"no_such_character"
	session.start_single()
	await tree.process_frame
	assert_eq(session.get_local_player().character_id, Characters.DEFAULT_ID)
