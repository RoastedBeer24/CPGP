class_name PlayerBody
extends Node3D
## 플레이어의 몸. 다른 사람 눈과 내 3인칭 화면에 보이고, 1인칭에서는 그림자만 남는다.
##
## 모델에 애니메이션이 있으면(tools/extract_character.py로 만든 파일) 애니메이션으로 움직인다.
##   - 평소: 움직이는 방향으로 몸을 돌리고, 속도에 따라 서기·걷기·달리기·전력 질주를 섞는다.
##   - 전투 자세(조준 중이거나 방금 쏨): 조준 방향을 보고, 발은 여러 방향 걷기 동작을 쓴다.
##   - 공중: 낙하 동작, 착지하면 착지 동작.
##   애니메이션 위에 코드로 덧입히는 것(BodyPoseModifier): 총을 겨눈 팔, 위아래 시선, 웅크린 다리
##   (원본에 웅크리기 동작이 없다).
## 애니메이션이 없는 모델이면 걷기·웅크리기·점프·겨누기 자세를 전부 코드로 만든다.
##
## 뼈마다 축 방향이 제각각이라 각도 대신 "이 뼈가 몸 기준으로 어느 쪽을 가리켜야 하는지"를 정하고,
## 그 방향으로 돌린다. 움직임은 위치 변화로 잰다. 원격 플레이어는 속도가 동기화되지 않기 때문이다.
##
## 모델 파일이 없으면(재배포할 수 없는 모델이라 저장소에 없다) 캡슐 몸으로 대신한다.
## 모델을 어디서 찾는지는 CharacterAppearance에 있다.

enum ViewMode { VISIBLE, SHADOW_ONLY, HIDDEN }

const DEFAULT_APPEARANCE := "res://data/player/default_appearance.tres"

# 몸 기준 방향. 앞은 -Z, 오른쪽은 +X다.
const FORWARD := Vector3(0, 0, -1)
const RIGHT := Vector3(1, 0, 0)

## 이 속도(m/s)보다 위아래로 빠르게 움직이면 공중에 뜬 것으로 본다 (원격 플레이어용)
const AIRBORNE_VERTICAL_SPEED := 1.5
## 순간 이동(부활 등)으로 생긴 속도 튐을 막는다.
const MAX_TRACKED_SPEED := 15.0

## 애니메이션 모드에 꼭 있어야 하는 동작. 하나라도 없으면 코드로 만든 자세를 쓴다.
const REQUIRED_ANIMATIONS: Array[StringName] = [&"idle", &"walk", &"run", &"sprint", &"fall"]
## 각 동작이 원래 속도로 재생될 때의 이동 속도(m/s). 속도 섞기의 기준점이다.
const LOCOMOTION_SPEEDS := {&"idle": 0.0, &"walk": 1.5, &"run": 4.0, &"sprint": 6.8}
## 전투 자세 걷기 동작의 원래 속도(m/s). 더 빨리 움직이면 재생 속도를 올린다.
const STRAFE_SPEED := 1.6
const STRAFE_POINTS := {
	&"strafe_f": Vector2(0, 1), &"strafe_fl": Vector2(-0.7, 0.7), &"strafe_fr": Vector2(0.7, 0.7),
	&"strafe_b": Vector2(0, -1), &"strafe_bl": Vector2(-0.7, -0.7), &"strafe_br": Vector2(0.7, -0.7),
}
## 몸이 움직이는 방향으로 도는 속도(라디안/초)
const TURN_SPEED := 10.0

## 비워 두면 기본 외형을 쓴다.
@export var appearance: CharacterAppearance

var view_mode := ViewMode.VISIBLE
## 캐릭터 모델을 불러왔으면 true. false면 캡슐 몸이다.
var has_model := false
## 모델의 애니메이션으로 움직이면 true, 코드로 만든 자세면 false
var animated := false
## 0이면 팔을 내린 자세, 1이면 총을 겨눈 자세
var ready_blend := 0.0

var _model: Node3D
var _skeleton: Skeleton3D
var _tree: AnimationTree
var _bone: Dictionary[StringName, int] = {}
## 뼈대 공간 → 모델 공간 변환. 모델 안의 배치는 바뀌지 않으므로 한 번만 구한다.
var _model_from_skeleton := Transform3D.IDENTITY
## 뼈대 공간 → 몸 공간 변환 (모델을 들어 올리기 전 기준). 모델이 돌면 다시 구한다.
var _body_from_skeleton := Transform3D.IDENTITY
var _to_skeleton := Basis.IDENTITY
var _rest_foot_height := 0.0
var _upper_arm_length := 0.0
var _forearm_length := 0.0
var _model_base_position := Vector3.ZERO
var _model_base_yaw := 0.0
## 몸(플레이어 방향) 기준으로 모델이 돌아간 각도. 움직이는 방향을 보게 할 때 쓴다.
var _model_yaw := 0.0
var _ground_offset := 0.0
var _phase := 0.0
var _last_position := Vector3.ZERO
var _velocity := Vector3.ZERO
var _air_time := 0.0
var _held: Node3D
var _held_index := -1
var _muzzle: Node3D

# 이번 프레임의 움직임 (애니메이션 위에 자세를 덧입힐 때 다시 쓴다)
var _speed := 0.0
var _move_dir := FORWARD
var _crouch := 0.0
var _airborne := false
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
	_last_position = global_position


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
func bone_position(bone_name: StringName) -> Vector3:
	if _skeleton == null:
		return Vector3.ZERO
	var index := _skeleton.find_bone(bone_name)
	if index < 0:
		return Vector3.ZERO
	return _body_from_skeleton * _skeleton.get_bone_global_pose(index).origin + Vector3.UP * _ground_offset


## 지금 섞이고 있는 동작 이름 중 가장 비중이 큰 것 (테스트와 디버그용). 애니메이션 모드가 아니면 빈 이름.
func dominant_animation() -> StringName:
	if not animated:
		return &""
	if _airborne:
		return &"fall"
	if ready_blend > 0.5:
		return &"strafe"
	var best := &"idle"
	var best_gap := INF
	for name: StringName in LOCOMOTION_SPEEDS:
		var gap := absf(float(LOCOMOTION_SPEEDS[name]) - _speed)
		if gap < best_gap:
			best = name
			best_gap = gap
	return best


## 모델이 바라보는 방향 (몸 기준). 움직이는 방향을 보거나 조준 방향을 본다.
func facing() -> Vector3:
	return FORWARD.rotated(Vector3.UP, _model_yaw)


func _process(delta: float) -> void:
	if player == null or delta <= 0.0:
		return
	var local_velocity := _track_velocity(delta)
	if not has_model:
		_pose_placeholder()
		return
	if _skeleton == null or not visible:
		return
	_read_motion(delta, local_velocity)
	if animated:
		_drive_animation(delta)
	else:
		_pose_procedural()
		_update_held_weapon()


func _track_velocity(delta: float) -> Vector3:
	var raw := ((global_position - _last_position) / delta).limit_length(MAX_TRACKED_SPEED)
	_last_position = global_position
	_velocity = _velocity.lerp(raw, minf(delta * 12.0, 1.0))
	return global_basis.orthonormalized().inverse() * _velocity


func _pose_placeholder() -> void:
	var config := player.config
	var height := lerpf(config.stand_height, config.crouch_height, player.crouch_blend)
	placeholder.scale.y = height / config.stand_height
	placeholder.position.y = height * 0.5


func _read_motion(delta: float, velocity: Vector3) -> void:
	var config := player.config
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	_delta = delta
	_speed = horizontal.length()
	_crouch = player.crouch_blend
	_airborne = (
		not player.is_on_floor() if player.is_multiplayer_authority()
		else absf(velocity.y) > AIRBORNE_VERTICAL_SPEED
	)
	_gait = clampf(_speed / config.walk_speed, 0.0, 1.0)
	_sprint = clampf((_speed - config.walk_speed) / (config.sprint_speed - config.walk_speed), 0.0, 1.0)
	_move_dir = horizontal / _speed if _speed > 0.2 else _move_dir
	# 한 주기(두 걸음)에 나아가는 거리. 빠를수록 보폭이 넓어진다. 코드로 만든 걸음과 웅크려 걷기에 쓴다.
	if not _airborne:
		_phase = fmod(_phase + _speed * delta / lerpf(2.4, 3.0, _sprint) * TAU, TAU)

	var weapon := player.weapons.current_weapon()
	var wants_ready: bool
	if animated:
		# 애니메이션 모드는 조준하거나 쏠 때만 겨눈다. 평소에는 달리는 동작을 그대로 보여 준다.
		wants_ready = player.health.is_alive() and not weapon.is_melee() and player.combat_ready and _sprint < 0.5
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
	_setup_animation()


## 모델이 돌거나 들어 올려지면 뼈대 공간과 몸 공간의 관계가 바뀐다. 모델을 들어 올리기 전 기준으로 다시 구한다.
func _update_space() -> void:
	var model := Transform3D(_model.transform.basis, _model_base_position)
	_body_from_skeleton = model * _model_from_skeleton
	_to_skeleton = _body_from_skeleton.basis.orthonormalized().inverse()


func _apply_shadow_mode(geometry: GeometryInstance3D) -> void:
	if view_mode == ViewMode.SHADOW_ONLY:
		geometry.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	else:
		geometry.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON


# ---- 애니메이션 모드 ----

func _setup_animation() -> void:
	var players := _model.find_children("*", "AnimationPlayer", true, false)
	if players.is_empty():
		return
	var animation_player := players[0] as AnimationPlayer
	_normalize_animation_names(animation_player)
	for name in REQUIRED_ANIMATIONS:
		if not animation_player.has_animation(name):
			return

	var root := AnimationNodeBlendTree.new()
	var locomotion := AnimationNodeBlendSpace1D.new()
	locomotion.min_space = 0.0
	locomotion.max_space = 8.0
	for name: StringName in LOCOMOTION_SPEEDS:
		locomotion.add_blend_point(_clip(name), LOCOMOTION_SPEEDS[name])
	var strafe := AnimationNodeBlendSpace2D.new()
	strafe.add_blend_point(_clip(&"idle"), Vector2.ZERO)
	for name: StringName in STRAFE_POINTS:
		if animation_player.has_animation(name):
			strafe.add_blend_point(_clip(name), STRAFE_POINTS[name])
	root.add_node(&"locomotion", locomotion)
	root.add_node(&"strafe", strafe)
	root.add_node(&"strafe_speed", AnimationNodeTimeScale.new())
	root.add_node(&"ready", AnimationNodeBlend2.new())
	root.add_node(&"fall", _clip(&"fall"))
	root.add_node(&"air", AnimationNodeBlend2.new())
	root.connect_node(&"strafe_speed", 0, &"strafe")
	root.connect_node(&"ready", 0, &"locomotion")
	root.connect_node(&"ready", 1, &"strafe_speed")
	root.connect_node(&"air", 0, &"ready")
	root.connect_node(&"air", 1, &"fall")
	var last := &"air"
	if animation_player.has_animation(&"land"):
		# 착지 동작은 원래 길어서(1.7초) 조금 빠르게 틀고, 움직이기 시작하면 곧 풀리게 짧게 섞는다.
		var land := AnimationNodeOneShot.new()
		land.fadein_time = 0.08
		land.fadeout_time = 0.3
		root.add_node(&"land_clip", _clip(&"land"))
		root.add_node(&"land_speed", AnimationNodeTimeScale.new())
		root.add_node(&"land", land)
		root.connect_node(&"land_speed", 0, &"land_clip")
		root.connect_node(&"land", 0, &"air")
		root.connect_node(&"land", 1, &"land_speed")
		last = &"land"
	root.connect_node(&"output", 0, last)

	_tree = AnimationTree.new()
	_tree.name = "AnimationTree"
	_tree.tree_root = root
	animation_player.get_parent().add_child(_tree)
	_tree.anim_player = _tree.get_path_to(animation_player)
	_tree.root_node = _tree.get_path_to(animation_player.get_node(animation_player.root_node))
	_tree.set(&"parameters/land_speed/scale", 1.6)
	_tree.active = true

	var modifier := BodyPoseModifier.new()
	modifier.body = self
	_skeleton.add_child(modifier)
	animated = true


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


func _drive_animation(delta: float) -> void:
	# 전투 자세면 조준 방향을, 아니면 움직이는 방향을 본다. 멈춰 있으면 마지막 방향을 유지한다.
	var target_yaw := _model_yaw
	if ready_blend > 0.5:
		target_yaw = 0.0
	elif _speed > 0.5 and not _airborne:
		target_yaw = atan2(-_move_dir.x, -_move_dir.z)
	_model_yaw = rotate_toward(_model_yaw, target_yaw, TURN_SPEED * delta)
	_model.rotation.y = _model_base_yaw + _model_yaw

	_tree.set(&"parameters/locomotion/blend_position", _speed)
	# 전투 자세 걷기: 조준 방향 기준으로 어느 쪽으로 움직이는지 (앞 +y, 오른쪽 +x)
	var strafe := Vector2(_move_dir.x, -_move_dir.z) * clampf(_speed / STRAFE_SPEED, 0.0, 1.0)
	_tree.set(&"parameters/strafe/blend_position", strafe.limit_length(1.0))
	_tree.set(&"parameters/strafe_speed/scale", clampf(_speed / STRAFE_SPEED, 0.8, 1.8))
	_tree.set(&"parameters/ready/blend_amount", ready_blend)

	var was_airborne := _air_time > 0.25
	_air_time = _air_time + delta if _airborne else 0.0
	_tree.set(&"parameters/air/blend_amount", 1.0 if _air_time > 0.15 else 0.0)
	if was_airborne and not _airborne and _speed < 1.0 and _tree.get(&"parameters/land/request") != null:
		_tree.set(&"parameters/land/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


## 애니메이션이 뼈에 적용된 뒤 BodyPoseModifier가 부른다. 총 겨누기, 시선, 웅크린 다리를 덧입힌다.
func apply_overlays() -> void:
	_update_space()
	var pitch := player.head.rotation.x
	var aim := FORWARD.rotated(RIGHT, pitch)
	var weapon := player.weapons.current_weapon()
	# 고개를 드는 만큼 가슴과 머리를 나눠 든다. 겨눌 때는 더 많이 따라간다.
	_rotate_bone(&"chest", RIGHT, pitch * lerpf(0.15, 0.35, ready_blend))
	_rotate_bone(&"head", RIGHT, pitch * 0.4)
	if ready_blend > 0.0:
		for side: float in [-1.0, 1.0]:
			var roles := _arm_roles(side)
			var solved := _ready_arm(side, aim, weapon)
			_point_bone(roles[0], roles[1], _current_direction(roles[0], roles[1]).slerp(solved[0], ready_blend))
			_point_bone(roles[1], roles[2], _current_direction(roles[1], roles[2]).slerp(solved[1], ready_blend))
	if _crouch > 0.01:
		_rotate_bone(&"spine", RIGHT, -deg_to_rad(25.0) * _crouch)
		var swing := deg_to_rad(28.0 * _gait) * 0.5
		for side: float in [-1.0, 1.0]:
			var phase := _phase if side < 0.0 else _phase + PI
			var dirs := _leg_directions(side, phase, swing, _gait, 1.0, false)
			var roles := _leg_roles(side)
			_point_bone(roles[0], roles[1], _current_direction(roles[0], roles[1]).slerp(dirs[0], _crouch))
			_point_bone(roles[1], roles[2], _current_direction(roles[1], roles[2]).slerp(dirs[1], _crouch))
			_keep_rest_orientation(roles[2])
	# 웅크리면 발이 땅에 닿도록 모델을 내린다. 서 있을 때는 애니메이션의 높이를 그대로 쓴다.
	var target_offset := 0.0
	if _crouch > 0.01 and not _airborne:
		var lowest := minf(_posed_point(&"foot_l").y, _posed_point(&"foot_r").y)
		target_offset = (_rest_foot_height - lowest) * _crouch
	_ground_offset = move_toward(_ground_offset, target_offset, _delta * 4.0)
	_model.position = _model_base_position + Vector3.UP * _ground_offset
	_update_held_weapon()


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


## 두 마디(위팔·아래팔)가 root에서 target에 닿는 방향을 구한다. 팔꿈치는 pole 쪽으로 굽는다.
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

## 모델을 들어 올리기 전 기준의 뼈 위치 (몸 공간)
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
