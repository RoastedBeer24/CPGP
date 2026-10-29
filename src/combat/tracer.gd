class_name Tracer
extends MeshInstance3D
## 탄 궤적. 잠깐 보였다가 사라진다.

const LIFETIME := 0.06
const MATERIAL := preload("res://src/combat/tracer_material.tres")

var _age := 0.0


static func spawn(parent: Node, from: Vector3, to: Vector3) -> void:
	var length := from.distance_to(to)
	if length < 0.05:
		return
	var tracer := Tracer.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.015, 0.015, length)
	tracer.mesh = mesh
	tracer.material_override = MATERIAL
	tracer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	tracer.top_level = true
	parent.add_child(tracer)
	var middle := (from + to) * 0.5
	tracer.global_transform = Transform3D(Basis(), middle).looking_at(to, Vector3.UP if absf((to - from).normalized().y) < 0.99 else Vector3.RIGHT)


func _process(delta: float) -> void:
	_age += delta
	if _age >= LIFETIME:
		queue_free()
