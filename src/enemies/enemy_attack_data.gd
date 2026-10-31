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
## 맞힌 뒤 앞으로 나아가는 거리(m). travel이 있으면 맞힌 뒤 구간을 이 거리로 늘이거나 줄이고, 없으면 맞히는 순간
## 한꺼번에 내디딘다.
@export var lunge := 0.0
## 원작 동작에서 몸(뿌리 뼈)이 앞으로 나아간 거리(m)와 좌우로 돈 각도(도): [동작 시각(초), 값, ...]. tools/extract_enemy.py가
## 잰다(모델 동작에서는 이 이동·회전을 빼서 제자리로 묶는다). 적은 동작의 재생 위치를 따라 이 곡선대로 직접 나아가고
## (벽·플레이어에 막힌다), 모델은 이 각도만큼 돌려 그린다. 예전에는 맞히는 순간 한꺼번에 밀어 줘서 순간이동처럼 보였다.
@export var travel := PackedVector2Array()
@export var turn := PackedVector2Array()
## 0보다 크면 돌진 공격: 내디디는 동안(초) 지나는 길의 플레이어를 맞힌다(한 사람당 한 번).
@export var sweep_time := 0.0
## 0보다 크면 원거리 공격: 이 속도(m/s)로 날아가는 탄을 쏜다. reach와 arc는 쓰지 않는다.
@export var projectile_speed := 0.0


## 공격 동작의 재생 위치(초): 예고 동안(state_time이 예고 시간 wind_up_time 안)은 clip_from에서 clip_hit까지를 예고 시간에
## 맞춰, 맞힌 뒤(recovering)에는 clip_hit부터 원래 빠르기로.
func clip_time(state_time: float, wind_up_time: float, recovering: bool) -> float:
	if recovering:
		return maxf(clip_hit, clip_from) + state_time
	if clip_hit <= clip_from:
		return clip_from + state_time
	return lerpf(clip_from, clip_hit, clampf(state_time / maxf(wind_up_time, 0.05), 0.0, 1.0))


## 동작 시각 time까지 앞으로 나아간 거리(m). 맞힌 뒤 구간은 lunge가 있으면 그 거리가 되게 늘이거나 줄인다
## (end_time은 맞힌 뒤 동작이 끝나는 시각).
func travel_at(time: float, end_time: float) -> float:
	var hit := maxf(clip_hit, clip_from)
	var at_hit := _sample(travel, hit)
	if time <= hit:
		return _sample(travel, time)
	var after := _sample(travel, minf(time, end_time)) - at_hit
	var span := _sample(travel, end_time) - at_hit
	if lunge > 0.0 and absf(span) > 0.01:
		after *= lunge / span
	return at_hit + after


## 동작 시각 time에 몸이 돈 각도(도)
func turn_at(time: float) -> float:
	return _sample(turn, time)


## [시각, 값, ...] 곡선에서 time의 값 (사이는 직선으로 잇는다, 끝 밖은 끝 값)
static func _sample(curve: PackedVector2Array, time: float) -> float:
	if curve.is_empty():
		return 0.0
	if time <= curve[0].x:
		return curve[0].y
	for i in range(1, curve.size()):
		if curve[i].x >= time:
			var a := curve[i - 1]
			var b := curve[i]
			return lerpf(a.y, b.y, (time - a.x) / maxf(b.x - a.x, 0.0001))
	return curve[curve.size() - 1].y
