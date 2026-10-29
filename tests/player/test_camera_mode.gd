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
