extends SceneTree
## 자동 테스트 러너.
## tests/ 아래의 test_*.gd 파일을 모두 찾아 test_로 시작하는 메서드를 실행한다.
##
## 사용법:
##   godot --headless --path . --script res://tests/run_tests.gd
##   godot --headless --path . --script res://tests/run_tests.gd -- 필터
## 필터를 주면 파일 경로나 테스트 이름에 그 문자열이 들어간 테스트만 실행한다.
## 실패한 테스트가 하나라도 있으면 종료 코드 1로 끝난다.

const TEST_ROOT := "res://tests"
const FRAMEWORK_DIR := "res://tests/framework"


## 테스트 중에 발생한 엔진 오류와 스크립트 오류를 모은다.
class ErrorCapture extends Logger:
	var _mutex := Mutex.new()
	var _errors: PackedStringArray = []

	func _log_error(
		_function: String,
		file: String,
		line: int,
		code: String,
		rationale: String,
		_editor_notify: bool,
		error_type: int,
		_script_backtrace: Array[ScriptBacktrace]
	) -> void:
		if error_type == ERROR_TYPE_WARNING:
			return
		var text := code if rationale.is_empty() else "%s: %s" % [code, rationale]
		_mutex.lock()
		_errors.append("%s (%s:%d)" % [text, file, line])
		_mutex.unlock()

	func take() -> PackedStringArray:
		_mutex.lock()
		var taken := _errors
		_errors = PackedStringArray()
		_mutex.unlock()
		return taken


var _capture := ErrorCapture.new()
var _passed := 0
var _failed := 0


func _initialize() -> void:
	OS.add_logger(_capture)
	_run()


func _run() -> void:
	# _initialize 시점에는 root가 아직 트리에 들어가지 않았으므로, 첫 프레임 뒤에 시작한다.
	await process_frame
	# 사용자의 실제 설정 파일을 읽거나 덮어쓰지 않도록 테스트용 파일을 쓴다.
	GameSettings.path = "user://test_settings.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(GameSettings.path))
	GameSettings.reset_to_defaults()
	# 메인 장면을 띄우는 테스트마다 배경에서 모든 모델을 미리 읽으면 느리고 흔들린다. 미리 읽기 자체는 따로 시험한다.
	AssetPreloader.enabled = false
	var args := OS.get_cmdline_user_args()
	var test_filter := args[0] if args.size() > 0 else ""

	var paths := _find_test_files(TEST_ROOT)
	paths.sort()
	for path in paths:
		await _run_file(path, test_filter)

	print("")
	print("결과: 통과 %d, 실패 %d" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


func _run_file(path: String, test_filter: String) -> void:
	_capture.take()
	var script := load(path) as GDScript
	var load_errors := _capture.take()
	if script == null or not load_errors.is_empty():
		_report(path, "(스크립트 불러오기)", PackedStringArray(["스크립트를 불러오지 못함"]) + load_errors)
		return

	var names: PackedStringArray = []
	for method in script.get_script_method_list():
		var method_name: String = method["name"]
		if method_name.begins_with("test_") and not names.has(method_name):
			names.append(method_name)

	var printed_header := false
	for method_name in names:
		if not test_filter.is_empty() and not (test_filter in path or test_filter in method_name):
			continue
		if not printed_header:
			print(path)
			printed_header = true
		await _run_test(script, path, method_name)


func _run_test(script: GDScript, path: String, method_name: String) -> void:
	var test := script.new() as TestCase
	if test == null:
		_report(path, method_name, PackedStringArray(["TestCase를 상속하지 않음"]))
		return

	test.tree = self
	_capture.take()
	await test.before_each()
	await test.call(method_name)
	await test.after_each()
	test.free_autofree_nodes()
	await process_frame

	_report(path, method_name, test.get_failures() + _capture.take())


func _report(path: String, method_name: String, failures: PackedStringArray) -> void:
	if failures.is_empty():
		_passed += 1
		print("  [통과] %s" % method_name)
		return
	_failed += 1
	print("  [실패] %s  (%s)" % [method_name, path])
	for failure in failures:
		print("      - %s" % failure)


func _find_test_files(dir_path: String) -> PackedStringArray:
	var found: PackedStringArray = []
	if dir_path == FRAMEWORK_DIR:
		return found
	for file_name in DirAccess.get_files_at(dir_path):
		if file_name.begins_with("test_") and file_name.ends_with(".gd"):
			found.append(dir_path.path_join(file_name))
	for sub_dir in DirAccess.get_directories_at(dir_path):
		found.append_array(_find_test_files(dir_path.path_join(sub_dir)))
	return found
