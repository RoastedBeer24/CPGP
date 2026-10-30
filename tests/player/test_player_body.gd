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
	assert_true(player.body.facing().dot(Vector3.FORWARD) > 0.9, "조준하면 앞을 본다: %s" % player.body.facing())
	assert_eq(player.body.dominant_animation(), &"strafe")


func test_animated_body_falls_in_air() -> void:
	if not await _spawn_with_model() or not player.body.animated:
		return
	intent.jump_pressed = true
	await _frames(15)
	assert_eq(player.body.dominant_animation(), &"fall")


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
