extends NetTestCase
## 코옵 전투: 참여자가 쏜 공격을 호스트가 판정하고, 결과가 모두에게 퍼지는지 확인한다.

const DUMMY_PATH := "World/TestRange/ShootingRange/Dummy1"


func test_client_shot_is_judged_by_host_and_synced() -> void:
	var sessions := await connect_peers(1)
	var host := sessions[0]
	var client := sessions[1]
	var shooter := client.get_local_player()
	var host_dummy := host.get_node(DUMMY_PATH) as TrainingDummy
	var client_dummy := client.get_node(DUMMY_PATH) as TrainingDummy

	var confirmations: Array[float] = []
	shooter.weapons.hit_confirmed.connect(
		func(_p: Vector3, amount: float, _h: bool, _k: bool) -> void: confirmations.append(amount)
	)
	_aim(shooter, host_dummy.global_position + Vector3.UP * 0.9)
	await physics_frames(2)
	var intent := PlayerIntent.new()
	intent.fire_pressed = true
	shooter.intent_override = intent

	assert_true(await wait_until(func() -> bool: return host_dummy.health.current < 100.0), "호스트에서 피해 판정")
	assert_true(await wait_until(func() -> bool: return client_dummy.health.current == host_dummy.health.current), "클라이언트에 체력 동기화")
	assert_true(await wait_until(func() -> bool: return not confirmations.is_empty()), "쏜 사람에게 명중 확인")


func test_players_cannot_hurt_each_other() -> void:
	var sessions := await connect_peers(1)
	var host := sessions[0]
	var client := sessions[1]
	var shooter := client.get_local_player()
	var host_player := host.get_local_player()
	_aim(shooter, host_player.global_position + Vector3.UP * 1.2)
	await physics_frames(2)
	var intent := PlayerIntent.new()
	intent.fire_pressed = true
	shooter.intent_override = intent
	await physics_frames(30)
	assert_eq(host_player.health.current, host_player.health.max_health, "같은 편 공격은 피해 없음")


func test_dead_client_player_respawns_on_every_peer() -> void:
	var sessions := await connect_peers(1)
	var host := sessions[0]
	var client := sessions[1]
	var client_id := client.multiplayer.get_unique_id()
	var on_host := host.get_player(client_id)
	var on_client := client.get_player(client_id)
	on_host.health.apply_damage(DamageInfo.create(1000.0, 0, Vector3.ZERO, &"test", false))
	assert_true(await wait_until(func() -> bool: return not on_client.health.is_alive()), "클라이언트도 사망을 알아야 함")
	await physics_frames(ceili(Session.RESPAWN_DELAY * 60.0) + 5)
	assert_true(await wait_until(func() -> bool: return on_client.health.is_alive()), "클라이언트에서도 부활")


## 플레이어가 target을 바라보도록 몸과 고개를 돌린다.
func _aim(player: Player, target: Vector3) -> void:
	var eye := player.camera.global_position
	var flat := Vector3(target.x - eye.x, 0.0, target.z - eye.z)
	player.rotation.y = atan2(-flat.x, -flat.z)
	player.head.rotation.x = atan2(target.y - eye.y, flat.length())
