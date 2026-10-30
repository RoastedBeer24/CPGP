class_name QuickhackData
extends Resource
## 퀵핵 하나의 수치. 손맛 조정은 data/hacking/*.tres를 고친다.

## 퀵핵이 하는 일. 대상(적, 카메라, 문, 포탑)이 apply_quickhack에서 이 값을 보고 처리한다.
enum Effect { CAMERA_SHUTDOWN, DISTRACT, OVERHEAT, WEAPON_GLITCH, OPEN_DOOR, TURRET_TAKEOVER }

@export var id := &""
@export var display_name := ""
@export_multiline var description := ""
@export var effect := Effect.DISTRACT
@export var ram_cost := 2
## 업로드에 걸리는 시간(초). 이 동안 대상은 눈치채지 못한다.
@export var upload_time := 0.8
## 효과가 이어지는 시간(초). 0이면 한 번에 끝난다.
@export var duration := 0.0
## 과열처럼 지속 피해를 주는 퀵핵의 초당 피해 (장갑 무시)
@export var damage_per_second := 0.0
