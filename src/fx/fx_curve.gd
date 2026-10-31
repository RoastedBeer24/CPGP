class_name FxCurve
extends RefCounted
## 원작 이펙트의 파티클 설정(유니티 파티클 시스템을 JSON으로 옮겨 적은 것)에 든 곡선과 색 변화를 계산한다.
##
## 값(MinMaxCurve): {"m": 방식, ...}
##   0 고정값 c / 1 곡선 max(× mul) / 2 두 곡선 min·max 사이(× mul) / 3 두 값 min·max 사이
## 색(MinMaxGradient): {"m": 방식, ...}
##   0 고정색 c / 1 색 변화 max / 2 두 색 min·max 사이 / 3 두 색 변화 사이 / 4 색 변화 max에서 무작위로 한 점
## 곡선은 열쇠 [시각, 값, 들어오는 기울기, 나가는 기울기]의 목록이고 열쇠 사이는 허밋 곡선이다.
## 색 변화는 {"mode": 0 섞기 / 1 계단, "c": [[시각, r, g, b], ...], "a": [[시각, a], ...]}다.
## rand는 파티클마다 정해 둔 0~1 값이다(두 값 사이를 고를 때 쓴다).


## 미리 만든 표의 칸 수. 파티클 계산(FxSystem)은 곡선을 파티클마다 매 프레임 여러 번 계산한다. 그때마다 설정(사전·배열)을
## 뒤지면 궁극기처럼 파티클이 1,000개를 넘을 때 프레임당 수십 ms가 걸려서, 곡선을 표로 펴 두고 두 칸 사이만 잇는다.
const SAMPLES := 64


## 값 곡선을 표로 만든다. 고정값·두 값 사이는 [0, 1, 최소, 최대], 곡선은 [1, 곱, 0, 0, 최소 곡선 표, 최대 곡선 표]
## (표는 SAMPLES + 1칸, 곡선이 하나면 최소·최대가 같다). 설정이 없으면 fallback 고정값. sample로 계산한다.
static func compile(curve: Variant, fallback: float = 0.0) -> PackedFloat32Array:
	if typeof(curve) != TYPE_DICTIONARY:
		return PackedFloat32Array([0.0, 1.0, fallback, fallback])
	var data: Dictionary = curve
	match int(data.get("m", 0)):
		0:
			var c := float(data.get("c", fallback))
			return PackedFloat32Array([0.0, 1.0, c, c])
		1, 2:
			var high: Variant = data.get("max", [])
			var low: Variant = data.get("min", []) if int(data.get("m", 0)) == 2 else high
			var out := PackedFloat32Array([1.0, float(data.get("mul", 1.0)), 0.0, 0.0])
			out.append_array(_table(low, false))
			out.append_array(_table(high, false))
			return out
		3:
			return PackedFloat32Array([0.0, 1.0, float(data.get("min", fallback)), float(data.get("max", fallback))])
	return PackedFloat32Array([0.0, 1.0, fallback, fallback])


## compile로 만든 표에서 시각 t(0~1)의 값 (value와 같은 값)
static func sample(c: PackedFloat32Array, t: float, rand: float) -> float:
	if c[0] == 0.0:
		# 같은 두 값(고정값)은 그대로: 무한대(속도 상한 없음)를 섞으면 NaN이 된다.
		return c[2] if c[2] == c[3] else c[2] + (c[3] - c[2]) * rand
	var x := clampf(t, 0.0, 1.0) * SAMPLES
	var i := mini(int(x), SAMPLES - 1)
	var f := x - i
	var low := c[4 + i] + (c[5 + i] - c[4 + i]) * f
	var j := 5 + SAMPLES + i
	var high := c[j] + (c[j + 1] - c[j]) * f
	return (low + (high - low) * rand) * c[1]


## 적분(0부터 t까지 쌓은 양)을 표로 만든다. 고정값·두 값 사이는 [0, 1, 최소, 최대](값 × t), 곡선은 누적표 둘.
## sample_integral로 계산한다(integral과 같은 값).
static func compile_integral(curve: Variant) -> PackedFloat32Array:
	if typeof(curve) != TYPE_DICTIONARY:
		return PackedFloat32Array([0.0, 1.0, 0.0, 0.0])
	var data: Dictionary = curve
	match int(data.get("m", 0)):
		0:
			var c := float(data.get("c", 0.0))
			return PackedFloat32Array([0.0, 1.0, c, c])
		1, 2:
			var high: Variant = data.get("max", [])
			var low: Variant = data.get("min", []) if int(data.get("m", 0)) == 2 else high
			var out := PackedFloat32Array([1.0, float(data.get("mul", 1.0)), 0.0, 0.0])
			out.append_array(_table(low, true))
			out.append_array(_table(high, true))
			return out
		3:
			return PackedFloat32Array([0.0, 1.0, float(data.get("min", 0.0)), float(data.get("max", 0.0))])
	return PackedFloat32Array([0.0, 1.0, 0.0, 0.0])


static func sample_integral(c: PackedFloat32Array, t: float, rand: float) -> float:
	t = clampf(t, 0.0, 1.0)
	if c[0] == 0.0:
		return (c[2] + (c[3] - c[2]) * rand) * t
	return sample(c, t, rand)


## 열쇠 목록을 SAMPLES칸 표로 편다. cumulative면 0부터 쌓은 양(칸마다 심프슨 공식)이다.
static func _table(points: Variant, cumulative: bool) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(SAMPLES + 1)
	var step := 1.0 / SAMPLES
	var total := 0.0
	for i in SAMPLES + 1:
		if not cumulative:
			out[i] = keys(points, i * step)
			continue
		out[i] = total
		if i < SAMPLES:
			total += (keys(points, i * step) + 4.0 * keys(points, (i + 0.5) * step) + keys(points, (i + 1) * step)) * step / 6.0
	return out


## 색 설정을 표로 만든다. 고정색·두 색 사이는 [최소, 최대], 색 변화는 [최소 표, 최대 표](표는 SAMPLES + 1칸),
## "색 변화에서 무작위로 한 점"은 표 뒤에 한 칸을 더 붙여(홀수 길이) 시각 대신 rand로 고른다. sample_color로 계산한다.
static func compile_color(gradient: Variant) -> PackedColorArray:
	if typeof(gradient) != TYPE_DICTIONARY:
		return PackedColorArray([Color.WHITE, Color.WHITE])
	var data: Dictionary = gradient
	match int(data.get("m", 0)):
		0:
			var c := _color(data.get("c", null))
			return PackedColorArray([c, c])
		1:
			var table := _color_table(data.get("max", {}))
			table.append_array(table.duplicate())
			return table
		2:
			return PackedColorArray([_color(data.get("min", null)), _color(data.get("max", null))])
		3:
			var table := _color_table(data.get("min", {}))
			table.append_array(_color_table(data.get("max", {})))
			return table
		4:
			var table := _color_table(data.get("max", {}))
			table.append_array(table.duplicate())
			table.append(Color.WHITE)
			return table
	return PackedColorArray([Color.WHITE, Color.WHITE])


## compile_color로 만든 표에서 시각 t의 색 (color와 같은 값)
static func sample_color(c: PackedColorArray, t: float, rand: float) -> Color:
	if c.size() == 2:
		return c[0].lerp(c[1], rand)
	var random_point := c.size() % 2 == 1
	var x := clampf(rand if random_point else t, 0.0, 1.0) * SAMPLES
	var i := mini(int(x), SAMPLES - 1)
	var f := x - i
	var low := c[i].lerp(c[i + 1], f)
	if random_point:
		return low
	var j := SAMPLES + 1 + i
	return low.lerp(c[j].lerp(c[j + 1], f), rand)


static func _color_table(gradient: Variant) -> PackedColorArray:
	var out := PackedColorArray()
	out.resize(SAMPLES + 1)
	for i in SAMPLES + 1:
		out[i] = gradient_at(gradient, float(i) / SAMPLES)
	return out


## 값을 시각 t(0~1, 수명이나 재생 시간에 대한 비율)에서 계산한다. 설정이 없으면 fallback.
static func value(curve: Variant, t: float, rand: float, fallback: float = 0.0) -> float:
	if typeof(curve) != TYPE_DICTIONARY:
		return fallback
	var data: Dictionary = curve
	match int(data.get("m", 0)):
		0:
			return float(data.get("c", fallback))
		1:
			return keys(data.get("max", []), t) * float(data.get("mul", 1.0))
		2:
			var low := keys(data.get("min", []), t)
			var high := keys(data.get("max", []), t)
			return lerpf(low, high, rand) * float(data.get("mul", 1.0))
		3:
			return lerpf(float(data.get("min", fallback)), float(data.get("max", fallback)), rand)
	return fallback


## 값을 0부터 t까지 쌓은 양(적분). 수명 동안의 회전처럼 "초당 얼마"인 값을 지금까지 얼마나 움직였는지로 바꿀 때 쓴다.
## 곡선은 64칸으로 나눈 누적표를 곡선 설정 안에 만들어 두고 쓴다.
static func integral(curve: Variant, t: float, rand: float) -> float:
	if typeof(curve) != TYPE_DICTIONARY:
		return 0.0
	var data: Dictionary = curve
	t = clampf(t, 0.0, 1.0)
	match int(data.get("m", 0)):
		0:
			return float(data.get("c", 0.0)) * t
		3:
			return lerpf(float(data.get("min", 0.0)), float(data.get("max", 0.0)), rand) * t
		1:
			return _table_at(data, "max", t) * float(data.get("mul", 1.0))
		2:
			return lerpf(_table_at(data, "min", t), _table_at(data, "max", t), rand) * float(data.get("mul", 1.0))
	return 0.0


const _TABLE_STEPS := 64


static func _table_at(data: Dictionary, key: String, t: float) -> float:
	var cache_key := "_integral_" + key
	if not data.has(cache_key):
		var points: Variant = data.get(key, data.get("max", []))
		var table := PackedFloat32Array([0.0])
		var total := 0.0
		var step := 1.0 / _TABLE_STEPS
		for i in _TABLE_STEPS:
			# 칸마다 심프슨 공식
			var a := keys(points, i * step)
			var m := keys(points, (i + 0.5) * step)
			var b := keys(points, (i + 1) * step)
			total += (a + 4.0 * m + b) * step / 6.0
			table.append(total)
		data[cache_key] = table
	var table: PackedFloat32Array = data[cache_key]
	var x := t * _TABLE_STEPS
	var i := mini(int(x), _TABLE_STEPS - 1)
	return lerpf(table[i], table[i + 1], x - i)


## 값이 시간에 따라 바뀌는지 (고정값이나 두 값 사이면 false)
static func is_varying(curve: Variant) -> bool:
	return typeof(curve) == TYPE_DICTIONARY and int((curve as Dictionary).get("m", 0)) in [1, 2]


## 열쇠 목록을 시각 t에서 계산한다. 열쇠 밖이면 끝 열쇠의 값이다.
static func keys(list: Variant, t: float) -> float:
	if typeof(list) != TYPE_ARRAY or (list as Array).is_empty():
		return 0.0
	var points: Array = list
	var first: Array = points[0]
	if points.size() == 1 or t <= float(first[0]):
		return float(first[1])
	for i in range(1, points.size()):
		var right: Array = points[i]
		var t1 := float(right[0])
		if t > t1:
			continue
		var left: Array = points[i - 1]
		var t0 := float(left[0])
		var span := t1 - t0
		if span <= 0.000001:
			return float(right[1])
		var s := (t - t0) / span
		var s2 := s * s
		var s3 := s2 * s
		return (2.0 * s3 - 3.0 * s2 + 1.0) * float(left[1]) + (s3 - 2.0 * s2 + s) * span * float(left[3]) \
				+ (-2.0 * s3 + 3.0 * s2) * float(right[1]) + (s3 - s2) * span * float(right[2])
	var last: Array = points.back()
	return float(last[1])


## 색을 시각 t(0~1)에서 계산한다. 설정이 없으면 흰색.
static func color(gradient: Variant, t: float, rand: float) -> Color:
	if typeof(gradient) != TYPE_DICTIONARY:
		return Color.WHITE
	var data: Dictionary = gradient
	match int(data.get("m", 0)):
		0:
			return _color(data.get("c", null))
		1:
			return gradient_at(data.get("max", {}), t)
		2:
			return _color(data.get("min", null)).lerp(_color(data.get("max", null)), rand)
		3:
			return gradient_at(data.get("min", {}), t).lerp(gradient_at(data.get("max", {}), t), rand)
		4:
			return gradient_at(data.get("max", {}), rand)
	return Color.WHITE


## 색 변화 하나를 시각 t에서 계산한다.
static func gradient_at(gradient: Variant, t: float) -> Color:
	if typeof(gradient) != TYPE_DICTIONARY:
		return Color.WHITE
	var data: Dictionary = gradient
	var stepped := int(data.get("mode", 0)) == 1
	var rgb := _gradient_channel(data.get("c", []), t, 3, stepped)
	var alpha := _gradient_channel(data.get("a", []), t, 1, stepped)
	return Color(rgb[0], rgb[1], rgb[2], alpha[0])


static func _gradient_channel(list: Variant, t: float, width: int, stepped: bool) -> Array[float]:
	var out: Array[float] = []
	out.resize(width)
	out.fill(1.0)
	if typeof(list) != TYPE_ARRAY or (list as Array).is_empty():
		return out
	var points: Array = list
	var chosen: Array = points[0]
	if t <= float(chosen[0]) or points.size() == 1:
		return _channel_values(chosen, width)
	for i in range(1, points.size()):
		var right: Array = points[i]
		if t > float(right[0]):
			continue
		var left: Array = points[i - 1]
		if stepped:
			return _channel_values(right, width)
		var span := float(right[0]) - float(left[0])
		var s := 0.0 if span <= 0.000001 else (t - float(left[0])) / span
		for k in width:
			out[k] = lerpf(float(left[k + 1]), float(right[k + 1]), s)
		return out
	return _channel_values(points.back(), width)


static func _channel_values(point: Array, width: int) -> Array[float]:
	var out: Array[float] = []
	for k in width:
		out.append(float(point[k + 1]) if k + 1 < point.size() else 1.0)
	return out


static func _color(values: Variant) -> Color:
	if typeof(values) != TYPE_ARRAY:
		return Color.WHITE
	var list: Array = values
	if list.size() < 3:
		return Color.WHITE
	return Color(float(list[0]), float(list[1]), float(list[2]), float(list[3]) if list.size() > 3 else 1.0)
