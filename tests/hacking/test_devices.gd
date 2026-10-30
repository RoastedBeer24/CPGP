extends TestCase
## 해킹 장치: 감시 카메라(경보, 차단, 파괴), 잠긴 문(해킹으로 열기), 포탑(공격, 장악).
## 플레이어는 원점에서 -Z를 본다.

const PLAYER_SCENE := preload("res://src/player/player.tscn")
const ENEMY_SCENE := preload("res://src/enemies/enemy.tscn")

var player: Player
var intent: PlayerIntent


func before_each() -> void:
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(80, 1, 80)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position.y = -0.5
	add_child_autofree(floor_body)
	player = PLAYER_SCENE.instantiate()
	player.use_device_input = false
	intent = PlayerIntent.new()
	player.intent_override = intent
	add_child_autofree(player)
	await _frames(2)


func test_camera_spots_player_and_calls_guards() -> void:
	var camera := _spawn_camera(Vector3(0, 3, -8), PI)
	var guard := await _spawn_enemy(Vector3(6, 0, -14), 0.0)
	for i in 200:
		await _frames(1)
		if camera.state == SecurityCamera.State.ALARM:
			break
	assert_eq(camera.state, SecurityCamera.State.ALARM)
	# 부름을 받은 경비는 수색하러 온다(오다가 플레이어를 보면 전투로 넘어간다).
	assert_true(guard.alert >= Enemy.Alert.SEARCHING, "근처 경비가 수색하러 온다: %s" % guard.alert)


func test_camera_shutdown_by_quickhack() -> void:
	var camera := _spawn_camera(Vector3(0, 2, -8), PI)
	player.head.rotation.x = atan2(2.0 - 1.6, 8.0)
	intent.scan_held = true
	await _frames(2)
	assert_eq(player.cyberdeck.focus, camera.get_node("Hackable"))
	intent.weapon_slot = 1
	await _frames(2)
	intent.scan_held = false
	await _frames(60)
	assert_eq(camera.state, SecurityCamera.State.DISABLED)
	await _frames(120)
	assert_almost_eq(camera.detection, 0.0, 0.001, "꺼진 동안은 보지 못한다")


func test_shooting_camera_destroys_it() -> void:
	var camera := _spawn_camera(Vector3(0, 2, -8), 0.0)
	player.head.rotation.x = atan2(1.95 - 1.6, 8.0)
	intent.fire_pressed = true
	for i in 6:
		intent.fire_pressed = true
		await _frames(20)
	assert_eq(camera.state, SecurityCamera.State.DESTROYED)
	assert_false(camera.is_hackable())


func test_door_opens_by_hack_and_lets_player_through() -> void:
	var door := HackDoor.new()
	door.position = Vector3(0, 0, -4)
	add_child_autofree(door)
	await _frames(2)
	intent.scan_held = true
	await _frames(2)
	assert_eq(player.cyberdeck.focus, door.get_node("Hackable"))
	intent.weapon_slot = 1
	await _frames(2)
	intent.scan_held = false
	await _frames(100)
	assert_true(door.opened)
	intent.move = Vector2(0, 1)
	await _frames(120)
	assert_true(player.global_position.z < -5.0, "열린 문을 지나간다: %s" % player.global_position)


func test_locked_door_blocks_player() -> void:
	var door := HackDoor.new()
	door.position = Vector3(0, 0, -4)
	add_child_autofree(door)
	await _frames(2)
	intent.move = Vector2(0, 1)
	await _frames(120)
	assert_true(player.global_position.z > -3.9, "잠긴 문은 막는다: %s" % player.global_position)


func test_turret_shoots_player_in_view() -> void:
	var turret := Turret.new()
	turret.position = Vector3(0, 0, -10)
	turret.rotation.y = PI
	add_child_autofree(turret)
	await _frames(150)
	assert_true(player.health.current < player.health.max_health, "포탑에 맞는다")


func test_turret_takeover_shoots_enemies_not_player() -> void:
	var turret := Turret.new()
	turret.position = Vector3(0, 0, -6)
	add_child_autofree(turret)
	var enemy := await _spawn_enemy(Vector3(0, 0, -16), 0.0)
	turret.apply_quickhack(load("res://data/hacking/turret_takeover.tres") as QuickhackData, player)
	assert_true(turret.is_friendly())
	# 장악한 포탑은 플레이어 쪽으로 돌아도 플레이어를 겨누지 않는다.
	turret.rotation.y = PI
	await _frames(5)
	assert_eq(turret._pick_target(), Vector3.INF, "보이는 적이 없으면 아무도 겨누지 않는다(플레이어 제외)")
	turret.rotation.y = 0.0
	await _frames(180)
	assert_true(enemy.health.current < enemy.data.max_health, "장악한 포탑이 적을 쏜다")


func _spawn_camera(position: Vector3, yaw: float) -> SecurityCamera:
	var camera := SecurityCamera.new()
	camera.position = position
	camera.rotation.y = yaw
	camera.sweep_degrees = 0.0
	add_child_autofree(camera)
	return camera


func _spawn_enemy(position: Vector3, yaw: float) -> Enemy:
	var enemy := ENEMY_SCENE.instantiate() as Enemy
	enemy.data = (load("res://data/enemies/guard.tres") as EnemyData).duplicate() as EnemyData
	enemy.position = position
	enemy.rotation.y = yaw
	add_child_autofree(enemy)
	await _frames(2)
	return enemy


func _frames(count: int) -> void:
	for i in count:
		await tree.physics_frame
