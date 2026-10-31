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
## 3인칭(기본 시점): 카메라가 도는 중심의 높이(m)와 거리(m). 기본 시점은 휠로 당기거나 밀지 않는다.
@export var camera_pivot_height := 1.45
@export var camera_distance := 4.2
## 싸우는 중(적이 나를 알아챘거나 방금 싸웠으면)에는 조금 물러나 주변 적이 보이게 한다(m).
@export var camera_combat_distance := 5.0
## 카메라가 벽·바닥·기둥에 막히면 바로 당기고, 풀리면 이 빠르기(m/초)로 천천히 되돌린다(덜컹이지 않게).
@export var camera_return_speed := 3.0
## 카메라가 벽을 뚫지 않게 재는 공의 반지름(m). 자유 시점에서 얼굴 가까이 갈 때는 작은 공을 쓴다.
@export var camera_probe_radius := 0.2
## 1인칭: 눈 위치를 따라가는 빠르기. 동작으로 머리가 흔들려도 화면이 덜 흔들리게 조금 늦게 따라간다.
@export var first_person_follow := 20.0
## 자유 시점(과 캐릭터 화면): 휠로 당기고 밀 수 있는 범위(m). 가까이 당기면 카메라 중심이 얼굴로 옮겨 가서
## 얼굴을 화면 가득 볼 수 있다.
@export var camera_min_distance := 0.18
@export var camera_max_distance := 18.0
## 자유 시점에서 이 거리(m)보다 가까우면 카메라 중심이 얼굴(눈), 이 거리보다 멀면 몸 가운데다(사이는 섞는다).
@export var camera_face_distance := 0.8
@export var camera_body_distance := 3.0
## 모델이 없을 때 눈 높이(m)
@export var camera_close_pivot_height := 1.55
## 위아래로 돌릴 수 있는 한계(도). 음수가 아래를 내려다보는 쪽이다.
@export var camera_min_pitch := -85.0
@export var camera_max_pitch := 75.0
## 대상 고정 중에 카메라가 대상 쪽으로 돌아가는 빠르기
@export var lock_on_turn_speed := 6.0
## 질주할 때 시야각에 더하는 값(도)
@export var sprint_fov_bonus := 5.0
@export var fov_transition_speed := 6.0


func jump_velocity() -> float:
	return sqrt(2.0 * gravity * jump_height)
