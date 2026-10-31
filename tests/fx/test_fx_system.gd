extends TestCase
## 원작 이펙트: 파티클 시스템 계산(FxSystem)과 재질 변환(FxMaterial), 실제 꾸러미의 이펙트 재생(FxEffect).
## 실제 이펙트는 원작 자산이라 저장소에 없으므로, 꾸러미가 있는 PC에서만 검사한다.

const PLAYER_SCENE := preload("res://src/player/player.tscn")

var emitter: Node3D


func before_each() -> void:
	emitter = Node3D.new()
	add_child_autofree(emitter)
	await tree.process_frame


func test_burst_particles_live_their_lifetime() -> void:
	var system := _system({"main": {"lengthInSec": 1.0}, "initial": {"startLifetime": {"m": 0, "c": 0.5}, "maxNumParticles": 100},
		"modules": {"EmissionModule": {"m_Bursts": [{"time": 0.0, "countCurve": {"m": 0, "c": 5.0}, "cycleCount": 1, "repeatInterval": 0.01, "probability": 1.0}]}}})
	system.advance(0.1)
	assert_eq(system.alive(), 5, "처음에 다섯 개가 한꺼번에 나온다")
	system.advance(0.6)
	assert_eq(system.alive(), 0, "수명(0.5초)이 지나면 사라진다")


func test_rate_over_time_and_particle_cap() -> void:
	var system := _system({"main": {"lengthInSec": 1.0}, "initial": {"startLifetime": {"m": 0, "c": 5.0}, "maxNumParticles": 100},
		"modules": {"EmissionModule": {"rateOverTime": {"m": 0, "c": 20.0}}}})
	for i in 61:
		system.advance(i / 60.0)
	assert_almost_eq(float(system.alive()), 20.0, 1.0, "초당 20개씩 1초")
	var capped := _system({"main": {"lengthInSec": 1.0}, "initial": {"startLifetime": {"m": 0, "c": 5.0}, "maxNumParticles": 3},
		"modules": {"EmissionModule": {"rateOverTime": {"m": 0, "c": 20.0}}}})
	capped.advance(1.0)
	assert_eq(capped.alive(), 3, "원작 설정의 최대 파티클 수를 넘지 않는다")


func test_start_delay_and_speed() -> void:
	var system := _system({"main": {"lengthInSec": 1.0, "startDelay": {"m": 0, "c": 0.3}},
		"initial": {"startLifetime": {"m": 0, "c": 1.0}, "startSpeed": {"m": 0, "c": 2.0}},
		"modules": {"EmissionModule": {"m_Bursts": [{"time": 0.0, "countCurve": {"m": 0, "c": 1.0}, "cycleCount": 1, "probability": 1.0}]}}})
	system.advance(0.2)
	assert_eq(system.alive(), 0, "시작 지연 전에는 나오지 않는다")
	system.advance(0.3)
	assert_eq(system.alive(), 1)
	system.advance(0.8)
	var p: FxSystem.Particle = system._particles[0]
	assert_almost_eq(p.pos.z, 1.0, 0.05, "기본 방향(+Z)으로 초속 2m, 0.5초")


func test_world_space_particles_stay_behind_moving_emitter() -> void:
	var data := {"main": {"lengthInSec": 1.0, "moveWithTransform": 1},
		"initial": {"startLifetime": {"m": 0, "c": 2.0}},
		"modules": {"EmissionModule": {"m_Bursts": [{"time": 0.0, "countCurve": {"m": 0, "c": 1.0}, "cycleCount": 1, "probability": 1.0}]}}}
	var world := _system(data)
	world.advance(0.05)
	emitter.position = Vector3(5, 0, 0)
	world.advance(0.1)
	var p: FxSystem.Particle = world._particles[0]
	assert_almost_eq(p.pos.x, 0.0, 0.001, "세상 기준 파티클은 태어난 자리에 남는다")


func test_cone_shape_and_mirror() -> void:
	var system := _system({"main": {"lengthInSec": 1.0}, "initial": {"startLifetime": {"m": 0, "c": 1.0}, "maxNumParticles": 50},
		"modules": {"EmissionModule": {"m_Bursts": [{"time": 0.0, "countCurve": {"m": 0, "c": 30.0}, "cycleCount": 1, "probability": 1.0}]},
			"ShapeModule": {"type": 4, "angle": 0.0, "radius": {"value": 1.0}, "radiusThickness": 0.0, "arc": {"value": 360.0},
				"m_Position": [1.0, 0.0, 0.0]}}})
	system.advance(0.01)
	for p: FxSystem.Particle in system._particles:
		assert_almost_eq(Vector2(p.pos.x - 1.0, p.pos.y).length(), 1.0, 0.001, "원뿔 밑면의 원 둘레(두께 0)")
	# 유니티 좌표(+X)는 Godot에서 -X다.
	emitter.position = Vector3.ZERO
	system._read_emitter()
	var world := system._sim_to_world * Vector3(1, 0, 0)
	assert_almost_eq(world.x, -1.0, 0.0001, "그릴 때 X를 뒤집는다")


func test_material_slot_roles_follow_original_settings() -> void:
	# 슬롯 두 개: 0번은 마스크, 1번은 녹이기 (원작 재질 M_fx_endminf_218과 같은 꼴)
	var floats := {"_SampleTex0UseWeight0": 0.0, "_SampleTex0UseWeight2": 0.0, "_SampleTex0UseWeight3": 1.0,
		"_SampleTex0UseWeight4": 0.0, "_SampleTex0UseWeight5": 0.0, "_SampleTex1UseWeight1": 0.0, "_SampleTex1UseWeight2": 0.0,
		"_SampleTex1UseWeight3": 0.0, "_SampleTex1UseWeight4": 0.0, "_SampleTex1UseWeight5": 1.0, "_BlendMode": 1.0, "_ZTest": 8.0}
	var extras := {"shader": "HGRP/Effect/VFXBaseV2", "floats": floats, "colors": {"_TintColor": [2.0, 0.5, 0.0, 1.0]},
		"vfx": {"keywords": ["_SAMPLE_TEX0", "_SAMPLE_TEX1"], "st": {"_MaskTex": [1.0, 3.0, 0.0, -1.78]}, "textures": {}}}
	assert_true(FxMaterial.supported(extras))
	var material := FxMaterial.build(extras, EffectLibrary.Effect.new(), {}, FxMaterial.Draw.AXES, true, false)
	var roles: PackedVector4Array = material.get_shader_parameter(&"slot_roles")
	assert_eq(roles[0], Vector4(0, 0, 1, 0), "0번 슬롯은 마스크")
	var dissolve: PackedFloat32Array = material.get_shader_parameter(&"slot_dissolve")
	assert_eq(dissolve[1], 1.0, "1번 슬롯은 녹이기")
	var sts: PackedVector4Array = material.get_shader_parameter(&"slot_st")
	assert_eq(sts[0], Vector4(1.0, 3.0, 0.0, -1.78), "마스크 슬롯은 마스크의 타일링을 쓴다")
	var tint: Vector4 = material.get_shader_parameter(&"tint_color")
	assert_almost_eq(tint.x, pow(2.0, 2.4), 0.001, "1보다 밝은 색은 c^2.4로 선형으로 바꾼다")
	assert_true(material.shader.code.contains("blend_add"), "_BlendMode 1은 더하기")
	assert_true(material.shader.code.contains("depth_test_disabled"), "_ZTest 8은 항상 보인다")
	var polar := extras.duplicate(true)
	(polar["vfx"] as Dictionary)["keywords"] = ["_USE_POLARUV", "_USE_SCREENUV"]
	assert_true(FxMaterial.supported(polar), "극좌표 UV(충격파 고리)도 그린다")
	var unknown := extras.duplicate(true)
	(unknown["vfx"] as Dictionary)["keywords"] = ["_USE_VERTOFFSET"]
	assert_false(FxMaterial.supported(unknown), "원작 계산을 모르는 정점 밀기는 건너뛴다")
	assert_true(FxMaterial.screen_effect("HGRP/Effect/VFXRefract"), "재질 자료가 없는 화면 왜곡은 비슷하게 만든다")


func test_original_attack_effect_plays_with_attack() -> void:
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40, 1, 40)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position.y = -0.5
	add_child_autofree(floor_body)
	var player := PLAYER_SCENE.instantiate() as Player
	player.use_device_input = false
	var intent := PlayerIntent.new()
	player.intent_override = intent
	add_child_autofree(player)
	for i in 8:
		await tree.physics_frame
	if not player.body.has_model or player.body.fx == null or not player.body.fx.has_effects(&"attack_1"):
		print("    (원작 이펙트 꾸러미가 없어 건너뜀)")
		return
	intent.attack_pressed = true
	var most := 0
	for i in 40:
		await tree.physics_frame
		var count := 0
		for effect in _effects(player):
			count += effect.alive()
		most = maxi(most, count)
	assert_true(most > 0, "첫 공격에 원작 칼빛 파티클이 나온다")
	assert_false(player.body.trail.active, "원작 이펙트가 있는 동작은 임시 검기를 그리지 않는다")
	for i in 90:
		await tree.physics_frame
	assert_eq(_effects(player).size(), 0, "끝 시각이 지나면 사라진다")


func _effects(player: Player) -> Array[FxEffect]:
	var found: Array[FxEffect] = []
	for node: Node in player.body.find_children("Effect_*", "", true, false):
		if node is FxEffect:
			found.append(node as FxEffect)
	return found


func _system(data: Dictionary) -> FxSystem:
	data["renderer"] = {"mode": 0, "align": 0}
	var system := FxSystem.new()
	system.setup(data, EffectLibrary.Effect.new(), emitter, null)
	add_child_autofree(system)
	return system
