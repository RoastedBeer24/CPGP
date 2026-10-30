extends TestCase
## 해킹: 스캔으로 대상 고르기, RAM, 퀵핵(주의 분산, 과열, 무기 오작동), 적 넷러너의 역해킹.
## 플레이어는 원점에서 -Z를 본다. 적의 yaw가 0이면 -Z(플레이어 반대쪽)를, PI면 플레이어 쪽을 본다.

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


func test_scan_focuses_target_at_crosshair() -> void:
	var ahead := await _spawn_enemy(Vector3(0, 0, -10), 0.0)
	await _spawn_enemy(Vector3(6, 0, -10), 0.0)
	intent.scan_held = true
	await _frames(2)
	assert_true(player.cyberdeck.scanning)
	assert_eq(player.cyberdeck.focus, ahead.hackable, "조준점에 있는 적")
	intent.scan_held = false
	await _frames(2)
	assert_eq(player.cyberdeck.focus, null, "스캔을 끄면 대상도 없음")


func test_scanning_blocks_shooting_and_number_keys_pick_hacks() -> void:
	var enemy := await _spawn_enemy(Vector3(0, 0, -10), 0.0)
	var ammo := player.weapons.ammo_in_magazine()
	intent.scan_held = true
	intent.fire_pressed = true
	await _frames(2)
	assert_eq(player.weapons.ammo_in_magazine(), ammo, "스캔 중에는 쏘지 않는다")
	intent.weapon_slot = 3
	await _frames(2)
	assert_eq(player.weapons.current_index, 0, "1~3 키가 무기를 바꾸지 않는다")
	assert_true(player.cyberdeck.is_uploading(), "세 번째 퀵핵(무기 오작동)을 올린다")
	assert_almost_eq(player.cyberdeck.ram, player.cyberdeck.max_ram - 3.0, 0.2, "RAM 3을 쓴다")
	await _frames(70)
	assert_true(enemy.is_weapon_glitched())


func test_not_enough_ram_refuses_hack() -> void:
	await _spawn_enemy(Vector3(0, 0, -10), 0.0)
	player.cyberdeck.ram = 1.0
	intent.scan_held = true
	await _frames(2)
	intent.weapon_slot = 2  # 과열, RAM 4
	await _frames(2)
	assert_false(player.cyberdeck.is_uploading())


func test_ram_regenerates() -> void:
	player.cyberdeck.ram = 0.0
	await _frames(120)
	assert_almost_eq(player.cyberdeck.ram, 1.0, 0.1, "초당 0.5")


func test_overheat_ignores_armor_and_does_not_reveal_player() -> void:
	var heavy := await _spawn_enemy(Vector3(0, 0, -10), 0.0, load("res://data/enemies/heavy.tres") as EnemyData)
	var hack := player.cyberdeck.hack_by_id(&"overheat")
	heavy.apply_quickhack(hack, player)
	assert_eq(heavy.alert, Enemy.Alert.SEARCHING, "누가 했는지 모르고 수색만 한다")
	assert_eq(heavy.target, null)
	await _frames(ceili(hack.duration * 60.0) + 10)
	var lost := heavy.data.max_health - heavy.health.current
	assert_almost_eq(lost, hack.damage_per_second * hack.duration, 2.0, "장갑 80이어도 그대로 들어간다")


func test_distract_lures_enemy_away_from_hacker() -> void:
	var enemy := await _spawn_enemy(Vector3(0, 0, -10), 0.0)
	enemy.apply_quickhack(player.cyberdeck.hack_by_id(&"distract"), player)
	assert_eq(enemy.alert, Enemy.Alert.SUSPICIOUS)
	await _frames(240)
	assert_true(enemy.global_position.z < -12.0, "해커에게서 멀어진다: %s" % enemy.global_position)


func test_weapon_glitch_stops_shooting() -> void:
	var data := (load("res://data/enemies/guard.tres") as EnemyData).duplicate() as EnemyData
	data.spread_degrees = 0.0
	var enemy := await _spawn_enemy(Vector3(0, 0, -10), PI, data)
	enemy._enter_combat(player)
	enemy.apply_quickhack(player.cyberdeck.hack_by_id(&"weapon_glitch"), player)
	await _frames(300)
	assert_eq(player.health.current, player.health.max_health, "오작동 동안은 맞지 않는다")
	await _frames(400)
	assert_true(player.health.current < player.health.max_health, "끝나면 다시 쏜다")


func test_netrunner_reverse_hacks_player() -> void:
	var netrunner := await _spawn_enemy(Vector3(0, 0, -12), PI, load("res://data/enemies/netrunner.tres") as EnemyData)
	netrunner._enter_combat(player)
	await _frames(120)
	assert_true(player.cyberdeck.incoming_progress > 0.3, "역해킹 진행이 보인다: %s" % player.cyberdeck.incoming_progress)
	assert_eq(player.health.current, player.health.max_health, "올리는 동안은 피해가 없다")
	await _frames(240)
	assert_true(player.health.current < player.health.max_health, "끝나면 화상 피해")


func test_hitting_netrunner_interrupts_reverse_hack() -> void:
	var netrunner := await _spawn_enemy(Vector3(0, 0, -12), PI, load("res://data/enemies/netrunner.tres") as EnemyData)
	netrunner._enter_combat(player)
	await _frames(150)
	assert_true(player.cyberdeck.incoming_progress > 0.4)
	netrunner.health.apply_damage(DamageInfo.create(5.0, player.get_multiplayer_authority(), Vector3.ZERO, &"test", false))
	await _frames(2)
	assert_true(player.cyberdeck.incoming_progress < 0.1, "맞으면 처음부터: %s" % player.cyberdeck.incoming_progress)


func _spawn_enemy(position: Vector3, yaw: float, data: EnemyData = null) -> Enemy:
	var enemy := ENEMY_SCENE.instantiate() as Enemy
	enemy.data = data if data != null else (load("res://data/enemies/guard.tres") as EnemyData).duplicate() as EnemyData
	enemy.position = position
	enemy.rotation.y = yaw
	add_child_autofree(enemy)
	await _frames(2)
	return enemy


func _frames(count: int) -> void:
	for i in count:
		await tree.physics_frame
