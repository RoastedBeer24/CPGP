class_name PlayerBody
extends Node3D
## 플레이어의 몸. 다른 사람 눈과 내 3인칭 화면에 보이고, 1인칭에서는 그림자만 남는다.
##
## 캐릭터 모델에 애니메이션이 없어서 걷기, 달리기, 웅크리기, 점프, 총 겨누기 자세를
## 매 프레임 뼈를 직접 돌려서 만든다. 뼈마다 축 방향이 제각각이라 각도 대신
## "이 뼈가 몸 기준으로 어느 쪽을 가리켜야 하는지"를 정하고, 그 방향으로 돌린다.
## 움직임은 위치 변화로 잰다. 원격 플레이어는 속도가 동기화되지 않기 때문이다.
##
## 모델 파일이 없으면(재배포할 수 없는 모델이라 저장소에 없다) 캡슐 몸으로 대신한다.

enum ViewMode { VISIBLE, SHADOW_ONLY, HIDDEN }

const DEFAULT_APPEARANCE := "res://data/player/default_appearance.tres"

# 몸 기준 방향. 앞은 -Z, 오른쪽은 +X다.
const FORWARD := Vector3(0, 0, -1)
const RIGHT := Vector3(1, 0, 0)

## 이 속도(m/s)보다 위아래로 빠르게 움직이면 공중에 뜬 것으로 본다 (원격 플레이어용)
const AIRBORNE_VERTICAL_SPEED := 1.5
## 순간 이동(부활 등)으로 생긴 속도 튐을 막는다.
const MAX_TRACKED_SPEED := 15.0

## 비워 두면 기본 외형을 쓴다.
@export var appearance: CharacterAppearance

var view_mode := ViewMode.VISIBLE
## 캐릭터 모델을 불러왔으면 true. false면 캡슐 몸이다.
var has_model := false
## 0이면 팔을 내린 자세, 1이면 총을 겨눈 자세
var ready_blend := 0.0

var _model: Node3D
var _skeleton: Skeleton3D
var _bone: Dictionary[StringName, int] = {}
## 뼈대 공간 → 몸 공간 변환 (모델을 들어 올리기 전 기준). 모델 안의 배치는 바뀌지 않으므로 한 번만 구한다.
var _body_from_skeleton := Transform3D.IDENTITY
var _to_skeleton := Basis.IDENTITY
var _rest_foot_height := 0.0
var _upper_arm_length := 0.0
var _forearm_length := 0.0
var _model_base_position := Vector3.ZERO
var _ground_offset := 0.0
var _phase := 0.0
var _last_position := Vector3.ZERO
var _velocity := Vector3.ZERO
var _held: Node3D
var _held_index := -1
var _muzzle: Node3D

@onready var player: Player = owner as Player
@onready var placeholder: MeshInstance3D = $Placeholder


func _ready() -> void:
	if appearance == null:
		# Player와 서로 참조하는 중에 리소스를 미리 불러오면 깨지므로 실행 시점에 불러온다.
		appearance = load(DEFAULT_APPEARANCE) as CharacterAppearance
	if appearance != null and appearance.has_model_file():
		_load_model()
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


func _process(delta: float) -> void:
	if player == null or delta <= 0.0:
		return
	var local_velocity := _track_velocity(delta)
	if not has_model:
		_pose_placeholder()
		return
	if _skeleton == null or not visible:
		return
	_pose(delta, local_velocity)
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


# ---- 모델 불러오기 ----

func _load_model() -> void:
	var scene := load(appearance.model_path) as PackedScene
	if scene == null:
		return
	_model = scene.instantiate() as Node3D
	_model.name = "Model"
	_model.scale = Vector3.ONE * appearance.model_scale
	if appearance.faces_positive_z:
		_model.rotation.y = PI
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

	_body_from_skeleton = _model.transform * (_model.global_transform.affine_inverse() * _skeleton.global_transform)
	_to_skeleton = _body_from_skeleton.basis.orthonormalized().inverse()
	_skeleton.reset_bone_poses()
	_rest_foot_height = minf(_rest_point(&"foot_l").y, _rest_point(&"foot_r").y)
	_upper_arm_length = _skeleton.get_bone_rest(_bone[&"forearm_r"]).origin.length()
	_forearm_length = _skeleton.get_bone_rest(_bone[&"hand_r"]).origin.length()


func _rest_point(role: StringName) -> Vector3:
	return _body_from_skeleton * _skeleton.get_bone_global_pose(_bone[role]).origin


func _apply_shadow_mode(geometry: GeometryInstance3D) -> void:
	if view_mode == ViewMode.SHADOW_ONLY:
		geometry.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	else:
		geometry.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON


# ---- 자세 만들기 ----

func _pose(delta: float, velocity: Vector3) -> void:
	var config := player.config
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var speed := horizontal.length()
	var crouch := player.crouch_blend
	var airborne := (
		not player.is_on_floor() if player.is_multiplayer_authority()
		else absf(velocity.y) > AIRBORNE_VERTICAL_SPEED
	)
	var gait := clampf(speed / config.walk_speed, 0.0, 1.0)
	var sprint := clampf((speed - config.walk_speed) / (config.sprint_speed - config.walk_speed), 0.0, 1.0)
	var move_dir := horizontal / speed if speed > 0.2 else FORWARD

	# 한 주기(두 걸음)에 나아가는 거리. 빠를수록 보폭이 넓어진다.
	var stride := lerpf(2.4, 3.0, sprint)
	if not airborne:
		_phase = fmod(_phase + speed * delta / stride * TAU, TAU)
	var swing := deg_to_rad(28.0 * gait + 14.0 * sprint) * (1.0 - 0.5 * crouch)

	var weapon := player.weapons.current_weapon()
	var wants_ready := player.health.is_alive() and not weapon.is_melee() and sprint < 0.5
	ready_blend = move_toward(ready_blend, 1.0 if wants_ready else 0.0, delta * 6.0)
	var pitch := player.head.rotation.x
	var aim := FORWARD.rotated(RIGHT, pitch)

	_skeleton.reset_bone_poses()

	# 몸통: 달리거나 웅크리면 앞으로 숙이고, 고개를 드는 만큼 가슴과 머리를 나눠 든다.
	var lean := deg_to_rad(10.0) * sprint + deg_to_rad(30.0) * crouch
	_rotate_bone(&"spine", RIGHT, -lean)
	_rotate_bone(&"chest", RIGHT, pitch * 0.35)
	_rotate_bone(&"head", RIGHT, pitch * 0.4 + lean * 0.8)

	_pose_arm(-1.0, swing, gait, sprint, aim, weapon)
	_pose_arm(1.0, swing, gait, sprint, aim, weapon)
	_pose_leg(-1.0, _phase, swing, gait, crouch, airborne, move_dir)
	_pose_leg(1.0, _phase + PI, swing, gait, crouch, airborne, move_dir)

	# 발이 땅에 닿도록 모델 높이를 맞춘다. 웅크리면 이것으로 몸이 내려간다.
	# 공중에서는 맞추지 않아서 다리가 접혀 올라간 것처럼 보인다.
	var target_offset := 0.0
	if not airborne:
		var lowest := minf(_posed_point(&"foot_l").y, _posed_point(&"foot_r").y)
		target_offset = _rest_foot_height - lowest
	_ground_offset = move_toward(_ground_offset, target_offset, delta * 4.0)
	_model.position = _model_base_position + Vector3.UP * _ground_offset


## side: 왼쪽 -1, 오른쪽 +1
func _pose_arm(side: float, swing: float, gait: float, sprint: float, aim: Vector3, weapon: WeaponData) -> void:
	var suffix := "_l" if side < 0.0 else "_r"
	var upper_role := StringName("upper_arm" + suffix)
	var fore_role := StringName("forearm" + suffix)
	var hand_role := StringName("hand" + suffix)

	# 내린 팔: 다리와 반대로 흔들고, 달릴수록 팔꿈치를 굽힌다.
	var arm_angle := -side * sin(_phase) * swing * 0.9
	var relaxed_upper := (Vector3.DOWN * cos(arm_angle) + FORWARD * sin(arm_angle) + RIGHT * side * 0.15).normalized()
	var elbow := deg_to_rad(12.0 + 20.0 * gait + 55.0 * sprint)
	var relaxed_fore := (relaxed_upper * cos(elbow) + FORWARD * sin(elbow)).normalized()

	var upper_dir := relaxed_upper
	var fore_dir := relaxed_fore
	if ready_blend > 0.0:
		# 겨눈 팔: 두 손을 가슴 앞, 조준 방향 위에 모은다. 산탄총은 왼손이 총열을 받친다.
		var shoulder := _posed_point(upper_role)
		var grip := _shoulder_center() + Vector3.DOWN * 0.08 + aim * 0.38
		var target := grip + RIGHT * 0.02
		if side < 0.0:
			target = grip + aim * (0.2 if weapon.pellets > 1 else 0.0) + RIGHT * -0.04
		var pole := (Vector3.DOWN + RIGHT * side * 0.8).normalized()
		var solved := _two_bone(shoulder, target, _upper_arm_length, _forearm_length, pole)
		upper_dir = relaxed_upper.slerp(solved[0], ready_blend)
		fore_dir = relaxed_fore.slerp(solved[1], ready_blend)

	_point_bone(upper_role, fore_role, upper_dir)
	_point_bone(fore_role, hand_role, fore_dir)


## side: 왼쪽 -1, 오른쪽 +1. phase가 0에서 π로 갈 때 다리가 앞으로 나간다.
func _pose_leg(side: float, phase: float, swing: float, gait: float, crouch: float, airborne: bool, move_dir: Vector3) -> void:
	var suffix := "_l" if side < 0.0 else "_r"
	var thigh_role := StringName("thigh" + suffix)
	var calf_role := StringName("calf" + suffix)
	var foot_role := StringName("foot" + suffix)

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

	var thigh_dir := (Vector3.DOWN * cos(angle) + move_dir * sin(angle)).rotated(RIGHT, hip_flex)
	# 웅크리면 무릎을 살짝 벌린다.
	thigh_dir = (thigh_dir + RIGHT * side * 0.12 * crouch).normalized()
	var calf_dir := thigh_dir.rotated(RIGHT, -knee)

	_point_bone(thigh_role, calf_role, thigh_dir)
	_point_bone(calf_role, foot_role, calf_dir)
	# 발은 처음 자세 그대로 땅과 나란하게 둔다.
	_keep_rest_orientation(foot_role)


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


## 뼈(role)에서 자식 뼈(child_role)로 가는 방향이 direction(몸 공간)을 가리키도록 돌린다.
func _point_bone(role: StringName, child_role: StringName, direction: Vector3) -> void:
	var index := _bone[role]
	var pose := _skeleton.get_bone_global_pose(index)
	var child_offset := _skeleton.get_bone_rest(_bone[child_role]).origin
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
