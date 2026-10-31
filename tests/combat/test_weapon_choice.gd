extends TestCase
## 무기 고르기: 원작처럼 캐릭터의 무기군 안에서만 바꾸고, 고른 무기의 공격력 보너스가 피해에 더해지며, 몸이 그
## 무기를 쥔다. 내 플레이어가 고른 무기는 설정에 남아 다음에 켤 때도 든다.

const PLAYER_SCENE := preload("res://src/player/player.tscn")

var player: Player


func before_each() -> void:
	player = PLAYER_SCENE.instantiate()
	player.use_device_input = false
	player.intent_override = PlayerIntent.new()
	add_child_autofree(player)
	for i in 2:
		await tree.physics_frame


func after_each() -> void:
	GameSettings.reset_to_defaults()


func test_every_character_starts_with_weapon_of_its_type() -> void:
	assert_true(Weapons.of_type(&"sword").size() >= 2, "한손검이 둘 이상이라 고를 수 있다")
	for character in Characters.all():
		var weapon := Weapons.find(character.default_weapon)
		assert_true(weapon != null and weapon.weapon_type == character.weapon_type, "%s의 처음 무기는 그 무기군" % character.id)
	for weapon in Weapons.all():
		assert_true(not weapon.display_name.is_empty() and weapon.rarity > 0, "무기 이름과 등급: %s" % weapon.id)


func test_switch_weapon_within_type() -> void:
	var character := Characters.find(player.character_id)
	assert_eq(player.weapon().id, character.default_weapon, "처음에는 캐릭터의 처음 무기")
	var other := _other_weapon(character)
	assert_true(player.set_weapon(other.id), "같은 무기군이면 바꾼다")
	assert_eq(player.weapon().id, other.id, "바꾼 무기를 든다")
	if player.body.has_model:
		assert_eq(player.body.weapon_id(), other.id, "몸이 새 무기를 쥔다")
	assert_false(player.set_weapon(&"no_such_weapon"), "없는 무기는 들 수 없다")
	assert_eq(player.weapon().id, other.id, "실패하면 그대로")


func test_other_weapon_type_is_refused() -> void:
	var character := Characters.find(player.character_id)
	var other := _other_weapon(character)
	# 무기군이 다른 캐릭터라고 치면 그 무기는 고를 수 없고, 무기 이름이 동기화되어 와도(옛 설정 등) 처음 무기를 든다.
	# 캐릭터 자료는 모두 함께 쓰므로 확인한 뒤 바로 되돌린다.
	var original := character.weapon_type
	character.weapon_type = &"polearm"
	var refused := not player.set_weapon(other.id)
	player.weapon_id = other.id
	var held := player.weapon().id
	character.weapon_type = original
	assert_true(refused, "다른 무기군의 무기는 고를 수 없다")
	assert_eq(held, character.default_weapon, "동기화로 와도 처음 무기를 든다")
	player.weapon_id = &"no_such_weapon"
	assert_eq(player.weapon().id, character.default_weapon, "알 수 없는 무기면 처음 무기")


func test_weapon_bonus_raises_damage() -> void:
	var character := Characters.find(player.character_id)
	var attack := player.kit.basic_chain[0]
	player.set_weapon(character.default_weapon)
	var base := player.attack_power_for(attack)
	var stronger: WeaponData = null
	for weapon in Weapons.of_type(character.weapon_type):
		if weapon.attack_bonus > player.weapon().attack_bonus:
			stronger = weapon
	assert_true(stronger != null, "공격력 보너스가 더 큰 무기가 있다")
	player.set_weapon(stronger.id)
	assert_true(is_equal_approx(player.attack_power_for(attack), base / (1.0 + Weapons.find(character.default_weapon).attack_bonus) * (1.0 + stronger.attack_bonus)),
		"무기 보너스만큼 세진다: %s → %s" % [base, player.attack_power_for(attack)])


func test_local_choice_is_saved() -> void:
	var character := Characters.find(player.character_id)
	var other := _other_weapon(character)
	# 내 플레이어(장치 입력을 받는 플레이어)가 고른 무기만 저장한다.
	player.use_device_input = true
	player.set_weapon(other.id)
	assert_eq(GameSettings.weapon_choices.get(character.id, &""), other.id, "고른 무기를 캐릭터마다 저장")
	GameSettings.save()
	GameSettings.weapon_choices = {}
	GameSettings.load_settings()
	assert_eq(GameSettings.weapon_choices.get(character.id, &""), other.id, "다시 읽어도 남는다")


func _other_weapon(character: CharacterData) -> WeaponData:
	for weapon in Weapons.of_type(character.weapon_type):
		if weapon.id != player.weapon().id:
			return weapon
	return null
