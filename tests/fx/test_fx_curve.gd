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
