class_name FxSystem
extends MultiMeshInstance3D
## 원작 이펙트의 파티클 시스템 하나. 원작은 유니티 파티클 시스템으로 이펙트를 만들었다. 원작 이펙트가 쓰는 기능만
## CPU로 계산해 MultiMesh로 그린다(파티클 하나 = 인스턴스 하나, 셰이더는 vfx_base.gdshaderinc).
## 계산 방식은 사이트(studio.warfarin.wiki)가 그리는 방식을 따랐다(docs/dev/effects.md).
##
## 파티클 설정 JSON은 유니티(왼손 좌표) 그대로라서, 파티클은 유니티 좌표로 계산하고 그릴 때 X를 뒤집어(MIRROR)
## 이펙트 노드의 세계 변환을 곱한다. 이펙트 메시는 glTF로 옮기면서 이미 뒤집혀 있다.
## 세상 기준 시뮬레이션(moveWithTransform 1)은 태어날 때 세상 위치로 바꿔 두고 이펙트가 움직여도 따라가지 않는다.

## 방출을 나누는 간격(초). 움직임도 이 간격 이하로 쪼개 계산한다(속도 제한이 1/60초 기준이다).
const STEP := 1.0 / 60.0
const GRAVITY := 9.81
const MIRROR := Basis(Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1))
## 한 시스템이 한꺼번에 그리는 파티클 수의 상한 (원작 설정 maxNumParticles가 더 작으면 그것)
const MAX_INSTANCES := 256
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


var system: Dictionary
## 파티클이 생기는 노드 (이펙트 모델 안의 노드)
var emitter: Node3D

var _main: Dictionary
var _initial: Dictionary
var _modules: Dictionary
var _renderer: Dictionary
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
var _seed := 0
var _emitted := 0.0
var _rate_acc := 0.0
var _distance_acc := 0.0
var _last_emitter := Vector3.ZERO
var _has_last_emitter := false
var _births := 0
var _particles: Array[Particle] = []
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


## 시스템을 준비한다. material은 FxEffect가 이펙트마다 한 번 만들어 둔 것을 함께 쓴다.
func setup(data: Dictionary, effect: EffectLibrary.Effect, node: Node3D, material: ShaderMaterial) -> void:
	system = data
	emitter = node
	_main = data.get("main", {})
	_initial = data.get("initial", {})
	_modules = data.get("modules", {})
	_renderer = data.get("renderer", {})
	var mode := int(_renderer.get("mode", 0))
	_align = int(_renderer.get("align", 0))
	_mesh_particles = mode == 4
	_draw = draw_mode(mode, _align)
	_world_space = int(_main.get("moveWithTransform", 0)) == 1
	_scaling = int(_main.get("scalingMode", 0))
	_duration = maxf(float(_main.get("lengthInSec", 1.0)), 0.0001)
	_speed = float(_main.get("simulationSpeed", 1.0))
	_looping = bool(_main.get("looping", false))
	_seed = int(_main.get("randomSeed", 0)) & 0xffffffff
	_delay = FxCurve.value(_main.get("startDelay", null), 0.0, _hash_unit(_seed, 0x5eed), 0.0)
	_max = clampi(int(_initial.get("maxNumParticles", 1000)), 1, MAX_INSTANCES)
	top_level = true
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	material_override = material
	var instances := MultiMesh.new()
	instances.transform_format = MultiMesh.TRANSFORM_3D
	instances.use_colors = true
	instances.use_custom_data = true
	if _mesh_particles:
		instances.mesh = effect.meshes[int((_renderer.get("meshes", [0]) as Array)[0])]
	else:
		var quad := QuadMesh.new()
		quad.size = Vector2.ONE
		instances.mesh = quad
	instances.instance_count = _max
	instances.visible_instance_count = 0
	multimesh = instances


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
	var emission: Dictionary = _modules.get("EmissionModule", {})
	while _emitted < limit - 0.000001:
		var t0 := _emitted
		var t1 := minf(t0 + STEP, limit)
		var births: Array[Array] = []
		var normalized := _system_time(t0)
		var rate := FxCurve.value(emission.get("rateOverTime", null), normalized, 0.5)
		if rate > 0.0:
			var before := _rate_acc
			_rate_acc += rate * (t1 - t0)
			var k := floorf(before) + 1.0
			while k <= _rate_acc:
				births.append([t0 + (k - before) / rate, 0, 1])
				k += 1.0
		var per_meter := FxCurve.value(emission.get("rateOverDistance", null), normalized, 0.5)
		if per_meter > 0.0 and _has_last_emitter:
			var moved := _origin.distance_to(_last_emitter)
			if moved < 100.0:
				var before_distance := _distance_acc
				_distance_acc += per_meter * moved
				var count := int(floorf(_distance_acc) - floorf(before_distance))
				for i in count:
					births.append([t0 + (t1 - t0) * (i + 1) / (count + 1), 0, 1])
		_add_bursts(emission.get("m_Bursts", []), t0, t1, births)
		births.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
		for birth in births:
			_spawn(float(birth[0]), int(birth[1]), int(birth[2]))
		_emitted = t1
	_last_emitter = _origin
	_has_last_emitter = true


func _add_bursts(bursts: Variant, t0: float, t1: float, births: Array[Array]) -> void:
	if typeof(bursts) != TYPE_ARRAY:
		return
	var first_loop := int(floorf(t0 / _duration)) if _looping else 0
	var last_loop := int(floorf(t1 / _duration)) if _looping else 0
	var list: Array = bursts
	for b in list.size():
		var burst: Dictionary = list[b]
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
				for slot in count:
					births.append([when, slot, count])


## 파티클 하나를 낳는다 (time은 방출 시각, slot/count는 한꺼번에 나온 파티클 중 몇 번째인지).
func _spawn(time: float, slot: int, count: int) -> void:
	# 이 시각까지 수명이 다한 파티클은 먼저 치워야 상한을 바르게 센다.
	if _particles.size() >= _max:
		var living: Array[Particle] = []
		for other in _particles:
			if other.birth + other.life > time:
				living.append(other)
		_particles = living
	if _particles.size() >= _max:
		return
	var p := Particle.new()
	p.rand = _randoms(_births)
	_births += 1
	var normalized := _system_time(time)
	p.life = FxCurve.value(_initial.get("startLifetime", null), normalized, p.rand[R.LIFE], 1.0)
	if p.life <= 0.0:
		return
	p.birth = time
	var size_x := FxCurve.value(_initial.get("startSize", null), normalized, p.rand[R.SIZE_X], 1.0)
	if bool(_initial.get("size3D", false)):
		p.size = Vector3(size_x, FxCurve.value(_initial.get("startSizeY", null), normalized, p.rand[R.SIZE_Y], 1.0),
				FxCurve.value(_initial.get("startSizeZ", null), normalized, p.rand[R.SIZE_Z], 1.0))
	else:
		p.size = Vector3.ONE * size_x
	p.spin = -1.0 if p.rand[R.SIGN] < float(_initial.get("randomizeRotationDirection", 0.0)) else 1.0
	var rotation_z := FxCurve.value(_initial.get("startRotation", null), normalized, p.rand[R.ROT_Z], 0.0)
	if bool(_initial.get("rotation3D", false)):
		p.rot = Vector3(FxCurve.value(_initial.get("startRotationX", null), normalized, p.rand[R.ROT_X], 0.0),
				FxCurve.value(_initial.get("startRotationY", null), normalized, p.rand[R.ROT_Y], 0.0), rotation_z) * p.spin
	else:
		p.rot = Vector3(0.0, 0.0, rotation_z * p.spin)
	p.color = FxCurve.color(_initial.get("startColor", null), normalized, p.rand[R.COLOR])
	p.gravity = FxCurve.value(_initial.get("gravityModifier", null), normalized, p.rand[R.GRAVITY], 0.0)
	var shaped := _shape(p, time, normalized, slot, count)
	var position: Vector3 = shaped[0]
	var direction: Vector3 = shaped[1]
	var velocity := direction * FxCurve.value(_initial.get("startSpeed", null), normalized, p.rand[R.SPEED], 0.0)
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


## 모양 모듈: 태어날 자리와 나아갈 방향(유니티 지역 좌표). 모듈이 없으면 원점에서 +Z로.
func _shape(p: Particle, time: float, normalized: float, slot: int, count: int) -> Array:
	var shape: Dictionary = _modules.get("ShapeModule", {})
	if shape.is_empty():
		return [Vector3.ZERO, Vector3(0, 0, 1)]
	var radius_info: Dictionary = shape.get("radius", {})
	var radius := float(radius_info.get("value", 1.0))
	var thickness := clampf(float(shape.get("radiusThickness", 1.0)), 0.0, 1.0)
	var inner := 1.0 - thickness
	var area_radius := radius * sqrt(inner * inner + p.rand[R.RADIUS] * (1.0 - inner * inner))
	var volume_radius := radius * pow(inner * inner * inner + p.rand[R.RADIUS] * (1.0 - inner * inner * inner), 1.0 / 3.0)
	var arc_info: Dictionary = shape.get("arc", {})
	var arc := float(arc_info.get("value", 360.0))
	var fraction := _arc_fraction(arc_info, p.rand[R.ARC], time, normalized, slot, count)
	var phi := fraction * deg_to_rad(arc)
	var position := Vector3.ZERO
	var direction := Vector3(0, 0, 1)
	match int(shape.get("type", 4)):
		0, 2:
			direction = _random_direction(p.rand[R.SHAPE_X], p.rand[R.SHAPE_Y])
			if arc < 360.0:
				var flat := Vector2(direction.x, direction.y).length()
				direction = Vector3(cos(phi) * flat, sin(phi) * flat, direction.z)
			if int(shape.get("type", 0)) == 2:
				direction.z = absf(direction.z)
			position = direction * volume_radius
		4, 8:
			var angle := deg_to_rad(float(shape.get("angle", 25.0)))
			var disc := Vector2(cos(phi), sin(phi)) * (area_radius / maxf(radius, 0.000001))
			direction = Vector3(disc.x * sin(angle), disc.y * sin(angle), cos(angle)).normalized()
			position = Vector3(disc.x * radius, disc.y * radius, 0.0)
			if int(shape.get("type", 4)) == 8:
				position += direction * float(shape.get("length", 5.0)) * p.rand[R.SHAPE_Z]
		5:
			position = Vector3(p.rand[R.SHAPE_X] - 0.5, p.rand[R.SHAPE_Y] - 0.5, p.rand[R.SHAPE_Z] - 0.5)
		10:
			position = Vector3(cos(phi), sin(phi), 0.0) * area_radius
			direction = Vector3(cos(phi), sin(phi), 0.0)
		12:
			var along := (2.0 * fraction - 1.0) if int(arc_info.get("mode", 0)) == 3 else (2.0 * p.rand[R.SHAPE_X] - 1.0)
			position = Vector3(along * radius, 0.0, 0.0)
			direction = Vector3(0, 1, 0)
		18:
			position = Vector3(p.rand[R.SHAPE_X] - 0.5, p.rand[R.SHAPE_Y] - 0.5, 0.0)
	position *= _vector3(shape.get("m_Scale", null), Vector3.ONE)
	var turn := _euler_unity(_vector3(shape.get("m_Rotation", null), Vector3.ZERO) * (PI / 180.0))
	position = turn * position
	direction = turn * direction
	position += _vector3(shape.get("m_Position", null), Vector3.ZERO)
	var spherical := float(shape.get("sphericalDirectionAmount", 0.0))
	if spherical > 0.0 and position.length_squared() > 0.0:
		direction = direction.lerp(position.normalized(), spherical).normalized()
	var random_direction := float(shape.get("randomDirectionAmount", 0.0))
	if random_direction > 0.0:
		direction = direction.lerp(_random_direction(p.rand[R.DIR_X], p.rand[R.DIR_Y]), random_direction).normalized()
	var jitter := float(shape.get("randomPositionAmount", 0.0))
	if jitter > 0.0:
		position += Vector3(p.rand[R.POS_X] * 2.0 - 1.0, p.rand[R.POS_Y] * 2.0 - 1.0, p.rand[R.POS_Z] * 2.0 - 1.0) * jitter
	return [position, direction]


## 호(arc) 위 어디서 나올지 (0~1): 0 무작위, 1 돌아가며, 2 왕복, 3 한꺼번에 나온 것끼리 고르게
static func _arc_fraction(arc_info: Dictionary, rand: float, time: float, normalized: float, slot: int, count: int) -> float:
	var fraction := rand
	var speed := FxCurve.value(arc_info.get("speed", null), normalized, 0.5, 1.0)
	match int(arc_info.get("mode", 0)):
		1:
			fraction = fposmod(time * speed, 1.0)
		2:
			fraction = pingpong(time * speed, 1.0)
		3:
			fraction = float(slot) / maxf(count, 1)
	var spread := float(arc_info.get("spread", 0.0))
	if spread > 0.0:
		fraction = floorf(fraction / spread) * spread
	return fraction


# ---- 움직임 ----
func _update_particles(emit_time: float) -> void:
	var kept: Array[Particle] = []
	for p in _particles:
		var target := emit_time - p.birth
		if target >= p.life:
			continue
		while p.age < target - 0.000001:
			var dt := minf(STEP, target - p.age)
			p.age += dt
			_step(p, dt, clampf(p.age / p.life, 0.0, 1.0))
		kept.append(p)
	_particles = kept


func _step(p: Particle, dt: float, n: float) -> void:
	var acceleration := Vector3.ZERO
	if p.gravity != 0.0:
		acceleration += _to_sim_from_world(Vector3(0.0, -GRAVITY * p.gravity, 0.0))
	var force: Dictionary = _modules.get("ForceModule", {})
	if not force.is_empty():
		var push := Vector3(FxCurve.value(force.get("x", null), n, p.rand[R.FORCE_X]),
				FxCurve.value(force.get("y", null), n, p.rand[R.FORCE_Y]), FxCurve.value(force.get("z", null), n, p.rand[R.FORCE_Z]))
		acceleration += _module_vector(push, bool(force.get("inWorldSpace", false)))
	p.vel += acceleration * dt
	var anim := Vector3.ZERO
	var speed_scale := 1.0
	var velocity: Dictionary = _modules.get("VelocityModule", {})
	if not velocity.is_empty():
		var linear := Vector3(FxCurve.value(velocity.get("x", null), n, p.rand[R.VEL_X]),
				FxCurve.value(velocity.get("y", null), n, p.rand[R.VEL_Y]), FxCurve.value(velocity.get("z", null), n, p.rand[R.VEL_Z]))
		anim += _module_vector(linear, bool(velocity.get("inWorldSpace", false)))
		var orbit := Vector3(FxCurve.value(velocity.get("orbitalX", null), n, p.rand[R.ORBIT_X]),
				FxCurve.value(velocity.get("orbitalY", null), n, p.rand[R.ORBIT_Y]),
				FxCurve.value(velocity.get("orbitalZ", null), n, p.rand[R.ORBIT_Z]))
		var radial := FxCurve.value(velocity.get("radial", null), n, p.rand[R.RADIAL])
		if orbit != Vector3.ZERO or radial != 0.0:
			var center := p.origin
			if not _world_space:
				center = Vector3(FxCurve.value(velocity.get("orbitalOffsetX", null), n, 0.5),
						FxCurve.value(velocity.get("orbitalOffsetY", null), n, 0.5),
						FxCurve.value(velocity.get("orbitalOffsetZ", null), n, 0.5))
			var relative := p.pos - center
			if _world_space:
				orbit = _rotation * (MIRROR * orbit)
			anim += orbit.cross(relative)
			if relative.length_squared() > 0.0:
				anim += relative.normalized() * radial
		speed_scale = FxCurve.value(velocity.get("speedModifier", null), n, p.rand[R.SPEED_MOD], 1.0)
	var limit: Dictionary = _modules.get("ClampVelocityModule", {})
	if not limit.is_empty():
		var total := p.vel + anim
		var cap := FxCurve.value(limit.get("magnitude", null), n, p.rand[R.LIMIT], INF)
		var length := total.length()
		if length > cap and length > 0.0:
			# 넘친 속도의 dampen만큼을 1/60초마다 줄인다.
			var dampen := 1.0 - pow(1.0 - clampf(float(limit.get("dampen", 0.0)), 0.0, 1.0), dt / STEP)
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


func _draw_particles() -> void:
	var count := mini(_particles.size(), _max)
	multimesh.visible_instance_count = count
	if count == 0:
		return
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	var view := camera.global_basis.orthonormalized() if camera != null else Basis.IDENTITY
	var size_module: Dictionary = _modules.get("SizeModule", {})
	var rotation_module: Dictionary = _modules.get("RotationModule", {})
	var color_module: Dictionary = _modules.get("ColorModule", {})
	var custom_module: Dictionary = _modules.get("CustomDataModule", {})
	var sheet: Dictionary = _modules.get("UVModule", {})
	var tiles := Vector2i(int(sheet.get("tilesX", 1)), int(sheet.get("tilesY", 1))) if int(sheet.get("mode", 0)) == 0 else Vector2i.ONE
	var low := Vector3.INF
	var high := -Vector3.INF
	for i in count:
		var p := _particles[i]
		var n := clampf(p.age / p.life, 0.0, 1.0)
		var size := p.size
		if not size_module.is_empty():
			if bool(size_module.get("separateAxes", false)):
				size *= Vector3(FxCurve.value(size_module.get("curve", null), n, p.rand[R.OL_SIZE_X], 1.0),
						FxCurve.value(size_module.get("y", null), n, p.rand[R.OL_SIZE_Y], 1.0),
						FxCurve.value(size_module.get("z", null), n, p.rand[R.OL_SIZE_Z], 1.0))
			else:
				size *= FxCurve.value(size_module.get("curve", null), n, p.rand[R.OL_SIZE_X], 1.0)
		var rot := p.rot
		if not rotation_module.is_empty():
			rot.z += p.spin * p.life * FxCurve.integral(rotation_module.get("curve", null), n, p.rand[R.OL_ROT_Z])
			if bool(rotation_module.get("separateAxes", false)):
				rot.x += p.spin * p.life * FxCurve.integral(rotation_module.get("x", null), n, p.rand[R.OL_ROT_X])
				rot.y += p.spin * p.life * FxCurve.integral(rotation_module.get("y", null), n, p.rand[R.OL_ROT_Y])
		var color := p.color
		if not color_module.is_empty():
			color *= FxCurve.color(color_module.get("gradient", null), n, p.rand[R.OL_COLOR])
		color = color.clamp()
		var custom := _custom(custom_module, n, p)
		if tiles.x * tiles.y > 1:
			custom.a = _sheet_frame(sheet, tiles, n, p)
		var centre := p.pos if _world_space else _sim_to_world * p.pos
		low = low.min(centre)
		high = high.max(centre)
		multimesh.set_instance_transform(i, _instance(p, centre, size, rot, view))
		multimesh.set_instance_color(i, color)
		multimesh.set_instance_custom_data(i, custom)
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


## 커스텀 데이터 1 (셰이더의 x 메인 텍스처 밀기, y 슬롯 밀기, z 녹이기)
static func _custom(module: Dictionary, n: float, p: Particle) -> Color:
	if module.is_empty():
		return Color(0, 0, 0, 0)
	match int(module.get("mode0", 0)):
		1:
			var parts := int(module.get("vectorComponentCount0", 4))
			var values: Array[float] = [0.0, 0.0, 0.0, 0.0]
			for k in mini(parts, 4):
				values[k] = FxCurve.value(module.get("vector0_%d" % k, null), n, p.rand[R.CUSTOM_0 + k], 0.0)
			return Color(values[0], values[1], values[2], values[3])
		2:
			return FxCurve.color(module.get("color0", null), n, p.rand[R.CUSTOM_0])
	return Color(0, 0, 0, 0)


## 텍스처 시트(격자)에서 지금 쓸 칸 번호
static func _sheet_frame(sheet: Dictionary, tiles: Vector2i, n: float, p: Particle) -> float:
	var frames := tiles.x * tiles.y
	var first := FxCurve.value(sheet.get("startFrame", null), 0.0, p.rand[R.START_FRAME], 0.0) / frames
	var phase := float(sheet.get("cycles", 1.0)) * FxCurve.value(sheet.get("frameOverTime", null), n, p.rand[R.FRAME], 0.0) + first
	phase = fposmod(phase, 1.0)
	return float(mini(int(floorf(phase * frames)), frames - 1))


# ---- 도움 ----
## 재생 시간 → 시스템 한 바퀴 안의 비율(0~1)
func _system_time(time: float) -> float:
	var t := fposmod(time, _duration) if _looping else time
	return clampf(t / _duration, 0.0, 0.9999)


## 파티클마다 쓰는 무작위 값들. 시스템 씨앗과 태어난 순서로 정해지므로 모든 피어에서 같다.
func _randoms(index: int) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = _hash(_seed, index)
	var values := PackedFloat32Array()
	values.resize(R.COUNT)
	for k in R.COUNT:
		values[k] = rng.randf()
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
