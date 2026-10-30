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
## 실행 중에 읽은 glTF의 이미지(재질이 쓰지 않는 색 띠·마스크 포함): 파일 키 → {이미지 이름: 텍스처}
static var _runtime_images: Dictionary[String, Dictionary] = {}

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
## 몸을 따라 흔들리는 옷자락 뼈 사슬("시작 뼈:끝 뼈"). 등에서 늘어진 망토 다섯 갈래와 후드다.
## 동작 자세를 따라가되 몸보다 조금 늦게 따라오고, 다리와 땅을 뚫지 않게 물리로 움직인다.
@export var cloth_chains: PackedStringArray = [
	"clothes_pifeng_L_a_1_jnt:clothes_pifeng_L_a_4_jnt",
	"clothes_pifeng_L_b_1_jnt:clothes_pifeng_L_b_4_jnt",
	"clothes_pifeng_M_a_1_jnt:clothes_pifeng_M_a_4_jnt",
	"clothes_pifeng_R_a_1_jnt:clothes_pifeng_R_a_4_jnt",
	"clothes_pifeng_R_b_1_jnt:clothes_pifeng_R_b_4_jnt",
	"maozi_a1_M:maozi_a3_M",
]
## 장식 끈. 망토와 후드에 매달려 있어서 그 뒤에 계산하고, 더 가볍게 날린다.
@export var ribbon_chains: PackedStringArray = [
	"piaodai_b_1_ctrl_jnt:piaodai_b_4_ctrl_jnt",
	"piaodai_a_1_ctrl_jnt:piaodai_a_4_ctrl_jnt",
	"piaodai_hou_L_0_skin_jnt:piaodai_hou_L_3_skin_jnt",
	"piaodai_hou_R_0_skin_jnt:piaodai_hou_R_3_skin_jnt",
	"piaodai_back_L_0_skin_jnt:piaodai_back_L_4_skin_jnt",
	"piaodai_back_R_0_skin_jnt:piaodai_back_R_4_skin_jnt",
	"piaodai_c_1_ctrl_jnt:piaodai_c_2_ctrl_jnt",
]
## 머리카락 뼈 사슬(예: "hair_L_d_01_jnt:hair_L_d_04_jnt"). 이 모델은 비워 둔다. 원본 동작에 머리카락 흔들림이
## 이미 들어 있고, 물리를 더하면 몸을 돌 때마다 머리카락이 어색하게 휘날렸다.
@export var hair_chains: PackedStringArray = []

@export_group("재질")
## 얼굴 재질(얼굴, 눈썹, 눈동자). 얼굴 전체를 얼굴이 보는 방향으로 고르게 비춘다(toon.gdshader의 flatness).
@export var face_materials: Array[StringName] = [&"M_actor_endminf_face_01", &"M_actor_endminf_brow_01", &"M_actor_endminf_iris_01"]
## 아래 색에 곱해 그림자만 지우는 재질 → 세기(0~1). 원본은 마스크의 빨간 채널에 그림자를 넣어 두었다(shade_overlay.gdshader).
@export var shade_materials: Dictionary[StringName, float] = {
	&"M_hairshadow_common_03": 1.0,
}
## 숨기는 메시. 눈 흰자 위 그림자 메시는 원본 전용 셰이더 없이는 홍채 위에 곡선 경계의 회색 막처럼 보인다.
@export var hidden_meshes: Array[StringName] = [&"S_actor_endminf_eyeshadow_01_lod0"]
## 만화풍(셀 셰이딩) 재질 → 색 띠(ramp) 이미지. 원본 게임은 빛을 받는 정도를 이 띠의 색으로 바꿔 칠한다
## (그늘은 회색, 경계는 살구색, 밝은 곳은 흰색). 반투명 재질은 기본 재질로 둔다(toon.gdshader).
@export var toon_ramps: Dictionary[StringName, String] = {
	&"M_actor_endminf_body_01": "T_actor_common_body_01_RD",
	&"M_actor_endminf_cloth_01": "T_actor_common_cloth_04_RD",
	&"M_actor_endminf_cloth_03": "T_actor_common_cloth_04_RD",
	&"M_actor_endminf_cloth_04": "T_actor_common_cloth_04_RD",
	&"M_actor_endminf_hair_01": "T_actor_common_hair_01_RD",
	&"M_actor_endminf_face_01": "T_actor_common_face_01_RD",
	&"M_actor_endminf_brow_01": "T_actor_common_face_01_RD",
	&"M_actor_endminf_iris_01": "T_actor_common_face_01_RD",
}
## 빛나는 부분 마스크 이미지 (팔 장치의 하늘색 불빛 등)
@export var emission_masks: Dictionary[StringName, String] = {&"M_actor_endminf_cloth_04": "T_actor_endminf_cloth_04_E"}
## 외곽선 굵기 배율. 없는 재질은 외곽선을 그리지 않는다(눈, 눈썹, 바이저).
@export var outline_widths: Dictionary[StringName, float] = {
	&"M_actor_endminf_body_01": 1.0,
	&"M_actor_endminf_cloth_01": 1.0,
	&"M_actor_endminf_cloth_04": 1.0,
	&"M_actor_endminf_hair_01": 1.0,
	&"M_actor_endminf_face_01": 0.6,
}
## 카메라 쪽으로 당겨 그리는 재질 → 거리(m). 눈썹과 속눈썹이 앞머리 뒤에 가려 이마에 끊긴 선처럼 보여서,
## 원본 게임처럼 앞머리 위에 보이게 한다.
@export var depth_biases: Dictionary[StringName, float] = {&"M_actor_endminf_brow_01": 0.035}
## 숨기는 뼈: 이 뼈를 따르는 정점을 한 점으로 모아 보이지 않게 한다. 눈 하이라이트(흰 마름모)는 원래 게임이
## 따로 움직이는데 처음 자세 그대로면 동공 밖 흰자에 떠 있다.
@export var hidden_bones: Array[StringName] = [&"faceLfHighlightJoint", &"faceRtHighlightJoint"]

## 지금 쓰는 모델의 이미지 (실행 중에 읽은 glTF일 때만)
var _images: Dictionary = {}


## 모델 장면. 찾지 못하면 null이다.
func load_model_scene() -> PackedScene:
	if not model_path.is_empty() and ResourceLoader.exists(model_path):
		return load(model_path) as PackedScene
	var file := external_model_path()
	if file.is_empty() or not FileAccess.file_exists(file):
		return null
	var scene := load_gltf_file(file)
	_images = _runtime_images.get(_cache_key(file), {})
	return scene


## 모델에 들어 있는 이미지를 이름으로 찾는다(재질이 쓰지 않는 색 띠·마스크 포함). 없으면 null.
## 실행 중에 읽은 glTF는 읽을 때 모아 둔 것을, 에디터로 가져온 모델은 꺼내 둔 파일
## ("<모델 파일 이름>_<이미지 이름>.webp")을 쓴다.
func texture(image_name: String) -> Texture2D:
	if _images.has(image_name):
		return _images[image_name]
	var path := "%s_%s.webp" % [model_path.get_basename(), image_name]
	if not model_path.is_empty() and ResourceLoader.exists(path):
		return load(path) as Texture2D
	return null


static func _cache_key(path: String) -> String:
	return "%s@%d" % [path, FileAccess.get_modified_time(path)]


## 실행 파일 옆 모델의 실제 경로. 지정하지 않았으면 빈 문자열.
func external_model_path() -> String:
	if external_model_file.is_empty():
		return ""
	if external_model_file.is_absolute_path():
		return external_model_file
	return OS.get_executable_path().get_base_dir().path_join(external_model_file)


## 실행 중에 읽은 glTF의 텍스처에는 밉맵이 없어서, 멀리서 보면 자글거리고 거칠어 보인다(에디터로 가져온 것은 있다).
## 크기는 원본 그대로 두고 밉맵만 만든다.
static func _add_mipmaps(root: Node) -> void:
	var done := {}
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh := (node as MeshInstance3D).mesh
		if mesh == null:
			continue
		for i in mesh.get_surface_count():
			var material := mesh.surface_get_material(i) as BaseMaterial3D
			if material == null:
				continue
			for slot in BaseMaterial3D.TEXTURE_MAX:
				var texture := material.get_texture(slot) as ImageTexture
				if texture == null or done.has(texture):
					continue
				done[texture] = true
				var image := texture.get_image()
				if image != null and not image.has_mipmaps() and not image.is_compressed():
					image.generate_mipmaps()
					texture.set_image(image)


## glTF 파일을 실행 중에 읽어 장면으로 만든다. 실패하면 null이다.
static func load_gltf_file(path: String) -> PackedScene:
	var key := _cache_key(path)
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
	_add_mipmaps(root)
	var images := {}
	var image_list: Array = state.json.get("images", [])
	var textures := state.get_images()
	for i in mini(image_list.size(), textures.size()):
		images[str((image_list[i] as Dictionary).get("name", ""))] = textures[i]
	_runtime_images[key] = images
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
