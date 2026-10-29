extends TestCase
## 체력, 장갑, 죽음과 부활, 무기 데이터를 확인한다.

var health: Health


func before_each() -> void:
	health = Health.new()
	health.max_health = 100.0
	add_child_autofree(health)


func test_damage_reduces_health() -> void:
	var dealt := health.apply_damage(DamageInfo.create(30.0, 0, Vector3.ZERO, &"test", false))
	assert_eq(dealt, 30.0)
	assert_eq(health.current, 70.0)


func test_armor_reduces_damage() -> void:
	health.armor = 100.0
	health.apply_damage(DamageInfo.create(40.0, 0, Vector3.ZERO, &"test", false))
	assert_almost_eq(health.current, 80.0, 0.001, "장갑 100이면 피해 절반")


func test_dies_once_and_ignores_further_damage() -> void:
	var deaths: Array[int] = []
	health.died.connect(func(_info: DamageInfo) -> void: deaths.append(1))
	health.apply_damage(DamageInfo.create(150.0, 0, Vector3.ZERO, &"test", false))
	assert_eq(health.current, 0.0, "체력은 0 아래로 내려가지 않음")
	assert_false(health.is_alive())
	health.apply_damage(DamageInfo.create(10.0, 0, Vector3.ZERO, &"test", false))
	assert_eq(deaths.size(), 1)


func test_heal_is_capped_and_revive_restores() -> void:
	health.apply_damage(DamageInfo.create(50.0, 0, Vector3.ZERO, &"test", false))
	health.heal(80.0)
	assert_eq(health.current, 100.0)
	health.apply_damage(DamageInfo.create(200.0, 0, Vector3.ZERO, &"test", false))
	health.heal(50.0)
	assert_eq(health.current, 0.0, "죽은 뒤에는 회복되지 않음")
	health.revive()
	assert_eq(health.current, 100.0)


func test_weapon_data_files_are_valid() -> void:
	for file_name in DirAccess.get_files_at("res://data/weapons"):
		if not file_name.ends_with(".tres"):
			continue
		var weapon := load("res://data/weapons/" + file_name) as WeaponData
		assert_not_null(weapon, file_name)
		assert_eq(String(weapon.id), file_name.get_basename(), "id와 파일 이름이 같아야 함")
		assert_true(weapon.damage > 0.0 and weapon.fire_interval > 0.0, file_name)
		if not weapon.is_melee():
			assert_true(weapon.magazine_size > 0 and weapon.pellets > 0, file_name)


func test_falloff_reduces_damage_with_distance() -> void:
	var weapon := load("res://data/weapons/shotgun.tres") as WeaponData
	assert_eq(weapon.falloff(1.0), 1.0)
	assert_true(weapon.falloff(20.0) < 1.0)
	assert_almost_eq(weapon.falloff(1000.0), weapon.falloff_min_ratio, 0.001)
