class_name MovementConfig
extends Resource
## 플레이어 이동 수치. 손맛 조정은 코드 대신 data/player/default_movement.tres를 고친다.

@export_group("속도 (m/s)")
@export var walk_speed := 4.0
@export var sprint_speed := 6.8
@export var crouch_speed := 2.4

@export_group("가속 (m/s²)")
@export var ground_acceleration := 45.0
@export var ground_deceleration := 35.0
@export var air_acceleration := 10.0

@export_group("점프")
@export var gravity := 18.0
## 지면에서 정점까지의 높이(m)
@export var jump_height := 1.15
## 발판에서 떨어진 직후에도 점프를 받아 주는 시간(초)
@export var coyote_time := 0.1
## 착지 직전에 누른 점프를 기억해 두는 시간(초)
@export var jump_buffer_time := 0.12

@export_group("웅크리기")
## true면 웅크리기 키가 토글, false면 누르고 있는 동안만 웅크림
@export var crouch_toggle := true
@export var stand_height := 1.8
@export var crouch_height := 1.1
@export var stand_eye_height := 1.6
@export var crouch_eye_height := 0.95
## 웅크리기 전환 속도 (초당 비율)
@export var crouch_transition_speed := 10.0

@export_group("슬라이딩")
## 이 속도 이상으로 달리다 웅크리면 슬라이딩
@export var slide_min_entry_speed := 5.5
@export var slide_boost_speed := 9.5
@export var slide_friction := 7.0
@export var slide_max_duration := 0.9
## 이 속도 아래로 떨어지면 슬라이딩이 끝남
@export var slide_exit_speed := 3.0

@export_group("턱 오르기")
## 현재 발 높이 기준으로 오를 수 있는 최대 높이(m)
@export var mantle_max_height := 1.6
@export var mantle_min_height := 0.3
## 벽을 감지하는 거리(캡슐 표면 기준, m)
@export var mantle_reach := 0.45
@export var mantle_base_duration := 0.22
@export var mantle_duration_per_meter := 0.12

@export_group("회피")
## 같은 방향키를 이 시간(초) 안에 두 번 누르면 회피
@export var dodge_double_tap_window := 0.25
@export var dodge_speed := 11.0
@export var dodge_duration := 0.18
@export var dodge_cooldown := 0.9

@export_group("전투 중 이동")
## 조준 중 이동 속도 배율
@export var aim_speed_multiplier := 0.6

@export_group("시점")
@export var mouse_sensitivity := 0.0025
@export var base_fov := 80.0
@export var sprint_fov_bonus := 6.0
@export var slide_fov_bonus := 10.0
@export var fov_transition_speed := 8.0

@export_group("3인칭 시점")
## 머리에서 카메라까지의 거리(m). 벽에 막히면 그 앞까지 당겨진다.
@export var third_person_distance := 2.2
## 카메라를 오른쪽(x)과 위(y)로 옮기는 정도(m). 조준점이 캐릭터에 가리지 않게 어깨 너머로 본다.
@export var third_person_shoulder := Vector2(0.5, 0.15)
## 1인칭과 3인칭 사이를 바꾸는 속도 (초당 비율)
@export var camera_switch_speed := 6.0


func jump_velocity() -> float:
	return sqrt(2.0 * gravity * jump_height)
