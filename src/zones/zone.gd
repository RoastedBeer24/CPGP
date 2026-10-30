class_name Zone
extends Node3D
## 구역(맵)의 뿌리. 적의 길찾기 지도(내비게이션 메시)를 준비한다.
##
## 길찾기 지도는 "navigation_geometry" 그룹에 든 지형으로 실행할 때 만든다(굽기).
## 씬에 들어 있는 NavigationMesh는 굽기 설정만 담고, 구운 결과는 새 리소스로 만들어 지역(region)에 넣는다.
## 이미 트리에 있는 지역에 지도를 바꿔 넣으면 길찾기 서버가 받지 못하는 경우가 있어서(--fixed-fps에서 재현됨),
## 굽는 동안 지역을 트리에서 빼 두었다가 구운 지도를 넣은 뒤 다시 붙인다.
## 구운 지도는 구역 씬마다 한 번만 만들어 두고 다음 인스턴스(코옵 테스트의 여러 피어 등)가 다시 쓴다.

const GEOMETRY_GROUP := &"navigation_geometry"

## 구역 씬 경로 → 구운 지도
static var _baked: Dictionary[String, NavigationMesh] = {}

@onready var navigation: NavigationRegion3D = get_node_or_null("Navigation") as NavigationRegion3D


func _ready() -> void:
	if navigation == null or navigation.navigation_mesh == null:
		return
	if _baked.has(scene_file_path):
		navigation.navigation_mesh = _baked[scene_file_path]
		return
	# CSG 지형은 트리에 들어간 다음 프레임에 모양이 만들어진다. 그 전에 구우면 바닥과 벽이 빠진다.
	remove_child(navigation)
	await get_tree().process_frame
	if not is_inside_tree():
		return
	navigation.navigation_mesh = bake_navigation()
	add_child(navigation)


func _notification(what: int) -> void:
	# 굽는 도중(지역을 빼 둔 동안) 구역이 지워지면 빼 둔 지역도 함께 지운다.
	if what == NOTIFICATION_PREDELETE and is_instance_valid(navigation) and navigation.get_parent() == null:
		navigation.free()


## 지금 지형으로 길찾기 지도를 새로 굽는다.
func bake_navigation() -> NavigationMesh:
	if _baked.has(scene_file_path):
		return _baked[scene_file_path]
	var mesh := navigation.navigation_mesh.duplicate() as NavigationMesh
	mesh.clear()
	var source := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(mesh, source, self)
	NavigationServer3D.bake_from_source_geometry_data(mesh, source)
	if not scene_file_path.is_empty():
		_baked[scene_file_path] = mesh
	return mesh
