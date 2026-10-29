extends TestCase
## 테스트 프레임워크 자체가 올바르게 판정하는지 확인한다.


func test_eq_treats_int_and_float_as_numbers() -> void:
	var probe := TestCase.new()
	probe.assert_eq(1, 1.0)
	assert_eq(probe.get_failures().size(), 0)


func test_eq_fails_on_different_types() -> void:
	var probe := TestCase.new()
	probe.assert_eq(1, "1")
	assert_eq(probe.get_failures().size(), 1)


func test_almost_eq_respects_tolerance() -> void:
	var probe := TestCase.new()
	probe.assert_almost_eq(1.0, 1.05, 0.1)
	probe.assert_almost_eq(1.0, 1.5, 0.1)
	assert_eq(probe.get_failures().size(), 1)


func test_autofree_releases_nodes() -> void:
	var node := Node.new()
	add_child_autofree(node)
	assert_true(node.is_inside_tree())
	free_autofree_nodes()
	await tree.process_frame
	assert_false(is_instance_valid(node))
