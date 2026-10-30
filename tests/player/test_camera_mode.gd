extends TestCase
## 1인칭·3인칭 전환: 카메라 위치, 몸과 1인칭 무기 모델의 표시, 벽 충돌, 3인칭 조준을 확인한다.
## 플레이어는 원점에서 -Z를 보고 서 있다.

const PLAYER_SCENE := preload("res://src/player/player.tscn")
const DUMMY_SCENE := preload("res://src/enemies/training_dummy.tscn")

var player: Player
var intent: PlayerIntent


func before_each() -> void:
	add_child_autofree(_box(Vector3(80, 1, 80), Vector3(0, -0.5, 0)))
	player = PLAYER_SCENE.instantiate()
	player.use_device_input = false
	intent = PlayerIntent.new()
	player.intent_override = intent
	add_child_autofree(player)
	await _frames(2)


func test_starts_in_first_person() -> void:
	assert_false(player.third_person)
	assert_almost_eq(player.camera.global_position.distance_to(player.head.global_position), 0.0, 0.01, "카메라가 눈에 있음")
	assert_true(player.weapons.viewmodel.visible, "1인칭 무기 모델이 보임")
	assert_eq(player.body.view_mode, PlayerBody.ViewMode.SHADOW_ONLY, "내 몸은 그림자만")


func test_third_person_moves_camera_behind_shoulder() -> void:
	player.set_third_person(true)
	await _frames(90)
	var offset := player.camera.global_position - player.head.global_position
	assert_almost_eq(offset.z, player.config.third_person_distance, 0.05, "뒤로 물러남")
	assert_almost_eq(offset.x, player.config.third_person_shoulder.x, 0.05, "오른쪽 어깨 너머")
	assert_false(player.weapons.viewmodel.visible, "1인칭 무기 모델은 숨김")
	assert_eq(player.body.view_mode, PlayerBody.ViewMode.VISIBLE, "내 몸이 보임")


func test_switching_back_returns_camera_to_eyes() -> void:
	player.set_third_person(true)
	await _frames(90)
	player.set_third_person(false)
	await _frames(90)
	assert_almost_eq(player.camera.global_position.distance_to(player.head.global_position), 0.0, 0.01)
	assert_true(player.weapons.viewmodel.visible)
	assert_eq(player.body.view_mode, PlayerBody.ViewMode.SHADOW_ONLY)


func test_mode_change_is_signalled_once() -> void:
	var changes: Array[bool] = []
	player.camera_mode_changed.connect(func(third: bool) -> void: changes.append(third))
	player.set_third_person(true)
	player.set_third_person(true)
	player.set_third_person(false)
	assert_eq(changes, [true, false] as Array[bool])


func test_camera_stops_in_front_of_wall_behind_player() -> void:
	add_child_autofree(_box(Vector3(6, 4, 0.4), Vector3(0, 2, 1.2)))
	player.set_third_person(true)
	await _frames(90)
	assert_true(player.camera.global_position.z < 1.0, "벽(앞면 z=1.0)을 뚫지 않음: %s" % player.camera.global_position.z)


func test_third_person_aim_hits_crosshair_point() -> void:
	add_child_autofree(_box(Vector3(20, 10, 0.4), Vector3(0, 2, -10)))
	player.set_third_person(true)
	await _frames(90)
	var space := player.get_world_3d().direct_space_state
	var crosshair := CombatQuery.trace(space, player.camera.global_position, -player.camera.global_basis.z, 100.0, WeaponHolder.TEAM)
	var shot := CombatQuery.trace(space, player.aim_origin(), player.aim_direction(), 100.0, WeaponHolder.TEAM)
	assert_not_null(shot)
	assert_almost_eq(shot.position.distance_to(crosshair.position), 0.0, 0.05, "눈에서 쏜 탄이 조준점에 맞음")


func test_first_person_aim_is_camera_forward() -> void:
	player.head.rotation.x = 0.3
	await _frames(1)
	assert_true(player.aim_direction().is_equal_approx(-player.camera.global_basis.z))
	assert_true(player.aim_origin().is_equal_approx(player.camera.global_position))


func test_third_person_shot_damages_target_on_crosshair() -> void:
	var dummy := DUMMY_SCENE.instantiate() as TrainingDummy
	dummy.respawn_delay = 100.0
	add_child_autofree(dummy)
	player.set_third_person(true)
	await _frames(90)
	# 어깨 너머 조준점이 가리키는 곳에 허수아비를 세운다. 눈에서 똑바로 쏘면 빗나가는 위치다.
	dummy.global_position = Vector3(player.config.third_person_shoulder.x, 0, -8)
	player.head.rotation.x = atan2(1.1 - player.camera.global_position.y, 8.0 + player.camera.global_position.z)
	await _frames(2)
	intent.fire_pressed = true
	intent.fire_held = true
	await _frames(1)
	intent.fire_held = false
	await _frames(5)
	assert_true(dummy.health.current < 100.0, "조준점의 허수아비가 맞음")


func test_free_look_orbits_camera_without_turning_player() -> void:
	var yaw := player.rotation.y
	var pitch := player.head.rotation.x
	player.set_free_look(true)
	player.orbit(Vector2(PI * 0.5, 0.0))
	await _frames(90)
	assert_almost_eq(player.rotation.y, yaw, 0.0001, "몸 방향은 그대로")
	assert_almost_eq(player.head.rotation.x, pitch, 0.0001, "조준 높이도 그대로")
	var offset := player.camera.global_position - player.head.global_position
	assert_true(offset.length() > 1.5, "1인칭에서도 카메라가 몸 밖으로 나간다: %s" % offset)
	assert_true(absf(offset.x) > absf(offset.z), "옆으로 돌아간다: %s" % offset)
	assert_eq(player.body.view_mode, PlayerBody.ViewMode.VISIBLE, "둘러보는 동안 내 몸이 보임")
	assert_false(player.weapons.viewmodel.visible)


func test_free_look_release_returns_to_first_person() -> void:
	player.set_free_look(true)
	player.orbit(Vector2(1.0, 0.3))
	await _frames(60)
	player.set_free_look(false)
	await _frames(90)
	assert_almost_eq(player.camera.global_position.distance_to(player.head.global_position), 0.0, 0.02)
	assert_eq(player.body.view_mode, PlayerBody.ViewMode.SHADOW_ONLY)


func test_free_look_zoom_changes_distance_within_limits() -> void:
	player.set_free_look(true)
	await _frames(90)
	var start := player.camera.global_position.distance_to(player.head.global_position)
	player.zoom(3)
	await _frames(30)
	var farther := player.camera.global_position.distance_to(player.head.global_position)
	assert_true(farther > start + 0.8, "멀어진다: %s → %s" % [start, farther])
	for i in 40:
		player.zoom(-1)
	assert_almost_eq(player.camera_distance, Player.MIN_CAMERA_DISTANCE, 0.001, "가장 가까운 거리에서 멈춘다")


func test_can_fire_during_free_look_toward_character_facing() -> void:
	player.set_free_look(true)
	player.orbit(Vector2(PI * 0.7, 0.4))
	await _frames(30)
	var ammo := player.weapons.ammo_in_magazine()
	intent.fire_pressed = true
	await _frames(3)
	assert_eq(player.weapons.ammo_in_magazine(), ammo - 1, "둘러보는 중에도 쏜다")
	assert_true(player.aim_direction().is_equal_approx(-player.head.global_basis.z), "카메라가 아니라 캐릭터가 보는 쪽으로")


func test_free_look_orbits_all_the_way_around_and_far() -> void:
	player.set_free_look(true)
	player.orbit(Vector2(PI, 0.3))  # 반 바퀴 돌아 캐릭터 정면을 조금 위에서 본다
	for i in 12:
		player.zoom(1)
	await _frames(120)
	var offset := player.camera.global_position - player.head.global_position
	assert_true(offset.z < -1.0, "앞쪽(캐릭터 정면)으로 돌아간다: %s" % offset)
	assert_true(player.camera_distance > 15.0, "멀리까지 뺄 수 있다: %s" % player.camera_distance)
	player.orbit(Vector2(0.0, -3.0))
	assert_almost_eq(player._free_pitch, Player.FREE_LOOK_PITCH_LIMIT, 0.001, "위아래로 거의 수직까지 돌릴 수 있다")
	for i in 40:
		player.zoom(-1)
	assert_almost_eq(player.camera_distance, Player.MIN_CAMERA_DISTANCE, 0.001)

func _box(size: Vector3, center: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.position = center
	return body


func _frames(count: int) -> void:
	for i in count:
		await tree.physics_frame
