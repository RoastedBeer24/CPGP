extends NetTestCase
## 작전(M3): 로비에서 시작해 방들을 차례로 깨고, 방마다 보상을 고르고, 마지막 보스를 잡으면 작전 완료.
## 모두 쓰러지면 작전 실패로 로비에 돌아간다. 로비에서는 캐릭터를 바꿀 수 있고, 작전 중에는 새로 들어올 수 없다.

const COMBAT_ROOM := "res://src/zones/combat_room/combat_room.tscn"


func test_session_starts_in_lobby() -> void:
	var session := _solo()
	assert_true(session.zone() is Lobby, "로비에서 시작한다")
	assert_eq(session.run.phase, Run.Phase.LOBBY)
	assert_true(session.get_local_player().global_position.distance_to(Vector3(0, 0, 6)) < 3.0, "로비 시작 자리")


func test_run_clears_rooms_with_rewards_until_victory() -> void:
	var session := _solo()
	session.waves_enabled = true
	var player := session.get_local_player()
	var previous := String(session.zone().name)
	session.run.start()
	var stages := session.run.stage_count()
	for stage in stages:
		# 방을 바꿀 때는 앞 방의 적을 치우고 조금 기다린 뒤 구역을 바꾼다. 새 구역이 될 때까지 기다린다.
		assert_true(await wait_until_long(func() -> bool:
			return session.run.phase == Run.Phase.ROOM and session.run.stage == stage and session.zone() is CombatRoom and String(session.zone().name) != previous),
			"%d번째 방에 들어간다" % (stage + 1))
		previous = String(session.zone().name)
		var room := session.zone() as CombatRoom
		room.start_delay = 0.05
		room.between_delay = 0.05
		while room.phase != CombatRoom.Phase.CLEARED:
			await physics_frames(2)
			_defeat_all(room)
		if stage < stages - 1:
			assert_true(await wait_until(func() -> bool: return session.run.phase == Run.Phase.REWARD), "방을 깨면 보상을 고른다")
			assert_true(session.run.choosing(player))
			var offers := session.run.offers_for(player)
			assert_eq(offers.size(), Run.OFFER_COUNT, "후보 셋")
			player.add_reward(offers[0].id)
	assert_true(await wait_until(func() -> bool: return session.run.phase == Run.Phase.VICTORY), "마지막 방(보스)을 깨면 작전 완료")
	assert_eq(player.rewards.size(), stages - 1, "방마다 보상 하나")


func test_wipe_fails_run_and_returns_to_lobby() -> void:
	var session := _solo()
	session.waves_enabled = true
	var player := session.get_local_player()
	session.run.start()
	assert_true(await wait_until_long(func() -> bool: return session.zone() is CombatRoom), "방에 들어간다")
	player.add_reward(&"sharp_edge")
	player.health.apply_damage(DamageInfo.create(99999.0, 0, Vector3.ZERO, &"test"))
	assert_true(await wait_until_long(func() -> bool: return session.run.phase == Run.Phase.DEFEAT), "모두 쓰러지면 작전 실패")
	assert_true(await wait_until_long(func() -> bool: return session.zone() is Lobby), "잠시 뒤 로비로 돌아간다")
	assert_true(await wait_until(func() -> bool: return player.is_alive() and player.rewards.is_empty()), "일어나고 보상은 사라진다")
	assert_true(session.accepting_players, "로비에서는 다시 참여를 받는다")


func test_rewards_raise_damage_and_health() -> void:
	var session := _solo()
	var player := session.get_local_player()
	assert_eq(player.bonus(&"attack"), 0.0)
	player.add_reward(&"sharp_edge")
	player.add_reward(&"sharp_edge")
	assert_almost_eq(player.bonus(&"attack"), 0.3, 0.001, "같은 보상은 쌓인다")
	player.health.apply_damage(DamageInfo.create(600.0, 0, Vector3.ZERO, &"test"))
	player.add_reward(&"exoskeleton")
	assert_almost_eq(player.health.max_health, player.kit.max_health * 1.25, 0.1, "최대 체력 +25%")
	assert_true(player.health.current > player.kit.max_health - 600.0 + player.kit.max_health * 0.25 - 1.0, "늘어난 만큼과 25%를 회복한다")


func test_character_can_be_changed_in_lobby() -> void:
	var session := _solo()
	var before := session.get_local_player()
	before.rotation.y = 1.2
	session.request_character(&"endministrator_m")
	await physics_frames(2)
	var after := session.get_local_player()
	assert_ne(after, before, "새 캐릭터로 다시 나타난다")
	assert_eq(after.character_id, &"endministrator_m")
	assert_eq(after.kit.id, &"endministrator_m")
	assert_almost_eq(after.rotation.y, 1.2, 0.01, "같은 방향을 본다(캐릭터 화면 카메라가 그대로 앞에 있게)")


func test_coop_character_change_and_no_joining_during_run() -> void:
	var sessions := await connect_peers(1)
	var host := sessions[0]
	var client := sessions[1]
	var client_id := client.multiplayer.get_unique_id()
	client.request_character(&"endministrator_m")
	assert_true(await wait_until(func() -> bool:
		var mirror := host.get_player(client_id)
		return mirror != null and mirror.character_id == &"endministrator_m"), "호스트에도 바뀐 캐릭터로 보인다")
	assert_true(await wait_until(func() -> bool:
		var mine := client.get_local_player()
		return mine != null and mine.character_id == &"endministrator_m"), "참여한 사람 화면에서도")
	host.run.start()
	assert_true(await wait_until_long(func() -> bool: return client.zone() is CombatRoom), "참여한 사람도 같은 방으로 간다")
	assert_eq(client.zone().name, host.zone().name, "구역 이름(경로)이 같다")
	var late := new_peer("Late")
	var reasons: Array[String] = []
	late.ended.connect(func(reason: String) -> void: reasons.append(reason))
	late.join("127.0.0.1", port)
	assert_true(await wait_until_long(func() -> bool: return not reasons.is_empty() or late.mode == Session.Mode.NONE), "작전 중에는 들어올 수 없다")
	assert_eq(host.players.get_child_count(), 2)


func test_boss_enrages_below_half_health() -> void:
	var session := _solo()
	session.zone_scene = load(COMBAT_ROOM)
	var room_session := new_peer("BossRoom")
	room_session.zone_scene = load(COMBAT_ROOM)
	room_session.start_single()
	var room := room_session.zone() as CombatRoom
	var boss := room.spawn_enemy("raider_chief", Vector3(0, 0, -15))
	boss.ai_enabled = false
	await physics_frames(2)
	var attack := boss.data.attacks[0]
	assert_almost_eq(boss.wind_up_time(attack), attack.wind_up, 0.001)
	boss.health.apply_damage(DamageInfo.create(boss.health.max_health * 0.55, 1, Vector3.ZERO, &"test"))
	await physics_frames(2)
	assert_true(boss.enraged, "체력이 절반 아래로 떨어지면 격노")
	assert_almost_eq(boss.wind_up_time(attack), attack.wind_up * Enemy.ENRAGED_WIND_UP, 0.001, "예고가 짧아진다")


func _solo() -> Session:
	var session := new_peer("Solo")
	session.start_single()
	return session


func _defeat_all(room: CombatRoom) -> void:
	var hit := HitData.new()
	hit.damage = 100000.0
	for node: Node in room.enemies.get_children():
		var enemy := node as Enemy
		if enemy != null and enemy.is_alive():
			enemy.receive_hit(1, hit, 1.0, enemy.global_position + Vector3.FORWARD)


## 구역을 바꾸고 웨이브를 기다리는 일은 더 오래 기다린다.
func wait_until_long(condition: Callable) -> bool:
	for i in 900:
		if condition.call():
			return true
		await tree.physics_frame
	return condition.call()
