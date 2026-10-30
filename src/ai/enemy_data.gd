class_name EnemyData
extends Resource
## 적 한 종류의 수치. 손맛 조정은 코드 대신 data/enemies/*.tres를 고친다.

@export var display_name := "경비"

@export_group("겉모습")
@export var body_color := Color(0.35, 0.38, 0.45)
@export var visor_color := Color(1, 0.15, 0.15)
## 몸 크기 배율 (보이는 모습만, 충돌 크기는 같다)
@export var body_scale := 1.0

@export_group("체력")
@export var max_health := 80.0
@export var armor := 10.0

@export_group("이동 (m/s)")
@export var walk_speed := 1.6
@export var run_speed := 4.2
## 초당 회전 각도(라디안)
@export var turn_speed := 4.0

@export_group("시야")
@export var eye_height := 1.6
@export var sight_range := 25.0
## 시야 원뿔의 반각(도). 이 안에서만 본다.
@export var sight_half_angle := 60.0
## 이 거리 안이면 가장 빨리 알아챈다.
@export var close_range := 5.0
## 무경계 상태에서 가까이 정면으로 보일 때 감지 게이지가 차는 속도(초당). 1이 되면 전투.
@export var detect_rate := 0.9
## 의심·수색 중에는 이 배율만큼 더 빨리 알아챈다.
@export var alert_detect_multiplier := 1.8
## 웅크린 대상은 이 배율만큼 늦게 알아챈다.
@export var crouch_visibility := 0.5
## 보이는 대상이 없을 때 감지 게이지가 줄어드는 속도(초당)
@export var detect_decay := 0.2
## 감지 게이지가 이 값을 넘으면 의심 상태가 된다.
@export var suspicion_threshold := 0.25
## 시체를 알아챌 수 있는 거리
@export var body_sight_range := 15.0

@export_group("경계")
## 전투를 시작하면 이 거리 안의 동료를 부른다.
@export var alert_radius := 20.0
## 대상을 놓친 뒤 수색으로 넘어가기까지의 시간
@export var lose_target_time := 5.0
## 수색을 이어 가는 시간. 끝나면 경계를 풀고 원래 자리로 돌아간다.
@export var search_time := 15.0
## 의심 상태에서 확인하러 가는 시간
@export var investigate_time := 8.0

@export_group("전투")
@export var damage := 8.0
@export var fire_interval := 1.2
@export var spread_degrees := 3.5
## 대상을 처음 본 뒤 첫 발까지의 시간
@export var reaction_time := 0.6
## 엄폐 지점을 찾는 거리
@export var cover_search_radius := 10.0
## 이 거리보다 멀면 다가간다.
@export var engage_distance := 18.0
