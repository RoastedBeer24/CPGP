extends TestCase
## 단순한 적(경비병)과 플레이어 사망·부활을 확인한다.

const PLAYER_SCENE := preload("res://src/player/player.tscn")
const GRUNT_SCENE := preload("res://src/enemies/grunt.tscn")
const SESSION_SCENE := preload("res://src/net/session.tscn")

var player: Player
var intent: PlayerIntent
var grunt: Grunt


func before_each() -> void:
	add_child_autofree(_make_floor())
	player = PLAYER_SCENE.instantiate()
	player.use_device_input = false
	intent = PlayerIntent.new()
	player.intent_override = intent
	add_child_autofree(player)
	grunt = GRUNT_SCENE.instantiate()
	grunt.spread_degrees = 0.0
	add_child_autofree(grunt)
	grunt.global_position = Vector3(0, 0, -10)
	# 플레이어와 반대쪽을 보고 시작한다.
	grunt.rotation.y = PI
	await _frames(2)


func test_grunt_turns_and_shoots_visible_player() -> void:
	await _frames(150)
	assert_eq(grunt.target, player)
	assert_true(player.health.current < player.health.max_health, "맞아야 함: %s" % player.health.current)


func test_grunt_does_not_shoot_through_walls() -> void:
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(6, 4, 0.5)
	shape.shape = box
	wall.add_child(shape)
	add_child_autofree(wall)
	wall.global_position = Vector3(0, 2, -5)
	await _frames(150)
	assert_eq(grunt.target, null)
	assert_eq(player.health.current, player.health.max_health)


func test_grunt_ignores_players_out_of_range() -> void:
	grunt.sight_range = 8.0
	await _frames(150)
	assert_eq(player.health.current, player.health.max_health)


func test_grunt_dies_and_stops_shooting() -> void:
	grunt.health.apply_damage(DamageInfo.create(1000.0, 1, Vector3.ZERO, &"test", false))
	await _frames(150)
	assert_false(grunt.health.is_alive())
	assert_eq(player.health.current, player.health.max_health)


func test_player_can_kill_grunt_with_pistol() -> void:
	for i in 10:
		# 반동과 밀림을 없애려고 매번 머리를 다시 겨눈다. 퍼짐(0.8도)은 머리 크기 안에 들어온다.
		_aim(player, grunt.global_position + Vector3.UP * Grunt.EYE_HEIGHT)
		intent.fire_pressed = true
		await _frames(16)
		if not grunt.health.is_alive():
			break
	assert_false(grunt.health.is_alive(), "권총 머리 맞히기로 쓰러뜨릴 수 있어야 함")


func test_player_respawns_after_death_in_session() -> void:
	var session := SESSION_SCENE.instantiate() as Session
	session.use_device_input = false
	add_child_autofree(session)
	session.start_single()
	await _frames(2)
	var own := session.get_local_player()
	own.global_position = Vector3(5, 0, 5)
	own.health.apply_damage(DamageInfo.create(1000.0, 0, Vector3.ZERO, &"test", false))
	assert_false(own.health.is_alive())
	await _frames(ceili(Session.RESPAWN_DELAY * 60.0) + 5)
	assert_true(own.health.is_alive(), "되살아나야 함")
	assert_eq(own.health.current, own.health.max_health)
	assert_true(own.global_position.distance_to(Vector3(5, 0, 5)) > 1.0, "시작 지점으로 옮겨져야 함")
	session.leave()


func _aim(shooter: Player, target: Vector3) -> void:
	var eye := shooter.camera.global_position
	var flat := Vector3(target.x - eye.x, 0.0, target.z - eye.z)
	shooter.rotation.y = atan2(-flat.x, -flat.z)
	shooter.head.rotation.x = atan2(target.y - eye.y, flat.length())


func _make_floor() -> Node3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(80, 1, 80)
	shape.shape = box
	body.add_child(shape)
	body.position.y = -0.5
	return body


func _frames(count: int) -> void:
	for i in count:
		await tree.physics_frame
