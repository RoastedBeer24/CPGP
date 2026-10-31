extends TestCase
## 플레이어 이동을 실제 물리로 시뮬레이션해서 확인한다: 카메라 기준 이동, 몸 돌리기, 점프, 회피, 질주.

const PLAYER_SCENE := preload("res://src/player/player.tscn")

var player: Player
var intent: PlayerIntent


func before_each() -> void:
	var arena := Node3D.new()
	_add_box(arena, Vector3(0, -0.5, 0), Vector3(60, 1, 60))
	add_child_autofree(arena)
	player = PLAYER_SCENE.instantiate()
	player.use_device_input = false
	intent = PlayerIntent.new()
	player.intent_override = intent
	add_child_autofree(player)
	await _frames(2)


func test_runs_at_run_speed() -> void:
	intent.move = Vector2(0, 1)
	await _frames(40)
	assert_almost_eq(player.horizontal_speed(), player.config.run_speed, 0.05)


func test_moves_relative_to_camera_and_turns_toward_movement() -> void:
	# 카메라를 오른쪽(시계 방향)으로 90도 돌리고 앞으로 가면 세상의 +X로 간다.
	player.look(Vector2(PI * 0.5, 0.0))
	intent.move = Vector2(0, 1)
	await _frames(40)
	var direction := Vector3(player.velocity.x, 0.0, player.velocity.z).normalized()
	assert_true(direction.dot(Vector3.RIGHT) > 0.98, "카메라가 보는 쪽으로 간다: %s" % direction)
	assert_true(player.facing().dot(Vector3.RIGHT) > 0.98, "몸이 가는 쪽을 본다: %s" % player.facing())


func test_camera_turns_without_turning_body() -> void:
	var before := player.facing()
	player.look(Vector2(1.0, 0.2))
	await _frames(2)
	assert_true(player.facing().is_equal_approx(before), "카메라만 돈다")
	assert_true(player.camera_pitch < deg_to_rad(-12.0), "아래로 내려다본다")


func test_jump_leaves_ground_and_lands() -> void:
	await _frames(5)
	intent.jump_pressed = true
	await _frames(10)
	assert_true(player.global_position.y > 0.3, "점프로 떠오름: %s" % player.global_position.y)
	await _frames(60)
	assert_true(player.is_on_floor(), "착지")
	assert_eq(player.jump_count, 1)


func test_dodge_dashes_with_invulnerability() -> void:
	await _frames(5)
	intent.move = Vector2(1, 0)
	await _frames(1)
	var start := player.global_position
	intent.dodge_pressed = true
	await _frames(2)
	assert_eq(player.state, Player.State.DODGE)
	assert_true(player.invulnerable, "회피 앞부분은 무적")
	intent.move = Vector2.ZERO
	await _frames(20)
	assert_false(player.invulnerable, "회피가 끝나면 무적도 끝난다")
	assert_true(player.global_position.distance_to(start) > 2.5, "회피로 내달린다: %s" % player.global_position.distance_to(start))
	assert_false(player.dodge_back)


func test_dodge_without_input_steps_back() -> void:
	await _frames(5)
	var start := player.global_position
	intent.dodge_pressed = true
	await _frames(20)
	var moved := player.global_position - start
	assert_true(player.dodge_back, "입력이 없으면 뒤로 물러난다")
	assert_true(moved.dot(Vector3.BACK) > 1.5, "몸 뒤쪽(+Z)으로: %s" % moved)


func test_holding_dodge_after_dodge_sprints() -> void:
	await _frames(5)
	intent.move = Vector2(0, 1)
	intent.dodge_pressed = true
	intent.dodge_held = true
	await _frames(60)
	assert_true(player.is_sprinting(), "회피 키를 누르고 있으면 질주")
	assert_almost_eq(player.horizontal_speed(), player.config.sprint_speed, 0.1)
	intent.dodge_held = false
	await _frames(30)
	assert_false(player.is_sprinting(), "놓으면 다시 달리기")
	assert_almost_eq(player.horizontal_speed(), player.config.run_speed, 0.1)


func test_sprint_key_sprints_without_dodging() -> void:
	intent.move = Vector2(0, 1)
	intent.sprint_held = true
	await _frames(40)
	assert_true(player.is_sprinting(), "질주 키를 누르고 있으면 질주")
	assert_eq(player.dodge_count, 0, "회피는 나가지 않는다")
	assert_almost_eq(player.horizontal_speed(), player.config.sprint_speed, 0.1)
	intent.sprint_held = false
	await _frames(30)
	assert_false(player.is_sprinting(), "떼면 달리기")


func test_zoom_is_clamped_in_free_view() -> void:
	player.toggle_free_view()
	for i in 40:
		player.zoom(1)
	assert_almost_eq(player.camera_distance, player.config.camera_max_distance, 0.001)
	for i in 60:
		player.zoom(-1)
	assert_almost_eq(player.camera_distance, player.config.camera_min_distance, 0.001)


func _add_box(parent: Node3D, center: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.position = center
	parent.add_child(body)


func _frames(count: int) -> void:
	for i in count:
		await tree.physics_frame
