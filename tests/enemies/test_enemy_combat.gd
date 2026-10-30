extends TestCase
## 적과의 전투: 알아챈 뒤 쏘기, 벽과 거리, 쓰러뜨리기, 중장갑병, 플레이어 사망·부활.
## 플레이어는 원점에서 -Z를 보고 서 있고, 적은 -Z 쪽 10m에서 플레이어를 보고 있다.

const PLAYER_SCENE := preload("res://src/player/player.tscn")
const ENEMY_SCENE := preload("res://src/enemies/enemy.tscn")
const SESSION_SCENE := preload("res://src/net/session.tscn")

var player: Player
var intent: PlayerIntent


func before_each() -> void:
	add_child_autofree(_make_floor())
	player = PLAYER_SCENE.instantiate()
	player.use_device_input = false
	intent = PlayerIntent.new()
	player.intent_override = intent
	add_child_autofree(player)
	await _frames(2)


func test_enemy_notices_then_shoots_visible_player() -> void:
	var enemy := await _spawn_enemy(Vector3(0, 0, -10), PI)
	await _frames(40)
	assert_true(enemy.detection > 0.0, "감지 게이지가 차기 시작")
	assert_true(enemy.alert != Enemy.Alert.COMBAT, "바로 전투에 들어가지 않음")
	await _frames(260)
	assert_eq(enemy.alert, Enemy.Alert.COMBAT)
	assert_eq(enemy.target, player)
	assert_true(player.health.current < player.health.max_health, "맞아야 함: %s" % player.health.current)


func test_enemy_does_not_see_through_walls() -> void:
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(6, 4, 0.5)
	shape.shape = box
	wall.add_child(shape)
	add_child_autofree(wall)
	wall.global_position = Vector3(0, 2, -5)
	var enemy := await _spawn_enemy(Vector3(0, 0, -10), PI)
	await _frames(200)
	assert_eq(enemy.alert, Enemy.Alert.UNAWARE)
	assert_almost_eq(enemy.detection, 0.0, 0.001)
	assert_eq(player.health.current, player.health.max_health)


func test_enemy_ignores_players_out_of_range() -> void:
	var data := (load("res://data/enemies/guard.tres") as EnemyData).duplicate() as EnemyData
	data.sight_range = 8.0
	var enemy := await _spawn_enemy(Vector3(0, 0, -10), PI, data)
	await _frames(200)
	assert_eq(enemy.alert, Enemy.Alert.UNAWARE)
	assert_eq(player.health.current, player.health.max_health)


func test_dead_enemy_stops_and_leaves_body() -> void:
	var enemy := await _spawn_enemy(Vector3(0, 0, -10), PI)
	enemy.health.apply_damage(DamageInfo.create(1000.0, 1, Vector3.ZERO, &"test", false))
	await _frames(150)
	assert_eq(enemy.condition, Enemy.Condition.DEAD)
	assert_true(enemy.is_visible_body())
	assert_eq(player.health.current, player.health.max_health)


func test_shooting_an_unaware_enemy_starts_combat() -> void:
	# 뒤돌아 있는 적을 쏘면 바로 쏜 사람을 알아챈다.
	var enemy := await _spawn_enemy(Vector3(0, 0, -10), 0.0)
	_aim(player, enemy.global_position + Vector3.UP * 1.0)
	intent.fire_pressed = true
	await _frames(3)
	assert_eq(enemy.alert, Enemy.Alert.COMBAT)
	assert_eq(enemy.target, player)


func test_player_can_kill_enemy_with_pistol() -> void:
	var enemy := await _spawn_enemy(Vector3(0, 0, -10), PI)
	for i in 10:
		# 반동과 밀림을 없애려고 매번 머리를 다시 겨눈다. 퍼짐(0.8도)은 머리 크기 안에 들어온다.
		_aim(player, enemy.global_position + Vector3.UP * enemy.data.eye_height)
		intent.fire_pressed = true
		await _frames(16)
		if not enemy.health.is_alive():
			break
	assert_false(enemy.health.is_alive(), "권총 머리 맞히기로 쓰러뜨릴 수 있어야 함")


func test_heavy_takes_much_less_damage() -> void:
	var guard := await _spawn_enemy(Vector3(-2, 0, -10), 0.0)
	var heavy := await _spawn_enemy(Vector3(2, 0, -10), 0.0, load("res://data/enemies/heavy.tres") as EnemyData)
	var hit := func(target: Enemy) -> float:
		var before := target.health.current
		target.health.apply_damage(DamageInfo.create(20.0, 0, Vector3.ZERO, &"test", false))
		return before - target.health.current
	var guard_loss: float = hit.call(guard)
	var heavy_loss: float = hit.call(heavy)
	assert_true(heavy_loss < guard_loss * 0.7, "중장갑병은 장갑으로 피해가 크게 준다: %s vs %s" % [heavy_loss, guard_loss])
	assert_true(heavy.health.max_health > guard.health.max_health)


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


func _spawn_enemy(position: Vector3, yaw: float, data: EnemyData = null) -> Enemy:
	var enemy := ENEMY_SCENE.instantiate() as Enemy
	if data != null:
		enemy.data = data
	else:
		enemy.data = (load("res://data/enemies/guard.tres") as EnemyData).duplicate() as EnemyData
	enemy.data.spread_degrees = 0.0
	enemy.position = position
	enemy.rotation.y = yaw
	add_child_autofree(enemy)
	await _frames(2)
	return enemy


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
