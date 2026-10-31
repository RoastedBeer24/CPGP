extends TestCase
## 적: 쫓아가기, 공격 예고와 판정 시각, 원거리 탄, 움찔과 경직, 쓰러짐.

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


func test_melee_enemy_chases_then_telegraphs_before_hitting() -> void:
	var enemy := _enemy("grunt", Vector3(0, 0, -10))
	var start := enemy.global_position.distance_to(player.global_position)
	var telegraph_seen := false
	var damaged_at_progress := -1.0
	for i in 400:
		await _frames(1)
		var progress := enemy.body.telegraph_progress()
		telegraph_seen = telegraph_seen or progress >= 0.0
		if player.health.current < player.kit.max_health:
			break
	assert_true(enemy.global_position.distance_to(player.global_position) < start - 4.0, "다가온다")
	assert_true(telegraph_seen, "때리기 전에 맞을 자리를 보여 준다")
	assert_true(player.health.current < player.kit.max_health, "예고가 끝나면 맞힌다")


func test_hit_lands_only_after_wind_up() -> void:
	var enemy := _enemy("grunt", Vector3(0, 0, -2.0))
	for i in 120:
		await _frames(1)
		if enemy.state == Enemy.State.WIND_UP:
			break
	assert_eq(enemy.state, Enemy.State.WIND_UP)
	await _frames(int(enemy.current_attack().wind_up * 60.0) - 6)
	assert_eq(player.health.current, player.kit.max_health, "예고 중에는 아직 맞지 않는다")
	await _frames(12)
	assert_true(player.health.current < player.kit.max_health, "예고가 끝나면 맞는다")


func test_shooter_keeps_distance_and_projectile_hits() -> void:
	var enemy := _enemy("shooter", Vector3(0, 0, -6))
	for i in 360:
		await _frames(1)
		if player.health.current < player.kit.max_health:
			break
	assert_true(player.health.current < player.kit.max_health, "원거리 탄에 맞는다")
	assert_true(enemy.global_position.distance_to(player.global_position) > 4.0, "가까이 붙지 않는다")


func test_grunt_flinches_but_heavy_does_not() -> void:
	var grunt := _enemy("grunt", Vector3(-3, 0, -6))
	var heavy := _enemy("heavy", Vector3(3, 0, -6))
	grunt.ai_enabled = false
	heavy.ai_enabled = false
	await _frames(2)
	var hit := HitData.new()
	hit.damage = 0.5
	hit.stagger = 5.0
	grunt.receive_hit(1, hit, 100.0, player.global_position)
	heavy.receive_hit(1, hit, 100.0, player.global_position)
	assert_eq(grunt.state, Enemy.State.HURT, "약탈자는 움찔한다")
	assert_ne(heavy.state, Enemy.State.HURT, "처형자는 버틴다")
	assert_eq(grunt.hurt_count, 1)


func test_full_stagger_gauge_staggers_and_takes_more_damage() -> void:
	var enemy := _enemy("grunt", Vector3(0, 0, -6))
	enemy.ai_enabled = false
	await _frames(2)
	var hit := HitData.new()
	hit.damage = 1.0
	hit.stagger = enemy.data.stagger_max
	var outcome := enemy.receive_hit(1, hit, 100.0, player.global_position)
	assert_true(enemy.is_staggered())
	assert_true(outcome.flags & Player.HIT_BREAK, "경직을 알린다")
	var normal := HitData.new()
	normal.damage = 1.0
	var staggered_hit := enemy.receive_hit(1, normal, 100.0, player.global_position)
	assert_almost_eq(staggered_hit.amount, 100.0 * Enemy.STAGGERED_DAMAGE, 0.01, "경직 중에는 더 아프다")
	await _frames(int(enemy.data.stagger_duration * 60.0) + 5)
	assert_false(enemy.is_staggered(), "시간이 지나면 풀린다")
	assert_eq(enemy.stagger, 0.0, "게이지도 비운다")


func test_crystal_shatter_deals_bonus_damage() -> void:
	var enemy := _enemy("heavy", Vector3(0, 0, -6))
	enemy.ai_enabled = false
	await _frames(2)
	var apply := HitData.new()
	apply.damage = 0.0
	apply.effect = HitData.Effect.APPLY_CRYSTAL
	enemy.receive_hit(1, apply, 100.0, player.global_position)
	assert_true(enemy.has_crystal())
	var shatter := HitData.new()
	shatter.damage = 1.0
	shatter.effect = HitData.Effect.SHATTER_CRYSTAL
	var outcome := enemy.receive_hit(1, shatter, 100.0, player.global_position)
	assert_almost_eq(outcome.amount, 100.0 + 100.0 * Enemy.SHATTER_BONUS, 0.01, "결정을 깨뜨리면 추가 피해")
	assert_true(outcome.flags & Player.HIT_SHATTER)
	assert_false(enemy.has_crystal())


func test_enemy_models_have_every_clip() -> void:
	# 원작 모델이 있으면(이 PC) 적마다 쓰는 동작(서기·이동·맞음·경직·쓰러짐·공격)이 모델에 다 있다.
	var slot := 0
	for file in DirAccess.get_files_at("res://data/enemies"):
		if not file.ends_with(".tres"):
			continue
		var data := load("res://data/enemies/" + file) as EnemyData
		if data.model_file.is_empty():
			continue
		slot += 1
		var enemy := _enemy(file.get_basename(), Vector3(slot * 8.0, 0, -40))
		await _frames(1)
		if not enemy.body.has_model:
			continue
		for role: StringName in [&"idle", &"move", &"hit", &"stun", &"dead"]:
			assert_ne(enemy.body._role_clip(role), &"", "%s: %s 동작" % [data.id, role])
		for attack in data.attacks:
			assert_ne(enemy.body._role_clip(attack.clip), &"", "%s: 공격 %s의 동작 %s" % [data.id, attack.id, attack.clip])
			assert_true(attack.clip_hit >= attack.clip_from, "%s: %s 타격 시각이 시작 시각 뒤" % [data.id, attack.id])


func test_boss_plays_original_sounds() -> void:
	# 로댄은 원작 소리 꾸러미가 있으면(이 PC) 싸움을 걸 때 도발하고, 공격 동작의 재생 위치에 맞춰 소리를 낸다.
	var enemy := _enemy("raider_chief", Vector3(0, 0, -4))
	await _frames(2)
	if enemy.body.fx == null:
		return
	for role: StringName in [&"attack_1", &"attack_2", &"attack_3", &"attack_4", &"cue_engage", &"cue_enrage"]:
		assert_true(enemy.body.fx.has_role(role), "로댄 소리: %s" % role)
	for i in 600:
		await _frames(1)
		if enemy.body.fx.sounds_started() > 1:
			break
	assert_true(enemy.body.fx.sounds_started() > 1, "도발과 공격 소리가 난다: %d" % enemy.body.fx.sounds_started())


func test_attack_curves() -> void:
	var attack := EnemyAttackData.new()
	attack.clip_from = 0.2
	attack.clip_hit = 1.0
	attack.recovery = 1.0
	attack.travel = PackedVector2Array([Vector2(0, 0), Vector2(1, 1), Vector2(2, 3)])
	attack.turn = PackedVector2Array([Vector2(0, 0), Vector2(2, 90)])
	assert_almost_eq(attack.clip_time(0.5, 1.0, false), 0.6, 0.001, "예고 동안 clip_from → clip_hit")
	assert_almost_eq(attack.clip_time(0.3, 1.0, true), 1.3, 0.001, "맞힌 뒤에는 원래 빠르기")
	assert_almost_eq(attack.travel_at(0.5, 2.0), 0.5, 0.001)
	assert_almost_eq(attack.travel_at(2.0, 2.0), 3.0, 0.001)
	assert_almost_eq(attack.turn_at(1.0), 45.0, 0.001)
	attack.lunge = 4.0
	assert_almost_eq(attack.travel_at(2.0, 2.0), 5.0, 0.001, "맞힌 뒤 구간을 lunge 거리로 늘인다")
	assert_almost_eq(attack.travel_at(1.5, 2.0), 3.0, 0.001)
	assert_almost_eq(attack.travel_at(0.5, 2.0), 0.5, 0.001, "맞히기 전은 그대로")


func test_attack_follows_original_travel_without_jumps() -> void:
	# 돌진은 원작 동작처럼 천천히 빨라지며 나아간다. 예전에는 맞는 순간 초속 16m로 한꺼번에 튀어 순간이동처럼 보였다.
	var enemy := _enemy("heavy_captain", Vector3(12, 0, -12))
	enemy.ai_enabled = false
	await _frames(2)
	var attack := enemy.find_attack(&"charge")
	assert_true(not attack.travel.is_empty(), "원작 이동 곡선이 있다")
	var start := enemy.global_position
	enemy._start_attack(attack)
	var largest := 0.0
	var previous := enemy.global_position
	for i in int((enemy.wind_up_time(attack) + attack.recovery) * 60.0) + 10:
		await _frames(1)
		largest = maxf(largest, enemy.global_position.distance_to(previous))
		previous = enemy.global_position
	var end := Enemy._attack_end_time(attack)
	var expected := attack.travel_at(end, end) - attack.travel_at(attack.clip_from, end)
	assert_almost_eq(start.distance_to(enemy.global_position), expected, 0.35, "곡선대로 나아간다")
	assert_true(largest < 0.22, "한 프레임에 튀지 않는다 (가장 크게 %.2fm)" % largest)


func test_knockback_pushes_smoothly() -> void:
	var enemy := _enemy("grunt", Vector3(0, 0, -6))
	enemy.ai_enabled = false
	await _frames(2)
	var start := enemy.global_position
	var hit := HitData.new()
	hit.damage = 0.01
	hit.knockback = 1.0
	enemy.receive_hit(1, hit, 1.0, player.global_position)
	var largest := 0.0
	var previous := enemy.global_position
	for i in 60:
		await _frames(1)
		largest = maxf(largest, enemy.global_position.distance_to(previous))
		previous = enemy.global_position
	var expected := pow(hit.knockback * enemy.data.knockback_scale, 2.0)
	assert_almost_eq(start.distance_to(enemy.global_position), expected, 0.15, "knockback 1이면 1m 밀린다")
	assert_true(largest < 0.09, "확 튀지 않는다 (가장 크게 %.2fm)" % largest)


func test_model_turns_back_smoothly_after_attack() -> void:
	# 원작 모델이 있으면(이 PC): 몸을 크게 돌리는 공격(로댄 돌진)이 끝나도 모델이 휙 돌아가지 않는다.
	var enemy := _enemy("raider_chief", Vector3(-12, 0, -12))
	enemy.ai_enabled = false
	await _frames(2)
	if not enemy.body.has_model:
		return
	var attack := enemy.find_attack(&"charge")
	enemy._start_attack(attack)
	var turned := 0.0
	var largest_back := 0.0
	var previous := 0.0
	for i in int((enemy.wind_up_time(attack) + attack.recovery) * 60.0) + 60:
		await _frames(1)
		var now := enemy.body.model_turn_degrees()
		turned = maxf(turned, absf(now))
		if enemy.state != Enemy.State.WIND_UP and enemy.state != Enemy.State.RECOVER:
			largest_back = maxf(largest_back, absf(wrapf(now - previous, -180.0, 180.0)))
		previous = now
	assert_true(turned > 30.0, "공격 중에 원작처럼 몸을 돌린다 (%.0f도)" % turned)
	assert_true(largest_back <= rad_to_deg(EnemyBody.TURN_BACK_SPEED) / 60.0 * 1.6, "천천히 돌아온다")
	assert_almost_eq(enemy.body.model_turn_degrees(), 0.0, 1.0, "원래 방향으로 돌아온다")


func test_defeated_enemy_disappears() -> void:
	var enemy := _enemy("grunt", Vector3(0, 0, -6))
	enemy.ai_enabled = false
	await _frames(2)
	var hit := HitData.new()
	hit.damage = 100.0
	var outcome := enemy.receive_hit(1, hit, 100.0, player.global_position)
	assert_true(outcome.flags & Player.HIT_KILL)
	assert_false(enemy.is_alive())
	await _frames(int(Enemy.CORPSE_TIME * 60.0) + 5)
	assert_false(is_instance_valid(enemy), "쓰러진 몸은 잠시 뒤 사라진다")


func _enemy(kind: String, at: Vector3) -> Enemy:
	var enemy := ENEMY_SCENE.instantiate() as Enemy
	enemy.data = load("res://data/enemies/%s.tres" % kind) as EnemyData
	enemy.position = at
	add_child_autofree(enemy)
	return enemy


func _frames(count: int) -> void:
	for i in count:
		await tree.physics_frame
