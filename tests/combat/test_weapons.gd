extends TestCase
## 플레이어 무기를 실제 물리로 확인한다. 혼자 하기(오프라인 피어)라서 이 프로세스가 호스트다.
## 플레이어는 원점에서 -Z를 보고 서 있고, 허수아비를 앞에 세운다.

const PLAYER_SCENE := preload("res://src/player/player.tscn")
const DUMMY_SCENE := preload("res://src/enemies/training_dummy.tscn")

var player: Player
var intent: PlayerIntent
var dummy: TrainingDummy


func before_each() -> void:
	var arena := Node3D.new()
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(80, 1, 80)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position.y = -0.5
	arena.add_child(floor_body)
	add_child_autofree(arena)

	player = PLAYER_SCENE.instantiate()
	player.use_device_input = false
	intent = PlayerIntent.new()
	player.intent_override = intent
	add_child_autofree(player)

	dummy = DUMMY_SCENE.instantiate()
	dummy.respawn_delay = 100.0
	add_child_autofree(dummy)
	await _place_dummy(8.0)


func test_pistol_body_shot_deals_base_damage() -> void:
	_aim_at_height(0.9, 8.0)
	await _fire_once()
	var pistol := player.weapons.current_weapon()
	assert_almost_eq(dummy.health.current, 100.0 - pistol.damage, 0.01)


func test_headshot_multiplies_damage() -> void:
	_aim_at_height(1.6, 8.0)
	await _fire_once()
	var pistol := player.weapons.current_weapon()
	assert_almost_eq(dummy.health.current, 100.0 - pistol.damage * pistol.headshot_multiplier, 0.01)


func test_hit_is_confirmed_to_shooter() -> void:
	var hits: Array[float] = []
	player.weapons.hit_confirmed.connect(
		func(_p: Vector3, amount: float, _h: bool, _k: bool) -> void: hits.append(amount)
	)
	_aim_at_height(0.9, 8.0)
	await _fire_once()
	assert_eq(hits.size(), 1)


func test_fire_rate_is_limited() -> void:
	var magazine := player.weapons.ammo_in_magazine()
	for i in 5:
		intent.fire_pressed = true
		await _frames(1)
	assert_eq(player.weapons.ammo_in_magazine(), magazine - 1, "쿨다운 중에는 발사되지 않음")


func test_magazine_empties_and_reload_refills() -> void:
	_aim_at_height(5.0, 8.0)  # 허공에 쏜다
	var pistol := player.weapons.current_weapon()
	for i in pistol.magazine_size + 3:
		await _fire_once()
	assert_eq(player.weapons.ammo_in_magazine(), 0)
	intent.reload_pressed = true
	await _frames(2)
	assert_true(player.weapons.reloading)
	await _frames(ceili(pistol.reload_time * 60.0) + 2)
	assert_eq(player.weapons.ammo_in_magazine(), pistol.magazine_size)


func test_empty_magazine_reloads_automatically_on_fire() -> void:
	_aim_at_height(5.0, 8.0)
	var pistol := player.weapons.current_weapon()
	for i in pistol.magazine_size:
		await _fire_once()
	await _fire_once()
	assert_true(player.weapons.reloading, "빈 탄창으로 쏘면 재장전")


func test_shotgun_damage_falls_off_with_distance() -> void:
	intent.weapon_slot = 2
	await _frames(20)
	assert_eq(player.weapons.current_weapon().id, &"shotgun")
	_aim_at_height(1.1, 4.0)
	await _place_dummy(4.0)
	await _fire_once()
	var near_damage := 100.0 - dummy.health.current

	dummy.health.revive()
	await _place_dummy(22.0)
	player.head.rotation.x = 0.0
	_aim_at_height(1.1, 22.0)
	await _frames(50)
	await _fire_once()
	var far_damage := 100.0 - dummy.health.current
	assert_true(near_damage > 0.0, "가까이서 맞아야 함")
	assert_true(far_damage < near_damage * 0.6, "멀면 피해가 크게 줄어야 함: %s vs %s" % [near_damage, far_damage])


func test_blade_hits_only_within_reach() -> void:
	intent.weapon_slot = 3
	await _frames(20)
	await _place_dummy(1.8)
	await _fire_once()
	var blade := player.weapons.current_weapon()
	assert_almost_eq(dummy.health.current, 100.0 - blade.damage, 0.01, "가까이 있으면 벤다")

	dummy.health.revive()
	await _place_dummy(4.5)
	await _frames(40)
	await _fire_once()
	assert_eq(dummy.health.current, 100.0, "닿지 않으면 피해 없음")


func test_recoil_kicks_view_up_then_recovers_partly() -> void:
	var before := player.head.rotation.x
	intent.fire_pressed = true
	await _frames(1)
	var kicked := player.head.rotation.x
	assert_true(kicked > before, "반동으로 시점이 올라가야 함")
	await _frames(30)
	assert_true(player.head.rotation.x < kicked and player.head.rotation.x > before, "일부만 되돌아옴")


func test_aiming_narrows_fov_and_slows_movement() -> void:
	intent.aim_held = true
	intent.move = Vector2(0, -1)
	await _frames(60)
	assert_true(player.weapons.aiming)
	assert_almost_eq(player.camera.fov, player.weapons.current_weapon().aim_fov, 1.0)
	assert_almost_eq(player.horizontal_speed(), player.config.walk_speed * player.config.aim_speed_multiplier, 0.05)


func test_dodge_dashes_and_has_cooldown() -> void:
	intent.dodge = Vector2(1, 0)
	await _frames(20)
	var first := player.global_position.x
	assert_true(first > 1.8, "오른쪽으로 빠르게 이동: %s" % first)
	intent.dodge = Vector2(1, 0)
	await _frames(20)
	assert_true(player.global_position.x - first < 0.5, "쿨다운 중에는 회피 불가")


func test_weapon_switching() -> void:
	intent.weapon_slot = 2
	await _frames(1)
	assert_eq(player.weapons.current_weapon().id, &"shotgun")
	intent.weapon_cycle = 1
	await _frames(1)
	assert_eq(player.weapons.current_weapon().id, &"arm_blade")
	intent.weapon_cycle = 1
	await _frames(1)
	assert_eq(player.weapons.current_weapon().id, &"pistol", "끝에서 처음으로 돌아감")


func test_dead_player_cannot_attack() -> void:
	player.health.apply_damage(DamageInfo.create(1000.0, 0, Vector3.ZERO, &"test", false))
	_aim_at_height(0.9, 8.0)
	await _fire_once()
	assert_eq(dummy.health.current, 100.0)


func _place_dummy(distance: float) -> void:
	dummy.global_position = Vector3(0, 0, -distance)
	await _frames(2)


## 눈높이(1.6m)에서 distance만큼 떨어진 곳의 height 높이를 보도록 상하 시점을 맞춘다.
func _aim_at_height(height: float, distance: float) -> void:
	var pitch := atan2(height - player.config.stand_eye_height, distance)
	player.head.rotation.x = pitch


func _fire_once() -> void:
	intent.fire_pressed = true
	intent.fire_held = true
	await _frames(1)
	intent.fire_held = false
	var weapon := player.weapons.current_weapon()
	await _frames(ceili(weapon.fire_interval * 60.0) + 1)


func _frames(count: int) -> void:
	for i in count:
		await tree.physics_frame
