class_name AssetUpdater
extends Node
## 실행 파일에 넣지 않는 에셋(캐릭터 모델 등)을 자동으로 받는다 (내보낸 Windows 게임 전용).
##
## 캐릭터 모델은 재배포할 수 없어서 공개 저장소(게임 릴리스)에 올리지 않는다. 비공개 에셋 저장소(REPOSITORY)의
## 릴리스(태그 RELEASE_TAG)에 올려 두고, PC마다 설정에 넣은 에셋 키(GitHub 토큰, 그 저장소 읽기 전용)로 받는다.
##
## 흐름:
##   1) 에셋 릴리스에서 목록(assets.json)을 받는다. 파일마다 실행 파일 폴더 기준 경로, SHA-256, 릴리스 파일 이름이 있다.
##   2) 실행 파일 옆 파일의 SHA-256이 목록과 다른 것만 받는다. 받은 파일의 SHA-256이 맞을 때만 바꿔 넣는다.
##   3) 모델은 플레이어가 생길 때 읽고 파일을 잡아 두지 않아서 게임 중에도 바꿀 수 있다. 다음에 생기는 플레이어부터
##      새 모델을 쓴다(CharacterAppearance가 파일을 고친 시각으로 다시 읽는다).
## 목록과 파일은 tools/publish_assets.py가 만들어 올린다.

## 메뉴에 보일 한 줄 (빈 문자열이면 지운다)
signal status_changed(message: String)
## 확인이 끝났다. updated는 바꾼 파일(실행 파일 폴더 기준 경로)이다.
signal finished(updated: Array[String])

enum State { IDLE, CHECKING, DOWNLOADING, DONE, FAILED }

const REPOSITORY := "RoastedBeer24/CPGP-assets"
const RELEASE_TAG := "assets"
const MANIFEST_NAME := "assets.json"
const STAGING_DIR := "user://asset_update"
## GitHub가 파일을 받을 곳으로 넘겨줄 때 쓰는 응답 코드
const REDIRECT_CODES: Array[int] = [301, 302, 303, 307, 308]

var state := State.IDLE
## 에셋 릴리스 정보를 묻는 주소
var release_url := "https://api.github.com/repos/%s/releases/tags/%s" % [REPOSITORY, RELEASE_TAG]
## 에셋을 넣을 폴더 (실행 파일 폴더)
var install_dir := OS.get_executable_path().get_base_dir()
## 에셋 키(GitHub 토큰). 비어 있으면 키 없이 묻는다(공개 저장소일 때만 받을 수 있다).
var key := ""
## 이번에 바꾼 파일
var updated: Array[String] = []


## 목록(assets.json)을 읽는다. 하나라도 형식이 틀리면 빈 배열이다.
## 항목: {"path": "characters/x.glb", "sha256": "64자리 16진수", "asset": "릴리스 파일 이름"}
static func parse_manifest(text: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var json := JSON.new()
	if json.parse(text) != OK or typeof(json.data) != TYPE_DICTIONARY:
		return result
	var files: Variant = (json.data as Dictionary).get("files", null)
	if typeof(files) != TYPE_ARRAY:
		return result
	for item: Variant in files:
		if typeof(item) != TYPE_DICTIONARY:
			return []
		var entry: Dictionary = item
		var path := str(entry.get("path", ""))
		var sha := str(entry.get("sha256", "")).to_lower()
		var asset := str(entry.get("asset", ""))
		if not Updater.is_safe_entry(path) or not _is_sha256(sha) or asset.is_empty() or asset.contains("/") or asset.contains("\\"):
			return []
		result.append({"path": path, "sha256": sha, "asset": asset})
	return result


## 릴리스 응답에서 파일 이름 → 내려받을 주소(API 주소)를 꺼낸다. 비공개 저장소는 API 주소로만 받을 수 있다.
static func parse_assets(release_json: String) -> Dictionary:
	var urls := {}
	var json := JSON.new()
	if json.parse(release_json) != OK or typeof(json.data) != TYPE_DICTIONARY:
		return urls
	var assets: Variant = (json.data as Dictionary).get("assets", [])
	if typeof(assets) != TYPE_ARRAY:
		return urls
	for asset: Variant in assets:
		if typeof(asset) == TYPE_DICTIONARY and (asset as Dictionary).has("name") and (asset as Dictionary).has("url"):
			urls[str(asset["name"])] = str(asset["url"])
	return urls


## 폴더(dir) 안의 파일이 목록과 다른 항목만 고른다 (없거나 SHA-256이 다르면).
static func outdated(entries: Array[Dictionary], dir: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry in entries:
		if FileAccess.get_sha256(dir.path_join(str(entry["path"]))) != str(entry["sha256"]):
			result.append(entry)
	return result


## 응답 헤더에서 넘겨줄 주소(Location)를 찾는다. 없으면 빈 문자열.
static func redirect_location(headers: PackedStringArray) -> String:
	for header: String in headers:
		if header.to_lower().begins_with("location:"):
			return header.substr(header.find(":") + 1).strip_edges()
	return ""


## 받은 파일(downloaded)의 SHA-256이 맞으면 target 자리에 넣는다. 틀리면 받은 파일을 지우고 false.
static func install_file(downloaded: String, target: String, sha256: String) -> bool:
	if FileAccess.get_sha256(downloaded) != sha256:
		DirAccess.remove_absolute(downloaded)
		return false
	DirAccess.make_dir_recursive_absolute(target.get_base_dir())
	if FileAccess.file_exists(target) and DirAccess.remove_absolute(target) != OK:
		DirAccess.remove_absolute(downloaded)
		return false
	return DirAccess.rename_absolute(downloaded, target) == OK


static func _is_sha256(text: String) -> bool:
	if text.length() != 64:
		return false
	for character: String in text:
		if not "0123456789abcdef".contains(character):
			return false
	return true


func check() -> void:
	state = State.CHECKING
	updated.clear()
	var http := HTTPRequest.new()
	http.timeout = 20.0
	add_child(http)
	if http.request(release_url, _headers(["Accept: application/vnd.github+json"], true)) != OK:
		http.queue_free()
		_fail("")
		return
	var result: Array = await http.request_completed
	http.queue_free()
	var code := int(result[1])
	if int(result[0]) != HTTPRequest.RESULT_SUCCESS:
		_fail("")
		return
	# 키가 없으면 비공개 저장소는 "없음(404)"으로 보인다. 받을 것이 없는 것으로 보고 조용히 넘어간다.
	if code == 404 and key.is_empty():
		_finish()
		return
	if code == 401 or code == 403 or code == 404:
		_fail("캐릭터 모델을 받지 못했습니다: 에셋 키가 맞지 않습니다.")
		return
	if code != 200:
		_fail("")
		return
	var urls := parse_assets((result[3] as PackedByteArray).get_string_from_utf8())
	if not urls.has(MANIFEST_NAME):
		_fail("")
		return
	var staging := ProjectSettings.globalize_path(STAGING_DIR)
	DirAccess.make_dir_recursive_absolute(staging)
	var manifest_path := staging.path_join(MANIFEST_NAME)
	if not await _download(str(urls[MANIFEST_NAME]), manifest_path):
		_fail("")
		return
	var entries := parse_manifest(FileAccess.get_file_as_string(manifest_path))
	DirAccess.remove_absolute(manifest_path)
	var stale := outdated(entries, install_dir)
	if stale.is_empty():
		_finish()
		return
	state = State.DOWNLOADING
	for entry in stale:
		var path := str(entry["path"])
		if not urls.has(entry["asset"]):
			continue
		status_changed.emit("새 에셋(%s)을 받는 중..." % path.get_file())
		var target := install_dir.path_join(path)
		var part := target + ".download"
		DirAccess.make_dir_recursive_absolute(target.get_base_dir())
		if await _download(str(urls[entry["asset"]]), part) and install_file(part, target, str(entry["sha256"])):
			updated.append(path)
		else:
			DirAccess.remove_absolute(part)
	if updated.size() < stale.size():
		_fail("에셋 일부를 받지 못했습니다. 다음에 켤 때 다시 받습니다.")
		return
	_finish()


## 릴리스 파일을 받는다. GitHub는 실제 파일이 있는 곳(다른 호스트)으로 넘겨주는데, 그곳에는 에셋 키를
## 보내면 안 되므로(거절되고, 키가 새어 나간다) 넘겨주기를 직접 따라가며 두 번째 요청에서는 키를 뺀다.
func _download(url: String, destination: String) -> bool:
	var http := HTTPRequest.new()
	http.timeout = 600.0
	http.max_redirects = 0
	http.download_file = destination
	add_child(http)
	var ok := false
	if http.request(url, _headers(["Accept: application/octet-stream"], true)) == OK:
		var result: Array = await http.request_completed
		if int(result[1]) in REDIRECT_CODES:
			var location := redirect_location(result[2])
			if not location.is_empty() and http.request(location, _headers([], false)) == OK:
				result = await http.request_completed
		ok = int(result[0]) == HTTPRequest.RESULT_SUCCESS and int(result[1]) == 200
	http.queue_free()
	return ok


## GitHub API는 User-Agent가 없는 요청을 거절한다. 에셋 키는 with_key일 때만(GitHub API에만) 붙인다.
func _headers(extra: Array[String], with_key: bool) -> PackedStringArray:
	var headers := PackedStringArray(["User-Agent: Crossfield-AssetUpdater"])
	headers.append_array(PackedStringArray(extra))
	if with_key and not key.is_empty():
		headers.append("Authorization: Bearer " + key)
	return headers


func _finish() -> void:
	state = State.DONE
	if not updated.is_empty():
		status_changed.emit("새 캐릭터 모델을 받았습니다.")
	finished.emit(updated)


func _fail(message: String) -> void:
	# 실패해도 게임은 그대로 한다(있던 모델을 쓴다). 메뉴에 한 줄로만 알린다.
	state = State.FAILED
	if not message.is_empty():
		status_changed.emit(message)
	finished.emit(updated)
