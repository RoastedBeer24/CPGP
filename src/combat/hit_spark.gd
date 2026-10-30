class_name HitSpark
extends Node3D
## 맞힌 자리에 잠깐 번쩍이는 불꽃. 때린 사람 화면에 바로 보여 준다(판정은 호스트가 따로 한다).
## 원석 결정 효과가 있는 타격은 주황빛 결정 조각이 튄다.

const LIFETIME := 0.25

## 가운데가 밝고 가장자리로 흐려지는 둥근 빛. 그림 없이 판만 그리면 흰 네모로 보였다.
static var _glow: GradientTexture2D

var _age := 0.0
var _flash: MeshInstance3D
var _material: StandardMaterial3D


static func _glow_texture() -> GradientTexture2D:
	if _glow == null:
		var gradient := Gradient.new()
		gradient.set_color(0, Color(1, 1, 1, 1))
		gradient.set_color(1, Color(1, 1, 1, 0))
		gradient.add_point(0.25, Color(1, 1, 1, 0.85))
		_glow = GradientTexture2D.new()
		_glow.gradient = gradient
		_glow.fill = GradientTexture2D.FILL_RADIAL
		_glow.fill_from = Vector2(0.5, 0.5)
		_glow.fill_to = Vector2(1.0, 0.5)
		_glow.width = 64
		_glow.height = 64
	return _glow


static func spawn(parent: Node, position: Vector3, effect: HitData.Effect) -> void:
	var spark := HitSpark.new()
	spark.top_level = true
	parent.add_child(spark)
	spark.global_position = position
	spark._build(effect)


func _build(effect: HitData.Effect) -> void:
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_material.albedo_texture = _glow_texture()
	_material.no_depth_test = true
	var color := Color(1.0, 0.95, 0.75)
	if effect != HitData.Effect.NONE:
		color = Color(1.0, 0.6, 0.15)
	_material.albedo_color = color
	var quad := QuadMesh.new()
	quad.size = Vector2(0.9, 0.9) if effect == HitData.Effect.NONE else Vector2(1.6, 1.6)
	quad.material = _material
	_flash = MeshInstance3D.new()
	_flash.mesh = quad
	_flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flash.rotation.z = randf() * TAU
	add_child(_flash)


func _process(delta: float) -> void:
	_age += delta
	var t := clampf(_age / LIFETIME, 0.0, 1.0)
	if _flash != null:
		_flash.scale = Vector3.ONE * lerpf(0.4, 1.3, t)
		_material.albedo_color.a = 1.0 - t
	if _age >= LIFETIME:
		queue_free()
