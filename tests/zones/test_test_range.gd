extends TestCase
## 그레이박스 시험장에서 주요 경로를 실제로 오를 수 있는지 확인한다.

const ZONE_SCENE := preload("res://src/zones/test_range/test_range.tscn")
const PLAYER_SCENE := preload("res://src/player/player.tscn")
const ROOF_HEIGHT := 3.0

var zone: Node3D
var player: Player
var intent: PlayerIntent


func before_each() -> void:
	zone = ZONE_SCENE.instantiate()
	add_child_autofree(zone)
	player = PLAYER_SCENE.instantiate()
	player.use_device_input = false
	intent = PlayerIntent.new()
	player.intent_override = intent
	add_child_autofree(player)


func test_has_three_spawn_points() -> void:
	assert_true(zone.get_node("SpawnPoints").get_child_count() >= 3)


func test_navigation_reaches_stealth_zone() -> void:
	var map := zone.get_world_3d().navigation_map
	# 길찾기 서버는 물리 프레임이 끝날 때 지도를 반영하므로 몇 프레임 기다린다.
	var path := PackedVector3Array()
	# 처음 몇 프레임은 지도가 덜 합쳐져 길이 중간에서 끊길 수 있으므로, 끝까지 닿을 때까지 기다린다.
	for i in 30:
		await tree.physics_frame
		path = NavigationServer3D.map_get_path(map, Vector3(0, 0, 10), Vector3(-70, 0, 10), true)
		if path.size() > 1 and Vector2(path[-1].x, path[-1].z).distance_to(Vector2(-70, 10)) < 1.0:
			break
	assert_true((zone as Zone).navigation.navigation_mesh.get_polygon_count() > 100, "길찾기 지도가 지형을 담아 구워짐")
	assert_true(path.size() > 1, "시작 지점에서 잠입 구역까지 길이 있음")
	if path.size() > 1:
		assert_true(Vector2(path[-1].x, path[-1].z).distance_to(Vector2(-70, 10)) < 1.0, "끝점 %s" % path[-1])


func test_stealth_zone_has_enemies_routes_and_hide_spots() -> void:
	var enemies := zone.get_node("Stealth/Enemies").get_children()
	assert_eq(enemies.size(), 7, "경비 넷, 중장갑병, 보초, 넷러너")
	var heavy := 0
	for node in enemies:
		var enemy := node as Enemy
		if enemy.data.max_health > 150.0:
			heavy += 1
		if not enemy.patrol_route.is_empty():
			assert_not_null(enemy.get_node_or_null(enemy.patrol_route), "%s의 순찰 경로" % enemy.name)
	assert_eq(heavy, 1, "중장갑병 하나")
	assert_eq(tree.get_nodes_in_group(HideSpot.GROUP).size(), 3)
	assert_true(tree.get_nodes_in_group(Enemy.COVER_GROUP).size() >= 16)


func test_patrol_guard_walks_its_route_on_navmesh() -> void:
	var guard := zone.get_node("Stealth/Enemies/Patrol1") as Enemy
	var start := guard.global_position
	for i in 300:
		await tree.physics_frame
	assert_true(guard.global_position.distance_to(start) > 3.0, "순찰을 돈다: %s" % guard.global_position)
	assert_eq(guard.alert, Enemy.Alert.UNAWARE)


func test_stairs_lead_to_rooftop() -> void:
	await _walk_from(Vector3(-14, 0.05, 7.5), 180)
	assert_almost_eq(player.global_position.y, ROOF_HEIGHT, 0.1)


func test_ramp_leads_to_rooftop() -> void:
	await _walk_from(Vector3(14, 0.05, 7.5), 180)
	assert_almost_eq(player.global_position.y, ROOF_HEIGHT, 0.1)


func test_tallest_ledge_is_climbable() -> void:
	player.global_position = Vector3(8, 0.05, -3.5)
	await _frames(5)
	intent.move = Vector2(0, 1)
	intent.jump_held = true
	intent.jump_pressed = true
	for i in 120:
		await tree.physics_frame
		if player.state == Player.State.MANTLE:
			intent.move = Vector2.ZERO
	await _frames(10)
	assert_almost_eq(player.global_position.y, 2.5, 0.1)


func _walk_from(start: Vector3, frames: int) -> void:
	player.global_position = start
	await _frames(5)
	intent.move = Vector2(0, 1)
	await _frames(frames)


func _frames(count: int) -> void:
	for i in count:
		await tree.physics_frame
