class_name AttackData
extends Resource
## 캐릭터의 공격 동작 하나(기본 공격 한 단계, 대시 공격, 처형, 배틀 스킬, 궁극기).
## 시간은 모두 동작이 시작된 뒤의 초다.
##
## 원본 동작은 몸(뿌리 뼈)이 앞으로 나가며 휘두른다. 모델 파일에서는 그 이동을 빼고(tools/extract_character.py의
## ROOT_LOCKED), 같은 거리를 advance에 적어 두면 플레이어가 직접 그만큼 나아간다. 그래야 벽과 적에 막히고,
## 다른 피어에도 위치로 전해진다.

@export var id := &""
@export var display_name := ""
## 몸 모델에서 틀 동작 이름 (tools/extract_character.py의 ROLES 이름)
@export var clip := &""
## 이 시간(초)이 지나면 동작이 끝난다.
@export var duration := 0.8
## 이 시각부터 다음 공격으로 이어진다. 그 전에 누른 공격은 기억해 두었다가 이때 낸다.
@export var chain_from := 0.35
## 이 시각부터 이동 입력이 있으면 동작을 끊고 움직인다.
@export var move_cancel_from := 0.6
## 이 시각부터 회피로 동작을 끊을 수 있다.
@export var dodge_cancel_from := 0.0
## 이 시각까지는 목표 쪽으로 몸을 돌린다.
@export var turn_until := 0.12
## 앞으로 나아가는 거리: (시각, 그때까지 나아간 거리 m) 점들. 원본 동작의 뿌리 이동을 잰 값이다.
@export var advance := PackedVector2Array()
## 목표 앞에서 이 거리(m)까지만 나아간다. 적을 지나치지 않게 한다. 0이면 막지 않는다.
@export var stop_short := 1.1
@export var hits: Array[HitData] = []

@export_group("자원")
@export var sp_cost := 0.0
## 궁극기 에너지를 이만큼 다 쓴다.
@export var energy_cost := 0.0
## 동작을 쓰기만 해도 얻는 궁극기 에너지
@export var energy_gain := 0.0
## 한 대 맞힐 때마다 얻는 궁극기 에너지와 SP
@export var energy_per_hit := 1.5
@export var sp_per_hit := 0.0

@export_group("방어")
## 이 시각까지 무적이다(궁극기 연출, 처형 등).
@export var invulnerable_until := 0.0
## 동작 중에 적의 강한 공격에 맞아도 끊기지 않는다.
@export var super_armor := false


## t초까지 나아간 거리(m)
func advance_at(t: float) -> float:
	if advance.is_empty() or t <= advance[0].x:
		return 0.0 if advance.is_empty() else advance[0].y
	for i in range(1, advance.size()):
		var a := advance[i - 1]
		var b := advance[i]
		if t <= b.x:
			return lerpf(a.y, b.y, (t - a.x) / maxf(b.x - a.x, 0.0001))
	return advance[advance.size() - 1].y
