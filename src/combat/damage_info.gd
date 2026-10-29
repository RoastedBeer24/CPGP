class_name DamageInfo
extends RefCounted
## 한 번의 피해에 대한 정보. 호스트에서 만들어 Health.apply_damage에 넘긴다.

var amount := 0.0
## 공격한 피어. 적 AI의 공격이면 0.
var attacker_peer := 0
var hit_position := Vector3.ZERO
var weapon_id := &""
var headshot := false


static func create(amount_value: float, attacker: int, position: Vector3, weapon: StringName, is_headshot: bool) -> DamageInfo:
	var info := DamageInfo.new()
	info.amount = amount_value
	info.attacker_peer = attacker
	info.hit_position = position
	info.weapon_id = weapon
	info.headshot = is_headshot
	return info
