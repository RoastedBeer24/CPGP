class_name Weapons
extends RefCounted
## 고를 수 있는 무기 목록. 캐릭터 화면에서 그 캐릭터의 무기군(CharacterData.weapon_type)에 맞는 것만 고른다.

const PATHS: Array[String] = [
	"res://data/weapons/tarr_11.tres",
	"res://data/weapons/edge_of_lightness.tres",
	"res://data/weapons/aspirant.tres",
	"res://data/weapons/twelve_questions.tres",
	"res://data/weapons/never_rest.tres",
]


static func all() -> Array[WeaponData]:
	var found: Array[WeaponData] = []
	for path in PATHS:
		var weapon := load(path) as WeaponData
		if weapon != null:
			found.append(weapon)
	return found


## 이름으로 찾는다. 없으면 null.
static func find(id: StringName) -> WeaponData:
	for weapon in all():
		if weapon.id == id:
			return weapon
	return null


## 그 무기군의 무기들 (목록 순서)
static func of_type(weapon_type: StringName) -> Array[WeaponData]:
	var found: Array[WeaponData] = []
	for weapon in all():
		if weapon.weapon_type == weapon_type:
			found.append(weapon)
	return found
