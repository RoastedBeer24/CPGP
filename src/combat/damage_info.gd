class_name DamageInfo
extends RefCounted
## 한 번의 피해에 대한 정보. 호스트에서 만들어 Health.apply_damage에 넘긴다.

var amount := 0.0
## 공격한 피어. 적 AI의 공격이면 0.
var attacker_peer := 0
var hit_position := Vector3.ZERO
var weapon_id := &""
var headshot := false
## true면 장갑을 무시한다 (과열 같은 퀵핵 피해)
var ignore_armor := false


## 장갑을 무시하는 퀵핵 피해
static func hack(amount_value: float, attacker: int, position: Vector3, hack_id: StringName) -> DamageInfo:
	var info := create(amount_value, attacker, position, hack_id, false)
	info.ignore_armor = true
	return info


static func create(amount_value: float, attacker: int, position: Vector3, weapon: StringName, is_headshot: bool) -> DamageInfo:
	var info := DamageInfo.new()
	info.amount = amount_value
	info.attacker_peer = attacker
	info.hit_position = position
	info.weapon_id = weapon
	info.headshot = is_headshot
	return info
