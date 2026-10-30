extends NetTestCase
## 코옵 전투: 판정은 호스트가 한다. 참여한 사람의 공격이 호스트의 적을 맞히고, 결과가 모두에게 퍼진다.
## 적의 공격도 호스트가 판정해 참여한 사람의 체력이 준다. 쓰러진 동료를 일으킨다.


func test_client_attack_damages_enemy_judged_by_host() -> void:
	var sessions := await _connect_in_room()
	var host := sessions[0]
	var client := sessions[1]
	var client_id := client.multiplayer.get_unique_id()
	var mine := client.get_player(client_id)
	var room := host.zone() as CombatRoom
	var enemy := room.spawn_enemy("grunt", mine.global_position + Vector3(0, 0, -2.0))
	enemy.ai_enabled = false
	assert_true(await wait_until(func() -> bool: return (client.zone() as CombatRoom).enemies.get_child_count() == 1), "적이 참여한 사람에게도 보인다")
	var mirror := (client.zone() as CombatRoom).enemies.get_child(0) as Enemy
	var numbers: Array[float] = []
	mine.hit_confirmed.connect(func(_at: Vector3, amount: float, _flags: int) -> void: numbers.append(amount))
	var intent := PlayerIntent.new()
	mine.intent_override = intent
	intent.attack_pressed = true
	assert_true(await wait_until(func() -> bool: return enemy.health.current < enemy.data.max_health), "호스트의 적이 다친다")
	assert_true(await wait_until(func() -> bool: return mirror.health.current == enemy.health.current), "체력이 참여한 사람에게도 퍼진다")
	assert_true(await wait_until(func() -> bool: return not numbers.is_empty()), "때린 사람에게 피해 숫자가 돌아온다")
	assert_true(await wait_until(func() -> bool: return mine.energy > 0.0), "때린 사람의 궁극기 에너지가 찬다")


func test_enemy_attack_on_client_is_judged_by_host() -> void:
	var sessions := await _connect_in_room()
	var host := sessions[0]
	var client := sessions[1]
	var client_id := client.multiplayer.get_unique_id()
	var mine := client.get_player(client_id)
	# 호스트는 멀리 보내 두고, 참여한 사람 옆에 적을 둔다.
	host.get_player(1).global_position += Vector3(15, 0, 0)
	var room := host.zone() as CombatRoom
	room.spawn_enemy("grunt", mine.global_position + Vector3(0, 0, -2.0))
	var hits: Array[bool] = []
	mine.got_hit.connect(func(heavy: bool) -> void: hits.append(heavy))
	assert_true(await wait_until_long(func() -> bool: return mine.health.current < mine.health.max_health), "참여한 사람이 맞는다")
	assert_true(await wait_until(func() -> bool: return not hits.is_empty()), "맞은 것을 알린다")


func test_downed_teammate_can_be_revived() -> void:
	var sessions := await connect_peers(1)
	var host := sessions[0]
	var client := sessions[1]
	var client_id := client.multiplayer.get_unique_id()
	var downed := host.get_player(client_id)
	downed.health.apply_damage(DamageInfo.create(99999.0, 0, Vector3.ZERO, &"test"))
	var mine := client.get_player(client_id)
	assert_true(await wait_until(func() -> bool: return mine.state == Player.State.DOWN), "쓰러진다")
	var helper := host.get_player(1)
	helper.global_position = downed.global_position + Vector3(1.0, 0, 0)
	var intent := PlayerIntent.new()
	intent.interact_held = true
	helper.intent_override = intent
	assert_true(await wait_until_long(func() -> bool: return mine.is_alive()), "F를 누르고 있으면 일어난다")
	assert_almost_eq(downed.health.current, downed.health.max_health * Player.REVIVE_HEALTH, 1.0)
	assert_true(await wait_until(func() -> bool: return mine.state != Player.State.DOWN), "다시 움직인다")


## 호스트와 참여자를 이은 뒤 전투 방으로 옮긴다(판은 로비에서 시작한다).
func _connect_in_room() -> Array[Session]:
	var sessions := await connect_peers(1)
	sessions[0].change_zone("res://src/zones/combat_room/combat_room.tscn")
	await wait_until(func() -> bool: return sessions[1].zone() is CombatRoom and sessions[0].zone() is CombatRoom)
	await physics_frames(5)
	return sessions


## 오래 걸리는 일(적이 다가와 예고하고 때리기, 일으키기)은 더 오래 기다린다.
func wait_until_long(condition: Callable) -> bool:
	for i in 600:
		if condition.call():
			return true
		await tree.physics_frame
	return condition.call()
