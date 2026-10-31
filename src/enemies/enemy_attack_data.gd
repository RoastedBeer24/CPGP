class_name EnemyAttackData
extends Resource
## 적의 공격 하나. 예고(wind_up) 동안 땅에 맞을 자리를 보여 주고, 예고가 끝나면 맞힌다.

@export var id := &""
## 모델에서 틀 동작 이름 (모델이 없으면 코드로 만든 자세를 쓴다)
@export var clip := &""
## 그 동작에서 맞히는 시각(초, tools/measure_attack_clips.py로 잰다)과 예고를 시작할 때 틀 시각. 예고 동안 clip_from에서
## clip_hit까지를 예고 시간에 맞춘 빠르기로 틀어, 예고가 끝나는 순간에 맞힌다(앞부분을 건너뛰면 뛰어오르는 동작이
## 이미 공중에서 시작했다). clip_hit가 0이면 clip_from부터 원래 빠르기로 튼다.
@export var clip_hit := 0.0
@export var clip_from := 0.0
## 이 거리(m, 몸 가장자리 사이) 안에 목표가 있을 때 쓴다.
@export var min_range := 0.0
@export var max_range := 2.2
## 예고 시간(초). 이 시간이 지나면 맞힌다. 플레이어는 이 사이에 회피한다.
@export var wind_up := 0.8
## 맞힌 뒤 다음 행동까지(초)
@export var recovery := 0.9
## 다시 쓸 수 있을 때까지(초)
@export var cooldown := 2.5
@export var damage := 90.0
## 강한 공격: 맞은 플레이어가 휘청인다(슈퍼 아머 동작 중이면 버틴다).
@export var heavy := false
## 판정: 몸 중심에서 reach(m) 안, 앞쪽 반각 arc(도) 안. 180이면 주위 전체.
@export var reach := 2.4
@export var arc := 60.0
## 맞히는 순간 앞으로 내딛는 거리(m)
@export var lunge := 0.0
## 0보다 크면 돌진 공격: 내디디는 동안(초) 지나는 길의 플레이어를 맞힌다(한 사람당 한 번).
@export var sweep_time := 0.0
## 0보다 크면 원거리 공격: 이 속도(m/s)로 날아가는 탄을 쏜다. reach와 arc는 쓰지 않는다.
@export var projectile_speed := 0.0
