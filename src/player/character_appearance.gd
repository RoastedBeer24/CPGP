class_name CharacterAppearance
extends Resource
## 플레이어 몸으로 쓸 캐릭터 모델과, 코드로 자세를 만들 때 쓸 뼈 이름.
## 모델 파일이 없으면 캡슐 몸으로 대신하므로, 저장소에 올리지 않는 모델도 경로만 적어 둘 수 있다.
##
## 모델을 찾는 순서:
##   1) 프로젝트 안의 model_path (에디터와 개발 중)
##   2) 실행 파일 옆의 external_model_file (내보낸 게임). 실행 중에 glTF를 직접 읽는다.
## 내보낸 게임에는 모델을 넣지 않는다(export_presets.cfg에서 제외). 공개 릴리스에 섞여 나가지 않게 하고,
## 자동 업데이트가 실행 파일만 바꿔도 각자 넣어 둔 모델이 그대로 남게 하기 위함이다.

## 실행 중에 읽은 glTF 장면. 플레이어마다 다시 읽지 않도록 파일 경로별로 한 번만 읽는다.
static var _runtime_scenes: Dictionary[String, PackedScene] = {}

## 프로젝트 안의 모델 파일(.glb) 경로
@export_file("*.glb", "*.gltf", "*.tscn") var model_path := ""
## 실행 파일 옆에서 찾을 모델 파일. 상대 경로면 실행 파일이 있는 폴더 기준이다.
@export var external_model_file := ""
@export var model_scale := 1.0
## glTF 모델은 보통 +Z를 앞으로 보고 있다. Godot 캐릭터의 앞은 -Z라서 돌려 세운다.
@export var faces_positive_z := true

@export_group("뼈 이름")
@export var pelvis_bone := &"Bip001_Pelvis"
@export var spine_bone := &"Bip001_Spine"
@export var chest_bone := &"Bip001_Spine2"
@export var head_bone := &"Bip001_Head"
@export var left_upper_arm_bone := &"Bip001_L_UpperArm"
@export var left_forearm_bone := &"Bip001_L_Forearm"
@export var left_hand_bone := &"Bip001_L_Hand"
@export var right_upper_arm_bone := &"Bip001_R_UpperArm"
@export var right_forearm_bone := &"Bip001_R_Forearm"
@export var right_hand_bone := &"Bip001_R_Hand"
@export var left_thigh_bone := &"Bip001_L_Thigh"
@export var left_calf_bone := &"Bip001_L_Calf"
@export var left_foot_bone := &"Bip001_L_Foot"
@export var right_thigh_bone := &"Bip001_R_Thigh"
@export var right_calf_bone := &"Bip001_R_Calf"
@export var right_foot_bone := &"Bip001_R_Foot"


## 모델 장면. 찾지 못하면 null이다.
func load_model_scene() -> PackedScene:
	if not model_path.is_empty() and ResourceLoader.exists(model_path):
		return load(model_path) as PackedScene
	var file := external_model_path()
	if file.is_empty() or not FileAccess.file_exists(file):
		return null
	return load_gltf_file(file)


## 실행 파일 옆 모델의 실제 경로. 지정하지 않았으면 빈 문자열.
func external_model_path() -> String:
	if external_model_file.is_empty():
		return ""
	if external_model_file.is_absolute_path():
		return external_model_file
	return OS.get_executable_path().get_base_dir().path_join(external_model_file)


## glTF 파일을 실행 중에 읽어 장면으로 만든다. 실패하면 null이다.
static func load_gltf_file(path: String) -> PackedScene:
	if _runtime_scenes.has(path):
		return _runtime_scenes[path]
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var error := document.append_from_file(path, state)
	if error != OK:
		push_warning("캐릭터 모델을 읽지 못했습니다 (%s): %s" % [error_string(error), path])
		return null
	var root := document.generate_scene(state)
	if root == null:
		return null
	# PackedScene은 owner가 장면 뿌리인 노드만 저장한다.
	for node: Node in root.find_children("*", "", true, false):
		node.owner = root
	var scene := PackedScene.new()
	error = scene.pack(root)
	root.free()
	if error != OK:
		return null
	_runtime_scenes[path] = scene
	return scene
