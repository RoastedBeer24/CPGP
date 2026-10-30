class_name CharacterData
extends Resource
## 고를 수 있는 캐릭터 하나: 이름, 모습(CharacterAppearance), 전투 구성(KitData).
## 모습과 전투 구성은 서로 참조하는 스크립트끼리 미리 불러오면 깨지므로 경로로 두고 쓸 때 불러온다.

@export var id := &""
@export var display_name := ""
@export_file("*.tres") var appearance_path := ""
@export_file("*.tres") var kit_path := ""


func appearance() -> CharacterAppearance:
	return load(appearance_path) as CharacterAppearance


func kit() -> KitData:
	return load(kit_path) as KitData
