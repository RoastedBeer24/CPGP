class_name PlayerBody
extends Node3D
## 플레이어의 몸. 모든 피어의 화면에 보인다(내 카메라가 머리에 붙으면 그림자만 남긴다).
##
## 모델에 애니메이션이 있으면(tools/extract_character.py로 만든 파일) 애니메이션으로 움직인다.
##   - 이동: 속도 구간마다 동작 하나(서기 / 걷기 / 달리기 / 질주)를 골라 부드럽게 바꾸고, 실제 속도에 맞춰 재생 속도를
##     바꾼다(발이 미끄러지지 않게). 싸우는 중에 서 있으면 전투 대기 동작을 한다.
##   - 점프: 도약 → (오래 떨어지면) 낙하 → 착지.
##   - 동작 층: 공격·스킬·회피·크게 맞음·쓰러짐. 동기화된 번호(Player.action_count, dodge_count, hurt_count)가 바뀌면
##     그 동작을 틀어서 원격 플레이어도 같은 동작을 본다. 연속 공격은 이전 동작에서 섞어 넘어간다.
##   - 검: 오른손의 무기 자리(wep_R)에 코드로 만든 검을 쥔다. 원본 모델에는 무기 메시가 없다. 싸우는 중에만 보인다.
##   애니메이션 위에 코드로 덧입히는 것(BodyPoseModifier): 다리 IK(계단에서 발마다 실제 땅 높이에 맞춘다), 얼굴 빛.
##
## 뼈마다 축 방향이 제각각이라 각도 대신 "이 뼈가 몸 기준으로 어느 쪽을 가리켜야 하는지"를 정하고, 그 방향으로 돌린다.
##
## 모델 파일이 없으면(재배포할 수 없는 모델이라 저장소에 없다) 캡슐 몸으로 대신한다.
## 어떤 모델을 쓰는지는 플레이어가 고른 캐릭터(Player.character_id → CharacterData)의 CharacterAppearance에 있다.

enum ViewMode { VISIBLE, SHADOW_ONLY, HIDDEN }

const TOON_SHADER := preload("res://src/player/toon.gdshader")
const TOON_ALPHA_SHADER := preload("res://src/player/toon_alpha.gdshader")
const OUTLINE_SHADER := preload("res://src/player/outline.gdshader")
const SHADE_SHADER := preload("res://src/player/shade_overlay.gdshader")
## 캐릭터를 따로 비추는 렌더 레이어(2번, 값 2)와 그 보조 조명의 세기
const CHARACTER_RENDER_LAYER := 2
const CHARACTER_LIGHT_ENERGY := 0.4
## 외곽선 굵기(m), 얼굴을 고르게 비추는 정도, 빛나는 부분의 세기
const OUTLINE_WIDTH := 0.0012
const FACE_FLATNESS := 0.85
const EMISSION_ENERGY := 2.0

## 몸 기준 앞(-Z)과 오른쪽(+X)
const FORWARD := Vector3(0, 0, -1)
const RIGHT := Vector3(1, 0, 0)
## 원격 플레이어의 속도를 잴 때 이보다 빠르면 순간이동으로 본다(m/s).
const MAX_TRACKED_SPEED := 15.0
## 있어야 애니메이션 모드로 움직이는 동작
const REQUIRED_ANIMATIONS: Array[StringName] = [&"idle", &"walk", &"run", &"sprint", &"fall"]
## 속도 구간마다 고르는 이동 동작
const LOCOMOTION_STATES: Array[StringName] = [&"idle", &"walk", &"run", &"sprint"]
## 이동 동작의 원래 속도(m/s). 실제 속도/원래 속도로 재생 속도를 맞춘다.
const NATURAL_SPEEDS := {&"walk": 1.0, &"run": 4.3, &"sprint": 6.2}
## 이동 동작을 바꾸는 속도(m/s)와 경계에서 깜빡이지 않게 두는 여유
const WALK_FROM := 0.3
const RUN_FROM := 1.8
const SPRINT_FROM := 5.8
const HYSTERESIS := 0.25
## 이보다 오래 공중에 있으면 낙하 동작으로 바꾼다(초). 턱을 내려갈 때마다 깜빡이지 않게 한다.
const AIR_DELAY := 0.12

## 동작 층에서 트는 동작들 (모델에 있는 것만 쓴다)
const ACTION_CLIPS: Array[StringName] = [
	&"attack_1", &"attack_2", &"attack_3", &"attack_4", &"attack_5", &"dash_attack", &"finisher", &"skill", &"ultimate",
	&"dodge_f", &"dodge_b", &"hit_heavy", &"dead",
]
## 공격이 아닌 동작 (상태가 바뀌어도 끝까지 보여 준다)
const NON_ATTACK_CLIPS: Array[StringName] = [&"dodge_f", &"dodge_b", &"hit_heavy", &"dead"]
## 동작이 바뀔 때 섞는 시간, 들어오고 나갈 때 섞는 시간(초)
const ACTION_CROSSFADE := 0.1
const ACTION_FADE_IN := 0.06
const ACTION_FADE_OUT := 0.22
## 회피 동작을 보여 주는 시간(초). 회피(0.3초)가 끝나도 질주로 이어지는 앞부분까지 보여 준다.
const DODGE_SHOW_TIME := 0.42

## 옷자락 물리: 망토·후드(사슬이 굵고 무겁다), 장식 끈(가볍다), 머리카락
const CLOTH_STIFFNESS := 6.0
const CLOTH_DRAG := 0.6
const CLOTH_GRAVITY := 2.0
const CLOTH_RADIUS := 0.03
const CLOTH_TAIL := 0.12
## 옷자락이 뚫지 않을 팔다리와 골반의 두께(m)
const THIGH_RADIUS := 0.08
const CALF_RADIUS := 0.06
const HIPS_RADIUS := 0.13
## 한 프레임에 이보다 멀리 움직이면 옷자락 물리를 처음부터 다시 한다(m, 순간이동)
const TELEPORT_DISTANCE := 2.0
const RIBBON_STIFFNESS := 5.0
const RIBBON_DRAG := 0.55
const RIBBON_GRAVITY := 1.5
const HAIR_STIFFNESS := 10.0
const HAIR_DRAG := 0.5
const HAIR_GRAVITY := 0.3
## 끈과 머리카락 가닥의 두께(m)
const STRAND_RADIUS := 0.02
## 발 IK가 딛는 물리 레이어: world(1)와 계단 디딤판(foot_ground, 5번 = 16)
const FOOT_GROUND_LAYER := 16
const FOOT_RAY_MASK := 1 | FOOT_GROUND_LAYER

## 무기 모델이 없을 때 코드로 만드는 검: 손잡이 끝에서 칼끝까지(m)와, 무기 자리 기준으로 칼날이 뻗는 방향
const SWORD_LENGTH := 1.0
const SWORD_AXIS := Vector3.UP
## 무기 자리를 찾지 못한 모델에서 손 뼈 기준으로 검을 쥐는 위치
const SWORD_HAND_OFFSET := Vector3(0.07, 0.02, 0.0)

## 비워 두면 플레이어가 고른 캐릭터의 모습을 쓴다.
@export var appearance: CharacterAppearance

var view_mode := ViewMode.VISIBLE
## 캐릭터 모델을 불러왔으면 true. false면 캡슐 몸이다.
var has_model := false
## 모델의 애니메이션으로 움직이면 true
var animated := false
## 발밑 땅이 캡슐이 선 바닥보다 얼마나 높은지(m). x는 왼발, y는 오른발. 계단에서 발 IK가 쓴다.
var foot_offsets := Vector2.ZERO
## 지금 쓰는 이동 동작 이름 (idle, walk, run, sprint, battle_idle)
var locomotion := &"idle"

var _model: Node3D
var _skeleton: Skeleton3D
var _tree: AnimationTree
var _tree_nodes: Dictionary[StringName, bool] = {}
## 한 번 트는 동작의 재생 속도와 처음 고를 종류 (나무를 만든 뒤 넣는다)
var _one_shot_speeds: Dictionary[StringName, float] = {}
var _first_kinds: Dictionary[StringName, StringName] = {}
var _locomotion_states: Array[StringName] = []
var _bone: Dictionary[StringName, int] = {}
## 뼈대 공간 → 모델 공간 변환. 뼈대의 부모 노드가 동작에 따라 움직이므로 _update_space()에서 매번 구한다.
var _model_from_skeleton := Transform3D.IDENTITY
## 뼈대 공간 → 몸 공간 변환 (모델을 들어 올리거나 내리기 전 기준)
var _body_from_skeleton := Transform3D.IDENTITY
var _to_skeleton := Basis.IDENTITY
var _rest_foot_height := 0.0
var _upper_arm_length := 0.0
var _forearm_length := 0.0
var _thigh_length := 0.0
var _calf_length := 0.0
var _model_base_position := Vector3.ZERO
var _model_base_yaw := 0.0
## 몸(플레이어 방향) 기준으로 모델이 돌아간 각도. 플레이어가 직접 가는 쪽을 보므로 0이다.
var _model_yaw := 0.0
## 모델을 내린 높이 (몸 기준, 내리면 음수)
var _ground_offset := 0.0
var _pelvis_drop := 0.0
# 벗을 수 있는 머리 장비(바이저) 메시와, 지금 보이는지
var _headgear: Array[GeometryInstance3D] = []
var _headgear_on := true
# 얼굴 메시(얼굴, 눈썹, 눈동자)와, 머리 뼈 공간에서 얼굴 정면·오른쪽 방향
var _face_meshes: Array[GeometryInstance3D] = []
var _face_axis := Vector3.ZERO
var _face_right_axis := Vector3.ZERO
## 숨기는 뼈(눈 하이라이트)
var _hidden_bones: Array[int] = []
# 옷자락 물리와, 옷자락이 뚫지 않을 땅
var _cloth: SpringBoneSimulator3D
var _cloth_ground: SpringBoneCollisionPlane3D
var _last_position := Vector3.ZERO
var _sword: Node3D
## 동작에 맞춰 원작 소리·보이스를 낸다. 꾸러미가 없으면 소리 없이 돈다.
var fx: CharacterFx

# 움직임 재기 (원격 플레이어는 위치가 네트워크로 띄엄띄엄 오므로 바뀐 시간 간격으로 잰다)
var _sample_position := Vector3.ZERO
var _since_sample := 0.0
var _remote_velocity := Vector3.ZERO
var _air_time := 0.0
var _was_airborne := false
var _last_jump_count := 0
var _last_dodge_count := 0
var _last_action_count := 0
var _last_hurt_count := 0

# 동작 층: 동작을 고르는 노드와 섞는 노드, 모델에 있는 동작들
var _action_choice: AnimationNodeTransition
var _action_blend: AnimationNodeBlend2
var _action_clips: Array[StringName] = []
## 지금 보여 주는 동작과, 보여 줄 시간·지난 시간(초)
var _action_clip := &""
var _action_end := 0.0
var _action_elapsed := 100.0
## 동작이 보이는 정도 (0~1)
var _action_amount := 0.0

# 이번 프레임의 움직임 (애니메이션 위에 자세를 덧입힐 때 다시 쓴다)
var _speed := 0.0
var _move_dir := FORWARD
var _airborne := false
var _delta := 0.0

@onready var player: Player = owner as Player
@onready var placeholder: MeshInstance3D = $Placeholder


func _ready() -> void:
	if appearance == null and player != null:
		# 플레이어와 서로 참조하는 중에 리소스를 미리 불러오면 깨지므로 실행 시점에 불러온다.
		var character := Characters.find(player.character_id)
		appearance = character.appearance() if character != null else null
	var scene := appearance.load_model_scene() if appearance != null else null
	if scene != null:
		_load_model(scene)
	_sample_position = global_position


func set_view_mode(mode: ViewMode) -> void:
	view_mode = mode
	visible = mode != ViewMode.HIDDEN
	for node: Node in find_children("*", "GeometryInstance3D", true, false):
		_apply_shadow_mode(node as GeometryInstance3D)

## 뼈의 몸 기준 위치. 모델이 없거나 뼈 이름이 없으면 Vector3.ZERO.
## 애니메이션 위에 덧입힌 자세(IK)는 그리는 프레임에만 남으므로 여기서는 애니메이션 자세가 나온다.
func bone_position(bone_name: StringName) -> Vector3:
	if _skeleton == null:
		return Vector3.ZERO
	var index := _skeleton.find_bone(bone_name)
	if index < 0:
		return Vector3.ZERO
	_update_space()
	return _body_from_skeleton * _skeleton.get_bone_global_pose(index).origin + Vector3.UP * _ground_offset

## 모델(다리)이 바라보는 방향 (몸 기준).
func facing() -> Vector3:
	return FORWARD.rotated(Vector3.UP, _model_yaw)

## 캐릭터만 비추는 약한 보조 조명을 만든다. 카메라에 붙이면 카메라 쪽에서 캐릭터 앞면을 비춰, 어두운 곳에서도
## 얼굴과 옷이 보인다(원본 게임처럼 캐릭터를 배경과 따로 비춘다). 주변(레이어 1)은 비추지 않는다.
static func make_character_light() -> DirectionalLight3D:
	var light := DirectionalLight3D.new()
	light.name = "CharacterLight"
	light.light_energy = CHARACTER_LIGHT_ENERGY
	light.light_cull_mask = CHARACTER_RENDER_LAYER
	light.light_specular = 0.0
	light.shadow_enabled = false
	return light

## 머리 장비(바이저) 메시가 있는 모델인지
func has_headgear() -> bool:
	return not _headgear.is_empty()

## 머리 장비(바이저)가 보이는지
func headgear_shown() -> bool:
	return has_headgear() and _headgear[0].visible

## 옷자락 물리를 쓰는지 (모델에 옷자락 뼈가 있으면)
func has_cloth() -> bool:
	return _cloth != null

## 모델을 내린 높이(m, 양수). 계단에서 낮은 쪽 발에 맞춰 골반을 내린 만큼이다.
func pelvis_drop() -> float:
	return _pelvis_drop

## 지금 보이는 동작 중 가장 눈에 띄는 것 (테스트와 디버그용). 애니메이션 모드가 아니면 빈 이름.
func dominant_animation() -> StringName:
	if not animated:
		return &""
	if _action_amount > 0.5:
		return _action_clip
	for shot: StringName in [&"land", &"jump"]:
		if _tree_nodes.has(shot) and bool(_tree.get(StringName("parameters/%s/active" % shot))):
			return shot
	if _airborne:
		return &"fall"
	return locomotion


## 검을 들고 있는지 (싸우는 중에만 보인다)
func sword_shown() -> bool:
	return _sword != null and _sword.visible

func _process(delta: float) -> void:
	if player == null or delta <= 0.0:
		return
	var velocity := global_basis.orthonormalized().inverse() * _measure_velocity(delta)
	if not has_model:
		return
	if player.visor_on != _headgear_on:
		_headgear_on = player.visor_on
		for mesh in _headgear:
			mesh.visible = _headgear_on
	if _cloth != null and global_position.distance_to(_last_position) > TELEPORT_DISTANCE:
		_cloth.reset()
	_last_position = global_position
	if _sword != null:
		_sword.visible = player.in_combat or _action_amount > 0.01
	if _skeleton == null or not visible:
		return
	_read_motion(delta, velocity)
	if animated:
		_drive_animation(delta)
	else:
		_update_face_light()
		_hide_bones()

## 지금 속도(세상 기준). 내가 조종하는 플레이어는 물리 엔진의 실제 속도를 쓴다.
## 원격 플레이어는 위치가 바뀐 간격으로 잰다. 그리는 프레임마다 위치를 빼면, 물리(60fps)보다
## 화면이 자주 그려질 때 속도가 0과 큰 값 사이를 오가서 동작이 깜빡인다.
func _measure_velocity(delta: float) -> Vector3:
	if player.is_multiplayer_authority():
		return player.get_real_velocity().limit_length(MAX_TRACKED_SPEED)
	_since_sample += delta
	var moved := global_position - _sample_position
	if moved.length_squared() > 1e-8:
		if moved.length() < 3.0:
			var raw := (moved / maxf(_since_sample, 1.0 / 120.0)).limit_length(MAX_TRACKED_SPEED)
			_remote_velocity = _remote_velocity.lerp(raw, 0.5)
		_sample_position = global_position
		_since_sample = 0.0
	elif _since_sample > 0.15:
		_remote_velocity = Vector3.ZERO
	return _remote_velocity

func _read_motion(delta: float, velocity: Vector3) -> void:
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var raw_speed := horizontal.length()
	_delta = delta
	_speed = lerpf(_speed, raw_speed, minf(delta * 15.0, 1.0))
	_air_time = _air_time + delta if player.state == Player.State.AIR else 0.0
	_airborne = _air_time > AIR_DELAY
	if raw_speed > 0.3:
		_move_dir = horizontal / raw_speed

# ---- 모델 불러오기 ----
func _load_model(scene: PackedScene) -> void:
	_model = scene.instantiate() as Node3D
	_model.name = "Model"
	_model.scale = Vector3.ONE * appearance.model_scale
	if appearance.faces_positive_z:
		_model_base_yaw = PI
	_model.rotation.y = _model_base_yaw
	add_child(_model)
	_model_base_position = _model.position
	has_model = true
	placeholder.queue_free()
	placeholder = null
	for geometry: Node in _model.find_children("*", "GeometryInstance3D", true, false):
		(geometry as GeometryInstance3D).layers |= CHARACTER_RENDER_LAYER
	for mesh_name: StringName in appearance.hidden_meshes:
		var hidden := _model.find_child(String(mesh_name), true, false) as GeometryInstance3D
		if hidden != null:
			hidden.visible = false
	for mesh_name: StringName in appearance.headgear_meshes:
		var mesh := _model.find_child(String(mesh_name), true, false) as GeometryInstance3D
		if mesh != null:
			_headgear.append(mesh)

	var skeletons := _model.find_children("*", "Skeleton3D", true, false)
	if skeletons.is_empty():
		return
	var skeleton := skeletons[0] as Skeleton3D
	var names: Dictionary[StringName, StringName] = {
		&"pelvis": appearance.pelvis_bone,
		&"spine": appearance.spine_bone,
		&"chest": appearance.chest_bone,
		&"head": appearance.head_bone,
		&"upper_arm_l": appearance.left_upper_arm_bone,
		&"forearm_l": appearance.left_forearm_bone,
		&"hand_l": appearance.left_hand_bone,
		&"upper_arm_r": appearance.right_upper_arm_bone,
		&"forearm_r": appearance.right_forearm_bone,
		&"hand_r": appearance.right_hand_bone,
		&"thigh_l": appearance.left_thigh_bone,
		&"calf_l": appearance.left_calf_bone,
		&"foot_l": appearance.left_foot_bone,
		&"thigh_r": appearance.right_thigh_bone,
		&"calf_r": appearance.right_calf_bone,
		&"foot_r": appearance.right_foot_bone,
	}
	for role: StringName in names:
		var index := skeleton.find_bone(names[role])
		if index < 0:
			push_warning("캐릭터 모델에 뼈 %s가 없어 자세를 만들지 않습니다." % names[role])
			return
		_bone[role] = index
	_skeleton = skeleton

	_update_space()
	_skeleton.reset_bone_poses()
	_rest_foot_height = minf(_posed_point(&"foot_l").y, _posed_point(&"foot_r").y)
	_upper_arm_length = _skeleton.get_bone_rest(_bone[&"forearm_r"]).origin.length()
	_forearm_length = _skeleton.get_bone_rest(_bone[&"hand_r"]).origin.length()
	_thigh_length = _skeleton.get_bone_rest(_bone[&"calf_l"]).origin.length()
	_calf_length = _skeleton.get_bone_rest(_bone[&"foot_l"]).origin.length()
	# 처음 자세에서 몸 앞쪽이 머리 뼈 공간의 어느 방향인지 (얼굴을 비출 방향을 매 프레임 구할 때 쓴다)
	var head_rest := _skeleton.get_bone_global_rest(_bone[&"head"]).basis.orthonormalized()
	_face_axis = (head_rest.inverse() * (_to_skeleton * FORWARD)).normalized()
	_face_right_axis = (head_rest.inverse() * (_to_skeleton * RIGHT)).normalized()
	for bone_name in appearance.hidden_bones:
		var index := _skeleton.find_bone(bone_name)
		if index >= 0:
			_hidden_bones.append(index)
	_setup_materials()
	_setup_animation()
	_setup_cloth()
	_attach_weapon()
	fx = CharacterFx.new()
	fx.name = "Fx"
	add_child(fx)
	fx.setup(appearance.fx_file())

## 원본 게임 전용 셰이더로 그리던 재질을 Godot에서 비슷하게 보이게 바꾼다.
##   - 만화풍(셀 셰이딩, toon.gdshader): 빛을 받는 정도를 원본의 색 띠(ramp)로 칠하고, 테두리 빛과 외곽선
##     (outline.gdshader)을 더한다. 빛나는 부분 마스크가 있으면 빛나게 한다.
##   - 얼굴(얼굴, 눈썹, 눈동자): 같은 재질이되 얼굴이 보는 방향으로 고르게 비춘다. 보통 조명은 얼굴이 반으로 갈라진다.
##   - 그림자 메시(눈 흰자 위, 앞머리): 아래 색에 곱한다(shade_overlay.gdshader). 그냥 칠하면 하늘색 줄이 생긴다.
##     반투명 재질(코트 겉감, 머리카락 끝)은 같은 그림을 반투명으로 그리고(toon_alpha.gdshader) 외곽선은 넣지 않는다.
##   - 색 띠가 없는 재질: 기본 재질 그대로, 비스듬히 봐도 흐려지지 않게 비등방 필터만 켠다.
## 재질은 모델을 쓰는 플레이어끼리 함께 쓰므로, 메시마다 덮어쓰는 재질(surface override)로 바꾼다.
func _setup_materials() -> void:
	for node: Node in _model.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		for i in mesh_instance.mesh.get_surface_count():
			var material := mesh_instance.mesh.surface_get_material(i) as BaseMaterial3D
			if material == null:
				continue
			var material_name := StringName(material.resource_name)
			if appearance.shade_materials.has(material_name):
				_set_material(mesh_instance, i, _shade_material(material, appearance.shade_materials[material_name]))
				continue
			var ramp_name: String = appearance.toon_ramps.get(material_name, "")
			var ramp := appearance.texture(ramp_name) if not ramp_name.is_empty() else null
			if ramp == null:
				material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
				continue
			var scissor := material.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
			var see_through := not scissor and material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED
			var cutoff := material.alpha_scissor_threshold if scissor else 0.0
			var toon := ShaderMaterial.new()
			toon.shader = TOON_ALPHA_SHADER if see_through else TOON_SHADER
			toon.set_shader_parameter(&"albedo_texture", material.albedo_texture)
			toon.set_shader_parameter(&"albedo_color", material.albedo_color)
			toon.set_shader_parameter(&"ramp", ramp)
			toon.set_shader_parameter(&"alpha_scissor", cutoff)
			if appearance.face_shadow_materials.has(material_name):
				var shadow_map := appearance.texture(appearance.face_shadow_map)
				if shadow_map != null:
					toon.set_shader_parameter(&"face_shadow_map", shadow_map)
					toon.set_shader_parameter(&"use_face_shadow", true)
			if appearance.face_materials.has(material_name):
				toon.set_shader_parameter(&"flatness", FACE_FLATNESS)
				toon.set_shader_parameter(&"rim_strength", 0.15)
				if not _face_meshes.has(mesh_instance):
					_face_meshes.append(mesh_instance)
			toon.set_shader_parameter(&"depth_bias", appearance.depth_biases.get(material_name, 0.0))
			toon.set_shader_parameter(&"gloss_strength", appearance.gloss_materials.get(material_name, 0.0))
			var normal_name: String = appearance.normal_maps.get(material_name, "")
			var normal_map := appearance.texture(normal_name) if not normal_name.is_empty() else null
			if normal_map != null:
				toon.set_shader_parameter(&"normal_texture", normal_map)
				toon.set_shader_parameter(&"use_normal_map", true)
			var mask_name: String = appearance.emission_masks.get(material_name, "")
			var mask := appearance.texture(mask_name) if not mask_name.is_empty() else null
			if mask != null:
				toon.set_shader_parameter(&"emission_mask", mask)
				toon.set_shader_parameter(&"emission_energy", EMISSION_ENERGY)
			if appearance.outline_widths.has(material_name) and not see_through:
				var outline := ShaderMaterial.new()
				outline.shader = OUTLINE_SHADER
				outline.set_shader_parameter(&"albedo_texture", material.albedo_texture)
				outline.set_shader_parameter(&"width", OUTLINE_WIDTH * appearance.outline_widths[material_name])
				outline.set_shader_parameter(&"alpha_scissor", cutoff)
				toon.next_pass = outline
			_set_material(mesh_instance, i, toon)
	# 얼굴 빛 방향은 메시마다 넣는 값(instance uniform)이다. 재질이 빈 면이 하나라도 있으면 렌더러가 오류를 내므로 뺀다.
	_face_meshes = _face_meshes.filter(func(face: GeometryInstance3D) -> bool: return _all_surfaces_have_material(face as MeshInstance3D))

## 메시의 한 면에 재질을 입힌다. 면이 하나뿐이면 메시 전체 재질(material_override)로 넣는다. 실행 중에 읽은 glTF의
## 눈동자 메시는 면별 재질을 넣으면 화면 없는 실행(테스트)의 렌더러가 오류를 냈다(보기는 같다).
static func _set_material(mesh_instance: MeshInstance3D, surface: int, material: Material) -> void:
	if mesh_instance.mesh.get_surface_count() == 1:
		mesh_instance.material_override = material
	else:
		mesh_instance.set_surface_override_material(surface, material)


static func _all_surfaces_have_material(mesh_instance: MeshInstance3D) -> bool:
	for i in mesh_instance.mesh.get_surface_count():
		if mesh_instance.get_active_material(i) == null:
			return false
	return true


## 아래 색에 곱해 그림자만 지우는 재질 (눈 흰자 위, 앞머리 그림자)
func _shade_material(material: BaseMaterial3D, strength: float) -> ShaderMaterial:
	var shade := ShaderMaterial.new()
	shade.shader = SHADE_SHADER
	shade.set_shader_parameter(&"mask", material.albedo_texture)
	shade.set_shader_parameter(&"use_mask", material.albedo_texture != null)
	shade.set_shader_parameter(&"shade", material.albedo_color.r)
	shade.set_shader_parameter(&"strength", strength)
	return shade

## 숨기는 뼈(눈 하이라이트)를 한 점으로 줄인다. 그 뼈만 따르는 정점이 모여서 보이지 않는다.
func _hide_bones() -> void:
	for index in _hidden_bones:
		_skeleton.set_bone_pose_scale(index, Vector3.ONE * 0.0001)

## 얼굴을 비출 방향을 머리 뼈의 지금 방향으로 맞춘다 (toon.gdshader의 face_forward).
func _update_face_light() -> void:
	if _face_meshes.is_empty():
		return
	var head := _skeleton.get_bone_global_pose(_bone[&"head"]).basis.orthonormalized()
	var to_world := _skeleton.global_basis.orthonormalized()
	var forward := (to_world * (head * _face_axis)).normalized()
	var right := (to_world * (head * _face_right_axis)).normalized()
	for mesh in _face_meshes:
		mesh.set_instance_shader_parameter(&"face_forward", forward)
		mesh.set_instance_shader_parameter(&"face_right", right)

## 옷자락(망토)을 물리로 흔든다(SpringBoneSimulator3D). 동작 자세를 따라가되 조금 늦게 따라오고,
## 아래로 처지며, 다리·골반·땅을 뚫지 않는다. 덧입힌 자세(BodyPoseModifier) 다음에 계산해야 IK로 옮긴 다리와
## 부딪히므로 그 뒤에 붙인다.
## 계산은 뼈대(Skeleton3D) 기준으로 한다. 세상 기준이면 플레이어가 달리거나 몸을 돌 때마다 옷자락이 크게 휘날려
## 어색했다(뛸 때 펄럭임은 원본 동작에 이미 있다). Godot 4.5는 다른 노드나 뼈를 기준으로 하면 충돌 모양의
## 위치를 잘못 옮기는데(get_transform_from_skeleton의 곱 순서), 뼈대 자신을 기준으로 하면 그 변환이 단위 행렬이라
## 틀리지 않는다. 대신 중력 방향을 뼈대 기준으로 바꿔 매 프레임 넣는다(_update_cloth_gravity).
func _setup_cloth() -> void:
	# 무리마다 (사슬들, 돌아가는 힘, 흔들림 줄임, 처짐, 두께, 다리·땅과 부딪히는지). 망토와 후드에 매달린 끈이 있어서
	# 망토 → 끈 순서로 계산한다. 머리카락은 다리나 땅에 닿을 일이 없다.
	var groups: Array[Array] = [
		[appearance.cloth_chains, CLOTH_STIFFNESS, CLOTH_DRAG, CLOTH_GRAVITY, CLOTH_RADIUS, true],
		[appearance.ribbon_chains, RIBBON_STIFFNESS, RIBBON_DRAG, RIBBON_GRAVITY, STRAND_RADIUS, true],
		[appearance.hair_chains, HAIR_STIFFNESS, HAIR_DRAG, HAIR_GRAVITY, STRAND_RADIUS, false],
	]
	var settings: Array[Array] = []
	for group in groups:
		for chain: String in group[0]:
			var ends := chain.split(":")
			if ends.size() == 2 and _is_chain(_skeleton.find_bone(ends[0]), _skeleton.find_bone(ends[1])):
				settings.append([ends[0], ends[1]] + group.slice(1))
	if settings.is_empty():
		return
	_cloth = SpringBoneSimulator3D.new()
	_cloth.name = "Cloth"
	_skeleton.add_child(_cloth)
	_add_limb_collision(&"thigh_l", &"calf_l", THIGH_RADIUS)
	_add_limb_collision(&"calf_l", &"foot_l", CALF_RADIUS)
	_add_limb_collision(&"thigh_r", &"calf_r", THIGH_RADIUS)
	_add_limb_collision(&"calf_r", &"foot_r", CALF_RADIUS)
	var hips := SpringBoneCollisionSphere3D.new()
	_cloth.add_child(hips)
	hips.bone_name = _skeleton.get_bone_name(_bone[&"pelvis"])
	hips.radius = HIPS_RADIUS
	_cloth_ground = SpringBoneCollisionPlane3D.new()
	_cloth.add_child(_cloth_ground)
	_cloth.setting_count = settings.size()
	for i in settings.size():
		var setting := settings[i]
		_cloth.set_root_bone_name(i, setting[0])
		_cloth.set_end_bone_name(i, setting[1])
		_cloth.set_extend_end_bone(i, true)
		_cloth.set_end_bone_length(i, CLOTH_TAIL)
		_cloth.set_center_from(i, SpringBoneSimulator3D.CENTER_FROM_NODE)
		_cloth.set_center_node(i, _cloth.get_path_to(_skeleton))
		_cloth.set_stiffness(i, setting[2])
		_cloth.set_drag(i, setting[3])
		_cloth.set_gravity(i, setting[4])
		_cloth.set_radius(i, setting[5])
		_cloth.set_enable_all_child_collisions(i, setting[6])

## 끝 뼈가 시작 뼈 아래에 매달린 사슬인지. 관리자(남)의 등 끈 하나는 마디마다 등뼈에 따로 붙어 있어 사슬이 아니다.
func _is_chain(root: int, end: int) -> bool:
	if root < 0 or end < 0:
		return false
	var bone := end
	while bone >= 0:
		if bone == root:
			return true
		bone = _skeleton.get_bone_parent(bone)
	return false


## 옷자락 물리는 뼈대 기준으로 계산하므로, 세상의 아래 방향을 뼈대 기준으로 바꿔 넣는다.
func _update_cloth_gravity() -> void:
	if _cloth == null:
		return
	var down := (_skeleton.global_basis.orthonormalized().inverse() * Vector3.DOWN).normalized()
	for i in _cloth.setting_count:
		_cloth.set_gravity_direction(i, down)

## 팔다리 한 마디(role에서 child_role까지)를 감싸는 원기둥. 옷자락이 이것을 뚫지 않는다.
func _add_limb_collision(role: StringName, child_role: StringName, radius: float) -> void:
	var capsule := SpringBoneCollisionCapsule3D.new()
	_cloth.add_child(capsule)
	capsule.bone_name = _skeleton.get_bone_name(_bone[role])
	# 자식 뼈의 처음 위치가 이 뼈 공간에서 본 마디의 방향과 길이다. 원기둥(세로가 Y)을 그 방향으로 눕혀 가운데에 둔다.
	var along := _skeleton.get_bone_rest(_bone[child_role]).origin
	capsule.position_offset = along * 0.5
	capsule.rotation_offset = Quaternion(Vector3.UP, along.normalized())
	capsule.radius = radius
	capsule.height = along.length() + radius * 2.0

## 뼈대 공간과 몸 공간의 관계를 다시 구한다(모델을 내리기 전 기준). 모델이 돌 때만이 아니라, 뼈대의 부모
## 노드(Bip001)도 동작에 따라 움직이므로(공격 동작은 몸을 낮추거나 띄운다) 동작이 적용될 때마다 구해야 한다.
func _update_space() -> void:
	_model_from_skeleton = _model.global_transform.affine_inverse() * _skeleton.global_transform
	var model := Transform3D(_model.transform.basis, _model_base_position)
	_body_from_skeleton = model * _model_from_skeleton
	_to_skeleton = _body_from_skeleton.basis.orthonormalized().inverse()

func _apply_shadow_mode(geometry: GeometryInstance3D) -> void:
	if view_mode == ViewMode.SHADOW_ONLY:
		geometry.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	else:
		geometry.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

# ---- 애니메이션 모드: 동작 나무 ----
func _setup_animation() -> void:
	var players := _model.find_children("*", "AnimationPlayer", true, false)
	if players.is_empty():
		return
	var animation_player := players[0] as AnimationPlayer
	_normalize_animation_names(animation_player)
	for name in REQUIRED_ANIMATIONS:
		if not animation_player.has_animation(name):
			return

	# 이동: 동작마다 재생 속도 노드를 달고, 속도 구간에 따라 하나를 고른다(교차 0.25초).
	var root := AnimationNodeBlendTree.new()
	var moves := AnimationNodeTransition.new()
	moves.xfade_time = 0.25
	root.add_node(&"locomotion", moves)
	_locomotion_states = LOCOMOTION_STATES.duplicate()
	if animation_player.has_animation(&"battle_idle"):
		_locomotion_states.append(&"battle_idle")
	var index := 0
	for name: StringName in _locomotion_states:
		moves.add_input(String(name))
		root.add_node(StringName(name + "_clip"), _clip(name))
		root.add_node(StringName(name + "_speed"), AnimationNodeTimeScale.new())
		root.connect_node(StringName(name + "_speed"), 0, StringName(name + "_clip"))
		root.connect_node(&"locomotion", index, StringName(name + "_speed"))
		index += 1
	root.add_node(&"fall_clip", _clip(&"fall"))
	root.add_node(&"air", AnimationNodeBlend2.new())
	root.connect_node(&"air", 0, &"locomotion")
	root.connect_node(&"air", 1, &"fall_clip")
	var last := &"air"
	last = _add_one_shot(root, animation_player, last, &"jump", {&"idle": &"jump_idle", &"run": &"jump_run"}, 1.0, 0.05, 0.25)
	last = _add_one_shot(root, animation_player, last, &"land", {&"idle": &"land", &"run": &"run_land"}, 1.4, 0.05, 0.25)
	last = _add_actions(root, animation_player, last)
	root.connect_node(&"output", 0, last)

	_tree = AnimationTree.new()
	_tree.name = "AnimationTree"
	_tree.tree_root = root
	animation_player.get_parent().add_child(_tree)
	_tree.anim_player = _tree.get_path_to(animation_player)
	_tree.root_node = _tree.get_path_to(animation_player.get_node(animation_player.root_node))
	_tree.active = true
	for name: StringName in _locomotion_states:
		_tree.set(StringName("parameters/%s_speed/scale" % name), 1.0)
	for speed_node: StringName in _one_shot_speeds:
		_tree.set(StringName("parameters/%s/scale" % speed_node), _one_shot_speeds[speed_node])
	# 고르기(Transition) 노드는 한 번도 요청을 받지 않으면 아무것도 내보내지 않는다. 그러면 뼈대 뿌리의
	# 회전이 초기값으로 돌아가 몸이 바닥에 눕는다. 처음 상태를 직접 정해 둔다.
	_tree.set(&"parameters/locomotion/transition_request", String(locomotion))
	for shot: StringName in _first_kinds:
		_tree.set(StringName("parameters/%s_kind/transition_request" % shot), String(_first_kinds[shot]))
	if _action_blend != null:
		_tree.set(&"parameters/action_kind/transition_request", String(_action_clips[0]))
		_tree.set(&"parameters/action_speed/scale", 1.0)
		_tree.set(&"parameters/action/blend_amount", 0.0)

	var modifier := BodyPoseModifier.new()
	modifier.body = self
	_skeleton.add_child(modifier)
	animated = true


## 동작 층: 동작 고르기(Transition) → 재생 속도 → 처음으로 되감기(TimeSeek) → Blend2.
## 한 번 트는 노드(OneShot)는 재생 중에 다시 틀면 섞지 않고 처음으로 튀므로(연속 공격이 끊겨 보인다),
## 섞는 양을 코드가 직접 정한다. 공격은 온몸으로 한다(다리도 동작대로 내디딘다).
func _add_actions(root: AnimationNodeBlendTree, animation_player: AnimationPlayer, input: StringName) -> StringName:
	for clip in ACTION_CLIPS:
		if animation_player.has_animation(clip):
			_action_clips.append(clip)
	if _action_clips.is_empty():
		return input
	_action_choice = AnimationNodeTransition.new()
	_action_choice.xfade_time = ACTION_CROSSFADE
	root.add_node(&"action_kind", _action_choice)
	for i in _action_clips.size():
		var clip := _action_clips[i]
		_action_choice.add_input(String(clip))
		var clip_node := StringName("action_" + clip)
		root.add_node(clip_node, _clip(clip))
		root.connect_node(&"action_kind", i, clip_node)
	root.add_node(&"action_speed", AnimationNodeTimeScale.new())
	root.connect_node(&"action_speed", 0, &"action_kind")
	root.add_node(&"action_seek", AnimationNodeTimeSeek.new())
	root.connect_node(&"action_seek", 0, &"action_speed")
	_action_blend = AnimationNodeBlend2.new()
	root.add_node(&"action", _action_blend)
	root.connect_node(&"action", 0, input)
	root.connect_node(&"action", 1, &"action_seek")
	return &"action"

## 한 번 트는 동작(점프, 착지, 회피). 종류마다 동작이 있으면 넣고, 하나도 없으면 건너뛴다.
func _add_one_shot(root: AnimationNodeBlendTree, animation_player: AnimationPlayer, input: StringName, shot: StringName,
		kinds: Dictionary, speed: float, fade_in: float, fade_out: float) -> StringName:
	var present: Array[StringName] = []
	for kind: StringName in kinds:
		if animation_player.has_animation(kinds[kind]):
			present.append(kind)
	if present.is_empty():
		return input
	var choice := AnimationNodeTransition.new()
	choice.xfade_time = 0.0
	var kind_node := StringName(shot + "_kind")
	root.add_node(kind_node, choice)
	for i in present.size():
		var kind := present[i]
		choice.add_input(String(kind))
		var clip_node := StringName("%s_%s" % [shot, kind])
		root.add_node(clip_node, _clip(kinds[kind]))
		root.connect_node(kind_node, i, clip_node)
	var speed_node := StringName(shot + "_speed")
	root.add_node(speed_node, AnimationNodeTimeScale.new())
	root.connect_node(speed_node, 0, kind_node)
	var one_shot := AnimationNodeOneShot.new()
	one_shot.fadein_time = fade_in
	one_shot.fadeout_time = fade_out
	root.add_node(shot, one_shot)
	root.connect_node(shot, 0, input)
	root.connect_node(shot, 1, speed_node)
	_tree_nodes[shot] = true
	for kind in present:
		_tree_nodes[StringName("%s:%s" % [shot, kind])] = true
	_one_shot_speeds[speed_node] = speed
	_first_kinds[shot] = present[0]
	return shot

## 실행 중에 glTF를 읽으면 "-loop" 꼬리가 이름에 그대로 남고 반복 설정도 빠진다(에디터 가져오기만 처리해 준다).
## 이름을 정리하고 반복을 직접 켠다.
static func _normalize_animation_names(animation_player: AnimationPlayer) -> void:
	for library_name in animation_player.get_animation_library_list():
		var library := animation_player.get_animation_library(library_name)
		for name in library.get_animation_list():
			if String(name).ends_with("-loop"):
				var clean := StringName(String(name).trim_suffix("-loop"))
				library.get_animation(name).loop_mode = Animation.LOOP_LINEAR
				if not library.has_animation(clean):
					library.rename_animation(name, clean)

static func _clip(name: StringName) -> AnimationNodeAnimation:
	var node := AnimationNodeAnimation.new()
	node.animation = name
	return node

# ---- 애니메이션 모드: 매 프레임 ----
func _drive_animation(delta: float) -> void:
	_update_locomotion()
	_tree.set(&"parameters/air/blend_amount", move_toward(float(_tree.get(&"parameters/air/blend_amount")), 1.0 if _airborne else 0.0, delta * 8.0))
	_update_actions(delta)
	# 점프는 동기화된 횟수가 바뀌었을 때 튼다(원격 플레이어도 같은 동작을 본다).
	if player.jump_count != _last_jump_count:
		_last_jump_count = player.jump_count
		_fire(&"jump", &"run" if _speed > 2.0 else &"idle")
	# 착지: 공중에 있다가 땅에 닿으면 도약 동작을 끊고 착지 동작을 튼다. 착지 중에 움직이기 시작하면 바로 푼다.
	if _was_airborne and not _airborne:
		_stop(&"jump")
		_fire(&"land", &"run" if _speed > 2.0 else &"idle")
	elif _speed > 1.5 and _is_playing(&"land") and String(_tree.get(&"parameters/land_kind/current_state")) == "idle":
		_stop(&"land")
	_was_airborne = _airborne


## 속도 구간에 맞는 이동 동작을 고르고, 실제 속도에 맞춰 재생 속도를 정한다. 싸우는 중에 서 있으면 전투 대기.
func _update_locomotion() -> void:
	var next := _pick_locomotion(_speed)
	if next == &"idle" and player.in_combat and _locomotion_states.has(&"battle_idle"):
		next = &"battle_idle"
	if next != locomotion:
		locomotion = next
		_tree.set(&"parameters/locomotion/transition_request", String(next))
	if NATURAL_SPEEDS.has(locomotion):
		var natural: float = NATURAL_SPEEDS[locomotion]
		var lowest := 0.5 if locomotion == &"walk" else 0.6
		_tree.set(StringName("parameters/%s_speed/scale" % locomotion), clampf(_speed / natural, lowest, 2.2))


## 동기화된 번호를 보고 동작 층의 동작을 튼다. 공격·스킬은 동작 길이만큼, 회피·맞음은 정해진 시간만큼,
## 쓰러짐은 일어날 때까지 보여 준다. 맞힌 순간 멈출 때(타격 정지)는 동작도 멈춘다.
func _update_actions(delta: float) -> void:
	if _action_blend == null:
		return
	if player.action_count != _last_action_count:
		_last_action_count = player.action_count
		var attack := player.kit.find_attack(player.action_id) if player.kit != null else null
		if attack != null:
			_play_action(attack.clip, attack.duration)
	if player.dodge_count != _last_dodge_count:
		_last_dodge_count = player.dodge_count
		_play_action(&"dodge_b" if player.dodge_back else &"dodge_f", DODGE_SHOW_TIME)
	if player.hurt_count != _last_hurt_count:
		_last_hurt_count = player.hurt_count
		_play_action(&"hit_heavy", Player.HURT_TIME)
	var down := player.state == Player.State.DOWN or not player.is_alive()
	if down and _action_clip != &"dead":
		_play_action(&"dead", INF)
	elif not down and _action_clip == &"dead":
		_action_end = 0.0
	var stopped := player.is_hit_stopped()
	if not stopped:
		_action_elapsed += delta
	_tree.set(&"parameters/action_speed/scale", 0.0 if stopped else 1.0)
	var showing := _action_elapsed < _action_end
	# 공격을 끊고 움직이면(조종하는 피어의 상태가 바뀌면) 원격 몸도 바로 푼다.
	if showing and not NON_ATTACK_CLIPS.has(_action_clip) and player.state != Player.State.ACTION:
		showing = false
	_action_amount = move_toward(_action_amount, 1.0 if showing else 0.0, delta / (ACTION_FADE_IN if showing else ACTION_FADE_OUT))
	_tree.set(&"parameters/action/blend_amount", _action_amount)


func _play_action(clip: StringName, length: float) -> void:
	if not _action_clips.has(clip):
		return
	if String(_tree.get(&"parameters/action_kind/current_state")) == String(clip):
		# 같은 동작을 다시 고르면 Transition이 아무것도 하지 않으므로 처음으로 되감는다.
		_tree.set(&"parameters/action_seek/seek_request", 0.0)
	else:
		# 동작 중이면 다음 동작으로 섞어 넘어가고, 아니면 바로 바꾼다(지난 동작의 끝 자세가 섞이지 않게).
		_action_choice.xfade_time = ACTION_CROSSFADE if _action_amount > 0.05 else 0.0
		_tree.set(&"parameters/action_kind/transition_request", String(clip))
	_action_clip = clip
	_action_end = length
	_action_elapsed = 0.0
	if fx != null:
		fx.play(clip)

func _pick_locomotion(speed: float) -> StringName:
	# 지금 동작에서 벗어날 때만 여유(HYSTERESIS)를 둬서 경계에서 깜빡이지 않게 한다.
	var bounds := {&"walk": WALK_FROM, &"run": RUN_FROM, &"sprint": SPRINT_FROM}
	var order: Array[StringName] = [&"idle", &"walk", &"run", &"sprint"]
	var current := order.find(locomotion)
	var pick := 0
	for i in range(1, order.size()):
		var bound: float = bounds[order[i]]
		# 지금보다 높은 구간으로 올라갈 때는 경계를 조금 넘어야, 내려갈 때는 경계보다 조금 아래여야 바꾼다.
		if i <= current:
			bound -= HYSTERESIS
		if speed >= bound:
			pick = i
	return order[pick]

func _fire(shot: StringName, kind: StringName) -> void:
	if not _tree_nodes.has(shot) or not _tree_nodes.has(StringName("%s:%s" % [shot, kind])):
		return
	_tree.set(StringName("parameters/%s_kind/transition_request" % shot), String(kind))
	_tree.set(StringName("parameters/%s/request" % shot), AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)

func _stop(shot: StringName) -> void:
	if _tree_nodes.has(shot):
		_tree.set(StringName("parameters/%s/request" % shot), AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT)

func _is_playing(shot: StringName) -> bool:
	return _tree_nodes.has(shot) and bool(_tree.get(StringName("parameters/%s/active" % shot)))

# ---- 애니메이션 위에 덧입히기 (BodyPoseModifier가 부른다) ----
## 애니메이션이 뼈에 적용된 뒤 부른다. 다리 IK, 얼굴 빛, 숨기는 뼈, 옷자락 중력을 덧입힌다.
func apply_overlays() -> void:
	_update_space()
	_legs_ik()
	_update_face_light()
	_hide_bones()
	_update_cloth_gravity()
	if _cloth_ground != null:
		# 옷자락이 뚫지 않을 땅: 낮은 쪽 발밑 높이
		var floor_y := player.global_position.y + minf(foot_offsets.x, foot_offsets.y) + 0.01
		_cloth_ground.global_transform = Transform3D(Basis.IDENTITY, Vector3(global_position.x, floor_y, global_position.z))

## 다리 IK. 한 발이 낮은 계단에서 골반을 내리고 발이 실제 땅에 닿도록 다리를 접는다.
func _legs_ik() -> void:
	var grounded := not _airborne
	if grounded:
		_sample_ground()
	else:
		foot_offsets = foot_offsets.lerp(Vector2.ZERO, minf(_delta * 10.0, 1.0))
	var drop := 0.0
	if grounded:
		# 낮은 쪽 발에 맞춰 골반을 내리고, 두 발이 다 높으면(디딤판 위) 조금 올린다.
		drop -= clampf(minf(foot_offsets.x, foot_offsets.y), -0.5, 0.25)
	_pelvis_drop = move_toward(_pelvis_drop, drop, _delta * 3.0)
	_ground_offset = -_pelvis_drop
	_model.position = _model_base_position + Vector3.UP * _ground_offset
	var level := absf(_pelvis_drop) < 0.003 and absf(foot_offsets.x) < 0.003 and absf(foot_offsets.y) < 0.003
	if level:
		return
	var forward := facing()
	for side: float in [-1.0, 1.0]:
		var roles := _leg_roles(side)
		var hip := _posed_point(roles[0])
		var foot_index := _bone[roles[2]]
		var foot_basis := _skeleton.get_bone_global_pose(foot_index).basis
		var offset := foot_offsets.x if side < 0.0 else foot_offsets.y
		# 동작의 발 위치에서, 모델을 내린 만큼(+땅 높이) 들어 올린 곳을 딛는다. 무릎은 동작이 굽힌 쪽으로 굽힌다.
		var target := _posed_point(roles[2]) + Vector3.UP * (_pelvis_drop + offset)
		var pole := (_posed_point(roles[1]) - hip).normalized() + forward * 0.1
		var dirs := _two_bone(hip, target, _thigh_length, _calf_length, pole)
		_point_bone(roles[0], roles[1], dirs[0])
		_point_bone(roles[1], roles[2], dirs[1])
		# 발목 각도는 동작 그대로 둔다.
		_set_global_basis(foot_index, foot_basis)

## 발마다 아래로 광선을 쏴서 캡슐이 선 바닥보다 땅이 얼마나 높은지 잰다.
## 계단은 몸이 미끄러지는 경사로(보이지 않음)와 발이 딛는 디딤판(foot_ground 레이어)이 따로 있다.
func _sample_ground() -> void:
	var space := player.get_world_3d().direct_space_state
	var floor_y := player.global_position.y
	var to_world := global_transform
	var measured := Vector2.ZERO
	for i in 2:
		var role := &"foot_l" if i == 0 else &"foot_r"
		var foot := to_world * (_posed_point(role) + Vector3.UP * _ground_offset)
		var from := Vector3(foot.x, floor_y + 0.6, foot.z)
		var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 1.2, FOOT_RAY_MASK, [player.get_rid()])
		var hit := space.intersect_ray(query)
		var height := 0.0
		if not hit.is_empty():
			height = clampf((hit["position"] as Vector3).y - floor_y, -0.5, 0.5)
		if i == 0:
			measured.x = height
		else:
			measured.y = height
	foot_offsets = foot_offsets.lerp(measured, minf(_delta * 14.0, 1.0))

# ---- 뼈 다루기 ----
static func _leg_roles(side: float) -> Array[StringName]:
	var suffix := "_l" if side < 0.0 else "_r"
	return [StringName("thigh" + suffix), StringName("calf" + suffix), StringName("foot" + suffix)]

## 두 마디(위팔·아래팔, 허벅지·정강이)가 root에서 target에 닿는 방향을 구한다. 가운데 관절은 pole 쪽으로 굽는다.
static func _two_bone(root: Vector3, target: Vector3, first_length: float, second_length: float, pole: Vector3) -> PackedVector3Array:
	var to_target := target - root
	var distance := clampf(to_target.length(), 0.05, (first_length + second_length) * 0.999)
	var direction := to_target.normalized()
	var cos_angle := (first_length * first_length + distance * distance - second_length * second_length) / (2.0 * first_length * distance)
	var angle := acos(clampf(cos_angle, -1.0, 1.0))
	var bend := (pole - direction * pole.dot(direction)).normalized()
	var first := direction * cos(angle) + bend * sin(angle)
	var joint := root + first * first_length
	var second := (root + direction * distance - joint).normalized()
	return PackedVector3Array([first, second])

## 모델을 내리기 전 기준의 뼈 위치 (몸 공간)
func _posed_point(role: StringName) -> Vector3:
	return _body_from_skeleton * _skeleton.get_bone_global_pose(_bone[role]).origin

## 뼈(role)에서 자식 뼈(child_role)로 가는 지금 방향 (몸 공간)
func _current_direction(role: StringName, child_role: StringName) -> Vector3:
	return (_posed_point(child_role) - _posed_point(role)).normalized()

## 뼈(role)에서 자식 뼈(child_role)로 가는 방향이 direction(몸 공간)을 가리키도록 돌린다.
func _point_bone(role: StringName, child_role: StringName, direction: Vector3) -> void:
	var index := _bone[role]
	var pose := _skeleton.get_bone_global_pose(index)
	var child_offset := _skeleton.get_bone_pose_position(_bone[child_role])
	var current := (pose.basis * child_offset).normalized()
	var target := (_to_skeleton * direction).normalized()
	var dot := current.dot(target)
	if dot > 0.99999 or dot < -0.99999:
		return
	_set_global_basis(index, Basis(Quaternion(current, target)) * pose.basis)

## 뼈를 몸 공간의 축(axis) 둘레로 angle만큼 돌린다.
func _rotate_bone(role: StringName, axis: Vector3, angle: float) -> void:
	var index := _bone[role]
	var pose := _skeleton.get_bone_global_pose(index)
	_set_global_basis(index, Basis((_to_skeleton * axis).normalized(), angle) * pose.basis)

func _keep_rest_orientation(role: StringName) -> void:
	var index := _bone[role]
	_set_global_basis(index, _skeleton.get_bone_global_rest(index).basis)

func _set_global_basis(index: int, global: Basis) -> void:
	var parent := _skeleton.get_bone_parent(index)
	var parent_basis := _skeleton.get_bone_global_pose(parent).basis if parent >= 0 else Basis.IDENTITY
	_skeleton.set_bone_pose_rotation(index, (parent_basis.inverse() * global).get_rotation_quaternion())

# ---- 검 ----
## 원작의 무기 자리(관리자는 왼손 wep_L)에 무기를 쥐여 준다. 무기 모델(타르 11)이 없으면 코드로 만든 검을 쥔다.
## 무기 자리가 없는 모델이면 손 뼈에 붙인다.
func _attach_weapon() -> void:
	var anchor := _model.find_child(String(appearance.weapon_mount), true, false) as Node3D
	if anchor == null:
		var attachment := BoneAttachment3D.new()
		attachment.name = "WeaponHand"
		_skeleton.add_child(attachment)
		var left := String(appearance.weapon_mount).ends_with("_L")
		attachment.bone_name = _skeleton.get_bone_name(_bone[&"hand_l" if left else &"hand_r"])
		anchor = Node3D.new()
		anchor.position = SWORD_HAND_OFFSET
		anchor.rotation.x = -PI * 0.5 if left else PI * 0.5
		attachment.add_child(anchor)
	var scene := appearance.load_weapon_scene()
	if scene != null:
		_sword = scene.instantiate() as Node3D
		_sword.name = "Weapon"
		_sword.scale = Vector3.ONE * appearance.weapon_scale
		for geometry: Node in _sword.find_children("*", "GeometryInstance3D", true, false):
			(geometry as GeometryInstance3D).layers |= CHARACTER_RENDER_LAYER
	else:
		_sword = _build_sword()
	anchor.add_child(_sword)
	_sword.visible = false


## 원작 무기 모델을 쥐었는지 (없으면 코드로 만든 검)
func has_weapon_model() -> bool:
	return _sword != null and _sword.name == "Weapon"


## 검: 손잡이, 코등이, 칼날(가장자리가 은은히 빛난다). SWORD_AXIS 쪽으로 뻗는다.
static func _build_sword() -> Node3D:
	var sword := Node3D.new()
	sword.name = "Sword"
	var up := SWORD_AXIS.normalized()
	sword.basis = Basis(Quaternion(Vector3.UP, up)) if not up.is_equal_approx(Vector3.UP) else Basis.IDENTITY
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.12, 0.12, 0.14)
	dark.roughness = 0.6
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.78, 0.8, 0.84)
	steel.metallic = 0.8
	steel.roughness = 0.25
	var edge := StandardMaterial3D.new()
	edge.albedo_color = Color(1.0, 0.82, 0.35)
	edge.emission_enabled = true
	edge.emission = Color(1.0, 0.75, 0.25)
	edge.emission_energy_multiplier = 1.5
	var grip := CylinderMesh.new()
	grip.top_radius = 0.017
	grip.bottom_radius = 0.017
	grip.height = 0.2
	_add_sword_part(sword, grip, Vector3(0, 0.0, 0), dark)
	var guard := BoxMesh.new()
	guard.size = Vector3(0.05, 0.03, 0.15)
	_add_sword_part(sword, guard, Vector3(0, 0.11, 0), dark)
	var blade_length := SWORD_LENGTH - 0.12
	var blade := BoxMesh.new()
	blade.size = Vector3(0.012, blade_length, 0.055)
	_add_sword_part(sword, blade, Vector3(0, 0.12 + blade_length * 0.5, 0), steel)
	var glow := BoxMesh.new()
	glow.size = Vector3(0.014, blade_length * 0.92, 0.008)
	_add_sword_part(sword, glow, Vector3(0, 0.12 + blade_length * 0.5, 0.03), edge)
	return sword


static func _add_sword_part(sword: Node3D, mesh: PrimitiveMesh, offset: Vector3, material: Material) -> void:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = offset
	instance.layers |= CHARACTER_RENDER_LAYER
	sword.add_child(instance)