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

## 실행 중에 읽은 glTF 장면. 플레이어마다 다시 읽지 않도록 파일(경로와 고친 시각)마다 한 번만 읽는다.
## 에셋 자동 업데이트로 파일이 바뀌면 고친 시각이 달라져서 새로 읽는다.
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

@export_group("장비와 옷자락")
## 벗을 수 있는 머리 장비(바이저) 메시. 이 모델은 바이저 본체와 얼굴에 지는 바이저 그림자가 따로 있다.
@export var headgear_meshes: Array[StringName] = [&"S_actor_endminf_cloth_03_lod0", &"S_actor_endminf_cloth_05_lod0"]
## 몸을 따라 흔들리는 옷자락 뼈 사슬("시작 뼈:끝 뼈"). 등에서 늘어진 망토 다섯 갈래다.
## 동작 자세를 따라가되 몸보다 조금 늦게 따라오고, 다리와 땅을 뚫지 않게 물리로 움직인다.
@export var cloth_chains: PackedStringArray = [
	"clothes_pifeng_L_a_1_jnt:clothes_pifeng_L_a_4_jnt",
	"clothes_pifeng_L_b_1_jnt:clothes_pifeng_L_b_4_jnt",
	"clothes_pifeng_M_a_1_jnt:clothes_pifeng_M_a_4_jnt",
	"clothes_pifeng_R_a_1_jnt:clothes_pifeng_R_a_4_jnt",
	"clothes_pifeng_R_b_1_jnt:clothes_pifeng_R_b_4_jnt",
]


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
	var key := "%s@%d" % [path, FileAccess.get_modified_time(path)]
	if _runtime_scenes.has(key):
		return _runtime_scenes[key]
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
	_runtime_scenes[key] = scene
	return scene
