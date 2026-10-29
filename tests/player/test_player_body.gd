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
	await _frames(30)
	var hand := player.body.bone_position(player.body.appearance.right_hand_bone)
	var chest := player.body.bone_position(player.body.appearance.chest_bone)
	assert_true(hand.z < chest.z - 0.25, "권총을 몸 앞으로 겨눔: 손 %s, 가슴 %s" % [hand.z, chest.z])
	assert_true(player.body.has_muzzle())
	var muzzle := player.to_local(player.body.muzzle_position())
	assert_true(muzzle.z < hand.z, "총구가 손보다 앞")


func test_blade_has_no_muzzle() -> void:
	if not await _spawn_with_model():
		return
	intent.weapon_slot = 3
	await _frames(10)
	assert_false(player.body.has_muzzle())


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
