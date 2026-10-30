class_name HitData
extends Resource
## 공격 동작 안의 타격 한 번. 동작이 시작된 뒤 time초에 캐릭터 앞쪽 부채꼴 안의 적을 맞힌다.

## 원석 결정: 배틀 스킬이 적에게 붙이고, 궁극기가 깨뜨려 추가 피해를 준다.
enum Effect { NONE, APPLY_CRYSTAL, SHATTER_CRYSTAL }

## 동작이 시작된 뒤 판정할 때까지의 시간(초)
@export var time := 0.2
## 공격력에 곱하는 배율
@export var damage := 1.0
## 적의 경직 게이지에 쌓는 양
@export var stagger := 10.0
## 판정 거리(m, 캐릭터 중심에서)
@export var reach := 2.6
## 앞쪽으로 펼쳐진 반각(도). 180이면 주위 전체다.
@export var arc := 70.0
## 맞은 적을 밀어내는 거리(m)
@export var knockback := 0.3
@export var effect := Effect.NONE
## 맞혔을 때 잠깐 멈추는 시간(초)과 화면 흔들림 세기. 타격감을 준다.
@export var hit_stop := 0.05
@export var shake := 0.15
