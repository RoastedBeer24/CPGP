class_name DamageInfo
extends RefCounted
## 한 번의 피해에 대한 정보. 호스트에서 만들어 Health.apply_damage에 넘긴다.

var amount := 0.0
## 공격한 피어. 적의 공격이면 0.
var attacker_peer := 0
var hit_position := Vector3.ZERO
## 공격 동작 이름 (예: attack_1, battle_skill, 적의 공격 이름)
var source := &""
## true면 장갑을 무시한다
var ignore_armor := false


static func create(amount_value: float, attacker: int, position: Vector3, source_id: StringName) -> DamageInfo:
	var info := DamageInfo.new()
	info.amount = amount_value
	info.attacker_peer = attacker
	info.hit_position = position
	info.source = source_id
	return info
