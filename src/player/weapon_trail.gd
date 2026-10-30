class_name WeaponTrail
extends MeshInstance3D
## 칼을 휘두를 때 칼날이 지나간 자리에 남는 빛의 띠(검기). 공격 동작 중에만 남기고, 짧은 시간에 사라진다.
## 칼날의 뿌리와 끝 위치를 프레임마다 기록해 띠 모양으로 잇는다. 원작 이펙트(전용 셰이더)를 옮기기 전까지 쓰는
## 간단한 효과다. 세상 기준으로 그리므로 top_level이다.

## 띠가 남는 시간(초)
const LIFETIME := 0.14
## 칼날 위 띠의 뿌리와 끝 (무기 기준, 칼날은 +Y로 뻗는다)
const BASE := Vector3(0, 0.3, 0)
const TIP := Vector3(0, 1.0, 0)
const COLOR := Color(1.0, 0.86, 0.55)
const SKILL_COLOR := Color(1.0, 0.55, 0.15)

## 띠를 남길 무기 (칼날이 +Y로 뻗는 노드)
var weapon: Node3D
## 이번 프레임에 띠를 이어 그릴지
var active := false
## 원석 결정을 쓰는 동작(배틀 스킬, 궁극기)이면 주황빛
var crystal := false

var _samples: Array[Array] = []
var _immediate := ImmediateMesh.new()


func _ready() -> void:
	top_level = true
	mesh = _immediate
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.vertex_color_use_as_albedo = true
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	material_override = material
	global_transform = Transform3D.IDENTITY


## 지금 띠가 그려지고 있는지 (테스트용)
func sample_count() -> int:
	return _samples.size()


func _process(delta: float) -> void:
	global_transform = Transform3D.IDENTITY
	for sample in _samples:
		sample[2] = float(sample[2]) + delta
	while not _samples.is_empty() and float(_samples[0][2]) > LIFETIME:
		_samples.pop_front()
	if active and weapon != null and is_instance_valid(weapon) and weapon.is_visible_in_tree():
		var transform := weapon.global_transform
		_samples.append([transform * BASE, transform * TIP, 0.0])
	_rebuild()


func _rebuild() -> void:
	_immediate.clear_surfaces()
	if _samples.size() < 2:
		return
	var color := SKILL_COLOR if crystal else COLOR
	_immediate.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for sample in _samples:
		var fade := 1.0 - clampf(float(sample[2]) / LIFETIME, 0.0, 1.0)
		_immediate.surface_set_color(Color(color, fade * 0.15))
		_immediate.surface_add_vertex(sample[0])
		_immediate.surface_set_color(Color(color, fade * 0.9))
		_immediate.surface_add_vertex(sample[1])
	_immediate.surface_end()
