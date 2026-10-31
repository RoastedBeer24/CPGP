class_name FxSystem
extends MultiMeshInstance3D
## 원작 이펙트의 파티클 시스템 하나. 원작은 유니티 파티클 시스템으로 이펙트를 만들었다. 원작 이펙트가 쓰는 기능만
## CPU로 계산해 MultiMesh로 그린다(파티클 하나 = 인스턴스 하나, 셰이더는 vfx_base.gdshaderinc).
## 계산 방식은 사이트(studio.warfarin.wiki)가 그리는 방식을 따랐다(docs/dev/effects.md).
##
## 파티클 설정 JSON은 유니티(왼손 좌표) 그대로라서, 파티클은 유니티 좌표로 계산하고 그릴 때 X를 뒤집어(MIRROR)
## 이펙트 노드의 세계 변환을 곱한다. 이펙트 메시는 glTF로 옮기면서 이미 뒤집혀 있다.
## 세상 기준 시뮬레이션(moveWithTransform 1)은 태어날 때 세상 위치로 바꿔 두고 이펙트가 움직여도 따라가지 않는다.
##
## 빠르기: 궁극기처럼 파티클이 1,000개를 넘으면 파티클마다 매 프레임 하는 계산이 그대로 프레임 시간이 된다(포그라니치니크
## 궁극기에서 프레임당 30~65ms였다). 설정(사전)과 곡선은 시스템 설정마다 한 번 표로 만들어 두고(Compiled, FxCurve.compile),
## 파티클을 만들 때 난수 생성기를 새로 만들지 않으며, 그리기 정보는 버퍼 하나로 한 번에 넘긴다. 프레임이 늦어도 따라잡는
## 계산은 MAX_CATCH_UP번까지만 쪼갠다(쪼갤수록 더 늦어지는 악순환이 있었다).

## 방출을 나누는 간격(초). 움직임도 이 간격으로 쪼개 계산한다(속도 제한이 1/60초 기준이다).
const STEP := 1.0 / 60.0
## 한 프레임에 파티클 움직임을 쪼개 계산하는 최대 횟수. 프레임이 늦으면 한 번에 더 길게 움직인다.
const MAX_CATCH_UP := 2
const GRAVITY := 9.81
const MIRROR := Basis(Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1))
## 한 시스템이 한꺼번에 그리는 파티클 수의 상한 (원작 설정 maxNumParticles가 더 작으면 그것)
const MAX_INSTANCES := 256
## MultiMesh 버퍼에서 인스턴스 하나가 차지하는 칸: 변환 12(행 우선 3x4), 색 4, 사용자 값 4
const STRIDE := 20
## 파티클마다 미리 뽑아 두는 무작위 값의 수와 쓰임
enum R { LIFE, SPEED, SIZE_X, SIZE_Y, SIZE_Z, ROT_X, ROT_Y, ROT_Z, COLOR, GRAVITY, SIGN, ARC, RADIUS, SHAPE_X, SHAPE_Y, SHAPE_Z,
	DIR_X, DIR_Y, DIR_Z, POS_X, POS_Y, POS_Z, OL_SIZE_X, OL_SIZE_Y, OL_SIZE_Z, OL_ROT_X, OL_ROT_Y, OL_ROT_Z, OL_COLOR,
	CUSTOM_0, CUSTOM_1, CUSTOM_2, CUSTOM_3, VEL_X, VEL_Y, VEL_Z, ORBIT_X, ORBIT_Y, ORBIT_Z, RADIAL, SPEED_MOD, LIMIT,
	FORCE_X, FORCE_Y, FORCE_Z, FRAME, START_FRAME, COUNT }


## 파티클 하나. 위치·속도는 시뮬레이션 공간(지역이면 유니티 지역 좌표, 세상이면 Godot 세상 좌표)이다.
class Particle:
	var birth := 0.0
	var age := 0.0
	var life := 1.0
	var pos := Vector3.ZERO
	var vel := Vector3.ZERO
	var anim := Vector3.ZERO
	var origin := Vector3.ZERO
	var size := Vector3.ONE
	var rot := Vector3.ZERO
	var spin := 1.0
	var color := Color.WHITE
	var gravity := 0.0
	var rand := PackedFloat32Array()


## 시스템 설정(JSON)을 계산하기 좋게 펴 둔 것. 곡선은 FxCurve.compile의 표다. 같은 이펙트를 여러 번 틀어도 함께 쓴다.
class Compiled:
	# 처음 값
	var life: PackedFloat32Array
	var size_x: PackedFloat32Array
	var size_y: PackedFloat32Array
	var size_z: PackedFloat32Array
	var size_3d := false
	var rot_x: PackedFloat32Array
	var rot_y: PackedFloat32Array
	var rot_z: PackedFloat32Array
	var rotation_3d := false
	var random_spin := 0.0
	var color: PackedColorArray
	var gravity: PackedFloat32Array
	var speed: PackedFloat32Array
	# 방출
	var rate_time: PackedFloat32Array
	var rate_distance: PackedFloat32Array
	var bursts: Array = []
	# 모양 (-1이면 모양 모듈 없음: 원점에서 +Z로)
	var shape_type := -1
	var radius := 1.0
	var thickness := 1.0
	var arc := 360.0
	var arc_mode := 0
	var arc_speed: PackedFloat32Array
	var arc_spread := 0.0
	var angle := 25.0
	var length := 5.0
	var shape_scale := Vector3.ONE
	var shape_turn := Basis.IDENTITY
	var shape_position := Vector3.ZERO
	var spherical := 0.0
	var random_direction := 0.0
	var jitter := 0.0
	# 움직임
	var has_force := false
	var force_world := false
	var force_x: PackedFloat32Array
	var force_y: PackedFloat32Array
	var force_z: PackedFloat32Array
	var has_velocity := false
	var velocity_world := false
	var has_linear := false
	var vel_x: PackedFloat32Array
	var vel_y: PackedFloat32Array
	var vel_z: PackedFloat32Array
	var has_orbit := false
	var orbit_x: PackedFloat32Array
	var orbit_y: PackedFloat32Array
	var orbit_z: PackedFloat32Array
	var radial: PackedFloat32Array
	var orbit_offset_x: PackedFloat32Array
	var orbit_offset_y: PackedFloat32Array
	var orbit_offset_z: PackedFloat32Array
	var speed_mod: PackedFloat32Array
	var has_clamp := false
	var clamp_magnitude: PackedFloat32Array
	var clamp_dampen := 0.0
	# 그리기
	var has_size := false
	var size_separate := false
	var over_size_x: PackedFloat32Array
	var over_size_y: PackedFloat32Array
	var over_size_z: PackedFloat32Array
	var has_rotation := false
	var rotation_separate := false
	var over_rot_x: PackedFloat32Array
	var over_rot_y: PackedFloat32Array
	var over_rot_z: PackedFloat32Array
	var has_color := false
	var over_color: PackedColorArray
	## 사용자 값 1: 0 없음, 1 값 네 개, 2 색
	var custom_mode := 0
	var custom_curves: Array[PackedFloat32Array] = []
	var custom_color: PackedColorArray
	var tiles := Vector2i.ONE
	var sheet_start: PackedFloat32Array
	var sheet_frame: PackedFloat32Array
	var sheet_cycles := 1.0


var system: Dictionary
## 파티클이 생기는 노드 (이펙트 모델 안의 노드)
var emitter: Node3D

var _c: Compiled
var _draw := FxMaterial.Draw.AXES
var _mesh_particles := false
var _align := 0
var _world_space := false
var _scaling := 0
var _duration := 1.0
var _speed := 1.0
var _delay := 0.0
var _looping := false
var _max := 1
## 이펙트 양 설정(GameSettings.effect_quality): 상한과 방출량에 곱한다.
var _amount := 1.0
var _seed := 0
var _rng := RandomNumberGenerator.new()
var _emitted := 0.0
var _rate_acc := 0.0
var _distance_acc := 0.0
var _last_emitter := Vector3.ZERO
var _has_last_emitter := false
var _births := 0
var _particles: Array[Particle] = []
## 지금 파티클 중 가장 먼저 사라지는 시각. 상한이 찼을 때 이 시각 전에는 치울 것이 없으니 살펴보지 않고 버린다.
var _next_death := INF
var _buffer := PackedFloat32Array()
## 이번 프레임의 이펙트 노드 세계 변환에서 뽑은 값
var _origin := Vector3.ZERO
var _rotation := Basis.IDENTITY
var _scale := Vector3.ONE
var _sim_to_world := Transform3D.IDENTITY


## 그릴 수 있는 시스템인지 (재질 데이터가 있는 VFXBaseV2, 메시가 빠지지 않은 것). 그릴 수 없으면 만들지 않는다.
static func drawable(data: Dictionary, effect: EffectLibrary.Effect) -> bool:
	var renderer: Dictionary = data.get("renderer", {})
	var mode := int(renderer.get("mode", 0))
	if mode not in [0, 1, 4]:
		return false
	var materials: Array = renderer.get("materials", [])
	var shaders: Array = renderer.get("shaders", [])
	var screen := not shaders.is_empty() and FxMaterial.screen_effect(str(shaders[0]))
	if not screen:
		if materials.is_empty() or materials[0] == null:
			return false
		var index := int(materials[0])
		if index < 0 or index >= effect.materials.size() or not FxMaterial.supported(effect.materials[index]["extras"]):
			return false
	if mode == 4:
		var meshes: Array = renderer.get("meshes", [])
		if meshes.is_empty() or meshes[0] == null or int(meshes[0]) >= effect.meshes.size() or effect.meshes[int(meshes[0])] == null:
			return false
	return true


## 시스템 설정을 계산하기 좋게 편다(설정 사전에 한 번만 만들어 둔다). 이펙트를 읽을 때(EffectLibrary, 배경 스레드)
## 미리 만들어 두고, 테스트처럼 바로 setup하면 그때 만든다.
static func compile(data: Dictionary) -> Compiled:
	if data.has("_compiled"):
		return data["_compiled"]
	var main: Dictionary = data.get("main", {})
	var initial: Dictionary = data.get("initial", {})
	var modules: Dictionary = data.get("modules", {})
	var c := Compiled.new()
	c.life = FxCurve.compile(initial.get("startLifetime", null), 1.0)
	c.size_x = FxCurve.compile(initial.get("startSize", null), 1.0)
	c.size_y = FxCurve.compile(initial.get("startSizeY", null), 1.0)
	c.size_z = FxCurve.compile(initial.get("startSizeZ", null), 1.0)
	c.size_3d = bool(initial.get("size3D", false))
	c.rot_x = FxCurve.compile(initial.get("startRotationX", null), 0.0)
	c.rot_y = FxCurve.compile(initial.get("startRotationY", null), 0.0)
	c.rot_z = FxCurve.compile(initial.get("startRotation", null), 0.0)
	c.rotation_3d = bool(initial.get("rotation3D", false))
	c.random_spin = float(initial.get("randomizeRotationDirection", 0.0))
	c.color = FxCurve.compile_color(initial.get("startColor", null))
	c.gravity = FxCurve.compile(initial.get("gravityModifier", null), 0.0)
	c.speed = FxCurve.compile(initial.get("startSpeed", null), 0.0)
	var emission: Dictionary = modules.get("EmissionModule", {})
	c.rate_time = FxCurve.compile(emission.get("rateOverTime", null), 0.0)
	c.rate_distance = FxCurve.compile(emission.get("rateOverDistance", null), 0.0)
	c.bursts = emission.get("m_Bursts", []) if typeof(emission.get("m_Bursts", [])) == TYPE_ARRAY else []
	var shape: Dictionary = modules.get("ShapeModule", {})
	if not shape.is_empty():
		c.shape_type = int(shape.get("type", 4))
		c.radius = float((shape.get("radius", {}) as Dictionary).get("value", 1.0))
		c.thickness = clampf(float(shape.get("radiusThickness", 1.0)), 0.0, 1.0)
		var arc_info: Dictionary = shape.get("arc", {})
		c.arc = float(arc_info.get("value", 360.0))
		c.arc_mode = int(arc_info.get("mode", 0))
		c.arc_speed = FxCurve.compile(arc_info.get("speed", null), 1.0)
		c.arc_spread = float(arc_info.get("spread", 0.0))
		c.angle = float(shape.get("angle", 25.0))
		c.length = float(shape.get("length", 5.0))
		c.shape_scale = _vector3(shape.get("m_Scale", null), Vector3.ONE)
		c.shape_turn = _euler_unity(_vector3(shape.get("m_Rotation", null), Vector3.ZERO) * (PI / 180.0))
		c.shape_position = _vector3(shape.get("m_Position", null), Vector3.ZERO)
		c.spherical = float(shape.get("sphericalDirectionAmount", 0.0))
		c.random_direction = float(shape.get("randomDirectionAmount", 0.0))
		c.jitter = float(shape.get("randomPositionAmount", 0.0))
	var force: Dictionary = modules.get("ForceModule", {})
	if not force.is_empty():
		c.has_force = true
		c.force_world = bool(force.get("inWorldSpace", false))
		c.force_x = FxCurve.compile(force.get("x", null))
		c.force_y = FxCurve.compile(force.get("y", null))
		c.force_z = FxCurve.compile(force.get("z", null))
	var velocity: Dictionary = modules.get("VelocityModule", {})
	if not velocity.is_empty():
		c.has_velocity = true
		c.velocity_world = bool(velocity.get("inWorldSpace", false))
		c.vel_x = FxCurve.compile(velocity.get("x", null))
		c.vel_y = FxCurve.compile(velocity.get("y", null))
		c.vel_z = FxCurve.compile(velocity.get("z", null))
		c.has_linear = not (_zero(c.vel_x) and _zero(c.vel_y) and _zero(c.vel_z))
		c.orbit_x = FxCurve.compile(velocity.get("orbitalX", null))
		c.orbit_y = FxCurve.compile(velocity.get("orbitalY", null))
		c.orbit_z = FxCurve.compile(velocity.get("orbitalZ", null))
		c.radial = FxCurve.compile(velocity.get("radial", null))
		c.has_orbit = not (_zero(c.orbit_x) and _zero(c.orbit_y) and _zero(c.orbit_z) and _zero(c.radial))
		c.orbit_offset_x = FxCurve.compile(velocity.get("orbitalOffsetX", null))
		c.orbit_offset_y = FxCurve.compile(velocity.get("orbitalOffsetY", null))
		c.orbit_offset_z = FxCurve.compile(velocity.get("orbitalOffsetZ", null))
		c.speed_mod = FxCurve.compile(velocity.get("speedModifier", null), 1.0)
	var limit: Dictionary = modules.get("ClampVelocityModule", {})
	if not limit.is_empty():
		c.has_clamp = true
		c.clamp_magnitude = FxCurve.compile(limit.get("magnitude", null), INF)
		c.clamp_dampen = clampf(float(limit.get("dampen", 0.0)), 0.0, 1.0)
	var size_module: Dictionary = modules.get("SizeModule", {})
	if not size_module.is_empty():
		c.has_size = true
		c.size_separate = bool(size_module.get("separateAxes", false))
		c.over_size_x = FxCurve.compile(size_module.get("curve", null), 1.0)
		c.over_size_y = FxCurve.compile(size_module.get("y", null), 1.0)
		c.over_size_z = FxCurve.compile(size_module.get("z", null), 1.0)
	var rotation_module: Dictionary = modules.get("RotationModule", {})
	if not rotation_module.is_empty():
		c.has_rotation = true
		c.rotation_separate = bool(rotation_module.get("separateAxes", false))
		c.over_rot_x = FxCurve.compile_integral(rotation_module.get("x", null))
		c.over_rot_y = FxCurve.compile_integral(rotation_module.get("y", null))
		c.over_rot_z = FxCurve.compile_integral(rotation_module.get("curve", null))
	var color_module: Dictionary = modules.get("ColorModule", {})
	if not color_module.is_empty():
		c.has_color = true
		c.over_color = FxCurve.compile_color(color_module.get("gradient", null))
	var custom: Dictionary = modules.get("CustomDataModule", {})
	if not custom.is_empty():
		c.custom_mode = int(custom.get("mode0", 0))
		if c.custom_mode == 1:
			for k in mini(int(custom.get("vectorComponentCount0", 4)), 4):
				c.custom_curves.append(FxCurve.compile(custom.get("vector0_%d" % k, null), 0.0))
		elif c.custom_mode == 2:
			c.custom_color = FxCurve.compile_color(custom.get("color0", null))
	var sheet: Dictionary = modules.get("UVModule", {})
	if int(sheet.get("mode", 0)) == 0:
		c.tiles = Vector2i(maxi(int(sheet.get("tilesX", 1)), 1), maxi(int(sheet.get("tilesY", 1)), 1))
	c.sheet_start = FxCurve.compile(sheet.get("startFrame", null), 0.0)
	c.sheet_frame = FxCurve.compile(sheet.get("frameOverTime", null), 0.0)
	c.sheet_cycles = float(sheet.get("cycles", 1.0))
	data["_compiled"] = c
	return c


static func _zero(curve: PackedFloat32Array) -> bool:
	return curve[0] == 0.0 and curve[2] == 0.0 and curve[3] == 0.0


## 시스템을 준비한다. material은 FxEffect가 이펙트마다 한 번 만들어 둔 것을 함께 쓴다.
func setup(data: Dictionary, effect: EffectLibrary.Effect, node: Node3D, material: ShaderMaterial) -> void:
	system = data
	emitter = node
	_c = compile(data)
	var main: Dictionary = data.get("main", {})
	var initial: Dictionary = data.get("initial", {})
	var renderer: Dictionary = data.get("renderer", {})
	var mode := int(renderer.get("mode", 0))
	_align = int(renderer.get("align", 0))
	_mesh_particles = mode == 4
	_draw = draw_mode(mode, _align)
	_world_space = int(main.get("moveWithTransform", 0)) == 1
	_scaling = int(main.get("scalingMode", 0))
	_duration = maxf(float(main.get("lengthInSec", 1.0)), 0.0001)
	_speed = float(main.get("simulationSpeed", 1.0))
	_looping = bool(main.get("looping", false))
	_seed = int(main.get("randomSeed", 0)) & 0xffffffff
	_delay = FxCurve.value(main.get("startDelay", null), 0.0, _hash_unit(_seed, 0x5eed), 0.0)
	_amount = GameSettings.EFFECT_AMOUNTS[GameSettings.effect_quality]
	_max = maxi(roundi(clampi(int(initial.get("maxNumParticles", 1000)), 1, MAX_INSTANCES) * _amount), 1)
	top_level = true
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	material_override = material
	var instances := MultiMesh.new()
	instances.transform_format = MultiMesh.TRANSFORM_3D
	instances.use_colors = true
	instances.use_custom_data = true
	if _mesh_particles:
		instances.mesh = effect.meshes[int((renderer.get("meshes", [0]) as Array)[0])]
	else:
		var quad := QuadMesh.new()
		quad.size = Vector2.ONE
		instances.mesh = quad
	instances.instance_count = _max
	instances.visible_instance_count = 0
	multimesh = instances
	_buffer.resize(_max * STRIDE)


func _enter_tree() -> void:
	global_transform = Transform3D.IDENTITY


## 렌더러 설정 → 그리기 방식: 늘어나는 판, 메시나 세상·지역 축에 맞춘 판(축), 나머지는 화면 정면 판
static func draw_mode(mode: int, align: int) -> FxMaterial.Draw:
	if mode == 1:
		return FxMaterial.Draw.STRETCH
	if mode == 4 or align == 1 or align == 2:
		return FxMaterial.Draw.AXES
	return FxMaterial.Draw.VIEW


## 살아 있는 파티클 수
func alive() -> int:
	return _particles.size()


## 이펙트가 시작된 뒤 time초가 됐다: 그때까지 파티클을 내보내고 움직이고 그린다.
func advance(time: float) -> void:
	_read_emitter()
	var emit_time := time * _speed - _delay
	if emit_time < 0.0:
		multimesh.visible_instance_count = 0
		return
	_emit_until(emit_time)
	_update_particles(emit_time)
	_draw_particles()


# ---- 방출 ----
func _emit_until(emit_time: float) -> void:
	var limit := emit_time if _looping else minf(emit_time, _duration)
	# 막 시작한 순간(0초)에 나오는 것도 내보낸다.
	limit = maxf(limit, 0.000002)
	while _emitted < limit - 0.000001:
		var t0 := _emitted
		var t1 := minf(t0 + STEP, limit)
		var births: Array[Array] = []
		var normalized := _system_time(t0)
		var rate := FxCurve.sample(_c.rate_time, normalized, 0.5) * _amount
		if rate > 0.0:
			var before := _rate_acc
			_rate_acc += rate * (t1 - t0)
			var k := floorf(before) + 1.0
			while k <= _rate_acc:
				births.append([t0 + (k - before) / rate, 0, 1])
				k += 1.0
		var per_meter := FxCurve.sample(_c.rate_distance, normalized, 0.5) * _amount
		if per_meter > 0.0 and _has_last_emitter:
			var moved := _origin.distance_to(_last_emitter)
			if moved < 100.0:
				var before_distance := _distance_acc
				_distance_acc += per_meter * moved
				var count := int(floorf(_distance_acc) - floorf(before_distance))
				for i in count:
					births.append([t0 + (t1 - t0) * (i + 1) / (count + 1), 0, 1])
		if not _c.bursts.is_empty():
			_add_bursts(_c.bursts, t0, t1, births)
		if births.size() > 1:
			births.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
		for birth in births:
			_spawn(float(birth[0]), int(birth[1]), int(birth[2]))
		_emitted = t1
	_last_emitter = _origin
	_has_last_emitter = true


func _add_bursts(bursts: Array, t0: float, t1: float, births: Array[Array]) -> void:
	var first_loop := int(floorf(t0 / _duration)) if _looping else 0
	var last_loop := int(floorf(t1 / _duration)) if _looping else 0
	for b in bursts.size():
		var burst: Dictionary = bursts[b]
		var interval := maxf(float(burst.get("repeatInterval", 0.01)), 0.0001)
		var cycles := int(burst.get("cycleCount", 1))
		if cycles <= 0:
			cycles = int(ceilf(_duration / interval))
		for v in cycles:
			var at := float(burst.get("time", 0.0)) + v * interval
			if at > _duration:
				break
			for loop in range(first_loop, last_loop + 1):
				var when := loop * _duration + at
				if when < t0 or when >= t1:
					continue
				var chance := _hash_unit(_seed, 0xb000 + b * 977 + v * 31 + loop * 7919)
				if chance >= float(burst.get("probability", 1.0)):
					continue
				var count := roundi(FxCurve.value(burst.get("countCurve", null), at / _duration, chance, 0.0))
				# 이펙트 양을 줄여도 하나뿐인 파티클(충격파 고리 등)은 남긴다.
				if count > 0 and _amount < 1.0:
					count = maxi(roundi(count * _amount), 1)
				for slot in count:
					births.append([when, slot, count])


## 파티클 하나를 낳는다 (time은 방출 시각, slot/count는 한꺼번에 나온 파티클 중 몇 번째인지).
func _spawn(time: float, slot: int, count: int) -> void:
	if _particles.size() >= _max:
		# 상한이 찼으면 이 시각까지 수명이 다한 파티클을 치운다. 사라질 것이 없는 동안은 다시 살피지 않는다.
		if time < _next_death:
			return
		_drop_dead(time)
		if _particles.size() >= _max:
			return
	var p := Particle.new()
	p.rand = _randoms(_births)
	_births += 1
	var r := p.rand
	var normalized := _system_time(time)
	p.life = FxCurve.sample(_c.life, normalized, r[R.LIFE])
	if p.life <= 0.0:
		return
	p.birth = time
	var size_x := FxCurve.sample(_c.size_x, normalized, r[R.SIZE_X])
	if _c.size_3d:
		p.size = Vector3(size_x, FxCurve.sample(_c.size_y, normalized, r[R.SIZE_Y]), FxCurve.sample(_c.size_z, normalized, r[R.SIZE_Z]))
	else:
		p.size = Vector3(size_x, size_x, size_x)
	p.spin = -1.0 if r[R.SIGN] < _c.random_spin else 1.0
	var rotation_z := FxCurve.sample(_c.rot_z, normalized, r[R.ROT_Z])
	if _c.rotation_3d:
		p.rot = Vector3(FxCurve.sample(_c.rot_x, normalized, r[R.ROT_X]), FxCurve.sample(_c.rot_y, normalized, r[R.ROT_Y]), rotation_z) * p.spin
	else:
		p.rot = Vector3(0.0, 0.0, rotation_z * p.spin)
	p.color = FxCurve.sample_color(_c.color, normalized, r[R.COLOR])
	p.gravity = FxCurve.sample(_c.gravity, normalized, r[R.GRAVITY])
	var position := Vector3.ZERO
	var direction := Vector3(0, 0, 1)
	if _c.shape_type >= 0:
		var shaped := _shape(p, time, normalized, slot, count)
		position = shaped[0]
		direction = shaped[1]
	var velocity := direction * FxCurve.sample(_c.speed, normalized, r[R.SPEED])
	if _world_space:
		# 세상 기준: 태어난 순간의 노드 위치·방향으로 세상 좌표로 바꿔 둔다(속도는 크기를 곱하지 않는다).
		p.pos = _origin + _rotation * (MIRROR * (position * _scale))
		p.vel = _rotation * (MIRROR * velocity)
		p.origin = p.pos
	else:
		p.pos = position
		p.vel = velocity
		p.origin = Vector3.ZERO
	_particles.append(p)
	_next_death = minf(_next_death, p.birth + p.life)


## time까지 수명이 다한 파티클을 치우고, 남은 것 중 가장 먼저 사라지는 시각을 기억한다.
func _drop_dead(time: float) -> void:
	var living: Array[Particle] = []
	var next := INF
	for other in _particles:
		var death := other.birth + other.life
		if death > time:
			living.append(other)
			next = minf(next, death)
	_particles = living
	_next_death = next


## 모양 모듈: 태어날 자리와 나아갈 방향(유니티 지역 좌표)
func _shape(p: Particle, time: float, normalized: float, slot: int, count: int) -> Array:
	var r := p.rand
	var radius := _c.radius
	var inner := 1.0 - _c.thickness
	var area_radius := radius * sqrt(inner * inner + r[R.RADIUS] * (1.0 - inner * inner))
	var fraction := _arc_fraction(r[R.ARC], time, normalized, slot, count)
	var phi := fraction * deg_to_rad(_c.arc)
	var position := Vector3.ZERO
	var direction := Vector3(0, 0, 1)
	match _c.shape_type:
		0, 2:
			direction = _random_direction(r[R.SHAPE_X], r[R.SHAPE_Y])
			if _c.arc < 360.0:
				var flat := Vector2(direction.x, direction.y).length()
				direction = Vector3(cos(phi) * flat, sin(phi) * flat, direction.z)
			if _c.shape_type == 2:
				direction.z = absf(direction.z)
			var volume_radius := radius * pow(inner * inner * inner + r[R.RADIUS] * (1.0 - inner * inner * inner), 1.0 / 3.0)
			position = direction * volume_radius
		4, 8:
			var angle := deg_to_rad(_c.angle)
			var disc := Vector2(cos(phi), sin(phi)) * (area_radius / maxf(radius, 0.000001))
			direction = Vector3(disc.x * sin(angle), disc.y * sin(angle), cos(angle)).normalized()
			position = Vector3(disc.x * radius, disc.y * radius, 0.0)
			if _c.shape_type == 8:
				position += direction * _c.length * r[R.SHAPE_Z]
		5:
			position = Vector3(r[R.SHAPE_X] - 0.5, r[R.SHAPE_Y] - 0.5, r[R.SHAPE_Z] - 0.5)
		10:
			position = Vector3(cos(phi), sin(phi), 0.0) * area_radius
			direction = Vector3(cos(phi), sin(phi), 0.0)
		12:
			var along := (2.0 * fraction - 1.0) if _c.arc_mode == 3 else (2.0 * r[R.SHAPE_X] - 1.0)
			position = Vector3(along * radius, 0.0, 0.0)
			direction = Vector3(0, 1, 0)
		18:
			position = Vector3(r[R.SHAPE_X] - 0.5, r[R.SHAPE_Y] - 0.5, 0.0)
	position *= _c.shape_scale
	position = _c.shape_turn * position
	direction = _c.shape_turn * direction
	position += _c.shape_position
	if _c.spherical > 0.0 and position.length_squared() > 0.0:
		direction = direction.lerp(position.normalized(), _c.spherical).normalized()
	if _c.random_direction > 0.0:
		direction = direction.lerp(_random_direction(r[R.DIR_X], r[R.DIR_Y]), _c.random_direction).normalized()
	if _c.jitter > 0.0:
		position += Vector3(r[R.POS_X] * 2.0 - 1.0, r[R.POS_Y] * 2.0 - 1.0, r[R.POS_Z] * 2.0 - 1.0) * _c.jitter
	return [position, direction]


## 호(arc) 위 어디서 나올지 (0~1): 0 무작위, 1 돌아가며, 2 왕복, 3 한꺼번에 나온 것끼리 고르게
func _arc_fraction(rand: float, time: float, normalized: float, slot: int, count: int) -> float:
	var fraction := rand
	match _c.arc_mode:
		1:
			fraction = fposmod(time * FxCurve.sample(_c.arc_speed, normalized, 0.5), 1.0)
		2:
			fraction = pingpong(time * FxCurve.sample(_c.arc_speed, normalized, 0.5), 1.0)
		3:
			fraction = float(slot) / maxf(count, 1)
	if _c.arc_spread > 0.0:
		fraction = floorf(fraction / _c.arc_spread) * _c.arc_spread
	return fraction


# ---- 움직임 ----
## 파티클을 지금 시각까지 움직인다. 1/60초씩 쪼개되, 프레임이 늦어 따라잡을 것이 많으면 MAX_CATCH_UP번으로 나눈다.
func _update_particles(emit_time: float) -> void:
	var kept := 0
	for index in _particles.size():
		var p := _particles[index]
		var target := emit_time - p.birth
		if target >= p.life:
			continue
		var remaining := target - p.age
		if remaining > 0.000001:
			var steps := mini(ceili(remaining / STEP - 0.000001), MAX_CATCH_UP)
			var dt := remaining / steps
			for s in steps:
				p.age += dt
				_step(p, dt, clampf(p.age / p.life, 0.0, 1.0))
		_particles[kept] = p
		kept += 1
	_particles.resize(kept)


func _step(p: Particle, dt: float, n: float) -> void:
	var r := p.rand
	if p.gravity != 0.0 or _c.has_force:
		var acceleration := Vector3.ZERO
		if p.gravity != 0.0:
			acceleration += _to_sim_from_world(Vector3(0.0, -GRAVITY * p.gravity, 0.0))
		if _c.has_force:
			var push := Vector3(FxCurve.sample(_c.force_x, n, r[R.FORCE_X]), FxCurve.sample(_c.force_y, n, r[R.FORCE_Y]),
					FxCurve.sample(_c.force_z, n, r[R.FORCE_Z]))
			acceleration += _module_vector(push, _c.force_world)
		p.vel += acceleration * dt
	var anim := Vector3.ZERO
	var speed_scale := 1.0
	if _c.has_velocity:
		if _c.has_linear:
			var linear := Vector3(FxCurve.sample(_c.vel_x, n, r[R.VEL_X]), FxCurve.sample(_c.vel_y, n, r[R.VEL_Y]),
					FxCurve.sample(_c.vel_z, n, r[R.VEL_Z]))
			anim += _module_vector(linear, _c.velocity_world)
		if _c.has_orbit:
			var orbit := Vector3(FxCurve.sample(_c.orbit_x, n, r[R.ORBIT_X]), FxCurve.sample(_c.orbit_y, n, r[R.ORBIT_Y]),
					FxCurve.sample(_c.orbit_z, n, r[R.ORBIT_Z]))
			var radial := FxCurve.sample(_c.radial, n, r[R.RADIAL])
			if orbit != Vector3.ZERO or radial != 0.0:
				var center := p.origin
				if not _world_space:
					center = Vector3(FxCurve.sample(_c.orbit_offset_x, n, 0.5), FxCurve.sample(_c.orbit_offset_y, n, 0.5),
							FxCurve.sample(_c.orbit_offset_z, n, 0.5))
				var relative := p.pos - center
				if _world_space:
					orbit = _rotation * (MIRROR * orbit)
				anim += orbit.cross(relative)
				if relative.length_squared() > 0.0:
					anim += relative.normalized() * radial
		speed_scale = FxCurve.sample(_c.speed_mod, n, r[R.SPEED_MOD])
	if _c.has_clamp:
		var total := p.vel + anim
		var cap := FxCurve.sample(_c.clamp_magnitude, n, r[R.LIMIT])
		var length := total.length()
		if length > cap and length > 0.0:
			# 넘친 속도의 dampen만큼을 1/60초마다 줄인다.
			var dampen := 1.0 - pow(1.0 - _c.clamp_dampen, dt / STEP)
			total *= (length + (cap - length) * dampen) / length
			p.vel = total - anim
	p.anim = anim
	p.pos += (p.vel + anim) * dt * speed_scale


## 모듈의 벡터(힘·속도)를 시뮬레이션 공간으로. inWorldSpace면 유니티 세상 좌표다.
func _module_vector(value: Vector3, in_world: bool) -> Vector3:
	if in_world:
		return _to_sim_from_world(MIRROR * value)
	if _world_space:
		return _rotation * (MIRROR * value)
	return value


## Godot 세상 방향 → 시뮬레이션 공간 방향
func _to_sim_from_world(value: Vector3) -> Vector3:
	if _world_space:
		return value
	return MIRROR * (_rotation.inverse() * value)


# ---- 그리기 ----
func _read_emitter() -> void:
	if emitter == null or not is_instance_valid(emitter) or not emitter.is_inside_tree():
		return
	var world := emitter.global_transform
	_origin = world.origin
	_rotation = world.basis.orthonormalized()
	var world_scale := world.basis.get_scale()
	_scale = world_scale if _scaling == 0 else (emitter.scale if _scaling == 1 else Vector3.ONE)
	_sim_to_world = Transform3D(_rotation * Basis.from_scale(_scale) * MIRROR, _origin)


## 파티클마다 그리기 정보(변환·색·사용자 값)를 버퍼에 적어 한 번에 넘긴다.
func _draw_particles() -> void:
	var count := mini(_particles.size(), _max)
	multimesh.visible_instance_count = count
	if count == 0:
		return
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	var view := camera.global_basis.orthonormalized() if camera != null else Basis.IDENTITY
	var sheet := _c.tiles.x * _c.tiles.y > 1
	var buffer := _buffer
	var low := Vector3.INF
	var high := -Vector3.INF
	for i in count:
		var p := _particles[i]
		var r := p.rand
		var n := clampf(p.age / p.life, 0.0, 1.0)
		var size := p.size
		if _c.has_size:
			if _c.size_separate:
				size *= Vector3(FxCurve.sample(_c.over_size_x, n, r[R.OL_SIZE_X]), FxCurve.sample(_c.over_size_y, n, r[R.OL_SIZE_Y]),
						FxCurve.sample(_c.over_size_z, n, r[R.OL_SIZE_Z]))
			else:
				size *= FxCurve.sample(_c.over_size_x, n, r[R.OL_SIZE_X])
		var rot := p.rot
		if _c.has_rotation:
			rot.z += p.spin * p.life * FxCurve.sample_integral(_c.over_rot_z, n, r[R.OL_ROT_Z])
			if _c.rotation_separate:
				rot.x += p.spin * p.life * FxCurve.sample_integral(_c.over_rot_x, n, r[R.OL_ROT_X])
				rot.y += p.spin * p.life * FxCurve.sample_integral(_c.over_rot_y, n, r[R.OL_ROT_Y])
		var color := p.color
		if _c.has_color:
			color *= FxCurve.sample_color(_c.over_color, n, r[R.OL_COLOR])
		color = color.clamp()
		var custom := _custom(n, p)
		if sheet:
			custom.a = _sheet_frame(n, p)
		var centre := p.pos if _world_space else _sim_to_world * p.pos
		low = low.min(centre)
		high = high.max(centre)
		var t := _instance(p, centre, size, rot, view)
		var o := i * STRIDE
		buffer[o] = t.basis.x.x
		buffer[o + 1] = t.basis.y.x
		buffer[o + 2] = t.basis.z.x
		buffer[o + 3] = t.origin.x
		buffer[o + 4] = t.basis.x.y
		buffer[o + 5] = t.basis.y.y
		buffer[o + 6] = t.basis.z.y
		buffer[o + 7] = t.origin.y
		buffer[o + 8] = t.basis.x.z
		buffer[o + 9] = t.basis.y.z
		buffer[o + 10] = t.basis.z.z
		buffer[o + 11] = t.origin.z
		buffer[o + 12] = color.r
		buffer[o + 13] = color.g
		buffer[o + 14] = color.b
		buffer[o + 15] = color.a
		buffer[o + 16] = custom.r
		buffer[o + 17] = custom.g
		buffer[o + 18] = custom.b
		buffer[o + 19] = custom.a
	multimesh.buffer = buffer
	# 인스턴스 변환 자리에 그리기 정보를 넣었으므로 화면 밖 판정용 상자를 직접 준다.
	multimesh.custom_aabb = AABB(low, high - low).grow(8.0)


## 그리기 방식에 맞춘 인스턴스 정보 (vfx_base.gdshaderinc의 정점 단계가 읽는다)
func _instance(p: Particle, centre: Vector3, size: Vector3, rot: Vector3, view: Basis) -> Transform3D:
	if _draw == FxMaterial.Draw.VIEW:
		return Transform3D(Basis(Vector3(size.x * _scale.x, size.y * _scale.y, rot.z), Vector3.ZERO, Vector3.ZERO), centre)
	if _draw == FxMaterial.Draw.STRETCH:
		var velocity := p.vel + p.anim
		if not _world_space:
			velocity = _sim_to_world.basis * velocity
		var width := size.x * maxf(_scale.x, _scale.y)
		return Transform3D(Basis(Vector3(width, size.x, 0.0), velocity, Vector3.ZERO), centre)
	var turn: Basis
	if _mesh_particles:
		turn = Basis(Vector3.UP, rot.y) * Basis(Vector3.RIGHT, rot.x) * Basis(Vector3(0, 0, 1), rot.z)
	else:
		turn = Basis(Vector3.UP, rot.y) * Basis(Vector3.RIGHT, rot.x) * Basis(Vector3(0, 0, 1), -rot.z)
	var frame: Basis
	var scaled := size
	if _align == 2 and not _world_space:
		frame = _sim_to_world.basis
	else:
		scaled = size * _scale
		if _align == 0 and _mesh_particles:
			frame = Basis(-view.x, view.y, -view.z)
		elif _align == 1:
			frame = MIRROR
		else:
			frame = _rotation * MIRROR
	var axes := frame * turn * Basis.from_scale(Vector3(-scaled.x if _mesh_particles else scaled.x, scaled.y, scaled.z))
	return Transform3D(axes, centre)


## 사용자 값 1 (셰이더의 x 메인 텍스처 밀기, y 슬롯 밀기, z 녹이기)
func _custom(n: float, p: Particle) -> Color:
	match _c.custom_mode:
		1:
			var values: Array[float] = [0.0, 0.0, 0.0, 0.0]
			for k in _c.custom_curves.size():
				values[k] = FxCurve.sample(_c.custom_curves[k], n, p.rand[R.CUSTOM_0 + k])
			return Color(values[0], values[1], values[2], values[3])
		2:
			return FxCurve.sample_color(_c.custom_color, n, p.rand[R.CUSTOM_0])
	return Color(0, 0, 0, 0)


## 텍스처 시트(격자)에서 지금 쓸 칸 번호
func _sheet_frame(n: float, p: Particle) -> float:
	var frames := _c.tiles.x * _c.tiles.y
	var first := FxCurve.sample(_c.sheet_start, 0.0, p.rand[R.START_FRAME]) / frames
	var phase := _c.sheet_cycles * FxCurve.sample(_c.sheet_frame, n, p.rand[R.FRAME]) + first
	phase = fposmod(phase, 1.0)
	return float(mini(int(floorf(phase * frames)), frames - 1))


# ---- 도움 ----
## 재생 시간 → 시스템 한 바퀴 안의 비율(0~1)
func _system_time(time: float) -> float:
	var t := fposmod(time, _duration) if _looping else time
	return clampf(t / _duration, 0.0, 0.9999)


## 파티클마다 쓰는 무작위 값들. 시스템 씨앗과 태어난 순서로 정해지므로 모든 피어에서 같다. 난수 생성기는 시스템마다
## 하나를 씨앗만 바꿔 다시 쓴다(파티클마다 새로 만들면 한꺼번에 수백 개가 나올 때 느렸다).
func _randoms(index: int) -> PackedFloat32Array:
	_rng.seed = _hash(_seed, index)
	var values := PackedFloat32Array()
	values.resize(R.COUNT)
	for k in R.COUNT:
		values[k] = _rng.randf()
	return values


static func _hash(seed: int, index: int) -> int:
	var h := (seed ^ ((index + 1) * 2654435761)) & 0xffffffff
	h ^= h >> 16
	h = (h * 0x85ebca6b) & 0xffffffff
	h ^= h >> 13
	h = (h * 0xc2b2ae35) & 0xffffffff
	h ^= h >> 16
	return h


static func _hash_unit(seed: int, salt: int) -> float:
	return float(_hash(seed, salt) & 0xffffff) / float(0xffffff)


static func _random_direction(u: float, v: float) -> Vector3:
	var z := u * 2.0 - 1.0
	var a := v * TAU
	var r := sqrt(maxf(1.0 - z * z, 0.0))
	return Vector3(r * cos(a), r * sin(a), z)


## 유니티 오일러 각(라디안, Z → X → Y 순서로 돈다)
static func _euler_unity(angles: Vector3) -> Basis:
	return Basis(Vector3.UP, angles.y) * Basis(Vector3.RIGHT, angles.x) * Basis(Vector3(0, 0, 1), angles.z)


static func _vector3(values: Variant, fallback: Vector3) -> Vector3:
	if typeof(values) != TYPE_ARRAY or (values as Array).size() < 3:
		return fallback
	var list: Array = values
	return Vector3(float(list[0]), float(list[1]), float(list[2]))
