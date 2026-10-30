extends TestCase
## 에셋 자동 업데이트에서 네트워크 없이 확인할 수 있는 부분: 목록 읽기, 바꿀 파일 고르기, 해시 확인 후 바꿔 넣기,
## 넘겨주기 주소 읽기, 에셋 키를 GitHub API에만 보내기, 올리는 도구와 이름 맞추기.
## 실제 내려받기는 내보낸 실행 파일로 따로 시험한다 (docs/dev/testing.md).

const WORK_DIR := "user://test_asset_updater"
const SHA_A := "a8a2f6ebe286697c527eb35a58b5539532e9b3ae3b64d4eb0a46fb657b41562c"


func after_each() -> void:
	var dir := ProjectSettings.globalize_path(WORK_DIR)
	for name: String in ["a.txt", "b.txt", "new.download", "target.txt", "sub/c.txt"]:
		DirAccess.remove_absolute(dir.path_join(name))
	DirAccess.remove_absolute(dir.path_join("sub"))
	DirAccess.remove_absolute(dir)


func test_parses_manifest() -> void:
	var text := '{"files": [{"path": "characters/model.glb", "sha256": "%s", "asset": "model.glb", "size": 5}]}' % SHA_A.to_upper()
	var entries := AssetUpdater.parse_manifest(text)
	assert_eq(entries.size(), 1)
	assert_eq(entries[0]["path"], "characters/model.glb")
	assert_eq(entries[0]["sha256"], SHA_A, "대소문자를 맞춘다")
	assert_eq(entries[0]["asset"], "model.glb")


func test_rejects_bad_manifests() -> void:
	assert_true(AssetUpdater.parse_manifest("not json").is_empty())
	assert_true(AssetUpdater.parse_manifest('{"files": "x"}').is_empty())
	var template := '{"files": [{"path": "%s", "sha256": "%s", "asset": "%s"}]}'
	assert_true(AssetUpdater.parse_manifest(template % ["../evil.exe", SHA_A, "evil.exe"]).is_empty(), "폴더 밖 경로")
	assert_true(AssetUpdater.parse_manifest(template % ["C:/Windows/evil.exe", SHA_A, "evil.exe"]).is_empty(), "절대 경로")
	assert_true(AssetUpdater.parse_manifest(template % ["a.glb", "1234", "a.glb"]).is_empty(), "SHA-256이 아님")
	assert_true(AssetUpdater.parse_manifest(template % ["a.glb", SHA_A, ""]).is_empty(), "릴리스 파일 이름이 없음")
	assert_true(AssetUpdater.parse_manifest(template % ["a.glb", SHA_A, "x/a.glb"]).is_empty(), "릴리스 파일 이름에 폴더")


func test_picks_only_missing_or_changed_files() -> void:
	var dir := ProjectSettings.globalize_path(WORK_DIR)
	_write(dir.path_join("a.txt"), "hello")
	_write(dir.path_join("b.txt"), "old")
	var entries: Array[Dictionary] = [
		{"path": "a.txt", "sha256": FileAccess.get_sha256(dir.path_join("a.txt")), "asset": "a.txt"},
		{"path": "b.txt", "sha256": SHA_A, "asset": "b.txt"},
		{"path": "sub/c.txt", "sha256": SHA_A, "asset": "c.txt"},
	]
	var stale := AssetUpdater.outdated(entries, dir)
	assert_eq(stale.size(), 2)
	assert_eq(stale[0]["path"], "b.txt", "내용이 다르면 받는다")
	assert_eq(stale[1]["path"], "sub/c.txt", "없으면 받는다")


func test_installs_only_when_hash_matches() -> void:
	var dir := ProjectSettings.globalize_path(WORK_DIR)
	var target := dir.path_join("target.txt")
	var part := dir.path_join("new.download")
	_write(target, "old model")
	_write(part, "broken")
	assert_false(AssetUpdater.install_file(part, target, SHA_A), "해시가 다르면 바꾸지 않는다")
	assert_eq(FileAccess.get_file_as_string(target), "old model")
	assert_false(FileAccess.file_exists(part), "받은 파일은 지운다")
	_write(part, "new model")
	assert_true(AssetUpdater.install_file(part, target, FileAccess.get_sha256(part)))
	assert_eq(FileAccess.get_file_as_string(target), "new model")


func test_reads_release_assets_and_redirect() -> void:
	var release := '{"assets": [{"name": "assets.json", "url": "https://api.github.com/repos/o/r/releases/assets/1"}, {"name": "x"}]}'
	var urls := AssetUpdater.parse_assets(release)
	assert_eq(urls.get("assets.json"), "https://api.github.com/repos/o/r/releases/assets/1")
	assert_false(urls.has("x"), "주소가 없는 파일은 뺀다")
	var headers := PackedStringArray(["Content-Type: text/html", "location: https://objects.example.com/file?sig=1"])
	assert_eq(AssetUpdater.redirect_location(headers), "https://objects.example.com/file?sig=1")
	assert_eq(AssetUpdater.redirect_location(PackedStringArray()), "")


func test_key_is_sent_only_to_github_api() -> void:
	var updater := AssetUpdater.new()
	updater.key = "secret"
	assert_true(" ".join(updater._headers([], true)).contains("Authorization: Bearer secret"), "GitHub API에는 키를 보낸다")
	assert_false(" ".join(updater._headers([], false)).contains("secret"), "넘겨받은 파일 주소에는 보내지 않는다")
	updater.key = ""
	assert_false(" ".join(updater._headers([], true)).contains("Authorization"), "키가 없으면 보내지 않는다")
	updater.free()


func test_publish_tool_uses_same_names() -> void:
	var tool := FileAccess.get_file_as_string("res://tools/publish_assets.py")
	assert_true(tool.contains('REPOSITORY = "%s"' % AssetUpdater.REPOSITORY))
	assert_true(tool.contains('RELEASE_TAG = "%s"' % AssetUpdater.RELEASE_TAG))
	assert_true(tool.contains('MANIFEST_NAME = "%s"' % AssetUpdater.MANIFEST_NAME))
	var appearance := Characters.find(Characters.DEFAULT_ID).appearance()
	assert_true(tool.contains('"%s"' % appearance.external_model_file), "게임이 읽는 모델 경로로 올린다")


func _write(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()
