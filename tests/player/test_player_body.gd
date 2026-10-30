extends TestCase
## 플레이어 몸: 모델이 없을 때의 캡슐 몸, 모델의 동작(이동·점프·공격·회피·쓰러짐), 검, 바이저, 옷자락, 재질.
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
	assert_false(player.body.sword_shown())


func test_each_character_uses_its_own_model_and_kit() -> void:
	for id: StringName in [&"endministrator_f", &"endministrator_m"]:
		await _spawn(null, id)
		var character := Characters.find(id)
		assert_eq(player.kit.id, id, "고른 캐릭터의 전투 구성")
		assert_eq(player.body.appearance.model_path, character.appearance().model_path, "고른 캐릭터의 모습")
		player.queue_free()
		await _frames(1)


func test_walking_swings_legs() -> void:
	if not await _spawn_with_model():
		return
	intent.move = Vector2(0, 1)
	var foot_z: Array[float] = []
	for i in 60:
		await _frames(1)
		foot_z.append(player.body.bone_position(player.body.appearance.left_foot_bone).z)
	assert_true(foot_z.max() - foot_z.min() > 0.3, "왼발이 앞뒤로 움직여야 함: %s" % (foot_z.max() - foot_z.min()))
	assert_eq(player.body.dominant_animation(), &"run", "달리기 동작")


func test_attack_chain_plays_attack_clips_and_draws_sword() -> void:
	if not await _spawn_with_model() or not player.body.animated:
		return
	assert_false(player.body.sword_shown(), "싸우기 전에는 검을 넣어 둔다")
	intent.attack_pressed = true
	await _frames(6)
	assert_eq(player.body.dominant_animation(), &"attack_1", "첫 공격 동작")
	assert_true(player.body.sword_shown(), "공격하면 검을 든다")
	await _frames(20)
	intent.attack_pressed = true
	await _frames(12)
	assert_eq(player.body.dominant_animation(), &"attack_2", "이어 누르면 다음 공격 동작")
	await _frames(90)
	assert_ne(player.body.dominant_animation(), &"attack_2", "끝나면 이동 동작으로 돌아온다")
	assert_eq(player.body.locomotion, &"battle_idle", "싸우는 중에는 전투 대기 동작")


func test_dodge_and_down_play_their_clips() -> void:
	if not await _spawn_with_model() or not player.body.animated:
		return
	intent.move = Vector2(0, 1)
	await _frames(10)
	intent.dodge_pressed = true
	await _frames(6)
	assert_eq(player.body.dominant_animation(), &"dodge_f", "앞으로 회피")
	intent.move = Vector2.ZERO
	await _frames(40)
	player.health.apply_damage(DamageInfo.create(99999.0, 0, Vector3.ZERO, &"test"))
	await _frames(10)
	assert_eq(player.body.dominant_animation(), &"dead", "쓰러지면 쓰러지는 동작")
	assert_eq(player.body.view_mode, PlayerBody.ViewMode.VISIBLE, "쓰러져도 몸은 보인다(동료가 찾아와 일으킨다)")
	player.health.revive(0.3)
	await _frames(30)
	assert_ne(player.body.dominant_animation(), &"dead", "일어나면 푼다")


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


func test_remote_body_follows_synced_action_count() -> void:
	# 원격 플레이어: 동작 번호가 바뀌면 같은 동작을 튼다.
	player = PLAYER_SCENE.instantiate()
	player.use_device_input = false
	player.set_multiplayer_authority(2)
	add_child_autofree(player)
	await _frames(2)
	if not player.body.animated:
		return
	player.state = Player.State.ACTION
	player.action_id = &"battle_skill"
	player.action_count += 1
	await _frames(6)
	assert_eq(player.body.dominant_animation(), &"skill", "원격 몸도 배틀 스킬 동작")


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


func test_cloth_hangs_and_stays_above_ground() -> void:
	for id: StringName in [&"endministrator_f", &"endministrator_m"]:
		if not await _spawn_with_model(id) or not player.body.has_cloth():
			continue
		# 옷자락 물리는 그리는 프레임에만 남으므로, 계산이 끝난 순간의 망토 끝 높이를 잰다.
		var skeleton: Skeleton3D = player.body._skeleton
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
		intent.move = Vector2(0, 1)
		await _frames(60)
		intent.move = Vector2.ZERO
		heights["low"] = INF
		await _frames(30)
		assert_true(float(heights["low"]) > -0.02, "%s: 망토가 땅을 뚫지 않는다: %s" % [id, heights["low"]])
		player.queue_free()
		await _frames(1)


func test_eyes_stay_still() -> void:
	if not await _spawn_with_model() or not player.body.animated:
		return
	# 원본 동작은 오른쪽 눈 뼈만 움직여서 한쪽 눈이 돌아갔다. 추출 도구가 눈 뼈 트랙을 뺀다.
	var animation_player := player.body.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	for clip in animation_player.get_animation_list():
		var animation := animation_player.get_animation(clip)
		for track in animation.get_track_count():
			var bone := animation.track_get_path(track).get_concatenated_subnames()
			assert_false(bone in ["eyeLfJoint", "eyeRtJoint"], "%s 동작이 눈 뼈(%s)를 움직이지 않는다" % [clip, bone])
	assert_false(player.body._face_meshes.is_empty(), "얼굴은 고르게 비추는 재질을 쓴다")


func test_toon_materials_use_original_maps() -> void:
	for id: StringName in [&"endministrator_f", &"endministrator_m"]:
		if not await _spawn_with_model(id):
			continue
		var prefix := "S_actor_endminf_" if id == &"endministrator_f" else "S_actor_endminm_"
		var face := player.body.find_child(prefix + "face_01_lod0", true, false) as MeshInstance3D
		var face_material := face.get_active_material(0) as ShaderMaterial
		assert_eq(face_material.shader, PlayerBody.TOON_SHADER, "%s: 얼굴은 만화풍 재질" % id)
		assert_true(face_material.get_shader_parameter(&"use_face_shadow"), "%s: 얼굴 그늘은 원본 그림자 지도로 만든다" % id)
		var coat := player.body.find_child(prefix + "cloth_01_lod0", true, false) as MeshInstance3D
		var coat_material := coat.get_active_material(0) as ShaderMaterial
		assert_true(coat_material.get_shader_parameter(&"use_normal_map"), "%s: 코트는 주름 법선 지도를 쓴다" % id)
		assert_not_null(coat_material.next_pass, "%s: 코트에 외곽선" % id)
		var shadow := player.body.find_child(prefix + "eyeshadow_01_lod0", true, false) as MeshInstance3D
		assert_false(shadow.visible, "%s: 눈 흰자 위 그림자 메시는 숨긴다" % id)
		player.queue_free()
		await _frames(1)


func test_model_next_to_executable_is_read_at_runtime() -> void:
	# 내보낸 게임은 모델을 실행 파일 옆에서 실행 중에 읽는다. 프로젝트 안의 원본 파일로 그 경로를 흉내 낸다.
	var source := ProjectSettings.globalize_path(Characters.find(Characters.DEFAULT_ID).appearance().model_path)
	if not FileAccess.file_exists(source):
		print("    (캐릭터 모델이 없어 건너뜀)")
		return
	var appearance := CharacterAppearance.new()
	appearance.external_model_file = source
	await _spawn(appearance)
	assert_true(player.body.has_model, "실행 중에 glTF를 읽어 몸으로 씀")
	assert_true(player.body.animated, "실행 중에 읽어도 애니메이션 이름(-loop)을 정리해 쓴다")
	assert_true(player.body._action_clips.has(&"attack_5"), "공격 동작을 읽는다")
	intent.move = Vector2(0, 1)
	await _frames(40)
	assert_eq(player.body.dominant_animation(), &"run", "읽어 온 모델도 달린다")


func test_runtime_model_is_read_only_once() -> void:
	var source := ProjectSettings.globalize_path(Characters.find(Characters.DEFAULT_ID).appearance().model_path)
	if not FileAccess.file_exists(source):
		return
	var first := CharacterAppearance.load_gltf_file(source)
	assert_not_null(first)
	assert_true(CharacterAppearance.load_gltf_file(source) == first, "같은 파일은 다시 읽지 않음")


func _spawn(appearance: CharacterAppearance, character_id: StringName = Characters.DEFAULT_ID) -> void:
	player = PLAYER_SCENE.instantiate()
	player.use_device_input = false
	player.character_id = character_id
	intent = PlayerIntent.new()
	player.intent_override = intent
	if appearance != null:
		(player.get_node("Body") as PlayerBody).appearance = appearance
	add_child_autofree(player)
	await _frames(2)


## 고른 캐릭터의 모델로 띄운다. 모델 파일이 없는 PC면 false를 돌려준다.
func _spawn_with_model(character_id: StringName = Characters.DEFAULT_ID) -> bool:
	await _spawn(null, character_id)
	if not player.body.has_model:
		print("    (캐릭터 모델이 없어 건너뜀: %s)" % character_id)
		return false
	await _frames(5)
	return true


func _frames(count: int) -> void:
	for i in count:
		await tree.physics_frame
