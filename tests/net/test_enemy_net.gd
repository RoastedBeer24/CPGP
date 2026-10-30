extends NetTestCase
## 코옵에서의 적: 판단은 호스트가 하고, 경계 단계·쓰러짐·몸 옮기기가 모든 피어에 퍼진다.

const SENTRY_PATH := "World/TestRange/Stealth/Enemies/Sentry1"


func test_enemy_alert_is_synced_to_client() -> void:
	var sessions := await connect_peers(1)
	var on_host := sessions[0].get_node(SENTRY_PATH) as Enemy
	var on_client := sessions[1].get_node(SENTRY_PATH) as Enemy
	on_host.notify_alarm(on_host.global_position + Vector3(3, 0, 3))
	assert_true(await wait_until(func() -> bool: return on_client.alert == Enemy.Alert.SEARCHING), "클라이언트에도 수색 표시")


func test_client_takedown_is_judged_by_host() -> void:
	var sessions := await connect_peers(1)
	var host := sessions[0]
	var client := sessions[1]
	var on_host := host.get_node(SENTRY_PATH) as Enemy
	var on_client := client.get_node(SENTRY_PATH) as Enemy
	var mine := client.get_local_player()
	# 보초 뒤 1.2m에 서서 보초 쪽을 본다.
	var behind := on_client.global_position - on_client.forward() * 1.2
	mine.global_position = Vector3(behind.x, on_client.global_position.y, behind.z)
	mine.rotation.y = on_client.rotation.y
	assert_true(await wait_until(func() -> bool: return mine.interactor.focus_action == Interactor.Action.TAKEDOWN), "제압 안내가 뜬다")
	# 호스트 쪽에도 내 위치가 도착할 때까지 기다린다.
	var host_copy := host.get_player(client.multiplayer.get_unique_id())
	assert_true(await wait_until(func() -> bool: return host_copy.global_position.distance_to(mine.global_position) < 0.1))
	mine.interactor.interact()
	assert_true(await wait_until(func() -> bool: return on_host.condition == Enemy.Condition.KNOCKED_OUT), "호스트가 제압 판정")
	assert_true(await wait_until(func() -> bool: return on_client.condition == Enemy.Condition.KNOCKED_OUT), "클라이언트에도 쓰러짐")

	# 몸을 들면 호스트가 알려 주고, 몸이 플레이어를 따라온다.
	assert_true(await wait_until(func() -> bool: return mine.interactor.focus_action == Interactor.Action.PICK_UP))
	mine.interactor.interact()
	assert_true(await wait_until(func() -> bool: return mine.interactor.carrying == on_client), "클라이언트가 몸을 든다")
	assert_eq(on_host.carrier_peer, client.multiplayer.get_unique_id())
