class_name WeaponData
extends Resource
## 무기 하나의 수치. 무기를 추가하거나 밸런스를 바꿀 때는 data/weapons/*.tres만 고친다.

enum Kind { HITSCAN, MELEE }

@export var id := &""
@export var display_name := ""
@export var kind := Kind.HITSCAN

@export_group("피해")
@export var damage := 10.0
@export var headshot_multiplier := 2.0
## 이 거리(m)까지는 피해가 그대로이고, 그 뒤로 range까지 줄어든다.
@export var falloff_start := 15.0
@export var falloff_min_ratio := 0.4
@export var max_range := 60.0

@export_group("사격")
## 한 번 쏠 때 나가는 탄 수 (산탄총은 여러 발)
@export var pellets := 1
## 퍼짐 각도(도). 조준하면 aim_spread_ratio만큼 줄어든다.
@export var spread_degrees := 1.0
@export var aim_spread_ratio := 0.4
## 다음 발사까지 걸리는 시간(초)
@export var fire_interval := 0.25
## 누르고 있으면 계속 쏘는지
@export var automatic := false
@export var magazine_size := 12
@export var reload_time := 1.4

@export_group("반동 (도)")
@export var recoil_pitch := 1.5
@export var recoil_yaw := 0.4
## 반동 중 자동으로 되돌아오는 비율
@export var recoil_recovery := 0.6

@export_group("근접")
@export var melee_reach := 2.6
## 정면 기준 좌우 판정 각도(도)
@export var melee_arc_degrees := 70.0

@export_group("조준")
@export var aim_fov := 55.0


func is_melee() -> bool:
	return kind == Kind.MELEE


## 거리에 따른 피해 배율
func falloff(distance: float) -> float:
	if distance <= falloff_start or max_range <= falloff_start:
		return 1.0
	var t := clampf((distance - falloff_start) / (max_range - falloff_start), 0.0, 1.0)
	return lerpf(1.0, falloff_min_ratio, t)
