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


func test_texture_sheet_draws_one_tile_per_particle() -> void:
	# 연기 그림처럼 한 장에 여러 칸(2x2)이 든 텍스처 시트: 재질이 칸 수를 알아야 파티클마다 한 칸만 그린다.
	var effect := EffectLibrary.Effect.new()
	effect.materials.append({"name": "smoke", "extras": {"shader": "HGRP/Effect/VFXBaseV2", "floats": {}, "colors": {}, "vfx": {"keywords": []}}})
	var data := {"renderer": {"mode": 0, "align": 0, "materials": [0]},
		"modules": {"UVModule": {"mode": 0, "tilesX": 2, "tilesY": 2, "cycles": 1.0, "frameOverTime": {"m": 0, "c": 0.6}}}}
	var material := FxEffect._material(effect, 0, data)
	assert_eq(material.get_shader_parameter(&"sheet_tiles"), Vector2(2, 2), "재질에 칸 수를 넘긴다")
	var p := FxSystem.Particle.new()
	p.rand = PackedFloat32Array()
	p.rand.resize(FxSystem.R.COUNT)
	var system := FxSystem.new()
	system.setup(data, effect, emitter, null)
	add_child_autofree(system)
	assert_eq(system._sheet_frame(0.5, p), 2.0, "수명에 따른 칸 번호 (0.6 x 4칸 → 2번째 칸)")


func test_many_particles_stay_fast() -> void:
	# 궁극기처럼 파티클이 1,000개를 넘어도 한 프레임 계산이 짧아야 한다(예전에는 포그라니치니크 궁극기에서
	# 프레임당 30~65ms였다). 힘·속도·크기·회전·색 모듈을 모두 쓰는 시스템 다섯 개, 각 256개.
	var systems: Array[FxSystem] = []
	for k in 5:
		systems.append(_system({"main": {"lengthInSec": 5.0, "looping": true},
			"initial": {"startLifetime": {"m": 0, "c": 4.0}, "maxNumParticles": 256, "startSpeed": {"m": 3, "min": 1.0, "max": 3.0},
				"startColor": {"m": 1, "max": {"mode": 0, "c": [[0.0, 1, 0.5, 0.2], [1.0, 0.2, 0.5, 1]], "a": [[0.0, 1.0], [1.0, 0.0]]}}},
			"modules": {"EmissionModule": {"rateOverTime": {"m": 0, "c": 400.0}},
				"ForceModule": {"x": {"m": 0, "c": 0.5}, "y": {"m": 1, "max": [[0.0, 0.0, 0.0, 1.0], [1.0, 1.0, 1.0, 0.0]]}},
				"VelocityModule": {"orbitalY": {"m": 0, "c": 1.0}, "speedModifier": {"m": 0, "c": 1.0}},
				"ClampVelocityModule": {"magnitude": {"m": 0, "c": 2.0}, "dampen": 0.2},
				"SizeModule": {"curve": {"m": 1, "max": [[0.0, 0.0, 0.0, 2.0], [1.0, 1.0, 0.0, 0.0]]}},
				"RotationModule": {"curve": {"m": 0, "c": 3.0}},
				"ColorModule": {"gradient": {"m": 1, "max": {"mode": 0, "c": [[0.0, 1, 1, 1]], "a": [[0.0, 1.0], [1.0, 0.0]]}}}}}))
	for k in systems.size():
		systems[k].advance(1.0)
	var started := Time.get_ticks_usec()
	for frame in 10:
		for system in systems:
			system.advance(1.0 + (frame + 1) / 60.0)
	var per_frame := (Time.get_ticks_usec() - started) / 10000.0
	var particles := 0
	for system in systems:
		particles += system.alive()
	assert_eq(particles, 5 * 256, "상한까지 찬다")
	print("    파티클 %d개, 프레임당 %.1fms" % [particles, per_frame])
	assert_true(per_frame < 40.0, "프레임당 %.1fms" % per_frame)


func test_effect_amount_setting_reduces_particles() -> void:
	# 설정의 "이펙트 양"을 낮추면 파티클이 줄되, 하나뿐인 파티클(충격파 고리 등)은 남는다.
	GameSettings.effect_quality = GameSettings.EffectQuality.LOW
	var burst := _system({"main": {"lengthInSec": 1.0}, "initial": {"startLifetime": {"m": 0, "c": 1.0}, "maxNumParticles": 100},
		"modules": {"EmissionModule": {"m_Bursts": [{"time": 0.0, "countCurve": {"m": 0, "c": 30.0}, "cycleCount": 1, "probability": 1.0}]}}})
	var single := _system({"main": {"lengthInSec": 1.0}, "initial": {"startLifetime": {"m": 0, "c": 1.0}},
		"modules": {"EmissionModule": {"m_Bursts": [{"time": 0.0, "countCurve": {"m": 0, "c": 1.0}, "cycleCount": 1, "probability": 1.0}]}}})
	GameSettings.reset_to_defaults()
	burst.advance(0.01)
	single.advance(0.01)
	assert_eq(burst.alive(), roundi(30 * GameSettings.EFFECT_AMOUNTS[GameSettings.EffectQuality.LOW]), "30개 → 약 3분의 1")
	assert_eq(single.alive(), 1, "하나뿐인 파티클은 남긴다")


func test_slow_frame_catches_up_in_few_steps() -> void:
	# 프레임이 늦어도(0.2초) 따라잡는 계산은 몇 번으로 나누고, 위치는 쪼개 계산한 것과 거의 같다.
	var data := {"main": {"lengthInSec": 1.0}, "initial": {"startLifetime": {"m": 0, "c": 2.0}, "startSpeed": {"m": 0, "c": 1.0}},
		"modules": {"EmissionModule": {"m_Bursts": [{"time": 0.0, "countCurve": {"m": 0, "c": 1.0}, "cycleCount": 1, "probability": 1.0}]}}}
	var fine := _system(data.duplicate(true))
	var coarse := _system(data.duplicate(true))
	for i in 31:
		fine.advance(i / 60.0)
	coarse.advance(0.0)
	coarse.advance(0.5)
	assert_almost_eq(coarse._particles[0].pos.z, fine._particles[0].pos.z, 0.001, "느린 프레임도 같은 자리")


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
