class_name DeviceParts
extends RefCounted
## 해킹 장치(카메라, 문, 포탑)를 코드로 조립할 때 쓰는 부품. 그레이박스 도형이다.
## 장치마다 씬 파일을 두지 않고 스크립트 하나로 만들어 시험장 생성 스크립트에서 바로 놓을 수 있게 한다.


static func box(parent: Node3D, size: Vector3, position: Vector3, color: Color, glow: float = 0.0) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	if glow > 0.0:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = glow
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = position
	parent.add_child(instance)
	return instance


## 체력. 판정은 호스트가 하고, 값은 sync가 퍼뜨린다.
static func health(parent: Node, max_value: float, armor: float) -> Health:
	var node := Health.new()
	node.name = "Health"
	node.max_health = max_value
	node.armor = armor
	parent.add_child(node)
	node.current = max_value
	return node


## 총에 맞는 영역. 장치 몸체보다 조금 크게 만들어 몸체보다 먼저 맞게 한다.
static func hitbox(parent: Node3D, health_node: Health, radius: float, position: Vector3) -> Hitbox:
	var area := Hitbox.new()
	area.name = "Hitbox"
	area.position = position
	# 아직 트리에 붙기 전이라 부모 기준 경로에 한 단계(..)를 더한다.
	area.health_path = NodePath("../" + String(parent.get_path_to(health_node)))
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	shape.shape = sphere
	area.add_child(shape)
	parent.add_child(area)
	return area


## 호스트가 정하는 값을 퍼뜨리는 동기화 노드. 경로는 장치 기준이다(".:state" 등).
static func sync(parent: Node, properties: Array[String]) -> MultiplayerSynchronizer:
	var config := SceneReplicationConfig.new()
	for property in properties:
		var path := NodePath(property)
		config.add_property(path)
		config.property_set_spawn(path, true)
		config.property_set_replication_mode(path, SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE)
	var synchronizer := MultiplayerSynchronizer.new()
	synchronizer.name = "StateSync"
	synchronizer.replication_config = config
	parent.add_child(synchronizer)
	return synchronizer


static func hackable(parent: Node3D, display_name: String, hack_paths: Array[String], position: Vector3) -> Hackable:
	var node := Hackable.new()
	node.name = "Hackable"
	node.display_name = display_name
	node.position = position
	for path in hack_paths:
		node.quickhacks.append(load(path) as QuickhackData)
	parent.add_child(node)
	return node
