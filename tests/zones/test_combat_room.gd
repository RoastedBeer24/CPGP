extends NetTestCase
## 전투 방: 웨이브가 차례로 나오고, 다 깨면 방 정리, 모두 쓰러지면 처음부터 다시 한다.


func test_waves_spawn_and_advance_until_cleared() -> void:
	var session := new_peer("Solo")
	session.waves_enabled = true
	session.start_single()
	var room := session.zone() as CombatRoom
	room.start_delay = 0.1
	room.between_delay = 0.1
	room.restart_delay = 100.0
	assert_true(await wait_until(func() -> bool: return room.phase == CombatRoom.Phase.FIGHTING), "첫 웨이브 시작")
	assert_eq(room.wave, 1)
	assert_eq(room.alive_enemies(), room.waves[0].size(), "웨이브의 적이 다 나온다")
	for wave in room.wave_count():
		assert_true(await wait_until(func() -> bool: return room.phase == CombatRoom.Phase.FIGHTING and room.alive_enemies() > 0), "웨이브 %d" % (wave + 1))
		_defeat_all(room)
		await physics_frames(3)
	assert_true(await wait_until(func() -> bool: return room.phase == CombatRoom.Phase.CLEARED), "마지막 웨이브를 깨면 방 정리")


func test_enemies_spawn_away_from_players() -> void:
	var session := new_peer("Solo")
	session.waves_enabled = true
	session.start_single()
	var room := session.zone() as CombatRoom
	room.start_delay = 0.1
	assert_true(await wait_until(func() -> bool: return room.alive_enemies() > 0))
	var player := session.get_local_player()
	for node: Node in room.enemies.get_children():
		var enemy := node as Enemy
		assert_true(enemy.global_position.distance_to(player.global_position) >= CombatRoom.SPAWN_CLEARANCE - 2.0, "플레이어 바로 옆에서 나오지 않는다")


func test_wipe_restarts_room() -> void:
	var session := new_peer("Solo")
	session.waves_enabled = true
	session.start_single()
	var room := session.zone() as CombatRoom
	room.start_delay = 0.1
	room.failed_delay = 0.2
	assert_true(await wait_until(func() -> bool: return room.phase == CombatRoom.Phase.FIGHTING))
	var player := session.get_local_player()
	player.health.apply_damage(DamageInfo.create(99999.0, 0, Vector3.ZERO, &"test"))
	assert_true(await wait_until(func() -> bool: return room.phase == CombatRoom.Phase.FAILED), "모두 쓰러지면 전멸")
	assert_true(await wait_until(func() -> bool: return room.phase == CombatRoom.Phase.WAITING or room.wave == 1 and room.phase == CombatRoom.Phase.FIGHTING), "다시 시작")
	assert_true(player.is_alive(), "다시 시작하면 일어난다")
	assert_eq(player.health.current, player.health.max_health)


func _defeat_all(room: CombatRoom) -> void:
	var hit := HitData.new()
	hit.damage = 1000.0
	for node: Node in room.enemies.get_children():
		var enemy := node as Enemy
		if enemy.is_alive():
			enemy.receive_hit(1, hit, 100.0, enemy.global_position + Vector3.FORWARD)
