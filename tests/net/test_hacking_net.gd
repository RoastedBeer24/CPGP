extends NetTestCase
## 코옵에서의 해킹: 클라이언트가 올린 퀵핵도 호스트가 판정하고, 쓴 RAM과 결과(문이 열림)가 모든 피어에 퍼진다.

const DOOR_PATH := "World/TestRange/Stealth/VaultDoor"


func test_client_hack_is_judged_by_host() -> void:
	var sessions := await connect_peers(1)
	var host := sessions[0]
	var client := sessions[1]
	var door_on_host := host.get_node(DOOR_PATH) as HackDoor
	var door_on_client := client.get_node(DOOR_PATH) as HackDoor
	var mine := client.get_local_player()
	var intent := await _scan_door(host, client)
	var ram_before := mine.cyberdeck.ram
	intent.weapon_slot = 1
	assert_true(await wait_until(func() -> bool: return mine.cyberdeck.ram < ram_before - 0.5), "호스트가 RAM을 쓰고 그 값이 클라이언트에 퍼진다")
	assert_true(await wait_until(func() -> bool: return door_on_host.opened), "호스트가 판정해 문이 열린다")
	assert_true(await wait_until(func() -> bool: return door_on_client.opened), "클라이언트에도 문이 열린다")


func test_host_refuses_client_hack_without_ram() -> void:
	var sessions := await connect_peers(1)
	var host := sessions[0]
	var client := sessions[1]
	var door_on_host := host.get_node(DOOR_PATH) as HackDoor
	var host_copy := host.get_player(client.multiplayer.get_unique_id())
	var intent := await _scan_door(host, client)
	# RAM은 호스트 값이 진짜다. 클라이언트 화면의 값과 상관없이 호스트에서 모자라면 거절한다.
	host_copy.cyberdeck.ram = 0.0
	intent.weapon_slot = 1
	await physics_frames(30)
	assert_false(host_copy.cyberdeck.is_uploading(), "RAM이 없으면 올리지 않는다")
	assert_false(door_on_host.opened)


## 클라이언트 플레이어를 금고 문 앞 4m에 세우고 스캔으로 문을 고르게 한다. 그 플레이어의 입력을 돌려준다.
## 금고 바깥이 어느 쪽인지 정하지 않고, 문의 해킹 지점이 보이는 쪽에 선다.
func _scan_door(host: Session, client: Session) -> PlayerIntent:
	var door := client.get_node(DOOR_PATH) as HackDoor
	var mine := client.get_local_player()
	var intent := PlayerIntent.new()
	mine.intent_override = intent
	var point := (door.get_node("Hackable") as Node3D).global_position
	var space := mine.get_world_3d().direct_space_state
	var stand := Vector3.INF
	for side: float in [1.0, -1.0]:
		var spot := door.global_position + door.global_basis.z * 4.0 * side
		if Senses.has_line_of_sight(space, spot + Vector3.UP * 1.6, point - (point - spot).normalized() * 0.6):
			stand = spot
			break
	assert_ne(stand, Vector3.INF, "문의 해킹 지점이 보이는 자리가 있다")
	mine.global_position = Vector3(stand.x, door.global_position.y + 0.05, stand.z)
	var to_target := point - (mine.global_position + Vector3.UP * mine.config.stand_eye_height)
	mine.rotation.y = atan2(-to_target.x, -to_target.z)
	mine.head.rotation.x = atan2(to_target.y, Vector2(to_target.x, to_target.z).length())
	var host_copy := host.get_player(client.multiplayer.get_unique_id())
	assert_true(await wait_until(func() -> bool: return host_copy.global_position.distance_to(mine.global_position) < 0.1),
		"호스트에도 내 위치가 도착한다")
	intent.scan_held = true
	assert_true(await wait_until(func() -> bool: return mine.cyberdeck.focus != null and mine.cyberdeck.focus.target() == door),
		"스캔으로 문을 고른다")
	return intent
