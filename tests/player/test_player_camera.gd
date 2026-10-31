extends TestCase
## 카메라: 기본 시점(3인칭 정해진 거리, V로 1인칭), 자유 시점(`, 휠로 얼굴까지), 벽에 막힐 때 당기고 천천히 되돌리기,
## 싸울 때 조금 물러나기.

const PLAYER_SCENE := preload("res://src/player/player.tscn")

var player: Player
var intent: PlayerIntent
var arena: Node3D


func before_each() -> void:
	arena = Node3D.new()
	_add_box(arena, Vector3(0, -0.5, 0), Vector3(60, 1, 60))
	add_child_autofree(arena)
	player = PLAYER_SCENE.instantiate()
	player.use_device_input = false
	intent = PlayerIntent.new()
	player.intent_override = intent
	add_child_autofree(player)
	await _frames(10)


func test_default_view_keeps_its_distance() -> void:
	assert_eq(player.camera_mode, Player.CameraMode.THIRD_PERSON)
	for i in 20:
		player.zoom(-1)
	await _frames(60)
	assert_almost_eq(player.camera_length(), player.config.camera_distance, 0.05, "기본 시점은 휠로 당기지 않는다")


func test_first_person_puts_camera_at_the_eyes() -> void:
	player.toggle_first_person()
	await _frames(90)
	assert_eq(player.camera_mode, Player.CameraMode.FIRST_PERSON)
	assert_true(player.camera_length() < 0.05, "1인칭은 카메라 팔이 없다: %s" % player.camera_length())
	assert_true(player.camera.global_position.distance_to(player.body.first_person_eye()) < 0.05, "눈 위치에서 본다")
	assert_true(player.body.first_person(), "머리를 뺀 내 몸이 보인다")
	if player.body.has_model:
		assert_true(player.body.view_mesh_count() > 0, "1인칭 몸 메시를 만든다")
		assert_true(player.body.first_person_body_visible(), "서 있어도 내 몸이 보인다")
		var look := player.body.appearance
		assert_true(player.body.first_person_hides(look.head_bone), "머리는 숨긴다")
		for bone: StringName in [look.right_hand_bone, look.left_upper_arm_bone, look.chest_bone, look.left_thigh_bone, look.right_foot_bone]:
			assert_false(player.body.first_person_hides(bone), "몸·팔·다리는 보인다: %s" % bone)
	player.toggle_first_person()
	await _frames(120)
	assert_eq(player.camera_mode, Player.CameraMode.THIRD_PERSON)
	assert_false(player.body.first_person())
	assert_almost_eq(player.camera_length(), player.config.camera_distance, 0.1, "3인칭으로 돌아간다")


func test_first_person_camera_sits_at_each_characters_eyes() -> void:
	# 시점은 캐릭터마다 그 모델의 눈동자 자리다(키가 큰 관리자(남)는 더 높다).
	var heights: Dictionary[StringName, float] = {}
	var slot := 0
	for character in Characters.all():
		var other := PLAYER_SCENE.instantiate() as Player
		other.character_id = character.id
		other.use_device_input = false
		other.intent_override = PlayerIntent.new()
		slot += 1
		other.position = Vector3(slot * 3.0, 0, 6)
		add_child_autofree(other)
		await _frames(20)
		if not other.body.has_model:
			continue
		other.toggle_first_person()
		await _frames(60)
		var depth := other.body.eye_depth()
		assert_true(depth > 0.02 and depth < 0.06, "%s: 눈알 가운데에서 눈동자까지 %s m" % [character.id, depth])
		var eye := other.body.first_person_eye()
		assert_true(other.camera.global_position.distance_to(eye) < 0.05, "%s: 카메라가 눈에 있다" % character.id)
		heights[character.id] = eye.y - other.global_position.y
	if heights.has(&"endministrator_m") and heights.has(&"endministrator_f"):
		assert_true(heights[&"endministrator_m"] > heights[&"endministrator_f"] + 0.05, "키 큰 캐릭터는 시점이 높다: %s" % heights)


func test_first_person_camera_keeps_up_when_running() -> void:
	# 예전에는 눈을 늦게 따라가서 달리면 카메라가 머리 뒤로 처져 목이 보였다.
	player.toggle_first_person()
	intent.move = Vector2(0, 1)
	await _frames(60)
	var eye := player.body.first_person_eye()
	var gap := Vector2(player.camera.global_position.x - eye.x, player.camera.global_position.z - eye.z).length()
	assert_true(gap < 0.03, "달려도 카메라가 눈에서 떨어지지 않는다: %s" % gap)


func test_first_person_body_faces_where_you_look() -> void:
	player.toggle_first_person()
	player.look(Vector2(PI * 0.5, 0.0))
	await _frames(5)
	assert_true(player.facing().dot(Vector3.RIGHT) > 0.99, "몸이 카메라가 보는 쪽을 본다: %s" % player.facing())
	# 옆으로 가며 공격해도 가는 쪽이 아니라 보는 쪽으로 공격한다(팔과 칼이 화면 앞에 있다).
	intent.move = Vector2(-1, 0)
	await _frames(10)
	assert_true(player.facing().dot(Vector3.RIGHT) > 0.99, "옆으로 가도 보는 쪽을 본다: %s" % player.facing())
	intent.attack_pressed = true
	await _frames(3)
	assert_not_null(player.current_action(), "공격한다")
	assert_true(player.facing().dot(Vector3.RIGHT) > 0.99, "보는 쪽으로 공격한다: %s" % player.facing())
	if player.body.animated:
		assert_true(player.body.first_person_body_visible(), "공격하는 동안에도 몸과 휘두르는 팔이 보인다")


func test_first_person_steadies_during_attacks() -> void:
	# 격한 동작 중에는 시점을 몸 가운데 위(처음 자세의 눈 자리)로 모아 몸·팔 속에 묻히지 않게 하고, 끝나면 다시
	# 지금 동작의 눈을 따라간다(사용자 지적: 격한 동작에서 시점이 몸속에 묻혔다).
	player.toggle_first_person()
	await _frames(30)
	if not player.body.animated:
		return
	intent.attack_pressed = true
	await _frames(12)
	assert_true(player.body.first_person_action() > 0.8, "공격 중: %s" % player.body.first_person_action())
	var eye := player.body.first_person_eye()
	var flat := Vector2(eye.x - player.global_position.x, eye.z - player.global_position.z).length()
	assert_true(flat < 0.2, "시점이 몸 가운데 위에 있다: %.2f" % flat)
	assert_true(eye.y - player.global_position.y > 1.0, "너무 낮게 내려가지 않는다: %.2f" % (eye.y - player.global_position.y))
	intent.attack_pressed = false
	await _frames(150)
	assert_true(player.body.first_person_action() < 0.05, "동작이 끝나면 다시 눈을 따라간다")


func test_first_person_legs_follow_movement() -> void:
	# 1인칭은 몸이 시선 쪽을 본다. 옆으로 가면 다리만 가는 쪽으로 돌리고, 뒤로 가면 이동 동작을 거꾸로 튼다
	# (예전에는 옆걸음에도 앞으로 뛰는 다리가 보였다).
	assert_false(player.strafing, "3인칭은 가는 쪽을 본다")
	player.toggle_first_person()
	intent.move = Vector2(1, 0)
	await _frames(40)
	assert_true(player.strafing, "1인칭은 시선 쪽을 보며 움직인다")
	if not player.body.animated:
		return
	assert_almost_eq(player.body.leg_twist_degrees(), -90.0, 8.0, "오른쪽으로 가면 다리가 오른쪽을 본다")
	assert_false(player.body.legs_backward())
	intent.move = Vector2(0, -1)
	await _frames(40)
	assert_true(player.body.legs_backward(), "뒤로 가면 이동 동작을 거꾸로 튼다")
	assert_almost_eq(player.body.leg_twist_degrees(), 0.0, 8.0, "곧장 뒤로 가면 다리는 앞을 본 채 뒷걸음질")
	intent.move = Vector2.ZERO
	player.toggle_first_person()
	await _frames(40)
	assert_false(player.strafing, "3인칭은 가는 쪽을 본다")
	assert_almost_eq(player.body.leg_twist_degrees(), 0.0, 2.0, "다리를 바로 놓는다")


func test_free_view_zooms_close_to_the_face() -> void:
	player.toggle_free_view()
	for i in 60:
		player.zoom(-1)
	await _frames(120)
	assert_almost_eq(player.camera_length(), player.config.camera_min_distance, 0.02, "얼굴 앞까지 당긴다")
	assert_true(player.camera_rig.global_position.distance_to(player.body.eye_position()) < 0.05, "가까이 당기면 얼굴을 중심으로 돈다")
	assert_eq(player.body.view_mode, PlayerBody.ViewMode.VISIBLE, "얼굴을 볼 때 몸을 숨기지 않는다")
	player.toggle_free_view()
	await _frames(5)
	assert_eq(player.camera_mode, Player.CameraMode.THIRD_PERSON, "자유 시점을 끄면 기본 시점으로")


func test_free_view_returns_to_first_person_base() -> void:
	player.toggle_first_person()
	player.toggle_free_view()
	assert_eq(player.camera_mode, Player.CameraMode.FREE)
	assert_false(player.body.first_person(), "자유 시점에서는 머리를 숨기지 않는다")
	player.toggle_free_view()
	assert_eq(player.camera_mode, Player.CameraMode.FIRST_PERSON, "1인칭에서 켰으면 1인칭으로 돌아간다")


func test_wall_pulls_camera_in_then_eases_back() -> void:
	# 카메라는 몸 뒤(+Z 쪽, 카메라가 -Z를 본다)에 있다. 2m 뒤에 벽을 세운다.
	var wall := _add_box(arena, player.global_position + Vector3(0, 1.5, 2.0), Vector3(6, 3, 0.4))
	await _frames(30)
	assert_true(player.camera_length() < 2.0, "벽 앞으로 당긴다: %s" % player.camera_length())
	wall.queue_free()
	await _frames(12)
	assert_true(player.camera_length() < player.config.camera_distance - 0.8, "막힌 것이 풀리면 천천히 되돌린다: %s" % player.camera_length())
	await _frames(150)
	assert_almost_eq(player.camera_length(), player.config.camera_distance, 0.05, "결국 원래 거리로")


func test_combat_pulls_the_camera_back() -> void:
	player.notify_hit(false, player.global_position + Vector3(0, 0, -3), 0.0)
	await _frames(180)
	assert_true(player.in_combat)
	assert_almost_eq(player.camera_length(), player.config.camera_combat_distance, 0.1, "싸우는 중에는 조금 물러난다")


func _add_box(parent: Node3D, center: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.position = center
	parent.add_child(body)
	return body


func _frames(count: int) -> void:
	for i in count:
		await tree.physics_frame


func test_free_view_key_is_held_by_default_and_toggles_by_setting() -> void:
	player.free_view_key(true)
	assert_eq(player.camera_mode, Player.CameraMode.FREE, "누르고 있으면 자유 시점")
	player.free_view_key(false)
	assert_eq(player.camera_mode, Player.CameraMode.THIRD_PERSON, "떼면 기본 시점으로")
	GameSettings.free_view_toggle = true
	player.free_view_key(true)
	player.free_view_key(false)
	assert_eq(player.camera_mode, Player.CameraMode.FREE, "설정을 바꾸면 눌러서 켜고")
	player.free_view_key(true)
	assert_eq(player.camera_mode, Player.CameraMode.THIRD_PERSON, "다시 눌러서 끈다")
	GameSettings.reset_to_defaults()


func test_character_screen_uses_original_camera_poses() -> void:
	# 원작 캐릭터 화면 카메라 자리: 캐릭터 앞 3.5m 높이 1m(시야각 20도), 무기 보기는 앞 2m 높이 0.5m(45도)
	var fx := CharacterFx.new()
	player.body.add_child(fx)
	player.body.fx = fx
	fx.set_camera_poses({
		"overview": [0.0, 1.0, 3.5, 0.0, 0.0, 0.0, 1.0, 20.0],
		"weapon": [0.0, 0.5, 2.0, 0.0, 0.0, 0.0, 1.0, 45.0],
	})
	player.showcase = true
	await _frames(60)
	var model := player.body.model_root().global_transform
	assert_true(player.camera.global_position.distance_to(model * Vector3(0.0, 1.0, 3.5)) < 0.05, "원작 구도 자리에서 비춘다")
	assert_almost_eq(player.camera.fov, 20.0, 0.5, "원작 구도의 시야각")
	assert_true(player.camera.global_basis.z.dot(model.basis.z.normalized()) > 0.99, "캐릭터 쪽을 본다")
	player.showcase_weapon = true
	await _frames(60)
	assert_true(player.camera.global_position.distance_to(model * Vector3(0.0, 0.5, 2.0)) < 0.05, "무기 보기 구도")
	assert_almost_eq(player.camera.fov, 45.0, 0.5)
	player.showcase_weapon = false
	for i in 8:
		player.zoom(-1)
	await _frames(90)
	var eye := player.body.eye_position()
	assert_almost_eq(player.camera.global_position.distance_to(eye), Player.SHOWCASE_FACE_DISTANCE, 0.05, "휠로 얼굴 앞까지 다가간다")
	player.showcase = false
	await _frames(60)
	assert_almost_eq(player.camera.fov, GameSettings.fov, 0.5, "닫으면 원래 카메라로")


func test_camera_shot_plays_then_returns() -> void:
	# 캐릭터 앞 2m, 높이 1.5m에서 캐릭터 쪽(모델의 -Z)을 보는 컷 0.5초, 끝나면 0.3초 동안 원래 카메라로
	var frames: Array = []
	for i in 31:
		frames.append_array([0.0, 1.5, 2.0, 0.0, 0.0, 0.0, 1.0, 25.0])
	player.play_camera_shot({"duration": 0.5, "easeOut": 0.3, "follow": [true, true], "rate": 60.0, "frames": frames})
	assert_true(player.cinematic)
	await _frames(15)
	var expected := player.body.model_root().global_transform * Vector3(0.0, 1.5, 2.0)
	assert_true(player.camera.global_position.distance_to(expected) < 0.05, "컷의 카메라 자리에서 비춘다")
	assert_almost_eq(player.camera.fov, 25.0, 0.5, "컷의 시야각")
	await _frames(60)
	assert_false(player.cinematic, "컷이 끝나면 원래 카메라로 돌아온다")
	assert_almost_eq(player.camera_length(), player.config.camera_distance, 0.1)


func test_camera_shot_without_ease_out_restores_camera_direction() -> void:
	# 원작 자료의 되돌아오기 시간이 0인 컷(아크라이트 궁극기): 끝난 뒤 카메라가 컷의 마지막 방향(위에서 내려다봄)으로
	# 남지 않고, 원래 카메라 방향과 시야각으로 돌아온다.
	var frames: Array = []
	var down := Quaternion(Vector3.RIGHT, deg_to_rad(-50.0))
	for i in 31:
		frames.append_array([0.0, 6.0, -5.0, down.x, down.y, down.z, down.w, 70.0])
	player.play_camera_shot({"duration": 0.5, "easeOut": 0, "follow": [true, true], "rate": 60.0, "frames": frames})
	await _frames(90)
	assert_false(player.cinematic)
	var tilt := player.camera.global_basis.z.angle_to(player.camera_rig.global_basis.z)
	assert_true(tilt < deg_to_rad(1.0), "카메라가 원래 방향으로: %.1f도" % rad_to_deg(tilt))
	assert_almost_eq(player.camera.fov, GameSettings.fov, 1.0, "시야각도 원래대로")
