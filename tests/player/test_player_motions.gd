extends TestCase
## 원작 동작 활용: 동작마다 바뀌는 무기 자리(오른손·등 뒤·왼손), 무기 꺼내기·거두기, 쉬는 자세와 특수 대기,
## 멈추기, 무거운 착지, 가볍게 맞아 움찔하기, 캐릭터 화면의 동작.
## 캐릭터 모델은 저장소에 없으므로, 모델이 필요한 검사는 모델 파일이 있는 PC에서만 한다.

const PLAYER_SCENE := preload("res://src/player/player.tscn")
const ENEMY_SCENE := preload("res://src/enemies/enemy.tscn")
const HIDDEN := PlayerBody.WeaponPlace.HIDDEN
const BACK := PlayerBody.WeaponPlace.BACK
const HAND := PlayerBody.WeaponPlace.HAND
const MENU := PlayerBody.WeaponPlace.MENU

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


func test_weapon_timelines_follow_original_data() -> void:
	for id: StringName in [&"endministrator_f", &"endministrator_m"]:
		var look := Characters.find(id).appearance()
		assert_eq(look.weapon_place(&"attack_1", 0.0), HAND, "%s: 공격은 오른손" % id)
		assert_eq(look.weapon_place(&"dash_attack", 0.3), HAND, "%s: 대시 공격도 오른손" % id)
		assert_eq(look.weapon_place(&"battle_idle", 0.0), HAND, "%s: 전투 대기는 무기를 든다" % id)
		assert_eq(look.weapon_place(&"draw", 0.1), BACK, "%s: 꺼내는 동작의 처음은 등 뒤" % id)
		assert_eq(look.weapon_place(&"draw", 0.6), HAND, "%s: 꺼내면 오른손" % id)
		assert_eq(look.weapon_place(&"ultimate", 1.0), HIDDEN, "%s: 궁극기 앞부분은 무기 없이" % id)
		assert_eq(look.weapon_place(&"ultimate", 3.0), HAND, "%s: 궁극기 마지막 일격은 무기로" % id)
		assert_eq(look.weapon_place(&"dodge_f", 0.2), HIDDEN, "%s: 회피 중에는 무기가 사라진다" % id)
		assert_eq(look.weapon_place(&"run", 0.0), HIDDEN, "%s: 달리기는 무기 없이" % id)
		assert_eq(look.weapon_place(&"relax", 0.0), HIDDEN, "%s: 쉬는 자세도 무기 없이" % id)
		assert_eq(look.weapon_place(&"ui_to_weapon", 0.0), HIDDEN, "%s: 무기 보기 시작" % id)
		assert_eq(look.weapon_place(&"ui_to_weapon", 0.8), MENU, "%s: 무기 보기는 왼손" % id)
		assert_eq(look.weapon_place(&"ui_weapon_out", 3.0), HIDDEN, "%s: 무기 보기를 끝내면 거둔다" % id)
		assert_eq(look.weapon_place(&"sheathe", 0.3), HAND, "%s: 거두는 동작 처음에는 들고 있다" % id)
		assert_eq(look.weapon_place(&"sheathe", 1.0), HIDDEN, "%s: 칼을 내린 뒤 지운다" % id)
	var akekuri := Characters.find(&"akekuri").appearance()
	assert_eq(akekuri.weapon_place(&"attack_4", 0.0), HAND, "아케쿠리: 공격은 오른손")
	assert_eq(akekuri.weapon_place(&"draw", 0.5), BACK, "아케쿠리: 꺼내는 동작은 0.85초까지 등 뒤")
	assert_eq(akekuri.weapon_place(&"draw", 0.9), HAND)
	assert_eq(akekuri.weapon_place(&"ultimate", 3.0), HIDDEN, "아케쿠리: 궁극기는 무기 없이 소대를 부른다")
	assert_eq(akekuri.weapon_place(&"ui_weapon", 0.0), MENU, "아케쿠리: 무기 보기")
	assert_eq(String(akekuri.weapon_menu_mount), "wep_R", "아케쿠리는 무기 보기도 오른손")
	var female := Characters.find(&"endministrator_f").appearance()
	var male := Characters.find(&"endministrator_m").appearance()
	assert_eq(female.weapon_place(&"draw", 0.41), HAND, "관리자(여)는 0.40초에 오른손으로 옮긴다")
	assert_eq(male.weapon_place(&"draw", 0.41), BACK, "관리자(남)는 0.42초에 옮긴다")


func test_props_follow_original_binding() -> void:
	# 소품(보조 무기): 포그라니치니크는 배틀 스킬 동안 칼 대신 왼손에 소품을 들고, 평소에는 숨긴다(사용자 지적: 맨손으로
	# 스킬을 썼다). 원작 소품 꾸러미가 있는 PC에서만 확인한다.
	assert_eq(PlayerBody._timeline_place([0.0, 0, 4.3, 2], 1.0), 0)
	assert_eq(PlayerBody._timeline_place([0.0, 2, 4.3, 0], 1.0), 2)
	if not await _spawn_with_model(&"pogranichnik") or player.body.prop_count() == 0:
		return
	await _frames(10)
	assert_eq(player.body.prop_place(0), 0, "평소에는 소품을 숨긴다")
	player.sp = player.kit.max_sp
	intent.skill_pressed = true
	await _frames(20)
	intent.skill_pressed = false
	assert_eq(player.current_action(), player.kit.battle_skill, "배틀 스킬")
	assert_eq(player.body.prop_place(0), 2, "배틀 스킬 동안 왼손에 소품을 든다")
	assert_eq(player.body.weapon_place(), HIDDEN, "칼은 거둔다")
	await _frames(int(player.kit.battle_skill.duration * 60.0) + 40)
	assert_eq(player.body.prop_place(0), 0, "스킬이 끝나면 소품을 거둔다")
	player.queue_free()
	await _frames(1)
	if not await _spawn_with_model(&"chen_qianyu") or player.body.prop_count() < 2:
		return
	await _frames(10)
	assert_eq(player.body.prop_place(0), 1, "진천우는 평소 소품을 몸에 단다")
	assert_eq(player.body.prop_place(1), 1)


func test_noticing_enemy_puts_player_in_combat() -> void:
	await _spawn()
	assert_false(player.in_combat)
	var enemy := ENEMY_SCENE.instantiate() as Enemy
	enemy.position = Vector3(0, 0, -9)
	add_child_autofree(enemy)
	var alerted := false
	for i in 30:
		await _frames(1)
		alerted = alerted or player.in_combat
	assert_eq(enemy.state, Enemy.State.CHASE, "적이 알아채고 다가온다")
	assert_true(alerted, "적이 알아채면 전투 자세가 된다")


func test_light_hit_flinches_toward_hit_side() -> void:
	await _spawn()
	player.notify_hit(false, player.global_position - player.facing() * 3.0, 0.0)
	await _frames(2)
	assert_eq(player.flinch_count, 1, "가볍게 맞으면 움찔한다")
	assert_eq(player.flinch_side, Player.HitSide.BACK, "뒤에서 맞았다")
	assert_eq(player.state, Player.State.GROUND, "움직임은 막지 않는다")
	player.notify_hit(false, player.global_position + player.global_basis.x * 3.0, 0.0)
	await _frames(2)
	assert_eq(player.flinch_side, Player.HitSide.RIGHT, "오른쪽에서 맞았다")
	if player.body.animated:
		assert_true(player.body.flinching(), "윗몸이 움찔하는 동작")


func test_weapon_appears_in_right_hand_only_while_fighting() -> void:
	if not await _spawn_with_model() or not player.body.animated:
		return
	assert_false(player.body.sword_shown(), "싸우기 전에는 무기가 없다")
	intent.attack_pressed = true
	await _frames(12)
	assert_true(player.body.sword_shown(), "공격하면 무기가 나타난다")
	assert_eq(player.body.weapon_place(), HAND)
	assert_eq(String(player.body.weapon_anchor().name), String(player.body.appearance.weapon_hand_mount), "오른손 무기 자리(wep_R)")
	await _frames(90)
	assert_eq(player.body.locomotion, &"battle_idle", "싸우는 중에 서 있으면 전투 대기")
	assert_true(player.body.sword_shown(), "전투 대기에서는 무기를 든다")
	intent.move = Vector2(0, 1)
	await _frames(60)
	assert_false(player.body.sword_shown(), "달리면 무기를 거둔다(원작처럼 전투 동작에서만 든다)")
	intent.move = Vector2.ZERO
	intent.attack_pressed = true
	await _frames(12)
	assert_true(player.body.sword_shown(), "다시 공격하면 꺼낸다")


func test_combat_start_draws_weapon_from_back() -> void:
	if not await _spawn_with_model() or not player.body.animated:
		return
	player.notify_hit(false, player.global_position + player.facing() * 3.0, 0.0)
	await _frames(16)
	assert_eq(player.body.dominant_animation(), &"draw", "전투가 시작되면 무기를 꺼낸다")
	assert_eq(player.body.weapon_place(), BACK, "꺼내는 동작의 처음에는 등 뒤에 나타난다")
	await _frames(20)
	assert_eq(player.body.weapon_place(), HAND, "곧 오른손으로 옮긴다")
	# 전투가 끝나면(6초) 무기를 거두는 동작
	var sheathed := false
	for i in 420:
		await _frames(1)
		sheathed = sheathed or player.body.dominant_animation() == &"sheathe"
	assert_true(sheathed, "전투가 끝나면 무기를 거둔다")
	await _frames(30)
	assert_false(player.body.sword_shown())


func test_standing_still_relaxes_and_moving_breaks_it() -> void:
	if not await _spawn_with_model() or not player.body.animated:
		return
	var seen: Array[StringName] = []
	for i in int((PlayerBody.RELAX_DELAY + 4.0) * 60.0):
		await _frames(1)
		var now := player.body.dominant_animation()
		if not seen.has(now):
			seen.append(now)
	assert_true(seen.has(&"relax_in"), "오래 서 있으면 쉬는 자세로 바꾼다: %s" % [seen])
	assert_eq(player.body.locomotion, &"relax", "쉬는 자세로 서 있다")
	intent.move = Vector2(0, 1)
	await _frames(20)
	assert_eq(player.body.locomotion, &"run", "움직이면 바로 달린다")
	assert_ne(player.body.dominant_animation(), &"relax_in")


func test_stopping_from_run_plays_stop_clip() -> void:
	if not await _spawn_with_model() or not player.body.animated:
		return
	intent.move = Vector2(0, 1)
	await _frames(40)
	intent.move = Vector2.ZERO
	var stop := &""
	for i in 30:
		await _frames(1)
		var now := player.body.dominant_animation()
		if String(now).begins_with("run_stop"):
			stop = now
	assert_true(String(stop).begins_with("run_stop"), "달리다 서면 멈추는 동작")


func test_long_fall_lands_heavy() -> void:
	if not await _spawn_with_model() or not player.body.animated:
		return
	player.global_position = Vector3(0, 7, 0)
	var heavy := false
	for i in 150:
		await _frames(1)
		heavy = heavy or player.body.dominant_animation() == &"land_heavy"
	assert_true(heavy, "높은 곳에서 떨어지면 무겁게 착지한다")


func test_character_screen_motions() -> void:
	if not await _spawn_with_model() or not player.body.animated:
		return
	player.showcase = true
	await _frames(10)
	assert_eq(player.body.dominant_animation(), &"ui_enter", "캐릭터 화면에 걸어 들어온다")
	await _frames(400)
	assert_eq(player.body.locomotion, &"ui_idle", "화면용 대기")
	player.showcase_pokes += 1
	await _frames(10)
	assert_eq(player.body.dominant_animation(), &"ui_react", "누르면 반응한다")
	player.showcase_weapon = true
	await _frames(10)
	assert_eq(player.body.dominant_animation(), &"ui_to_weapon", "무기 보기")
	await _frames(90)
	assert_true(player.body.sword_shown(), "무기를 꺼내 보여 준다")
	assert_eq(player.body.weapon_place(), MENU)
	assert_eq(String(player.body.weapon_anchor().name), String(player.body.appearance.weapon_menu_mount), "왼손 무기 자리(wep_L)")
	player.showcase_weapon = false
	await _frames(400)
	assert_false(player.body.sword_shown(), "무기 보기를 끄면 거둔다")
	player.showcase = false
	await _frames(30)
	assert_eq(player.body.locomotion, &"idle", "화면을 닫으면 평소 대기")


func _spawn(character_id: StringName = Characters.DEFAULT_ID) -> void:
	player = PLAYER_SCENE.instantiate()
	player.use_device_input = false
	player.character_id = character_id
	intent = PlayerIntent.new()
	player.intent_override = intent
	add_child_autofree(player)
	await _frames(2)


## 고른 캐릭터의 모델로 띄운다. 모델 파일이 없는 PC면 false를 돌려준다.
func _spawn_with_model(character_id: StringName = Characters.DEFAULT_ID) -> bool:
	await _spawn(character_id)
	if not player.body.has_model:
		print("    (캐릭터 모델이 없어 건너뜀: %s)" % character_id)
		return false
	await _frames(5)
	return true


func _frames(count: int) -> void:
	for i in count:
		await tree.physics_frame
