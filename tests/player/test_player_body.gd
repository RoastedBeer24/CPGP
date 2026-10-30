extends TestCase
## 플레이어 몸: 모델이 없을 때의 캡슐 몸, 코드로 만든 자세(웅크리기, 걷기, 총 겨누기)를 확인한다.
## 캐릭터 모델은 저장소에 없으므로, 모델이 필요한 검사는 모델 파일이 있는 PC에서만 한다.

const PLAYER_SCENE := preload("res://src/player/player.tscn")

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


func test_missing_model_falls_back_to_capsule() -> void:
	var appearance := CharacterAppearance.new()
	appearance.model_path = "res://assets/characters/없는_모델.glb"
	await _spawn(appearance)
	assert_false(player.body.has_model)
	assert_not_null(player.body.placeholder, "캡슐 몸이 남아 있음")
	assert_false(player.body.has_muzzle())


func test_capsule_shrinks_when_crouching() -> void:
	var appearance := CharacterAppearance.new()
	await _spawn(appearance)
	intent.crouch_pressed = true
	await _frames(30)
	var expected := player.config.crouch_height / player.config.stand_height
	assert_almost_eq(player.body.placeholder.scale.y, expected, 0.01)


func test_dead_player_body_is_hidden() -> void:
	await _spawn(null)
	player.set_third_person(true)
	player.health.apply_damage(DamageInfo.create(1000.0, 0, Vector3.ZERO, &"test", false))
	assert_eq(player.body.view_mode, PlayerBody.ViewMode.HIDDEN)
	player.health.revive()
	assert_eq(player.body.view_mode, PlayerBody.ViewMode.VISIBLE)


func test_crouch_lowers_model_head() -> void:
	if not await _spawn_with_model():
		return
	var standing := _head_height()
	intent.crouch_pressed = true
	await _frames(40)
	var crouching := _head_height()
	assert_true(standing - crouching > 0.4, "머리가 내려가야 함: %s → %s" % [standing, crouching])
	assert_true(_lowest_foot() < 0.2, "발은 땅에 붙어 있음: %s" % _lowest_foot())


func test_walking_swings_legs() -> void:
	if not await _spawn_with_model():
		return
	intent.move = Vector2(0, 1)
	var foot_z: Array[float] = []
	for i in 60:
		await _frames(1)
		foot_z.append(player.body.bone_position(player.body.appearance.left_foot_bone).z)
	assert_true(foot_z.max() - foot_z.min() > 0.3, "왼발이 앞뒤로 움직여야 함: %s" % (foot_z.max() - foot_z.min()))


func test_gun_is_held_forward_and_muzzle_follows() -> void:
	if not await _spawn_with_model():
		return
	# 애니메이션 모델은 조준할 때만 겨눈다(코드로 만든 자세는 늘 겨눈다).
	intent.aim_held = true
	await _frames(30)
	# 애니메이션 위에 덧입힌 팔 자세는 그리는 프레임에만 남고 뼈를 읽으면 원래 동작이 나온다.
	# 그래서 그 자세에 맞춰 놓은 총의 위치로 확인한다.
	var chest := player.body.bone_position(player.body.appearance.chest_bone)
	assert_true(player.body.has_muzzle())
	var muzzle := player.to_local(player.body.muzzle_position())
	assert_true(muzzle.z < chest.z - 0.4, "권총을 몸 앞으로 겨눔: 총구 %s, 가슴 %s" % [muzzle.z, chest.z])
	assert_true(muzzle.y > 1.0, "가슴 높이로 든다: %s" % muzzle.y)


func test_animated_model_blends_motion_by_speed() -> void:
	if not await _spawn_with_model() or not player.body.animated:
		return
	await _frames(20)
	assert_eq(player.body.dominant_animation(), &"idle", "서 있으면 서기 동작")
	intent.move = Vector2(0, 1)
	await _frames(40)
	assert_eq(player.body.dominant_animation(), &"run", "걷기 속도(4m/s)면 달리기 동작")
	intent.sprint = true
	await _frames(40)
	assert_eq(player.body.dominant_animation(), &"sprint")


func test_animated_body_turns_toward_movement_then_aim() -> void:
	if not await _spawn_with_model() or not player.body.animated:
		return
	intent.move = Vector2(1, 0)  # 오른쪽으로 옆걸음
	await _frames(40)
	assert_true(player.body.facing().dot(Vector3.RIGHT) > 0.9, "움직이는 방향(오른쪽)을 본다: %s" % player.body.facing())
	intent.aim_held = true
	await _frames(40)
	assert_true(player.body.chest_facing().dot(Vector3.FORWARD) > 0.95, "조준하면 상체는 앞을 본다: %s" % player.body.chest_facing())
	assert_true(player.body.facing().dot(Vector3.RIGHT) > 0.5, "다리는 여전히 오른쪽으로 간다: %s" % player.body.facing())
	intent.move = Vector2(0, -1)  # 조준한 채 뒤로
	await _frames(40)
	assert_true(player.body.facing().dot(Vector3.FORWARD) > 0.9, "뒷걸음은 앞을 본 채로: %s" % player.body.facing())
	assert_true(player.body._backpedal)


func test_animated_jump_then_land() -> void:
	if not await _spawn_with_model() or not player.body.animated:
		return
	await _frames(20)
	intent.jump_pressed = true
	await _frames(10)
	assert_eq(player.body.dominant_animation(), &"jump", "뛰면 도약 동작")
	var landed := false
	for i in 90:
		await _frames(1)
		landed = landed or player.body.dominant_animation() == &"land"
	assert_true(landed, "내려서면 착지 동작")


func test_animated_body_falls_when_dropped() -> void:
	if not await _spawn_with_model() or not player.body.animated:
		return
	player.global_position.y = 8.0
	await _frames(30)
	assert_eq(player.body.dominant_animation(), &"fall")



func test_motion_is_steady_when_screen_draws_faster_than_physics() -> void:
	if not await _spawn_with_model() or not player.body.animated:
		return
	# 화면(60번)이 물리(30번)보다 자주 그려져도 달리기 동작이 깜빡이지 않아야 한다.
	var ticks := Engine.physics_ticks_per_second
	Engine.physics_ticks_per_second = 30
	intent.move = Vector2(0, 1)
	for i in 40:
		await tree.process_frame
	var seen: Array[StringName] = []
	for i in 40:
		await tree.process_frame
		if not seen.has(player.body.locomotion):
			seen.append(player.body.locomotion)
	Engine.physics_ticks_per_second = ticks
	assert_eq(seen, [&"run"] as Array[StringName], "걷는 속도(4m/s) 내내 달리기 동작")


func test_remote_body_reads_speed_from_sparse_updates() -> void:
	# 원격 플레이어: 위치가 네트워크로 띄엄띄엄(두 프레임에 한 번) 와도 속도를 고르게 읽는다.
	player = PLAYER_SCENE.instantiate()
	player.use_device_input = false
	player.set_multiplayer_authority(2)
	add_child_autofree(player)
	await _frames(2)
	if not player.body.animated:
		return
	var seen: Array[StringName] = []
	for i in 120:
		if i % 2 == 0:
			player.global_position += Vector3(0, 0, -4.0 * 2.0 / 60.0)
		await tree.process_frame
		if i > 40 and not seen.has(player.body.locomotion):
			seen.append(player.body.locomotion)
	assert_eq(seen, [&"run"] as Array[StringName])


func test_foot_ik_finds_step_under_one_foot() -> void:
	if not await _spawn_with_model() or not player.body.animated:
		return
	# 왼발(-X 쪽) 밑에만 발이 딛는 디딤판(foot_ground 레이어)을 놓는다. 몸은 통과한다.
	var step := StaticBody3D.new()
	step.collision_layer = PlayerBody.FOOT_GROUND_LAYER
	step.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.0, 0.2, 2.0)
	shape.shape = box
	step.add_child(shape)
	step.position = Vector3(-0.55, 0.1, 0)
	add_child_autofree(step)
	await _frames(40)
	assert_almost_eq(player.body.foot_offsets.x, 0.2, 0.04, "왼발 밑 디딤판 높이")
	assert_almost_eq(player.body.foot_offsets.y, 0.0, 0.04, "오른발은 바닥")
	assert_almost_eq(player.global_position.y, 0.0, 0.05, "몸(캡슐)은 디딤판에 걸리지 않는다")

func test_blade_has_no_muzzle() -> void:
	if not await _spawn_with_model():
		return
	intent.weapon_slot = 3
	await _frames(10)
	assert_false(player.body.has_muzzle())


func test_model_next_to_executable_is_read_at_runtime() -> void:
	# 내보낸 게임은 모델을 실행 파일 옆에서 실행 중에 읽는다. 프로젝트 안의 원본 파일로 그 경로를 흉내 낸다.
	var source := ProjectSettings.globalize_path((load(PlayerBody.DEFAULT_APPEARANCE) as CharacterAppearance).model_path)
	if not FileAccess.file_exists(source):
		print("    (캐릭터 모델이 없어 건너뜀)")
		return
	var appearance := CharacterAppearance.new()
	appearance.external_model_file = source
	await _spawn(appearance)
	assert_true(player.body.has_model, "실행 중에 glTF를 읽어 몸으로 씀")
	assert_true(player.body.animated, "실행 중에 읽어도 애니메이션 이름(-loop)을 정리해 쓴다")
	player.set_third_person(true)
	intent.crouch_pressed = true
	await _frames(40)
	assert_true(_head_height() < 1.2, "읽어 온 모델도 자세를 만듦: %s" % _head_height())


func test_runtime_model_is_read_only_once() -> void:
	var source := ProjectSettings.globalize_path((load(PlayerBody.DEFAULT_APPEARANCE) as CharacterAppearance).model_path)
	if not FileAccess.file_exists(source):
		return
	var first := CharacterAppearance.load_gltf_file(source)
	assert_not_null(first)
	assert_true(CharacterAppearance.load_gltf_file(source) == first, "같은 파일은 다시 읽지 않음")


func _spawn(appearance: CharacterAppearance) -> void:
	player = PLAYER_SCENE.instantiate()
	player.use_device_input = false
	intent = PlayerIntent.new()
	player.intent_override = intent
	if appearance != null:
		(player.get_node("Body") as PlayerBody).appearance = appearance
	add_child_autofree(player)
	await _frames(2)


## 기본 외형(캐릭터 모델)으로 띄운다. 모델 파일이 없는 PC면 false를 돌려준다.
func _spawn_with_model() -> bool:
	await _spawn(null)
	player.set_third_person(true)
	if not player.body.has_model:
		print("    (캐릭터 모델이 없어 건너뜀)")
		return false
	await _frames(5)
	return true


func _head_height() -> float:
	return player.body.bone_position(player.body.appearance.head_bone).y


func _lowest_foot() -> float:
	var appearance := player.body.appearance
	return minf(player.body.bone_position(appearance.left_foot_bone).y, player.body.bone_position(appearance.right_foot_bone).y)


func _frames(count: int) -> void:
	for i in count:
		await tree.physics_frame
