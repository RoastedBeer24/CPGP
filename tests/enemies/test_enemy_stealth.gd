extends TestCase
## 잠입: 시야 원뿔, 웅크림, 소리, 경계 단계와 전파, 순찰, 제압, 몸 옮기기·숨기기, 시체 발견.
## 플레이어는 원점에서 -Z를 본다. 적의 yaw가 0이면 -Z(플레이어 반대쪽)를, PI면 +Z(플레이어 쪽)를 본다.

const PLAYER_SCENE := preload("res://src/player/player.tscn")
const ENEMY_SCENE := preload("res://src/enemies/enemy.tscn")

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
	player = PLAYER_SCENE.instantiate()
	player.use_device_input = false
	intent = PlayerIntent.new()
	player.intent_override = intent
	add_child_autofree(player)
	await _frames(2)


# ---- 시야 ----

func test_enemy_facing_away_does_not_see_player() -> void:
	var enemy := await _spawn_enemy(Vector3(0, 0, -8), 0.0)
	await _frames(180)
	assert_eq(enemy.alert, Enemy.Alert.UNAWARE)
	assert_almost_eq(enemy.detection, 0.0, 0.001)


func test_standing_right_behind_enemy_is_not_noticed() -> void:
	# 제압 거리(1.8m) 안까지 뒤로 다가가도 들키지 않아야 뒤에서 제압할 수 있다.
	var enemy := await _spawn_enemy(Vector3(0, 0, -1.2), 0.0)
	await _frames(120)
	assert_eq(enemy.alert, Enemy.Alert.UNAWARE)
	assert_almost_eq(enemy.detection, 0.0, 0.001)


func test_detection_goes_through_suspicious_before_combat() -> void:
	var enemy := await _spawn_enemy(Vector3(0, 0, -14), PI)
	var seen: Array[Enemy.Alert] = []
	for i in 400:
		await _frames(1)
		if seen.is_empty() or seen[-1] != enemy.alert:
			seen.append(enemy.alert)
		if enemy.alert == Enemy.Alert.COMBAT:
			break
	assert_eq(seen, [Enemy.Alert.UNAWARE, Enemy.Alert.SUSPICIOUS, Enemy.Alert.COMBAT] as Array[Enemy.Alert])


func test_crouching_halves_how_fast_enemy_notices() -> void:
	var data := _guard_data()
	data.detect_rate = 0.2  # 둘 다 게이지가 다 차기 전에 비교하려고 느리게 한다
	data.suspicion_threshold = 2.0  # 의심 상태로 바뀌어 속도 배율이 달라지지 않게 한다
	var standing_enemy := await _spawn_enemy(Vector3(0, 0, -12), PI, data)
	await _frames(60)
	var standing := standing_enemy.detection
	standing_enemy.queue_free()

	intent.crouch_pressed = true
	await _frames(30)
	assert_true(player.crouched)
	var crouch_enemy := await _spawn_enemy(Vector3(0, 0, -12), PI, data)
	await _frames(60)
	assert_almost_eq(crouch_enemy.detection, standing * data.crouch_visibility, standing * 0.15,
		"웅크리면 절반 속도: 서서 %s, 웅크려 %s" % [standing, crouch_enemy.detection])


# ---- 소리 ----

func test_gunshot_sends_enemy_to_search() -> void:
	var enemy := await _spawn_enemy(Vector3(0, 0, -20), 0.0)
	player.head.rotation.x = 1.2  # 하늘에 쏜다
	intent.fire_pressed = true
	await _frames(3)
	assert_eq(enemy.alert, Enemy.Alert.SEARCHING)
	var start := enemy.global_position.distance_to(player.global_position)
	await _frames(120)
	assert_true(enemy.global_position.distance_to(player.global_position) < start - 3.0, "총성이 난 쪽으로 간다")


func test_sprinting_behind_enemy_is_heard() -> void:
	var enemy := await _spawn_enemy(Vector3(0, 0, -8), 0.0)
	intent.move = Vector2(0, 1)
	intent.sprint = true
	# 출발 직후는 걷는 속도라 첫 발소리는 작다. 달리는 발소리가 한 번 날 때까지 기다린다.
	await _frames(45)
	assert_eq(enemy.alert, Enemy.Alert.SUSPICIOUS, "달리는 발소리를 듣고 의심")


func test_crouch_walking_behind_enemy_is_silent() -> void:
	intent.crouch_pressed = true
	await _frames(20)
	var enemy := await _spawn_enemy(Vector3(0, 0, -7), 0.0)
	intent.move = Vector2(0, 1)
	await _frames(60)
	assert_eq(enemy.alert, Enemy.Alert.UNAWARE, "웅크려 걸으면 들키지 않음")


# ---- 경계 단계 ----

func test_combat_alerts_nearby_allies() -> void:
	var spotter := await _spawn_enemy(Vector3(0, 0, -8), PI)
	var ally := await _spawn_enemy(Vector3(12, 0, -20), PI * 0.5)
	var far := await _spawn_enemy(Vector3(-35, 0, -30), 0.0)
	spotter._enter_combat(player)
	await _frames(2)
	assert_eq(ally.alert, Enemy.Alert.SEARCHING, "근처 동료는 수색하러 온다")
	assert_eq(far.alert, Enemy.Alert.UNAWARE, "멀리 있는 적은 모른다")


func test_lost_target_leads_to_search_then_calm() -> void:
	var data := _guard_data()
	data.lose_target_time = 0.5
	data.search_time = 2.0
	var enemy := await _spawn_enemy(Vector3(0, 0, -10), PI, data)
	enemy._enter_combat(player)
	# 적이 볼 수 없는 곳(벽 뒤)으로 옮긴다.
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(10, 4, 0.5)
	shape.shape = box
	wall.add_child(shape)
	add_child_autofree(wall)
	wall.global_position = Vector3(0, 2, -5)
	await _frames(45)
	assert_eq(enemy.alert, Enemy.Alert.SEARCHING, "놓치면 수색")
	await _frames(150)
	assert_eq(enemy.alert, Enemy.Alert.UNAWARE, "수색이 끝나면 경계를 푼다")


func test_patrol_walks_between_waypoints() -> void:
	var route := Node3D.new()
	add_child_autofree(route)
	for point: Vector3 in [Vector3(-20, 0, -20), Vector3(-20, 0, -28)]:
		var marker := Marker3D.new()
		marker.position = point
		route.add_child(marker)
	var enemy := ENEMY_SCENE.instantiate() as Enemy
	enemy.data = _guard_data()
	enemy.position = Vector3(-20, 0, -20)
	enemy.patrol_route = NodePath("../" + String(route.name))
	add_child_autofree(enemy)
	var closest := INF
	for i in 400:
		await _frames(1)
		closest = minf(closest, enemy.global_position.distance_to(Vector3(-20, 0, -28)))
	assert_true(closest < 1.0, "두 번째 지점까지 걸어간다: %s" % closest)
	assert_eq(enemy.alert, Enemy.Alert.UNAWARE)


# ---- 제압과 몸 ----

func test_takedown_from_behind() -> void:
	var enemy := await _spawn_enemy(Vector3(0, 0, -1.3), 0.0)
	await _frames(2)
	assert_eq(player.interactor.focus_action, Interactor.Action.TAKEDOWN)
	assert_eq(player.interactor.prompt, "F: 제압")
	player.interactor.interact()
	await _frames(2)
	assert_eq(enemy.condition, Enemy.Condition.KNOCKED_OUT)
	assert_true(enemy.is_visible_body())


func test_no_takedown_in_combat() -> void:
	var enemy := await _spawn_enemy(Vector3(0, 0, -1.3), PI)
	enemy._enter_combat(player)
	await _frames(2)
	assert_ne(player.interactor.focus_action, Interactor.Action.TAKEDOWN)
	assert_false(enemy.try_takedown(player))
	assert_eq(enemy.condition, Enemy.Condition.ACTIVE)


func test_carry_body_and_stash_it_in_container() -> void:
	var spot := HideSpot.new()
	spot.position = Vector3(0, 0, -6)
	add_child_autofree(spot)
	var enemy := await _spawn_enemy(Vector3(0, 0, -1.3), 0.0)
	enemy.try_takedown(player)
	await _frames(2)
	assert_eq(player.interactor.focus_action, Interactor.Action.PICK_UP)
	player.interactor.interact()
	await _frames(2)
	assert_eq(player.interactor.carrying, enemy, "몸을 듦")
	assert_eq(enemy.carrier_peer, player.get_multiplayer_authority())

	intent.move = Vector2(0, 1)
	await _frames(20)
	assert_true(player.horizontal_speed() < player.config.walk_speed * 0.7, "들고 있으면 느림: %s" % player.horizontal_speed())
	assert_true(enemy.global_position.distance_to(player.global_position) < 1.5, "몸이 플레이어를 따라온다")
	await _frames(100)
	intent.move = Vector2.ZERO
	await _frames(5)
	assert_eq(player.interactor.focus_action, Interactor.Action.STASH)
	player.interactor.interact()
	await _frames(2)
	assert_true(enemy.stashed, "컨테이너에 숨김")
	assert_eq(player.interactor.carrying, null)
	assert_false(enemy.is_visible_body())


func test_carrying_blocks_attacks() -> void:
	var enemy := await _spawn_enemy(Vector3(0, 0, -1.3), 0.0)
	enemy.try_takedown(player)
	await _frames(2)
	player.interactor.interact()
	await _frames(2)
	var ammo := player.weapons.ammo_in_magazine()
	intent.fire_pressed = true
	await _frames(2)
	assert_eq(player.weapons.ammo_in_magazine(), ammo, "몸을 들고는 쏠 수 없음")


func test_guard_who_sees_a_body_searches_but_not_a_hidden_one() -> void:
	var victim := await _spawn_enemy(Vector3(10, 0, -10), 0.0)
	victim.try_takedown(player)  # 거리 밖이라 실패해야 함
	assert_eq(victim.condition, Enemy.Condition.ACTIVE)
	victim._go_down(Enemy.Condition.KNOCKED_OUT)
	victim.stash()
	var watcher := await _spawn_enemy(Vector3(10, 0, -18), PI)
	await _frames(30)
	assert_eq(watcher.alert, Enemy.Alert.UNAWARE, "숨긴 몸은 보이지 않는다")

	victim.stashed = false
	await _frames(30)
	assert_eq(watcher.alert, Enemy.Alert.SEARCHING, "바닥의 몸을 보면 수색")
	assert_true(victim.body_discovered)


func _spawn_enemy(position: Vector3, yaw: float, data: EnemyData = null) -> Enemy:
	var enemy := ENEMY_SCENE.instantiate() as Enemy
	enemy.data = data if data != null else _guard_data()
	enemy.position = position
	enemy.rotation.y = yaw
	add_child_autofree(enemy)
	await _frames(2)
	return enemy


func _guard_data() -> EnemyData:
	return (load("res://data/enemies/guard.tres") as EnemyData).duplicate() as EnemyData


func _frames(count: int) -> void:
	for i in count:
		await tree.physics_frame
