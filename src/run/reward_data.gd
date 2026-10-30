class_name RewardData
extends Resource
## 방을 깰 때마다 고르는 보상(강화) 하나. 작전이 끝나면 사라진다.
## 수치 하나(stat)를 value만큼 올리거나, 체력을 heal(최대 체력 비율)만큼 채운다.

## 올리는 수치 (Player.bonus로 읽는다)
const STATS: Array[StringName] = [
	&"attack", &"max_health", &"basic_damage", &"skill_damage", &"ultimate_damage", &"finisher_damage",
	&"shatter_damage", &"stagger", &"sp_regen", &"energy_gain", &"dodge_invulnerable",
]

@export var id := &""
@export var title := ""
@export_multiline var description := ""
@export var stat := &""
## 배율 수치는 비율(0.15 = +15%), 회피 무적은 초
@export var value := 0.0
## 고르는 순간 최대 체력의 이 비율만큼 회복한다.
@export var heal := 0.0
