class_name EnemyData
extends Resource
## 적 종류 하나의 수치와 모습. data/enemies/*.tres

@export var id := &""
@export var display_name := ""
@export var max_health := 900.0

@export_group("경직")
## 경직 게이지. 공격마다 쌓이고, 다 차면 stagger_duration초 동안 경직된다(처형 가능, 받는 피해 증가).
@export var stagger_max := 100.0
@export var stagger_duration := 4.0
## 맞으면 움찔해서 하던 공격이 끊기는지. 덩치 큰 적은 경직될 때까지 버틴다.
@export var flinches := true
## 밀려나는 정도 (1이 보통, 0이면 밀리지 않음)
@export var knockback_scale := 1.0

@export_group("움직임")
@export var move_speed := 3.2
@export var turn_speed := 8.0
@export var radius := 0.45
@export var height := 1.7
## 원거리 적: 목표와 이 거리(m)를 유지하려 한다. 0이면 다가가서 싸운다.
@export var preferred_range := 0.0
## 이 거리(m) 안에 플레이어가 오면 싸움을 건다.
@export var aggro_range := 30.0

@export_group("공격")
@export var attacks: Array[EnemyAttackData] = []

@export_group("모습")
## 모델이 없을 때 쓰는 임시 몸의 색과 크기 배율
@export var color := Color(0.55, 0.58, 0.65)
@export var bulk := 1.0
## 모델 파일 (에셋 폴더 기준 상대 경로, 예: enemies/aggeloi_slug.glb). 없으면 임시 몸으로 그린다.
@export var model_file := ""
@export var model_scale := 1.0
## 모델 동작 이름: 역할(idle, move, hit, stun, dead, 공격의 clip 이름) → 모델 안의 동작 이름
@export var clips: Dictionary[StringName, String] = {}
