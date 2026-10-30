class_name Health
extends Node
## 체력. 피해 판정은 호스트에서만 하고, 값은 MultiplayerSynchronizer로 모두에게 퍼진다.
## 다른 피어에서 apply_damage를 불러도 무시된다.

signal damaged(info: DamageInfo, amount: float)
signal died(info: DamageInfo)
signal revived

@export var max_health := 100.0
## 장갑 점수. 받는 피해 = 원래 피해 × 100 / (100 + 장갑)
@export var armor := 0.0

## 현재 체력. 호스트가 정하고 다른 피어에는 동기화로 전달된다.
var current := 100.0:
	set(value):
		var was_alive := current > 0.0
		current = value
		# 호스트는 apply_damage/revive에서 직접 알린다. 다른 피어는 동기화된 값의 변화로 알게 된다.
		if not is_inside_tree() or multiplayer.is_server():
			return
		if was_alive and current <= 0.0:
			died.emit(null)
		elif not was_alive and current > 0.0:
			revived.emit()
## 쓰러진 플레이어를 동료가 일으킨 정도(0~1). 호스트가 정한다.
var revive_progress := 0.0


func _ready() -> void:
	current = max_health


func is_alive() -> bool:
	return current > 0.0


func ratio() -> float:
	return clampf(current / maxf(max_health, 1.0), 0.0, 1.0)


## 장갑을 적용한 실제 피해량
func mitigate(raw_amount: float) -> float:
	return raw_amount * 100.0 / (100.0 + maxf(armor, 0.0))


## 피해를 준다. 호스트에서만 효과가 있다. 실제로 깎인 양을 돌려준다.
func apply_damage(info: DamageInfo) -> float:
	if not multiplayer.is_server() or not is_alive():
		return 0.0
	var amount := minf(info.amount if info.ignore_armor else mitigate(info.amount), current)
	current -= amount
	damaged.emit(info, amount)
	if current <= 0.0:
		died.emit(info)
	return amount


func heal(amount: float) -> void:
	if not multiplayer.is_server() or not is_alive():
		return
	current = minf(current + amount, max_health)


## 쓰러진 상태에서 최대 체력의 fraction만큼 채워 되살린다. 호스트에서만 효과가 있다.
func revive(fraction: float = 1.0) -> void:
	if not multiplayer.is_server():
		return
	var was_alive := is_alive()
	current = maxf(max_health * clampf(fraction, 0.01, 1.0), current)
	revive_progress = 0.0
	if not was_alive:
		revived.emit()
