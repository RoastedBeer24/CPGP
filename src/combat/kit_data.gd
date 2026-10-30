class_name KitData
extends Resource
## 캐릭터 한 명의 전투 구성: 기본 공격 연속, 대시 공격, 처형, 배틀 스킬, 궁극기와 기본 수치.
## 수치 조정은 data/kits/*.tres를 고친다.

@export var id := &""
@export var display_name := ""
@export var max_health := 1200.0
## 피해 = 공격력 × 타격 배율
@export var attack_power := 100.0

@export_group("동작")
## 왼쪽 클릭을 이어 누르면 차례로 나간다. 마지막 단계가 끝나면 처음으로 돌아간다.
@export var basic_chain: Array[AttackData] = []
## 회피 직후에 공격하면 나간다.
@export var dash_attack: AttackData
## 경직된 적 가까이에서 공격하면 나간다.
@export var finisher: AttackData
@export var battle_skill: AttackData
@export var ultimate: AttackData

@export_group("SP와 궁극기 에너지")
@export var max_sp := 300.0
## 초당 저절로 차는 SP
@export var sp_regen := 8.0
## 궁극기에 필요한 에너지
@export var max_energy := 80.0
## 완벽한 회피(적의 공격을 회피 무적으로 피함)로 얻는 SP
@export var perfect_dodge_sp := 25.0


## 이름으로 동작을 찾는다. 없으면 null.
func find_attack(attack_id: StringName) -> AttackData:
	for attack in all_attacks():
		if attack.id == attack_id:
			return attack
	return null


func all_attacks() -> Array[AttackData]:
	var found: Array[AttackData] = []
	found.append_array(basic_chain)
	for attack: AttackData in [dash_attack, finisher, battle_skill, ultimate]:
		if attack != null:
			found.append(attack)
	return found
