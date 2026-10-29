class_name TestCase
extends RefCounted
## 테스트 스크립트의 기반 클래스.
## tests/ 아래의 test_*.gd 파일에서 이 클래스를 상속하고, test_로 시작하는 메서드를 만들면
## 각 메서드가 하나의 테스트가 된다. 테스트마다 새 인스턴스가 만들어진다.
## 테스트 중에 엔진 오류나 스크립트 오류가 나면 그 테스트는 자동으로 실패 처리된다.

## 테스트가 실행되는 SceneTree. 노드를 붙이거나 프레임을 기다릴 때 쓴다.
var tree: SceneTree

var _failures: PackedStringArray = []
var _autofree_nodes: Array[Node] = []


## 각 테스트 직전에 호출된다. 안에서 await를 써도 끝날 때까지 기다린 뒤 테스트를 시작한다.
func before_each() -> void:
	pass


## 각 테스트 직후에 호출된다.
func after_each() -> void:
	pass


func assert_true(condition: bool, message: String = "") -> void:
	if not condition:
		_fail("true를 기대했지만 false", message)


func assert_false(condition: bool, message: String = "") -> void:
	if condition:
		_fail("false를 기대했지만 true", message)


func assert_eq(actual: Variant, expected: Variant, message: String = "") -> void:
	if not _variants_equal(actual, expected):
		_fail("기대값 %s, 실제값 %s" % [var_to_str(expected), var_to_str(actual)], message)


func assert_ne(actual: Variant, unexpected: Variant, message: String = "") -> void:
	if _variants_equal(actual, unexpected):
		_fail("%s가 아니기를 기대했지만 같음" % var_to_str(unexpected), message)


func assert_almost_eq(actual: float, expected: float, tolerance: float = 0.0001, message: String = "") -> void:
	if absf(actual - expected) > tolerance:
		_fail("기대값 %s ± %s, 실제값 %s" % [expected, tolerance, actual], message)


func assert_not_null(value: Variant, message: String = "") -> void:
	if value == null:
		_fail("null이 아니기를 기대했지만 null", message)


func fail(message: String) -> void:
	_fail("실패", message)


## 노드를 씬 트리에 붙이고, 테스트가 끝나면 자동으로 해제한다.
func add_child_autofree(node: Node) -> Node:
	tree.root.add_child(node)
	_autofree_nodes.append(node)
	return node


func get_failures() -> PackedStringArray:
	return _failures


func free_autofree_nodes() -> void:
	for node in _autofree_nodes:
		if is_instance_valid(node):
			node.queue_free()
	_autofree_nodes.clear()


func _fail(reason: String, message: String) -> void:
	_failures.append(reason if message.is_empty() else "%s (%s)" % [message, reason])


func _variants_equal(a: Variant, b: Variant) -> bool:
	# 타입이 붙은 null(예: get_node_or_null의 결과)도 null로 취급한다.
	if a == null or b == null:
		return a == null and b == null
	var numeric := [TYPE_INT, TYPE_FLOAT]
	if typeof(a) in numeric and typeof(b) in numeric:
		return float(a) == float(b)
	if typeof(a) != typeof(b):
		return false
	return a == b
