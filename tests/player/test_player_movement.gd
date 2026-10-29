extends TestCase
## 플레이어 이동을 실제 물리로 시뮬레이션해서 확인한다.
## 시험장: 넓은 바닥, 앞쪽(-Z) 4m에 높이 1.5m 턱, 오른쪽(+X) 8m에 천장 높이 1.3m 터널.

const PLAYER_SCENE := preload("res://src/player/player.tscn")
const LEDGE_HEIGHT := 1.5

var player: Player
var intent: PlayerIntent


func before_each() -> void:
	var arena := Node3D.new()
	_add_box(arena, Vector3(0, -0.5, 0), Vector3(60, 1, 60))
	_add_box(arena, Vector3(0, LEDGE_HEIGHT * 0.5, -5), Vector3(6, LEDGE_HEIGHT, 2))
	_add_box(arena, Vector3(8, 1.3 + 0.5, 0), Vector3(3, 1, 6))
	add_child_autofree(arena)

	player = PLAYER_SCENE.instantiate()
	player.use_device_input = false
	intent = PlayerIntent.new()
	player.intent_override = intent
	add_child_autofree(player)


func test_walk_reaches_walk_speed() -> void:
	intent.move = Vector2(0, 1)
	await _frames(45)
	assert_almost_eq(player.horizontal_speed(), player.config.walk_speed, 0.05)
	assert_true(player.global_position.z < -1.5, "앞(-Z)으로 이동해야 함: %s" % player.global_position)


func test_sprint_is_faster_than_walk() -> void:
	player.position.z = 20.0
	intent.move = Vector2(0, 1)
	intent.sprint = true
	await _frames(45)
	assert_almost_eq(player.horizontal_speed(), player.config.sprint_speed, 0.05)


func test_stops_without_input() -> void:
	intent.move = Vector2(0, 1)
	await _frames(30)
	intent.move = Vector2.ZERO
	await _frames(20)
	assert_almost_eq(player.horizontal_speed(), 0.0, 0.01)


func test_crouch_toggle_lowers_eyes_and_speed() -> void:
	intent.crouch_pressed = true
	intent.move = Vector2(0, -1)
	await _frames(45)
	assert_true(player.crouched)
	assert_almost_eq(player.head.position.y, player.config.crouch_eye_height, 0.01)
	assert_almost_eq(player.horizontal_speed(), player.config.crouch_speed, 0.05)

	intent.crouch_pressed = true
	await _frames(20)
	assert_false(player.crouched)
	assert_almost_eq(player.head.position.y, player.config.stand_eye_height, 0.01)


func test_jump_reaches_expected_height_and_lands() -> void:
	await _frames(5)
	var start_y := player.global_position.y
	intent.jump_pressed = true
	var peak := start_y
	for i in 60:
		await tree.physics_frame
		peak = maxf(peak, player.global_position.y)
	assert_almost_eq(peak - start_y, player.config.jump_height, 0.1)
	assert_true(player.is_on_floor(), "착지해야 함")


func test_jump_buffer_accepts_early_press() -> void:
	intent.jump_pressed = true
	await _frames(1)
	# 첫 점프 후 착지 직전에 다시 누른다.
	for i in 60:
		await tree.physics_frame
		if player.velocity.y < 0.0 and player.global_position.y < 0.3:
			break
	intent.jump_pressed = true
	var jumped_again := false
	for i in 20:
		await tree.physics_frame
		if player.velocity.y > 1.0:
			jumped_again = true
			break
	assert_true(jumped_again, "착지 직전에 누른 점프가 실행되어야 함")


func test_slide_boosts_speed_then_ends_crouched() -> void:
	player.position.z = 20.0
	intent.move = Vector2(0, 1)
	intent.sprint = true
	await _frames(45)
	intent.sprint = false
	intent.crouch_pressed = true
	await _frames(2)
	assert_eq(player.state, Player.State.SLIDE)
	assert_true(player.horizontal_speed() >= player.config.slide_boost_speed - 0.5, "속도: %s" % player.horizontal_speed())
	await _frames(70)
	assert_ne(player.state, Player.State.SLIDE)
	assert_true(player.crouched, "슬라이딩 후에는 웅크린 자세")


func test_mantle_onto_ledge() -> void:
	player.position.z = -2.5
	await _frames(5)
	intent.move = Vector2(0, 1)
	intent.jump_held = true
	intent.jump_pressed = true
	var mantled := false
	for i in 120:
		await tree.physics_frame
		if player.state == Player.State.MANTLE:
			mantled = true
		if mantled and player.state == Player.State.GROUND:
			break
	assert_true(mantled, "턱 오르기를 시작해야 함")
	assert_almost_eq(player.global_position.y, LEDGE_HEIGHT, 0.1)
	assert_true(player.global_position.z < -4.0, "턱 위에 있어야 함: %s" % player.global_position)


func test_no_mantle_without_forward_input() -> void:
	player.position.z = -2.5
	await _frames(5)
	intent.jump_held = true
	intent.jump_pressed = true
	for i in 60:
		await tree.physics_frame
		assert_ne(player.state, Player.State.MANTLE)
	assert_almost_eq(player.global_position.y, 0.0, 0.05)


func test_cannot_stand_under_low_ceiling() -> void:
	intent.crouch_pressed = true
	await _frames(20)
	player.global_position = Vector3(8, 0, 0)
	await _frames(5)
	intent.crouch_pressed = true
	await _frames(20)
	assert_true(player.crouched, "천장이 낮으면 일어서지 못해야 함")
	assert_false(player.can_stand())


func _frames(count: int) -> void:
	for i in count:
		await tree.physics_frame


func _add_box(parent: Node3D, center: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.position = center
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	parent.add_child(body)
