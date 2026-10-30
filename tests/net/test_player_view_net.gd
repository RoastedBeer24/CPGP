extends NetTestCase
## 코옵에서의 시점과 몸: 시점 전환은 내 화면에만 적용되고, 든 무기는 다른 사람에게도 보인다.


func test_camera_mode_is_local_only() -> void:
	var sessions := await connect_peers(1)
	var host := sessions[0]
	var client := sessions[1]
	var client_id := client.multiplayer.get_unique_id()
	var mine := client.get_local_player()
	mine.set_third_person(true)
	await physics_frames(10)
	var on_host := host.get_player(client_id)
	assert_false(on_host.third_person, "다른 피어의 사본은 시점을 따라가지 않음")
	assert_eq(on_host.body.view_mode, PlayerBody.ViewMode.VISIBLE, "다른 사람 눈에는 몸이 보임")
	assert_false(on_host.weapons.viewmodel.visible, "다른 사람의 1인칭 무기 모델은 안 보임")
	var host_player := host.get_local_player()
	assert_eq(host_player.body.view_mode, PlayerBody.ViewMode.SHADOW_ONLY, "호스트 자신은 1인칭 그대로")


func test_weapon_switch_is_visible_to_others() -> void:
	var sessions := await connect_peers(1)
	var host := sessions[0]
	var client := sessions[1]
	var client_id := client.multiplayer.get_unique_id()
	var intent := PlayerIntent.new()
	intent.weapon_slot = 2
	client.get_local_player().intent_override = intent
	var on_host := host.get_player(client_id)
	assert_true(await wait_until(func() -> bool: return on_host.weapons.current_index == 1), "호스트에서도 산탄총을 든 것으로 보임")


func test_visor_is_visible_to_others() -> void:
	var sessions := await connect_peers(1)
	var host := sessions[0]
	var client := sessions[1]
	var client_id := client.multiplayer.get_unique_id()
	var intent := PlayerIntent.new()
	client.get_local_player().intent_override = intent
	var on_host := host.get_player(client_id)
	assert_true(on_host.visor_on)
	intent.visor_pressed = true
	assert_true(await wait_until(func() -> bool: return not on_host.visor_on), "바이저를 벗은 것이 호스트에도 보인다")


func test_melee_swing_is_visible_to_others() -> void:
	var sessions := await connect_peers(1)
	var host := sessions[0]
	var client := sessions[1]
	var client_id := client.multiplayer.get_unique_id()
	var intent := PlayerIntent.new()
	intent.weapon_slot = 3
	client.get_local_player().intent_override = intent
	var on_host := host.get_player(client_id)
	assert_true(await wait_until(func() -> bool: return on_host.weapons.current_index == 2), "칼을 든 것으로 보임")
	await physics_frames(20)  # 무기를 바꾼 뒤 0.25초는 공격하지 못한다
	intent.fire_pressed = true
	assert_true(await wait_until(func() -> bool: return on_host.melee_count == 1), "휘두른 횟수가 호스트에도 전해진다")
	if on_host.body.animated:
		assert_true(await wait_until(func() -> bool: return on_host.body.dominant_animation() == &"melee"), "호스트 화면에서도 휘두른다")
