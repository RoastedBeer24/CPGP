extends TestCase
## 플레이어의 전투: 기본 공격 연속, 배틀 스킬(SP, 원석 결정), 궁극기(에너지, 결정 파쇄), 경직과 처형,
## 회피 직후 대시 공격, 완벽한 회피, 적의 공격에 맞기. 한 세상 안에서 이 프로세스가 호스트다.

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
	await _frames(3)


func test_basic_attack_chain_runs_five_steps_and_hits() -> void:
	var enemy := _enemy("grunt", Vector3(0, 0, -2.0), false)
	await _frames(2)
	var seen: Array[StringName] = []
	for step in 5:
		intent.attack_pressed = true
		for i in 70:
			await _frames(1)
			if player.action_id != (seen.back() if not seen.is_empty() else &""):
				break
		seen.append(player.action_id)
		# 다음 공격으로 이어질 때까지 기다린다(미리 누른 공격은 이어지는 시각에 나간다).
		await _frames(int(player.current_action().chain_from * 60.0) if player.current_action() != null else 1)
	assert_eq(seen, [&"attack_1", &"attack_2", &"attack_3", &"attack_4", &"attack_5"] as Array[StringName], "다섯 단계가 차례로")
	assert_true(enemy.health.current < enemy.data.max_health, "적이 맞았다: %s" % enemy.health.current)
	assert_true(player.energy > 0.0, "맞힐 때마다 궁극기 에너지가 찬다")


func test_attack_turns_toward_nearby_enemy() -> void:
	# 적이 옆(+X)에 있으면 그쪽을 노려 친다. 몸은 원작 동작대로 돌며 휘두른다(AttackData.turn).
	var enemy := _enemy("grunt", Vector3(2.5, 0, 0), false)
	await _frames(2)
	intent.attack_pressed = true
	await _frames(20)
	assert_true(player.action_forward().dot(Vector3.RIGHT) > 0.9, "적 쪽을 노린다: %s" % player.action_forward())
	assert_true(enemy.health.current < enemy.data.max_health, "맞힌다")


func test_body_follows_original_turn_and_keeps_it_after_attack() -> void:
	# 5타처럼 몸을 크게 돌리는 동작은 플레이어가 직접 돌고, 끝난 뒤에도 그 방향을 본다(예전에는 동작 안에서만 돌아
	# 끝날 때 몸이 원래 방향으로 튀었다).
	var attack := player.kit.basic_chain[4]
	if attack.turn.is_empty():
		return
	player._start_action(attack, null, null)
	var aim := player.action_forward()
	await _frames(int(attack.duration * 60.0) - 2)
	var expected := player._yaw_of(aim) + attack.turn_at(player.action_time())
	assert_almost_eq(angle_difference(player.rotation.y, expected), 0.0, 0.05, "몸은 노린 방향 + 원작 회전")
	await _frames(20)
	assert_ne(player.state, Player.State.ACTION, "동작이 끝났다")
	assert_almost_eq(angle_difference(player.rotation.y, expected), 0.0, 0.1, "끝난 뒤에도 그 방향 그대로(튀지 않는다)")


func test_battle_skill_costs_sp_and_applies_crystal() -> void:
	var enemy := _enemy("grunt", Vector3(0, 0, -2.5), false)
	await _frames(2)
	player.sp = 100.0
	intent.skill_pressed = true
	await _frames(3)
	assert_eq(player.action_id, &"battle_skill")
	assert_true(player.sp < 10.0, "SP 100을 쓴다: %s" % player.sp)
	await _frames(40)
	assert_true(enemy.has_crystal(), "배틀 스킬에 맞으면 원석 결정이 붙는다")
	await _frames(40)
	var denied: Array[String] = []
	player.skill_denied.connect(func(reason: String) -> void: denied.append(reason))
	intent.skill_pressed = true
	await _frames(3)
	assert_eq(denied.size(), 1, "SP가 모자라면 쓰지 못한다")


func test_ultimate_needs_energy_and_shatters_crystal() -> void:
	var enemy := _enemy("heavy", Vector3(0, 0, -3.0), false)
	await _frames(2)
	intent.ultimate_pressed = true
	await _frames(3)
	assert_ne(player.action_id, &"ultimate", "에너지가 없으면 쓰지 못한다")
	enemy.crystal_left = 10.0
	player.energy = player.kit.max_energy
	var flags: Array[int] = []
	player.hit_confirmed.connect(func(_at: Vector3, _amount: float, hit_flags: int) -> void: flags.append(hit_flags))
	intent.ultimate_pressed = true
	await _frames(3)
	assert_eq(player.action_id, &"ultimate")
	assert_eq(player.energy, 0.0, "에너지를 다 쓴다")
	assert_true(player.invulnerable, "궁극기 중에는 무적")
	await _frames(int(player.kit.ultimate.duration * 60.0) + 10)
	var shattered := false
	for value in flags:
		shattered = shattered or (value & Player.HIT_SHATTER) != 0
	assert_true(shattered, "원석 결정을 깨뜨려 추가 피해: %s" % [flags])
	assert_false(enemy.has_crystal())


func test_holding_skill_key_uses_ultimate_when_ready() -> void:
	_enemy("grunt", Vector3(0, 0, -3.0), false)
	await _frames(2)
	player.energy = player.kit.max_energy
	intent.skill_pressed = true
	intent.skill_held = true
	await _frames(int(player.config.ultimate_hold_time * 60.0) + 4)
	assert_eq(player.action_id, &"ultimate", "길게 누르면 궁극기")
	intent.skill_held = false


func test_tapping_skill_key_uses_battle_skill_even_when_ultimate_ready() -> void:
	player.energy = player.kit.max_energy
	intent.skill_pressed = true
	intent.skill_held = true
	await _frames(3)
	intent.skill_held = false
	await _frames(3)
	assert_eq(player.action_id, &"battle_skill", "짧게 누르면 배틀 스킬")
	assert_true(player.energy >= player.kit.max_energy - 0.01, "궁극기 에너지는 그대로")


func test_staggered_enemy_can_be_finished() -> void:
	var enemy := _enemy("grunt", Vector3(0, 0, -2.0), false)
	await _frames(2)
	enemy.stagger = enemy.data.stagger_max - 1.0
	intent.attack_pressed = true
	await _frames(30)
	assert_true(enemy.is_staggered(), "경직 게이지가 차면 경직")
	await _frames(40)
	intent.attack_pressed = true
	await _frames(3)
	assert_eq(player.action_id, &"finisher", "경직된 적 가까이서 공격하면 처형")
	var before := enemy.health.current
	await _frames(int(player.kit.finisher.duration * 60.0))
	assert_true(before - enemy.health.current > player.kit.attack_power * 4.0, "처형은 크게 다친다: %s" % (before - enemy.health.current))


func test_attack_right_after_dodge_is_dash_attack() -> void:
	intent.move = Vector2(0, 1)
	intent.dodge_pressed = true
	await _frames(int(player.config.dodge_duration * 60.0) + 2)
	intent.move = Vector2.ZERO
	intent.attack_pressed = true
	await _frames(3)
	assert_eq(player.action_id, &"dash_attack")


func test_attack_in_air_is_plunge_that_hits_all_around_on_landing() -> void:
	# 적이 등 뒤(+Z)에 있어도 착지 타격은 둘레 전체를 내려친다.
	var enemy := _enemy("grunt", Vector3(0, 0, 2.2), false)
	await _frames(2)
	intent.jump_pressed = true
	await _frames(15)
	assert_eq(player.state, Player.State.AIR, "점프 중")
	var jumped_from := player.global_position.y
	intent.attack_pressed = true
	await _frames(2)
	assert_eq(player.state, Player.State.PLUNGE, "공중에서 공격하면 낙하 공격")
	assert_eq(player.action_id, &"plunge_start")
	var highest := jumped_from
	var landed := false
	for i in 120:
		await _frames(1)
		highest = maxf(highest, player.global_position.y)
		if player.action_id == &"plunge_land":
			landed = true
			break
	assert_true(highest > jumped_from + 1.0, "원작 동작처럼 먼저 뛰어오른다: %.2f → %.2f" % [jumped_from, highest])
	assert_true(landed, "땅에 닿으면 착지 동작")
	assert_true(player.is_on_floor())
	await _frames(10)
	assert_true(enemy.health.current < enemy.data.max_health, "착지하며 둘레의 적을 친다: %s" % enemy.health.current)
	await _frames(60)
	assert_ne(player.state, Player.State.PLUNGE, "착지 동작이 끝나면 다시 움직인다")


func test_plunge_onto_enemy_lands_on_the_floor_not_on_its_head() -> void:
	# 예전에는 적 위로 내리꽂으면 적의 몸 위에 내려서서, 그 위에서 움직이면 공중에 뜬 것처럼 보였다.
	var enemy := _enemy("heavy", Vector3(0, 0, -3.0), false)
	player.global_position = Vector3(0, 4.0, -3.0)
	await _frames(12)
	intent.attack_pressed = true
	for i in 150:
		await _frames(1)
		if player.action_id == &"plunge_land":
			break
	assert_eq(player.action_id, &"plunge_land", "땅에 닿는다")
	assert_true(player.global_position.y < 0.3, "적의 머리가 아니라 땅에 선다: %.2f" % player.global_position.y)
	await _frames(70)
	assert_true(player.global_position.y < 0.3, "착지 뒤에도 땅에 있다: %.2f" % player.global_position.y)
	assert_true(enemy.health.current < enemy.data.max_health, "바로 밑의 적도 맞는다")


func test_rally_ultimate_gives_sp_to_nearby_allies() -> void:
	# 아케쿠리 궁극기 "소대, 집합!": 곁(8m 안)의 동료 모두(나 포함)가 SP를 얻는다. 먼 동료는 얻지 않는다.
	player.kit = Characters.find(&"akekuri").kit()
	var near := PLAYER_SCENE.instantiate() as Player
	near.use_device_input = false
	near.position = Vector3(3, 0, 0)
	add_child_autofree(near)
	var far := PLAYER_SCENE.instantiate() as Player
	far.use_device_input = false
	far.position = Vector3(20, 0, 0)
	add_child_autofree(far)
	await _frames(3)
	for p: Player in [player, near, far]:
		p.sp = 50.0
	player.energy = player.kit.max_energy
	intent.ultimate_pressed = true
	await _frames(3)
	assert_eq(player.action_id, &"ultimate")
	assert_true(player.sp >= 145.0, "나도 SP를 얻는다: %s" % player.sp)
	assert_true(near.sp >= 145.0, "곁의 동료가 SP를 얻는다: %s" % near.sp)
	assert_true(far.sp < 60.0, "먼 동료는 얻지 않는다: %s" % far.sp)


func test_attack_on_ground_is_not_plunge() -> void:
	intent.attack_pressed = true
	await _frames(3)
	assert_eq(player.action_id, &"attack_1", "땅에서는 기본 공격")


func test_dodge_cancels_attack() -> void:
	intent.attack_pressed = true
	await _frames(5)
	assert_eq(player.state, Player.State.ACTION)
	intent.dodge_pressed = true
	await _frames(2)
	assert_eq(player.state, Player.State.DODGE, "공격 중에도 회피로 끊는다")


func test_enemy_attack_hurts_and_heavy_hit_staggers_player() -> void:
	var enemy := _enemy("heavy", Vector3(0, 0, -2.0), true)
	var hits: Array[bool] = []
	player.got_hit.connect(func(heavy: bool) -> void: hits.append(heavy))
	for i in 240:
		await _frames(1)
		if not hits.is_empty():
			break
	assert_false(hits.is_empty(), "처형자의 공격에 맞는다")
	assert_true(player.health.current < player.kit.max_health)
	assert_true(hits[0], "강한 공격")
	assert_eq(player.state, Player.State.HURT, "크게 맞으면 휘청인다")
	enemy.ai_enabled = false


func test_dodging_enemy_attack_is_perfect_dodge() -> void:
	var enemy := _enemy("grunt", Vector3(0, 0, -2.0), true)
	var perfect: Array[int] = []
	player.perfect_dodged.connect(func() -> void: perfect.append(1))
	player.sp = 0.0
	# 예고가 끝나기 직전에 회피한다.
	for i in 240:
		await _frames(1)
		if enemy.state == Enemy.State.WIND_UP and enemy.state_time() >= enemy.current_attack().wind_up - 0.1:
			break
	assert_eq(enemy.state, Enemy.State.WIND_UP, "적이 공격을 예고한다")
	intent.dodge_pressed = true
	await _frames(15)
	assert_eq(perfect.size(), 1, "완벽한 회피")
	assert_eq(player.health.current, player.kit.max_health, "맞지 않는다")
	assert_true(player.sp >= player.kit.perfect_dodge_sp, "SP를 얻는다: %s" % player.sp)


func _enemy(kind: String, at: Vector3, ai: bool) -> Enemy:
	var enemy := ENEMY_SCENE.instantiate() as Enemy
	enemy.data = load("res://data/enemies/%s.tres" % kind) as EnemyData
	enemy.ai_enabled = ai
	enemy.position = at
	var to_player := -at
	enemy.rotation.y = atan2(-to_player.x, -to_player.z)
	add_child_autofree(enemy)
	return enemy


func _frames(count: int) -> void:
	for i in count:
		await tree.physics_frame
