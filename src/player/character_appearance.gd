class_name CharacterAppearance
extends Resource
## 플레이어 몸으로 쓸 캐릭터 모델과, 코드로 자세를 만들 때 쓸 뼈 이름.
## 모델 파일이 없으면 캡슐 몸으로 대신하므로, 저장소에 올리지 않는 모델도 경로만 적어 둘 수 있다.

## 모델 파일(.glb) 경로. 비어 있거나 파일이 없으면 캡슐 몸을 쓴다.
@export_file("*.glb", "*.gltf", "*.tscn") var model_path := ""
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


func has_model_file() -> bool:
	return not model_path.is_empty() and ResourceLoader.exists(model_path)
