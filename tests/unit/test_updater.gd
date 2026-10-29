extends TestCase
## 자동 업데이트에서 네트워크 없이 확인할 수 있는 부분: 릴리스 응답 읽기, zip 풀기, 안전한 경로.
## 실제 내려받기와 설치는 내보낸 실행 파일로 따로 시험한다 (docs/dev/testing.md).

const RELEASE_JSON := """{
	"tag_name": "build-42",
	"assets": [
		{"name": "something-else.zip", "browser_download_url": "https://example.com/other.zip"},
		{"name": "CyberUniverse-windows.zip", "browser_download_url": "https://example.com/game.zip"}
	]
}"""

const WORK_DIR := "user://test_updater"


func after_each() -> void:
	_remove_tree(ProjectSettings.globalize_path(WORK_DIR))


func test_parses_build_number_and_zip_url() -> void:
	var release := Updater.parse_release(RELEASE_JSON)
	assert_eq(release.get("build"), 42)
	assert_eq(release.get("url"), "https://example.com/game.zip")


func test_rejects_unexpected_release_formats() -> void:
	assert_true(Updater.parse_release("not json").is_empty())
	assert_true(Updater.parse_release("[]").is_empty())
	assert_true(Updater.parse_release('{"tag_name": "v1.0", "assets": []}').is_empty(), "build- 태그가 아님")
	assert_true(Updater.parse_release('{"tag_name": "build-7", "assets": []}').is_empty(), "zip이 없음")
	assert_true(Updater.parse_release('{"tag_name": "build-x", "assets": []}').is_empty(), "번호가 아님")


func test_development_build_does_not_self_update() -> void:
	assert_eq(BuildInfo.NUMBER, 0, "저장소의 빌드 번호는 0이어야 함 (내보낼 때만 바꿈)")
	assert_false(Updater.can_self_update())


func test_unsafe_zip_paths_are_rejected() -> void:
	assert_true(Updater.is_safe_entry("CyberUniverse.exe"))
	assert_true(Updater.is_safe_entry("characters/model.glb"))
	assert_false(Updater.is_safe_entry("../evil.exe"))
	assert_false(Updater.is_safe_entry("a/../../evil.exe"))
	assert_false(Updater.is_safe_entry("C:/Windows/evil.exe"))
	assert_false(Updater.is_safe_entry("/etc/evil"))
	assert_false(Updater.is_safe_entry(""))


func test_extracts_zip_into_folder() -> void:
	var zip_path := _make_zip({"CyberUniverse.exe": "new exe", "README.txt": "hello"})
	var updater := Updater.new()
	var destination := ProjectSettings.globalize_path(WORK_DIR.path_join("files"))
	assert_true(updater._extract(zip_path, destination))
	assert_eq(FileAccess.get_file_as_string(destination.path_join("CyberUniverse.exe")), "new exe")
	assert_eq(FileAccess.get_file_as_string(destination.path_join("README.txt")), "hello")
	updater.free()


func test_zip_with_unsafe_path_is_refused() -> void:
	var zip_path := _make_zip({"../escape.txt": "bad"})
	var updater := Updater.new()
	assert_false(updater._extract(zip_path, ProjectSettings.globalize_path(WORK_DIR.path_join("files"))))
	assert_false(FileAccess.file_exists(ProjectSettings.globalize_path(WORK_DIR).path_join("escape.txt")))
	updater.free()


func test_apply_requires_downloaded_update() -> void:
	var updater := Updater.new()
	assert_eq(updater.apply(true), ERR_UNAVAILABLE, "받아 둔 업데이트가 없으면 설치하지 않음")
	updater.free()


func _make_zip(files: Dictionary) -> String:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(WORK_DIR))
	var path := ProjectSettings.globalize_path(WORK_DIR.path_join("update.zip"))
	var packer := ZIPPacker.new()
	packer.open(path)
	for name: String in files:
		packer.start_file(name)
		packer.write_file(str(files[name]).to_utf8_buffer())
		packer.close_file()
	packer.close()
	return path


func _remove_tree(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for sub in dir.get_directories():
		_remove_tree(path.path_join(sub))
	for file in dir.get_files():
		dir.remove(file)
	DirAccess.remove_absolute(path)
