class_name PlayerBody
extends Node3D
## 플레이어의 몸. 다른 사람 눈과 내 3인칭 화면에 보이고, 1인칭에서는 그림자만 남는다.
##
## 모델에 애니메이션이 있으면(tools/extract_character.py로 만든 파일) 애니메이션으로 움직인다.
##   - 이동: 속도 구간마다 동작 하나(서기 / 걷기 / 달리기 / 전력 질주)를 골라 부드럽게 바꾸고,
##     실제 속도에 맞춰 재생 속도를 바꾼다(발이 미끄러지지 않게). 원래 속도는 걷기 1.0, 달리기 4.3, 질주 6.2 m/s.
##   - 몸 방향: 평소엔 움직이는 방향을 본다. 전투 자세(조준 중이거나 방금 쏨)면 다리는 움직이는 방향으로
##     가고 상체만 조준 방향으로 비튼다. 뒤로 가면 몸은 조준 쪽을 보고 동작을 거꾸로 튼다(뒷걸음).
##   - 점프: 도약 → (오래 떨어지면) 낙하 → 착지. 회피는 회피 동작. 점프·회피는 횟수가 동기화되어 남도 본다.
##   애니메이션 위에 코드로 덧입히는 것(BodyPoseModifier): 상체 비틀기, 위아래 시선, 총을 겨눈 팔,
##   다리 IK(웅크리기·슬라이딩은 골반을 내리고 다리를 접는다, 계단에서는 발마다 실제 땅 높이에 맞춘다).
## 애니메이션이 없는 모델이면 걷기·웅크리기·점프·겨누기 자세를 전부 코드로 만든다.
##
## 뼈마다 축 방향이 제각각이라 각도 대신 "이 뼈가 몸 기준으로 어느 쪽을 가리켜야 하는지"를 정하고,
## 그 방향으로 돌린다.
##
## 모델 파일이 없으면(재배포할 수 없는 모델이라 저장소에 없다) 캡슐 몸으로 대신한다.
## 모델을 어디서 찾는지는 CharacterAppearance에 있다.

enum ViewMode { VISIBLE, SHADOW_ONLY, HIDDEN }

const DEFAULT_APPEARANCE := "res://data/player/default_appearance.tres"

# 몸 기준 방향. 앞은 -Z, 오른쪽은 +X다.
const FORWARD := Vector3(0, 0, -1)
const RIGHT := Vector3(1, 0, 0)

## 순간 이동(부활 등)으로 생긴 속도 튐을 막는다.
const MAX_TRACKED_SPEED := 15.0

## 애니메이션 모드에 꼭 있어야 하는 동작. 하나라도 없으면 코드로 만든 자세를 쓴다.
const REQUIRED_ANIMATIONS: Array[StringName] = [&"idle", &"walk", &"run", &"sprint", &"fall"]
## 이동 동작이 원래 속도로 재생될 때 나아가는 속도(m/s). 재생 속도를 실제 속도에 맞추는 기준이다.
const NATURAL_SPEEDS := {&"walk": 1.0, &"run": 4.3, &"sprint": 6.2}
## 이동 동작을 고르는 속도 경계(m/s). 경계 근처에서 깜빡이지 않도록 바꿀 때만 HYSTERESIS만큼 여유를 둔다.
const WALK_FROM := 0.3
const RUN_FROM := 1.8
const SPRINT_FROM := 5.3
const HYSTERESIS := 0.25
## 이 시간보다 오래 땅에서 떨어져 있어야 공중으로 본다(계단을 내려갈 때 잠깐 떨어지는 것은 무시).
const AIR_DELAY := 0.12
## 몸이 움직이는 방향으로 도는 속도(라디안/초)
const TURN_SPEED := 10.0
## 전투 자세에서 상체를 조준 방향으로 비트는 최대 각도. 이보다 옆으로 가면 다리를 조금 미끄러뜨린다.
const MAX_TWIST := 1.31
## 전투 자세에서 이보다 뒤쪽으로 가면 뒷걸음(동작 거꾸로)으로 바꾼다. 들어갈 때와 나올 때 경계가 다르다.
const BACKPEDAL_ENTER := 1.92
const BACKPEDAL_EXIT := 1.7
## 웅크리기와 슬라이딩에서 골반을 내리는 높이(m)
const CROUCH_DROP := 0.5
const SLIDE_DROP := 0.55
## 발 IK가 땅을 찾을 때 보는 물리 레이어: 1 world, 5 foot_ground(계단 디딤판처럼 발만 딛는 모양)
const FOOT_GROUND_LAYER := 16
const FOOT_RAY_MASK := 1 | FOOT_GROUND_LAYER

## 비워 두면 기본 외형을 쓴다.
@export var appearance: CharacterAppearance

var view_mode := ViewMode.VISIBLE
## 캐릭터 모델을 불러왔으면 true. false면 캡슐 몸이다.
var has_model := false
## 모델의 애니메이션으로 움직이면 true, 코드로 만든 자세면 false
var animated := false
## 0이면 팔을 내린 자세, 1이면 총을 겨눈 자세
var ready_blend := 0.0
## 발밑 땅이 캡슐이 선 바닥보다 얼마나 높은지(m). x는 왼발, y는 오른발. 계단에서 발 IK가 쓴다.
var foot_offsets := Vector2.ZERO
## 지금 쓰는 이동 동작 이름 (idle, walk, run, sprint)
var locomotion := &"idle"

var _model: Node3D
var _skeleton: Skeleton3D
var _tree: AnimationTree
var _tree_nodes: Dictionary[StringName, bool] = {}
## 한 번 트는 동작의 재생 속도 (나무를 만든 뒤 넣는다)
var _one_shot_speeds: Dictionary[StringName, float] = {}
var _bone: Dictionary[StringName, int] = {}
## 뼈대 공간 → 모델 공간 변환. 모델 안의 배치는 바뀌지 않으므로 한 번만 구한다.
var _model_from_skeleton := Transform3D.IDENTITY
## 뼈대 공간 → 몸 공간 변환 (모델을 들어 올리거나 내리기 전 기준). 모델이 돌면 다시 구한다.
var _body_from_skeleton := Transform3D.IDENTITY
var _to_skeleton := Basis.IDENTITY
var _rest_foot_height := 0.0
var _upper_arm_length := 0.0
var _forearm_length := 0.0
var _thigh_length := 0.0
var _calf_length := 0.0
var _model_base_position := Vector3.ZERO
var _model_base_yaw := 0.0
## 몸(플레이어 방향) 기준으로 모델이 돌아간 각도
var _model_yaw := 0.0
## 상체를 비트는 각도 (전투 자세에서 조준 방향을 보게)
var _twist := 0.0
var _backpedal := false
## 모델을 내린 높이 (몸 기준, 내리면 음수)
var _ground_offset := 0.0
var _pelvis_drop := 0.0
var _phase := 0.0
var _held: Node3D
var _held_index := -1
var _muzzle: Node3D

# 움직임 재기 (원격 플레이어는 위치가 네트워크로 띄엄띄엄 오므로 바뀐 시간 간격으로 잰다)
var _sample_position := Vector3.ZERO
var _since_sample := 0.0
var _remote_velocity := Vector3.ZERO
var _air_time := 0.0
var _was_airborne := false
var _last_jump_count := 0
var _last_dodge_count := 0

# 이번 프레임의 움직임 (애니메이션 위에 자세를 덧입힐 때 다시 쓴다)
var _speed := 0.0
var _move_dir := FORWARD
var _crouch := 0.0
var _airborne := false
var _sliding := false
var _gait := 0.0
var _sprint := 0.0
var _delta := 0.0

@onready var player: Player = owner as Player
@onready var placeholder: MeshInstance3D = $Placeholder


func _ready() -> void:
	if appearance == null:
		# Player와 서로 참조하는 중에 리소스를 미리 불러오면 깨지므로 실행 시점에 불러온다.
		appearance = load(DEFAULT_APPEARANCE) as CharacterAppearance
	var scene := appearance.load_model_scene() if appearance != null else null
	if scene != null:
		_load_model(scene)
	_sample_position = global_position


func set_view_mode(mode: ViewMode) -> void:
	view_mode = mode
	visible = mode != ViewMode.HIDDEN
	for node: Node in find_children("*", "GeometryInstance3D", true, false):
		_apply_shadow_mode(node as GeometryInstance3D)


## 손에 든 총의 총구가 있는지. 캡슐 몸이거나 칼을 들었으면 false다.
func has_muzzle() -> bool:
	return _muzzle != null and visible


func muzzle_position() -> Vector3:
	return _muzzle.global_position


## 뼈의 몸 기준 위치. 모델이 없거나 뼈 이름이 없으면 Vector3.ZERO.
## 애니메이션 위에 덧입힌 자세(IK)는 그리는 프레임에만 남으므로 여기서는 애니메이션 자세가 나온다.
func bone_position(bone_name: StringName) -> Vector3:
	if _skeleton == null:
		return Vector3.ZERO
	var index := _skeleton.find_bone(bone_name)
	if index < 0:
		return Vector3.ZERO
	return _body_from_skeleton * _skeleton.get_bone_global_pose(index).origin + Vector3.UP * _ground_offset


## 지금 보이는 동작 중 가장 눈에 띄는 것 (테스트와 디버그용). 애니메이션 모드가 아니면 빈 이름.
func dominant_animation() -> StringName:
	if not animated:
		return &""
	for shot: StringName in [&"dodge", &"land", &"jump"]:
		if _tree_nodes.has(shot) and bool(_tree.get(StringName("parameters/%s/active" % shot))):
			return shot
	if _airborne:
		return &"fall"
	return locomotion


## 모델(다리)이 바라보는 방향 (몸 기준).
func facing() -> Vector3:
	return FORWARD.rotated(Vector3.UP, _model_yaw)


## 상체(가슴)가 바라보는 방향 (몸 기준). 전투 자세면 조준 방향(앞)이다.
func chest_facing() -> Vector3:
	return FORWARD.rotated(Vector3.UP, _model_yaw + _twist)


## 모델을 내린 높이(m, 양수). 웅크리기·슬라이딩·계단에서 골반을 내린 만큼이다.
func pelvis_drop() -> float:
	return _pelvis_drop


func _process(delta: float) -> void:
	if player == null or delta <= 0.0:
		return
	var velocity := global_basis.orthonormalized().inverse() * _measure_velocity(delta)
	if not has_model:
		_pose_placeholder()
		return
	if _skeleton == null or not visible:
		return
	_read_motion(delta, velocity)
	if animated:
		_drive_animation(delta)
	else:
		_pose_procedural()
		_update_held_weapon()


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


func _pose_placeholder() -> void:
	var config := player.config
	var height := lerpf(config.stand_height, config.crouch_height, player.crouch_blend)
	placeholder.scale.y = height / config.stand_height
	placeholder.position.y = height * 0.5


func _read_motion(delta: float, velocity: Vector3) -> void:
	var config := player.config
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var raw_speed := horizontal.length()
	_delta = delta
	_speed = lerpf(_speed, raw_speed, minf(delta * 15.0, 1.0))
	_crouch = player.crouch_blend
	_sliding = player.state == Player.State.SLIDE
	var in_air := player.state == Player.State.AIR or player.state == Player.State.MANTLE
	_air_time = _air_time + delta if in_air else 0.0
	_airborne = _air_time > AIR_DELAY
	_gait = clampf(_speed / config.walk_speed, 0.0, 1.0)
	_sprint = clampf((_speed - config.walk_speed) / (config.sprint_speed - config.walk_speed), 0.0, 1.0)
	if raw_speed > 0.3:
		_move_dir = horizontal / raw_speed
	# 한 주기(두 걸음)에 나아가는 거리. 빠를수록 보폭이 넓어진다. 코드로 만든 걸음에 쓴다.
	if not _airborne:
		_phase = fmod(_phase + _speed * delta / lerpf(2.4, 3.0, _sprint) * TAU, TAU)

	var weapon := player.weapons.current_weapon()
	var wants_ready: bool
	if animated:
		# 애니메이션 모드는 조준하거나 쏠 때만 겨눈다. 평소에는 이동 동작을 그대로 보여 준다.
		wants_ready = player.health.is_alive() and not weapon.is_melee() and player.combat_ready and _sprint < 0.5 and not _sliding
	else:
		wants_ready = player.health.is_alive() and not weapon.is_melee() and _sprint < 0.5
	ready_blend = move_toward(ready_blend, 1.0 if wants_ready else 0.0, delta * 6.0)


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

	_model_from_skeleton = _model.global_transform.affine_inverse() * _skeleton.global_transform
	_update_space()
	_skeleton.reset_bone_poses()
	_rest_foot_height = minf(_posed_point(&"foot_l").y, _posed_point(&"foot_r").y)
	_upper_arm_length = _skeleton.get_bone_rest(_bone[&"forearm_r"]).origin.length()
	_forearm_length = _skeleton.get_bone_rest(_bone[&"hand_r"]).origin.length()
	_thigh_length = _skeleton.get_bone_rest(_bone[&"calf_l"]).origin.length()
	_calf_length = _skeleton.get_bone_rest(_bone[&"foot_l"]).origin.length()
	_setup_animation()


## 모델이 돌면 뼈대 공간과 몸 공간의 관계가 바뀐다. 모델을 내리기 전 기준으로 다시 구한다.
func _update_space() -> void:
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
	var index := 0
	for name: StringName in [&"idle", &"walk", &"run", &"sprint"]:
		moves.add_input(String(name))
		root.add_node(StringName(name + "_clip"), _clip(name))
		root.add_node(StringName(name + "_speed"), AnimationNodeTimeScale.new())
		root.connect_node(StringName(name + "_speed"), 0, StringName(name + "_clip"))
		root.connect_node(&"locomotion", index, StringName(name + "_speed"))
		index += 1
	# 뒷걸음은 이동 동작을 거꾸로 튼다.
	root.add_node(&"direction", AnimationNodeTimeScale.new())
	root.connect_node(&"direction", 0, &"locomotion")
	root.add_node(&"fall_clip", _clip(&"fall"))
	root.add_node(&"air", AnimationNodeBlend2.new())
	root.connect_node(&"air", 0, &"direction")
	root.connect_node(&"air", 1, &"fall_clip")
	var last := &"air"
	last = _add_one_shot(root, animation_player, last, &"jump", {&"idle": &"jump_idle", &"run": &"jump_run"}, 1.0, 0.05, 0.25)
	last = _add_one_shot(root, animation_player, last, &"land", {&"idle": &"land", &"run": &"run_land"}, 1.4, 0.05, 0.25)
	last = _add_one_shot(root, animation_player, last, &"dodge", {&"f": &"dodge_f", &"b": &"dodge_b"}, 1.8, 0.05, 0.2)
	root.connect_node(&"output", 0, last)

	_tree = AnimationTree.new()
	_tree.name = "AnimationTree"
	_tree.tree_root = root
	animation_player.get_parent().add_child(_tree)
	_tree.anim_player = _tree.get_path_to(animation_player)
	_tree.root_node = _tree.get_path_to(animation_player.get_node(animation_player.root_node))
	_tree.active = true
	for name: StringName in [&"idle", &"walk", &"run", &"sprint"]:
		_tree.set(StringName("parameters/%s_speed/scale" % name), 1.0)
	_tree.set(&"parameters/direction/scale", 1.0)
	for speed_node: StringName in _one_shot_speeds:
		_tree.set(StringName("parameters/%s/scale" % speed_node), _one_shot_speeds[speed_node])
	# 고르기(Transition) 노드는 한 번도 요청을 받지 않으면 아무것도 내보내지 않는다. 그러면 뼈대 뿌리의
	# 회전이 초기값으로 돌아가 몸이 바닥에 눕는다. 처음 상태를 직접 정해 둔다.
	_tree.set(&"parameters/locomotion/transition_request", String(locomotion))
	for shot: StringName in [&"jump", &"land", &"dodge"]:
		for kind: StringName in [&"idle", &"run", &"f", &"b"]:
			if _tree_nodes.has(StringName("%s:%s" % [shot, kind])):
				_tree.set(StringName("parameters/%s_kind/transition_request" % shot), String(kind))
				break

	var modifier := BodyPoseModifier.new()
	modifier.body = self
	_skeleton.add_child(modifier)
	animated = true


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
	_update_facing(delta)
	_update_locomotion()
	_tree.set(&"parameters/air/blend_amount", move_toward(float(_tree.get(&"parameters/air/blend_amount")), 1.0 if _airborne else 0.0, delta * 8.0))

	# 점프·회피는 동기화된 횟수가 바뀌었을 때 튼다(원격 플레이어도 같은 동작을 본다).
	if player.jump_count != _last_jump_count:
		_last_jump_count = player.jump_count
		_fire(&"jump", &"run" if _speed > 2.0 else &"idle")
	if player.dodge_count != _last_dodge_count:
		_last_dodge_count = player.dodge_count
		_fire(&"dodge", &"b" if facing().dot(_move_dir) < -0.3 else &"f")
	# 착지: 공중에 있다가 땅에 닿으면 도약 동작을 끊고 착지 동작을 튼다. 착지 중에 움직이기 시작하면 바로 푼다.
	if _was_airborne and not _airborne:
		_stop(&"jump")
		_fire(&"land", &"run" if _speed > 2.0 else &"idle")
	elif _speed > 1.5 and _is_playing(&"land") and String(_tree.get(&"parameters/land_kind/current_state")) == "idle":
		_stop(&"land")
	_was_airborne = _airborne


## 몸이 볼 방향과 상체를 비틀 각도를 정한다.
func _update_facing(delta: float) -> void:
	var moving := _speed > 0.6 and not _airborne
	var move_yaw := atan2(-_move_dir.x, -_move_dir.z)
	var target_yaw := _model_yaw
	if ready_blend > 0.5:
		if moving:
			# 다리는 움직이는 쪽으로 가고, 상체는 조준(앞)을 본다. 뒤쪽으로 가면 뒷걸음으로 바꾼다.
			var limit := BACKPEDAL_EXIT if _backpedal else BACKPEDAL_ENTER
			_backpedal = absf(move_yaw) > limit
			var legs_yaw := wrapf(move_yaw + PI, -PI, PI) if _backpedal else move_yaw
			target_yaw = clampf(legs_yaw, -MAX_TWIST, MAX_TWIST)
		else:
			_backpedal = false
			target_yaw = 0.0
	else:
		_backpedal = false
		if moving:
			target_yaw = move_yaw
	_model_yaw = rotate_toward(_model_yaw, target_yaw, TURN_SPEED * delta)
	_model.rotation.y = _model_base_yaw + _model_yaw
	_twist = -_model_yaw * ready_blend


## 속도 구간에 맞는 이동 동작을 고르고, 실제 속도에 맞춰 재생 속도를 정한다.
func _update_locomotion() -> void:
	var next := locomotion
	var speed := _speed
	if _sliding:
		# 슬라이딩은 다리를 IK로 따로 만든다. 상체는 서 있는 동작을 쓴다.
		next = &"idle"
	else:
		next = _pick_locomotion(speed)
	if next != locomotion:
		locomotion = next
		_tree.set(&"parameters/locomotion/transition_request", String(next))
	if NATURAL_SPEEDS.has(locomotion):
		var natural: float = NATURAL_SPEEDS[locomotion]
		var lowest := 0.5 if locomotion == &"walk" else 0.6
		_tree.set(StringName("parameters/%s_speed/scale" % locomotion), clampf(speed / natural, lowest, 2.2))
	_tree.set(&"parameters/direction/scale", -1.0 if _backpedal else 1.0)


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

## 애니메이션이 뼈에 적용된 뒤 부른다. 상체 비틀기, 시선, 총 겨누기, 다리 IK를 덧입힌다.
func apply_overlays() -> void:
	_update_space()
	var pitch := player.head.rotation.x
	var aim := FORWARD.rotated(RIGHT, pitch)
	var weapon := player.weapons.current_weapon()
	# 상체를 조준 쪽으로 비튼다(허리와 가슴에 나눠서).
	if absf(_twist) > 0.001:
		_rotate_bone(&"spine", Vector3.UP, _twist * 0.45)
		_rotate_bone(&"chest", Vector3.UP, _twist * 0.55)
	var chest_right := RIGHT.rotated(Vector3.UP, _model_yaw + _twist)
	# 웅크리면 앞으로 조금 숙이고, 슬라이딩하면 뒤로 젖힌다.
	var lean := deg_to_rad(18.0) * _crouch
	if _sliding:
		lean = -deg_to_rad(15.0)
	if absf(lean) > 0.001:
		_rotate_bone(&"spine", chest_right, -lean)
	# 고개를 드는 만큼 가슴과 머리를 나눠 든다. 겨눌 때는 더 많이 따라간다.
	_rotate_bone(&"chest", chest_right, pitch * lerpf(0.15, 0.35, ready_blend))
	_rotate_bone(&"head", chest_right, pitch * 0.4 + lean * 0.6)
	if ready_blend > 0.0:
		for side: float in [-1.0, 1.0]:
			var roles := _arm_roles(side)
			var solved := _ready_arm(side, aim, weapon)
			_point_bone(roles[0], roles[1], _current_direction(roles[0], roles[1]).slerp(solved[0], ready_blend))
			_point_bone(roles[1], roles[2], _current_direction(roles[1], roles[2]).slerp(solved[1], ready_blend))
	_legs_ik()
	_update_held_weapon()


## 골반을 내리고(웅크리기·슬라이딩·한 발이 낮은 계단) 발이 실제 땅에 닿도록 다리를 접는다.
func _legs_ik() -> void:
	var grounded := not _airborne
	if grounded:
		_sample_ground()
	else:
		foot_offsets = foot_offsets.lerp(Vector2.ZERO, minf(_delta * 10.0, 1.0))
	var drop := CROUCH_DROP * _crouch
	if _sliding:
		drop = SLIDE_DROP
	if grounded:
		# 낮은 쪽 발에 맞춰 골반을 내리고, 두 발이 다 높으면(디딤판 위) 조금 올린다.
		drop -= clampf(minf(foot_offsets.x, foot_offsets.y), -0.5, 0.25)
	_pelvis_drop = move_toward(_pelvis_drop, drop, _delta * 3.0)
	_ground_offset = -_pelvis_drop
	_model.position = _model_base_position + Vector3.UP * _ground_offset
	if absf(_pelvis_drop) < 0.003 and absf(foot_offsets.x) < 0.003 and absf(foot_offsets.y) < 0.003 and not _sliding:
		return
	var forward := facing()
	var right := RIGHT.rotated(Vector3.UP, _model_yaw)
	for side: float in [-1.0, 1.0]:
		var roles := _leg_roles(side)
		var hip := _posed_point(roles[0])
		var foot_index := _bone[roles[2]]
		var foot_basis := _skeleton.get_bone_global_pose(foot_index).basis
		var offset := foot_offsets.x if side < 0.0 else foot_offsets.y
		# 모델을 drop만큼 내렸으니, 발이 원래 높이(+땅 높이)에 남으려면 그만큼 들어 올린 곳이 목표다.
		var target := _posed_point(roles[2]) + Vector3.UP * (_pelvis_drop + offset)
		var pole := (forward + right * side * 0.25 + Vector3.UP * 0.1).normalized()
		if _sliding:
			# 슬라이딩: 왼발은 앞으로 뻗고, 오른발은 엉덩이 밑으로 접는다.
			var ground := _pelvis_drop + _rest_foot_height
			if side < 0.0:
				target = Vector3(hip.x, ground, hip.z) + forward * 0.75
			else:
				target = Vector3(hip.x, ground + 0.05, hip.z) - forward * 0.15
				pole = (forward + Vector3.UP * 0.6 + right * 0.3).normalized()
		var solved := _two_bone(hip, target, _thigh_length, _calf_length, pole)
		_point_bone(roles[0], roles[1], solved[0])
		_point_bone(roles[1], roles[2], solved[1])
		# 발목 각도는 애니메이션 그대로 둔다.
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


# ---- 코드로 만드는 자세 (애니메이션이 없는 모델) ----

func _pose_procedural() -> void:
	var weapon := player.weapons.current_weapon()
	var pitch := player.head.rotation.x
	var aim := FORWARD.rotated(RIGHT, pitch)
	var swing := deg_to_rad(28.0 * _gait + 14.0 * _sprint) * (1.0 - 0.5 * _crouch)

	_skeleton.reset_bone_poses()

	# 몸통: 달리거나 웅크리면 앞으로 숙이고, 고개를 드는 만큼 가슴과 머리를 나눠 든다.
	var lean := deg_to_rad(10.0) * _sprint + deg_to_rad(30.0) * _crouch
	_rotate_bone(&"spine", RIGHT, -lean)
	_rotate_bone(&"chest", RIGHT, pitch * 0.35)
	_rotate_bone(&"head", RIGHT, pitch * 0.4 + lean * 0.8)

	for side: float in [-1.0, 1.0]:
		var roles := _arm_roles(side)
		# 내린 팔: 다리와 반대로 흔들고, 달릴수록 팔꿈치를 굽힌다.
		var arm_angle := -side * sin(_phase) * swing * 0.9
		var relaxed_upper := (Vector3.DOWN * cos(arm_angle) + FORWARD * sin(arm_angle) + RIGHT * side * 0.15).normalized()
		var elbow := deg_to_rad(12.0 + 20.0 * _gait + 55.0 * _sprint)
		var relaxed_fore := (relaxed_upper * cos(elbow) + FORWARD * sin(elbow)).normalized()
		var upper_dir := relaxed_upper
		var fore_dir := relaxed_fore
		if ready_blend > 0.0:
			var solved := _ready_arm(side, aim, weapon)
			upper_dir = relaxed_upper.slerp(solved[0], ready_blend)
			fore_dir = relaxed_fore.slerp(solved[1], ready_blend)
		_point_bone(roles[0], roles[1], upper_dir)
		_point_bone(roles[1], roles[2], fore_dir)

	for side: float in [-1.0, 1.0]:
		var phase := _phase if side < 0.0 else _phase + PI
		var dirs := _leg_directions(side, phase, swing, _gait, _crouch, _airborne)
		var roles := _leg_roles(side)
		_point_bone(roles[0], roles[1], dirs[0])
		_point_bone(roles[1], roles[2], dirs[1])
		# 발은 처음 자세 그대로 땅과 나란하게 둔다.
		_keep_rest_orientation(roles[2])

	# 발이 땅에 닿도록 모델 높이를 맞춘다. 웅크리면 이것으로 몸이 내려간다.
	# 공중에서는 맞추지 않아서 다리가 접혀 올라간 것처럼 보인다.
	var target_offset := 0.0
	if not _airborne:
		var lowest := minf(_posed_point(&"foot_l").y, _posed_point(&"foot_r").y)
		target_offset = _rest_foot_height - lowest
	_ground_offset = move_toward(_ground_offset, target_offset, _delta * 4.0)
	_model.position = _model_base_position + Vector3.UP * _ground_offset


# ---- 팔다리 계산 (두 모드가 함께 쓴다) ----

static func _arm_roles(side: float) -> Array[StringName]:
	var suffix := "_l" if side < 0.0 else "_r"
	return [StringName("upper_arm" + suffix), StringName("forearm" + suffix), StringName("hand" + suffix)]


static func _leg_roles(side: float) -> Array[StringName]:
	var suffix := "_l" if side < 0.0 else "_r"
	return [StringName("thigh" + suffix), StringName("calf" + suffix), StringName("foot" + suffix)]


## 총을 겨눈 팔(위팔, 아래팔 방향): 두 손을 가슴 앞, 조준 방향 위에 모은다. 산탄총은 왼손이 총열을 받친다.
func _ready_arm(side: float, aim: Vector3, weapon: WeaponData) -> PackedVector3Array:
	var shoulder := _posed_point(_arm_roles(side)[0])
	var grip := _shoulder_center() + Vector3.DOWN * 0.08 + aim * 0.38
	var target := grip + RIGHT * 0.02
	if side < 0.0:
		target = grip + aim * (0.2 if weapon.pellets > 1 else 0.0) + RIGHT * -0.04
	var pole := (Vector3.DOWN + RIGHT * side * 0.8).normalized()
	return _two_bone(shoulder, target, _upper_arm_length, _forearm_length, pole)


## 다리(허벅지, 정강이 방향). side: 왼쪽 -1, 오른쪽 +1. phase가 0에서 π로 갈 때 다리가 앞으로 나간다.
func _leg_directions(side: float, phase: float, swing: float, gait: float, crouch: float, airborne: bool) -> PackedVector3Array:
	var angle := swing * sin(phase)
	# 다리를 앞으로 내미는 동안 무릎을 굽혀 발이 땅에 끌리지 않게 한다.
	var knee := deg_to_rad(6.0) + deg_to_rad(50.0) * gait * maxf(cos(phase), 0.0)
	var hip_flex := deg_to_rad(82.0) * crouch
	knee += deg_to_rad(135.0) * crouch
	if airborne:
		# 점프하면 한쪽 다리를 더 접어 올린다.
		hip_flex += deg_to_rad(40.0 if side < 0.0 else 15.0)
		knee += deg_to_rad(70.0 if side < 0.0 else 30.0)
		angle *= 0.3
	var thigh_dir := (Vector3.DOWN * cos(angle) + _move_dir * sin(angle)).rotated(RIGHT, hip_flex)
	# 웅크리면 무릎을 살짝 벌린다.
	thigh_dir = (thigh_dir + RIGHT * side * 0.12 * crouch).normalized()
	return PackedVector3Array([thigh_dir, thigh_dir.rotated(RIGHT, -knee)])


func _shoulder_center() -> Vector3:
	return (_posed_point(&"upper_arm_l") + _posed_point(&"upper_arm_r")) * 0.5


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


# ---- 뼈 다루기 (뼈대 공간과 몸 공간 변환) ----

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


# ---- 손에 든 무기 ----

func _update_held_weapon() -> void:
	var weapons := player.weapons
	if weapons.current_index != _held_index:
		_held_index = weapons.current_index
		_build_held(weapons.current_weapon())
	var hand := _posed_point(&"hand_r") + Vector3.UP * _ground_offset
	var fore := (_posed_point(&"hand_r") - _posed_point(&"forearm_r")).normalized()
	var aim := FORWARD.rotated(RIGHT, player.head.rotation.x)
	var direction := fore.slerp(aim, ready_blend) if not weapons.current_weapon().is_melee() else fore
	# 총이 거의 수직이면 위쪽 기준을 몸 앞쪽으로 바꾼다. 방향과 위쪽 기준이 나란하면 회전을 정할 수 없다.
	var up := Vector3.UP if absf(direction.y) < 0.9 else FORWARD
	_held.transform = Transform3D(Basis.looking_at(direction, up), hand)


## 3인칭과 다른 사람 눈에 보이는 무기. 1인칭 무기 모델(Viewmodel)처럼 그레이박스 도형이다.
func _build_held(weapon: WeaponData) -> void:
	if _held != null:
		_held.queue_free()
	_held = Node3D.new()
	_held.name = "Held"
	_muzzle = null
	if weapon.is_melee():
		_add_box(_held, Vector3(0.015, 0.06, 0.6), Vector3(0.0, 0.0, -0.3), Color(1, 0.25, 0.7), true)
	else:
		var length := 0.5 if weapon.pellets > 1 else 0.2
		_add_box(_held, Vector3(0.05, 0.08, length), Vector3(0.0, 0.04, -length * 0.5 + 0.05), Color(0.2, 0.2, 0.24))
		_add_box(_held, Vector3(0.04, 0.1, 0.05), Vector3(0.0, -0.03, 0.02), Color(0.15, 0.15, 0.18))
		_add_box(_held, Vector3(0.052, 0.012, length * 0.7), Vector3(0.0, 0.085, -length * 0.4), Color(0.1, 0.9, 1), true)
		_muzzle = Node3D.new()
		_muzzle.position = Vector3(0.0, 0.04, -length + 0.05)
		_held.add_child(_muzzle)
	add_child(_held)


func _add_box(parent: Node3D, size: Vector3, offset: Vector3, color: Color, glow: bool = false) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	if glow:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 1.2
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = offset
	parent.add_child(instance)
	_apply_shadow_mode(instance)
