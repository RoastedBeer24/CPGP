class_name WeaponData
extends Resource
## 무기 하나. 원작처럼 캐릭터는 같은 무기군(weapon_type) 안에서 무기를 바꿔 든다(관리자와 아케쿠리는 한손검).
## 무기 모델은 원작 자산이라 저장소에 없다(docs/assets.md). 없으면 코드로 만든 임시 검을 쥔다.

@export var id := &""
@export var display_name := ""
@export_multiline var description := ""
## 무기군: &"sword" 한손검
@export var weapon_type := &"sword"
## 등급(별 수)
@export var rarity := 3
## 무기 모델(.glb): 프로젝트 안 경로와, 실행 파일 옆에서 찾을 경로. 손잡이가 원점이고 칼날이 +Y로 뻗는다.
@export_file("*.glb") var model_path := ""
@export var external_file := ""
@export var scale := 1.0
## 공격력에 더하는 비율 (0.1이면 공격력 +10%)
@export var attack_bonus := 0.0


## 무기 모델 장면. 프로젝트 안 파일이 없으면 실행 파일 옆 파일을 실행 중에 읽는다. 둘 다 없으면 null.
func load_scene() -> PackedScene:
	if not model_path.is_empty() and ResourceLoader.exists(model_path):
		return load(model_path) as PackedScene
	var file := CharacterAppearance.executable_relative(external_file)
	if file.is_empty() or not FileAccess.file_exists(file):
		return null
	return CharacterAppearance.load_gltf_file(file)
