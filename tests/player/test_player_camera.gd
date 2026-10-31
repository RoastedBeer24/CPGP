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
	assert_true(player.camera.global_position.distance_to(player.body.eye_position()) < 0.1, "눈 위치에서 본다")
	assert_true(player.body.first_person(), "내 머리를 숨긴다")
	player.toggle_first_person()
	await _frames(120)
	assert_eq(player.camera_mode, Player.CameraMode.THIRD_PERSON)
	assert_false(player.body.first_person())
	assert_almost_eq(player.camera_length(), player.config.camera_distance, 0.1, "3인칭으로 돌아간다")


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
