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


func test_animated_crouch_kneels_then_steps() -> void:
	if not await _spawn_with_model() or not player.body.animated:
		return
	intent.crouch_pressed = true
	await _frames(30)
	assert_eq(player.body.dominant_animation(), &"crouch", "멈춰서 웅크리면 무릎을 꿇는다")
	assert_true(_head_height() < 1.0, "꿇으면 머리가 낮다: %s" % _head_height())
	assert_almost_eq(player.body.pelvis_drop(), 0.0, 0.02, "꿇는 동작 자체가 낮아서 골반을 더 내리지 않는다")
	intent.move = Vector2(0, 1)
	await _frames(30)
	assert_eq(player.body.dominant_animation(), &"crouch_walk", "웅크려 움직이면 걸음을 코드로 만든다")
	assert_almost_eq(player.body.pelvis_drop(), PlayerBody.CROUCH_WALK_DROP, 0.03, "걸을 때는 골반을 내린다")


func test_crouch_foot_shortens_stride_and_keeps_planted_foot_down() -> void:
	# 웅크려 걷기는 달리기 동작의 발을 따라가되 앞뒤 보폭과 발 든 높이를 줄인다. 모델이 없어도 확인한다.
	var hip := Vector3(0.1, 0.9, 0.0)
	var forward := Vector3.FORWARD
	var rest := 0.08
	var ground := 0.42
	# 땅을 딛고 엉덩이보다 0.5m 앞, 0.05m 바깥에 있는 발
	var planted := PlayerBody._crouch_foot(hip, Vector3(0.15, rest, -0.5), ground, rest, forward)
	assert_almost_eq(planted.y, ground, 0.0001, "딛은 발은 내린 골반 밑 땅에 그대로 있다")
	assert_almost_eq(planted.z, -0.5 * PlayerBody.CROUCH_STRIDE, 0.0001, "앞뒤 보폭은 줄인다")
	assert_almost_eq(planted.x, 0.15, 0.0001, "옆으로 벌린 거리는 그대로")
	# 0.3m 들어 올린 발
	var lifted := PlayerBody._crouch_foot(hip, Vector3(0.1, rest + 0.3, 0.2), ground, rest, forward)
	assert_almost_eq(lifted.y, ground + 0.3 * PlayerBody.CROUCH_LIFT_SCALE, 0.0001, "발 든 높이도 줄인다")


func test_animated_slide_stretches_leg() -> void:
	if not await _spawn_with_model() or not player.body.animated:
		return
	intent.move = Vector2(0, 1)
	intent.sprint = true
	await _frames(45)
	intent.sprint = false
	intent.crouch_pressed = true
	await _frames(15)
	assert_eq(player.state, Player.State.SLIDE)
	assert_eq(player.body.dominant_animation(), &"slide")
	assert_almost_eq(player.body._slide_weight, 1.0, 0.01, "다리를 뻗은 자세가 다 입혀진다")
	assert_true(_head_height() < 1.0, "몸을 낮춘다: %s" % _head_height())


func test_melee_attacks_chain_into_combo() -> void:
	if not await _spawn_with_model() or not player.body.animated:
		return
	intent.weapon_slot = 3
	await _frames(20)  # 무기를 바꾼 뒤 0.25초는 공격하지 못한다
	intent.fire_pressed = true
	await _frames(6)
	assert_eq(player.melee_count, 1)
	assert_eq(player.body.dominant_animation(), &"melee", "휘두르는 동작")
	assert_false(player.body._melee_blend.filter_enabled, "서서 휘두르면 온몸으로")
	var first := player.body._combo
	await _frames(24)
	intent.fire_pressed = true
	await _frames(4)
	assert_eq(player.melee_count, 2)
	assert_eq(player.body._combo, (first + 1) % 3, "이어서 치면 다음 동작")
	await _frames(120)
	assert_ne(player.body.dominant_animation(), &"melee", "끝나면 원래 동작으로")
	intent.fire_pressed = true
	await _frames(4)
	assert_eq(player.body._combo, 0, "한참 뒤에 치면 첫 동작부터")


func test_melee_while_moving_swings_upper_body_only() -> void:
	if not await _spawn_with_model() or not player.body.animated:
		return
	intent.weapon_slot = 3
	intent.move = Vector2(0, 1)
	await _frames(30)
	intent.fire_pressed = true
	await _frames(6)
	assert_eq(player.body.dominant_animation(), &"melee")
	assert_true(player.body._melee_blend.filter_enabled, "움직이며 휘두르면 상체만")
	assert_eq(player.body.locomotion, &"run", "다리는 계속 달린다")
	assert_true(player.body.chest_facing().dot(Vector3.FORWARD) > 0.9, "휘두르는 쪽(앞)을 본다")



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

func test_visor_key_takes_headgear_off_and_on() -> void:
	await _spawn(null)
	assert_true(player.visor_on, "처음에는 바이저를 쓰고 있다")
	intent.visor_pressed = true
	await _frames(2)
	assert_false(player.visor_on, "H를 누르면 벗는다")
	if player.body.has_headgear():
		assert_false(player.body.headgear_shown(), "바이저 메시가 숨는다")
	intent.visor_pressed = true
	await _frames(2)
	assert_true(player.visor_on, "다시 누르면 쓴다")
	if player.body.has_headgear():
		assert_true(player.body.headgear_shown())


func test_crouching_holds_gun_low_in_front() -> void:
	if not await _spawn_with_model() or not player.body.animated:
		return
	intent.crouch_pressed = true
	await _frames(40)
	var chest := player.body.bone_position(player.body.appearance.chest_bone)
	assert_true(player.body.has_muzzle())
	var muzzle := player.to_local(player.body.muzzle_position())
	assert_true(muzzle.z < chest.z - 0.2, "총을 몸 앞에 든다: 총구 %s, 가슴 %s" % [muzzle.z, chest.z])
	assert_true(muzzle.y < chest.y, "가슴보다 낮춰 든다: 총구 %s, 가슴 %s" % [muzzle.y, chest.y])


func test_cloth_hangs_and_stays_above_ground() -> void:
	if not await _spawn_with_model() or not player.body.has_cloth():
		return
	# 옷자락 물리는 그리는 프레임에만 남으므로, 계산이 끝난 순간의 망토 끝 높이를 잰다.
	var skeleton: Skeleton3D = player.body._skeleton
	# 등에서 늘어진 망토 갈래의 끝만 본다(목 뒤의 후드 끝은 원래 높다).
	var tips: Array[int] = []
	for chain in player.body.appearance.cloth_chains:
		if chain.contains("pifeng"):
			tips.append(skeleton.find_bone(chain.split(":")[1]))
	var heights := {"low": INF, "high": -INF}
	player.body._cloth.modification_processed.connect(func() -> void:
		for bone in tips:
			var y := (skeleton.global_transform * skeleton.get_bone_global_pose(bone)).origin.y - player.global_position.y
			heights["low"] = minf(heights["low"], y)
			heights["high"] = maxf(heights["high"], y))
	intent.crouch_pressed = true
	intent.move = Vector2(0, 1)
	await _frames(30)
	heights["high"] = -INF
	await _frames(30)
	var chest := player.body.bone_position(player.body.appearance.chest_bone)
	assert_true(float(heights["high"]) < chest.y, "웅크려 걸어도 망토 끝은 가슴 아래로 늘어진다: %s" % heights["high"])
	# 일어서서 달리다가 슬라이딩
	intent.crouch_pressed = true
	await _frames(20)
	intent.sprint = true
	await _frames(45)
	intent.sprint = false
	intent.crouch_pressed = true
	heights["low"] = INF
	await _frames(30)
	assert_eq(player.state, Player.State.SLIDE)
	assert_true(float(heights["low"]) > -0.02, "슬라이딩해도 망토가 땅을 뚫지 않는다: %s" % heights["low"])


func test_eyes_stay_still_and_shadows_are_multiplied() -> void:
	if not await _spawn_with_model() or not player.body.animated:
		return
	# 원본 동작은 오른쪽 눈 뼈만 움직여서 한쪽 눈이 돌아갔다. 추출 도구가 눈 뼈 트랙을 뺀다.
	var animation_player := player.body.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	for clip in animation_player.get_animation_list():
		var animation := animation_player.get_animation(clip)
		for track in animation.get_track_count():
			var bone := animation.track_get_path(track).get_concatenated_subnames()
			assert_false(bone in ["eyeLfJoint", "eyeRtJoint"], "%s 동작이 눈 뼈(%s)를 움직이지 않는다" % [clip, bone])
	# 눈 흰자 위 그림자 메시는 숨긴다(그냥 칠하면 하늘색 줄, 곱해도 홍채 위에 회색 막).
	var shadow := player.body.find_child("S_actor_endminf_eyeshadow_01_lod0", true, false) as MeshInstance3D
	assert_not_null(shadow)
	assert_false(shadow.visible)
	assert_false(player.body._face_meshes.is_empty(), "얼굴은 고르게 비추는 재질을 쓴다")


func test_fists_hold_nothing_and_raise_guard() -> void:
	if not await _spawn_with_model() or not player.body.animated:
		return
	intent.weapon_slot = 4
	await _frames(20)
	assert_false(player.body.has_muzzle())
	assert_eq(player.body._held.get_child_count(), 0, "맨손은 아무것도 들지 않는다")
	intent.fire_pressed = true
	await _frames(6)
	assert_eq(player.body.dominant_animation(), &"melee", "주먹을 내지른다")
	assert_eq(player.body._melee_clip, &"melee_2", "맨손은 찌르기(주먹 지르기)부터")
	await _frames(30)
	assert_true(player.body._guard_amount > 0.9, "싸우는 중에는 두 주먹을 든다: %s" % player.body._guard_amount)
	intent.weapon_slot = 1
	await _frames(30)
	assert_true(player.body._guard_amount < 0.1, "총을 들면 내린다")


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
	assert_true(player.body._has_kneel, "무릎 꿇기 동작도 읽는다")
	assert_eq(player.body._melee_kinds.size(), 3, "근접 공격 동작 셋을 읽는다")
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
