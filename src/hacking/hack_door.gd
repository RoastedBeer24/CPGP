class_name HackDoor
extends StaticBody3D
## 잠긴 문. 장치 해킹 "문 열기"로 연다. 한 번 열리면 계속 열려 있다.
## 열림 여부는 호스트가 정하고 동기화된다.

@export var size := Vector3(2.4, 3.0, 0.3)

# 동기화되는 상태
var opened := false

var _panel: Node3D
var _stripe: MeshInstance3D
var _shape: CollisionShape3D


func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	_shape = CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	_shape.shape = box
	_shape.position = Vector3(0, size.y * 0.5, 0)
	add_child(_shape)
	_panel = Node3D.new()
	add_child(_panel)
	DeviceParts.box(_panel, size, Vector3(0, size.y * 0.5, 0), Color(0.22, 0.24, 0.3))
	_stripe = DeviceParts.box(_panel, Vector3(size.x * 0.8, 0.08, size.z + 0.02), Vector3(0, size.y * 0.55, 0), Color(1, 0.2, 0.2), 3.0)
	DeviceParts.hackable(self, "잠긴 문", ["res://data/hacking/open_door.tres"], Vector3(0, size.y * 0.55, 0))
	DeviceParts.sync(self, [".:opened"])


func is_hackable() -> bool:
	return not opened


func scan_lines() -> PackedStringArray:
	return PackedStringArray(["잠긴 문", "상태: %s" % ("열림" if opened else "잠김"), "장치 해킹으로 열 수 있다"])


func apply_quickhack(hack: QuickhackData, _hacker: Player) -> void:
	if multiplayer.is_server() and hack.effect == QuickhackData.Effect.OPEN_DOOR:
		opened = true


func _process(delta: float) -> void:
	# 열리면 위로 밀려 올라가고 길을 막지 않는다.
	var target := size.y - 0.15 if opened else 0.0
	_panel.position.y = move_toward(_panel.position.y, target, delta * 3.0)
	if _shape.disabled != opened:
		_shape.set_deferred("disabled", opened)
	var material := _stripe.mesh.surface_get_material(0) as StandardMaterial3D
	var color := Color(0.2, 1, 0.4) if opened else Color(1, 0.2, 0.2)
	material.albedo_color = color
	material.emission = color
