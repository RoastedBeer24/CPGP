extends TestCase
## 체력, 장갑, 쓰러짐과 일으키기, 캐릭터 전투 구성(kit)과 적 데이터를 확인한다.

var health: Health


func before_each() -> void:
	health = Health.new()
	health.max_health = 100.0
	add_child_autofree(health)


func test_damage_reduces_health() -> void:
	var dealt := health.apply_damage(DamageInfo.create(30.0, 0, Vector3.ZERO, &"test"))
	assert_eq(dealt, 30.0)
	assert_eq(health.current, 70.0)


func test_armor_reduces_damage() -> void:
	health.armor = 100.0
	health.apply_damage(DamageInfo.create(40.0, 0, Vector3.ZERO, &"test"))
	assert_almost_eq(health.current, 80.0, 0.001, "장갑 100이면 피해 절반")


func test_dies_once_and_ignores_further_damage() -> void:
	var deaths: Array[int] = []
	health.died.connect(func(_info: DamageInfo) -> void: deaths.append(1))
	health.apply_damage(DamageInfo.create(150.0, 0, Vector3.ZERO, &"test"))
	assert_eq(health.current, 0.0, "체력은 0 아래로 내려가지 않음")
	assert_false(health.is_alive())
	health.apply_damage(DamageInfo.create(10.0, 0, Vector3.ZERO, &"test"))
	assert_eq(deaths.size(), 1)


func test_heal_is_capped_and_revive_restores_a_fraction() -> void:
	health.apply_damage(DamageInfo.create(50.0, 0, Vector3.ZERO, &"test"))
	health.heal(80.0)
	assert_eq(health.current, 100.0)
	health.apply_damage(DamageInfo.create(200.0, 0, Vector3.ZERO, &"test"))
	health.heal(50.0)
	assert_eq(health.current, 0.0, "쓰러진 뒤에는 회복되지 않음")
	var revived: Array[int] = []
	health.revived.connect(func() -> void: revived.append(1))
	health.revive(0.3)
	assert_almost_eq(health.current, 30.0, 0.001, "동료가 일으키면 30%")
	assert_eq(revived.size(), 1)
	health.revive(1.0)
	assert_eq(health.current, 100.0, "방을 다시 시작하면 가득")


func test_character_kits_are_consistent() -> void:
	var characters := Characters.all()
	assert_eq(characters.size(), 3, "관리자(여·남), 아케쿠리")
	for character in characters:
		var kit := character.kit()
		assert_not_null(kit, String(character.id))
		assert_not_null(character.appearance(), String(character.id))
		assert_true(kit.basic_chain.size() >= 4 and kit.basic_chain.size() <= 5, "기본 공격 4~5단계: %s" % character.id)
		for attack in kit.all_attacks():
			var label := "%s/%s" % [character.id, attack.id]
			assert_true(PlayerBody.ACTION_CLIPS.has(attack.clip), "몸이 틀 수 있는 동작: " + label)
			# 낙하 공격의 시작(뛰어오르기)과 떨어지기는 타격이 없다. 착지에서 친다.
			if attack != kit.plunge_start and attack != kit.plunge_fall:
				assert_true(attack.hits.size() > 0, "타격이 있음: " + label)
			var last := -1.0
			for hit in attack.hits:
				assert_true(hit.time > last and hit.time < attack.duration, "타격 시각이 차례대로 동작 안에: " + label)
				last = hit.time
			for i in range(1, attack.advance.size()):
				assert_true(attack.advance[i].x > attack.advance[i - 1].x and attack.advance[i].y >= attack.advance[i - 1].y,
					"내디딤 거리는 앞으로만 는다: " + label)
		assert_true(kit.battle_skill.sp_cost > 0.0, "배틀 스킬은 SP를 쓴다")
		assert_eq(kit.ultimate.energy_cost, kit.max_energy, "궁극기는 에너지를 다 쓴다")
		if String(character.id).begins_with("endministrator"):
			assert_eq(kit.battle_skill.hits[0].effect, HitData.Effect.APPLY_CRYSTAL, "관리자의 배틀 스킬이 원석 결정을 붙인다")
			assert_eq(kit.ultimate.hits[kit.ultimate.hits.size() - 1].effect, HitData.Effect.SHATTER_CRYSTAL, "관리자의 궁극기가 깨뜨린다")
		assert_true(kit.plunge_start.rise_end() > 0.0, "낙하 공격은 먼저 뛰어오른다")
		assert_true(kit.plunge_land.hits[0].arc >= 180.0, "낙하 공격 착지는 둘레 전체를 친다")
	var akekuri := Characters.find(&"akekuri").kit()
	assert_eq(akekuri.basic_chain.size(), 4, "아케쿠리는 기본 공격 4단계")
	assert_true(akekuri.dash_attack != null, "아케쿠리 대시 공격은 원작 연계 스킬(섬광 돌진)")
	assert_true(akekuri.ultimate.rally_sp > 0.0, "궁극기 소대, 집합!은 동료에게 SP를 나눠 준다")
	assert_true(akekuri.battle_skill.sp_per_hit > 0.0, "배틀 스킬은 맞히면 SP를 돌려받는다")


func test_attack_advance_interpolates() -> void:
	var attack := AttackData.new()
	attack.advance = PackedVector2Array([Vector2(0, 0), Vector2(0.2, 1.0), Vector2(0.4, 1.5)])
	assert_almost_eq(attack.advance_at(0.1), 0.5, 0.001)
	assert_almost_eq(attack.advance_at(0.3), 1.25, 0.001)
	assert_almost_eq(attack.advance_at(2.0), 1.5, 0.001, "끝난 뒤에는 그대로")


func test_enemy_data_is_consistent() -> void:
	for kind: String in ["grunt", "shooter", "heavy"]:
		var data := load("res://data/enemies/%s.tres" % kind) as EnemyData
		assert_not_null(data, kind)
		assert_true(data.max_health > 0.0 and data.stagger_max > 0.0, kind)
		assert_true(data.attacks.size() > 0, kind)
		for attack in data.attacks:
			assert_true(attack.wind_up >= 0.5, "예고 시간이 있어야 피할 수 있다: %s/%s" % [kind, attack.id])
			assert_true(attack.max_range > attack.min_range, "%s/%s" % [kind, attack.id])
