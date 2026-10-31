extends TestCase
## 원작 파티클 설정의 곡선·색 변화 계산 (FxCurve)


func test_constant_and_two_constants() -> void:
	assert_eq(FxCurve.value({"m": 0, "c": 0.15}, 0.7, 0.3), 0.15)
	assert_almost_eq(FxCurve.value({"m": 3, "min": 1.0, "max": 2.0}, 0.0, 0.25), 1.25, 0.0001, "두 값 사이는 파티클마다 정한 값으로 고른다")
	assert_eq(FxCurve.value(null, 0.5, 0.5, 3.0), 3.0, "설정이 없으면 기본값")


func test_curve_keys_follow_tangents() -> void:
	# 기울기가 1인 직선 (0,0) → (1,1)
	var line := {"m": 1, "mul": 2.0, "max": [[0.0, 0.0, 1.0, 1.0], [1.0, 1.0, 1.0, 1.0]]}
	assert_almost_eq(FxCurve.value(line, 0.5, 0.0), 1.0, 0.0001, "직선 곡선의 가운데 × 배율")
	# 기울기 0인 두 열쇠: 부드러운 S자
	var ease := [[0.0, 0.0, 0.0, 0.0], [1.0, 1.0, 0.0, 0.0]]
	assert_almost_eq(FxCurve.keys(ease, 0.5), 0.5, 0.0001)
	assert_almost_eq(FxCurve.keys(ease, 0.25), 0.15625, 0.0001, "허밋 곡선")
	assert_eq(FxCurve.keys(ease, -1.0), 0.0, "열쇠 앞은 첫 값")
	assert_eq(FxCurve.keys(ease, 2.0), 1.0, "열쇠 뒤는 끝 값")
	var two := {"m": 2, "mul": 1.0, "min": [[0.0, 0.0, 0.0, 0.0]], "max": [[0.0, 4.0, 0.0, 0.0]]}
	assert_almost_eq(FxCurve.value(two, 0.3, 0.5), 2.0, 0.0001, "두 곡선 사이")


func test_compiled_tables_match_direct_values() -> void:
	# 파티클 계산은 곡선을 미리 표로 만들어 쓴다(빠르기). 표에서 읽은 값이 곡선을 바로 계산한 값과 같아야 한다.
	var curves: Array = [
		null, {"m": 0, "c": 0.15}, {"m": 3, "min": 1.0, "max": 2.0},
		{"m": 1, "mul": 2.0, "max": [[0.0, 0.0, 1.0, 1.0], [1.0, 1.0, 1.0, 1.0]]},
		{"m": 2, "mul": 1.5, "min": [[0.0, 0.0, 0.0, 0.0], [1.0, 1.0, 0.0, 0.0]], "max": [[0.0, 2.0, 0.0, 0.0], [0.4, 3.0, 0.0, 0.0], [1.0, 1.0, 0.0, 0.0]]},
	]
	for curve: Variant in curves:
		var table := FxCurve.compile(curve, 0.7)
		var integral := FxCurve.compile_integral(curve)
		for step in 11:
			var t := step / 10.0
			for rand: float in [0.0, 0.3, 1.0]:
				assert_almost_eq(FxCurve.sample(table, t, rand), FxCurve.value(curve, t, rand, 0.7), 0.01, "값 %s t=%.1f" % [curve, t])
				assert_almost_eq(FxCurve.sample_integral(integral, t, rand), FxCurve.integral(curve, t, rand), 0.01, "적분 %s t=%.1f" % [curve, t])
	assert_eq(FxCurve.sample(FxCurve.compile(null, INF), 0.5, 0.5), INF, "무한대(상한 없음)는 그대로")
	var fade := {"mode": 0, "c": [[0.0, 1.0, 0.5, 0.0], [1.0, 0.0, 0.5, 1.0]], "a": [[0.0, 0.0], [0.3, 1.0], [1.0, 0.0]]}
	var gradients: Array = [null, {"m": 0, "c": [0.2, 0.3, 0.4, 0.5]}, {"m": 1, "max": fade},
		{"m": 2, "min": [0.0, 0.0, 0.0, 1.0], "max": [1.0, 1.0, 1.0, 1.0]}, {"m": 3, "min": fade, "max": fade}, {"m": 4, "max": fade}]
	for gradient: Variant in gradients:
		var table := FxCurve.compile_color(gradient)
		for step in 11:
			var t := step / 10.0
			for rand: float in [0.0, 0.6]:
				var expected := FxCurve.color(gradient, t, rand)
				var actual := FxCurve.sample_color(table, t, rand)
				assert_true(Vector4(actual.r, actual.g, actual.b, actual.a).distance_to(Vector4(expected.r, expected.g, expected.b, expected.a)) < 0.02,
						"색 %s t=%.1f: %s / %s" % [gradient, t, actual, expected])


func test_gradients() -> void:
	var fade := {"mode": 0, "c": [[0.0, 1.0, 0.5, 0.0], [1.0, 1.0, 0.5, 0.0]], "a": [[0.0, 0.0], [0.3, 1.0], [1.0, 0.0]]}
	var mid := FxCurve.color({"m": 1, "max": fade}, 0.15, 0.0)
	assert_almost_eq(mid.a, 0.5, 0.0001, "알파가 0 → 1로 차오르는 중간")
	assert_almost_eq(mid.g, 0.5, 0.0001)
	var two := FxCurve.color({"m": 2, "min": [0.0, 0.0, 0.0, 1.0], "max": [1.0, 1.0, 1.0, 1.0]}, 0.0, 0.5)
	assert_almost_eq(two.r, 0.5, 0.0001, "두 색 사이")
	var steps := {"mode": 1, "c": [[0.5, 1.0, 0.0, 0.0], [1.0, 0.0, 0.0, 1.0]], "a": [[0.0, 1.0]]}
	assert_eq(FxCurve.gradient_at(steps, 0.7), Color(0, 0, 1, 1), "계단 방식은 오른쪽 열쇠의 색")
	assert_eq(FxCurve.color({"m": 0, "c": [0.2, 0.3, 0.4, 0.5]}, 0.0, 0.0), Color(0.2, 0.3, 0.4, 0.5))
