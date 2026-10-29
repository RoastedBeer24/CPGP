class_name Viewmodel
extends Node3D
## 1인칭 화면에 보이는 무기 모델. 지금은 그레이박스 도형으로 만들고, M8에서 공개 에셋으로 바꾼다.
## 발사 반동, 근접 휘두르기, 재장전, 조준 자세를 코드로 움직인다.

const HIP_POSITION := Vector3(0.2, -0.2, -0.5)
const AIM_POSITION := Vector3(0.0, -0.11, -0.4)
const BLADE_POSITION := Vector3(0.28, -0.28, -0.42)

var aim_blend := 0.0

var _model: Node3D
var _muzzle: Node3D
var _flash: OmniLight3D
var _flash_time := 0.0
var _kick := 0.0
var _swing_time := -1.0
var _reload_time := 0.0
var _reload_duration := 0.0
var _is_blade := false


func show_weapon(weapon: WeaponData) -> void:
	if _model != null:
		_model.queue_free()
	_is_blade = weapon.is_melee()
	_model = _build_blade() if _is_blade else _build_gun(weapon)
	_model.scale = Vector3.ONE * 0.7
	add_child(_model)
	_swing_time = -1.0
	_reload_time = 0.0


func muzzle_position() -> Vector3:
	return _muzzle.global_position if _muzzle != null else global_position


func play_fire(weapon: WeaponData) -> void:
	_kick = clampf(weapon.recoil_pitch / 5.0, 0.3, 1.0)
	_flash_time = 0.05
	if _flash != null:
		_flash.visible = true


func play_swing() -> void:
	_swing_time = 0.0


func play_reload(duration: float) -> void:
	_reload_duration = duration
	_reload_time = duration


func _process(delta: float) -> void:
	if _model == null:
		return
	var holder := get_parent() as WeaponHolder
	var target_aim := 1.0 if holder != null and holder.aiming else 0.0
	aim_blend = move_toward(aim_blend, target_aim, delta * 8.0)

	_kick = move_toward(_kick, 0.0, delta * 6.0)
	_flash_time -= delta
	if _flash != null and _flash_time <= 0.0:
		_flash.visible = false

	var base := BLADE_POSITION if _is_blade else HIP_POSITION.lerp(AIM_POSITION, aim_blend)
	var offset := Vector3(0.0, 0.0, _kick * 0.08)
	var rotation_x := _kick * 0.25
	var rotation_y := 0.0

	if _reload_time > 0.0:
		_reload_time -= delta
		var t := 1.0 - _reload_time / maxf(_reload_duration, 0.01)
		var dip := sin(t * PI)
		offset.y -= dip * 0.12
		rotation_x -= dip * 0.6

	if _swing_time >= 0.0:
		_swing_time += delta
		var t := clampf(_swing_time / 0.22, 0.0, 1.0)
		rotation_y = lerpf(1.1, -1.2, ease(t, 0.4))
		offset.x -= sin(t * PI) * 0.2
		if t >= 1.0:
			_swing_time = -1.0

	_model.position = base + offset
	_model.rotation = Vector3(rotation_x, rotation_y, 0.0)


func _build_gun(weapon: WeaponData) -> Node3D:
	var root := Node3D.new()
	var length := 0.6 if weapon.pellets > 1 else 0.26
	_add_box(root, Vector3(0.07, 0.11, length), Vector3(0, 0, -length * 0.5 + 0.08), Color(0.2, 0.2, 0.24))
	_add_box(root, Vector3(0.05, 0.14, 0.07), Vector3(0, -0.1, 0.04), Color(0.15, 0.15, 0.18))
	_add_box(root, Vector3(0.075, 0.015, length * 0.7), Vector3(0, 0.062, -length * 0.4), Color(0.1, 0.9, 1), true)
	_muzzle = Node3D.new()
	_muzzle.position = Vector3(0, 0, -length + 0.06)
	root.add_child(_muzzle)
	_flash = OmniLight3D.new()
	_flash.light_color = Color(1, 0.8, 0.4)
	_flash.light_energy = 3.0
	_flash.omni_range = 4.0
	_flash.visible = false
	_muzzle.add_child(_flash)
	return root


func _build_blade() -> Node3D:
	var root := Node3D.new()
	_add_box(root, Vector3(0.09, 0.09, 0.35), Vector3(0, 0, 0.05), Color(0.25, 0.25, 0.3))
	_add_box(root, Vector3(0.015, 0.07, 0.75), Vector3(0.03, 0.02, -0.45), Color(1, 0.25, 0.7), true)
	_muzzle = null
	_flash = null
	return root


func _add_box(parent: Node3D, size: Vector3, position: Vector3, color: Color, glow: bool = false) -> void:
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
	instance.position = position
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)
