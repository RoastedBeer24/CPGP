class_name MovementConfig
extends Resource
## 플레이어 이동과 카메라 수치. 손맛 조정은 코드 대신 data/player/default_movement.tres를 고친다.

@export_group("속도 (m/s)")
## 평소 이동(달리기). 원본 달리기 동작의 원래 속도는 4.3m/s다.
@export var run_speed := 5.0
## 회피 뒤에 회피 키를 누르고 있으면 질주한다. 원본 질주 동작은 6.2m/s다.
@export var sprint_speed := 7.0
## 이동 방향으로 몸을 돌리는 속도(라디안/초)
@export var turn_speed := 14.0

@export_group("가속 (m/s²)")
@export var ground_acceleration := 40.0
@export var ground_deceleration := 40.0
@export var air_acceleration := 10.0

@export_group("점프")
@export var gravity := 18.0
## 지면에서 정점까지의 높이(m)
@export var jump_height := 1.15
## 발판에서 떨어진 직후에도 점프를 받아 주는 시간(초)
@export var coyote_time := 0.1
## 착지 직전에 누른 점프를 기억해 두는 시간(초)
@export var jump_buffer_time := 0.12

@export_group("몸 크기")
@export var height := 1.8
@export var radius := 0.35

@export_group("회피")
## 회피로 움직이는 속도(m/s)와 시간(초). 이동 입력이 있으면 그쪽으로 내닫고, 없으면 뒤로 물러난다.
@export var dodge_speed := 12.0
@export var dodge_duration := 0.3
@export var backstep_speed := 8.0
## 회피를 시작한 뒤 이 시간(초) 동안 무적이다.
@export var dodge_invulnerable := 0.3
## 회피가 끝난 뒤 다시 회피할 수 있을 때까지(초)
@export var dodge_cooldown := 0.25
## 회피가 끝난 뒤 이 시간(초) 안에 공격하면 대시 공격이 나간다.
@export var dash_attack_window := 0.35

@export_group("공격 보조")
## 공격할 때 이 거리(m) 안의 적 쪽으로 몸을 돌린다(대상 고정이 없을 때).
@export var auto_target_range := 5.0
## 경직된 적이 이 거리(m) 안에 있으면 공격 대신 처형이 나간다.
@export var finisher_range := 3.5
## 대상 고정을 걸 수 있는 거리(m). 이보다 멀어지면 풀린다.
@export var lock_on_range := 22.0
## 배틀 스킬 키를 이 시간(초) 넘게 누르고 있으면 궁극기가 나간다(에너지가 찼을 때).
@export var ultimate_hold_time := 0.35

@export_group("카메라")
## 카메라가 도는 중심의 높이(m)
@export var camera_pivot_height := 1.45
## 중심에서 카메라까지의 거리(m). 휠로 바꾼다.
@export var camera_distance := 4.2
@export var camera_min_distance := 2.0
@export var camera_max_distance := 8.0
## 위아래로 돌릴 수 있는 한계(도). 음수가 아래를 내려다보는 쪽이다.
@export var camera_min_pitch := -70.0
@export var camera_max_pitch := 45.0
## 대상 고정 중에 카메라가 대상 쪽으로 돌아가는 빠르기
@export var lock_on_turn_speed := 6.0
## 질주할 때 시야각에 더하는 값(도)
@export var sprint_fov_bonus := 5.0
@export var fov_transition_speed := 6.0


func jump_velocity() -> float:
	return sqrt(2.0 * gravity * jump_height)
