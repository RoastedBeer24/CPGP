class_name Updater
extends Node
## GitHub 릴리스로 게임을 자동 업데이트한다 (Windows 실행 파일 전용).
##
## 흐름:
##   1) 최신 릴리스(태그 build-<번호>)를 묻고, 내 빌드 번호보다 크면
##   2) 실행 파일 zip을 user://update에 받아 풀어 두고 update_ready를 알린다.
##   3) apply()가 PowerShell 스크립트를 띄우고 게임은 종료한다. 스크립트는 게임이 끝나길 기다렸다가
##      새 파일을 실행 파일 폴더에 덮어쓰고, 원하면 게임을 다시 실행한다.
##      실행 중인 exe는 스스로 덮어쓸 수 없어서 별도 프로세스가 바꾼다.
## 실행 파일 폴더의 다른 파일(캐릭터 모델 등)은 건드리지 않는다.
##
## 게임 이름을 CyberUniverse에서 크로스필드(Crossfield)로 바꿨다. 릴리스에는 같은 게임을 두 이름으로 묶은 zip이
## 함께 올라간다. 실행 파일 이름을 보고 같은 이름의 zip을 받으므로(asset_name_for), 옛 이름으로 설치한 게임은
## CyberUniverse.exe가 그대로 새 버전으로 바뀐다.

signal status_changed(message: String)
signal update_ready

enum State { IDLE, CHECKING, DOWNLOADING, READY, INSTALLING, UP_TO_DATE, FAILED }

const REPOSITORY := "RoastedBeer24/CPGP"
const TAG_PREFIX := "build-"
const GAME_NAME := "Crossfield"
## 이름을 바꾸기 전에 설치한 게임의 실행 파일 이름
const LEGACY_NAME := "CyberUniverse"
const ASSET_SUFFIX := "-windows.zip"
const ASSET_NAME := GAME_NAME + ASSET_SUFFIX
const STAGING_DIR := "user://update"

var state := State.IDLE
## 최신 릴리스의 빌드 번호. 확인 전이거나 실패하면 0.
var latest_build := 0
var current_build := BuildInfo.NUMBER
## 최신 릴리스 정보를 묻는 주소. 시험할 때는 명령줄 --update-url=로 바꾼다.
var release_url := "https://api.github.com/repos/%s/releases/latest" % REPOSITORY
## 새 파일을 덮어쓸 폴더
var install_dir := OS.get_executable_path().get_base_dir()
## 받을 zip 이름 (실행 파일 이름에 맞춘다)
var asset_name := asset_name_for(OS.get_executable_path())

var _download: HTTPRequest


## 이 실행 파일이 스스로 업데이트할 수 있는지. 내보낸 Windows 게임만 된다(에디터, 개발 빌드 제외).
static func can_self_update() -> bool:
	return OS.has_feature("template") and OS.get_name() == "Windows" and BuildInfo.NUMBER > 0


## 실행 파일에 맞는 zip 이름. 옛 이름(CyberUniverse.exe)으로 설치한 게임은 옛 이름의 zip을 받아야 한다.
## 새 이름의 zip을 받으면 Crossfield.exe만 새로 생기고, 다시 켜는 옛 exe는 그대로라 업데이트를 끝없이 되풀이한다.
static func asset_name_for(executable_path: String) -> String:
	var base := executable_path.get_file().get_basename().trim_suffix(".console")
	if base.to_lower() == LEGACY_NAME.to_lower():
		return LEGACY_NAME + ASSET_SUFFIX
	return ASSET_NAME


## 릴리스 응답(JSON)에서 빌드 번호와 zip 주소를 꺼낸다. 형식이 맞지 않으면 빈 사전.
static func parse_release(json_text: String, wanted_asset: String = ASSET_NAME) -> Dictionary:
	# JSON.parse_string은 실패하면 엔진 오류를 남기므로, 오류 코드만 돌려주는 parse를 쓴다.
	var json := JSON.new()
	if json.parse(json_text) != OK or typeof(json.data) != TYPE_DICTIONARY:
		return {}
	var release: Dictionary = json.data
	var tag := str(release.get("tag_name", ""))
	if not tag.begins_with(TAG_PREFIX) or not tag.trim_prefix(TAG_PREFIX).is_valid_int():
		return {}
	var assets: Variant = release.get("assets", [])
	if typeof(assets) != TYPE_ARRAY:
		return {}
	for asset: Variant in assets:
		if typeof(asset) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = asset
		if str(entry.get("name", "")) == wanted_asset:
			return {"build": tag.trim_prefix(TAG_PREFIX).to_int(), "url": str(entry.get("browser_download_url", ""))}
	return {}


## zip 안의 경로가 압축을 푸는 폴더 밖을 가리키지 않는지 (../ 같은 경로 막기)
static func is_safe_entry(path: String) -> bool:
	if path.is_empty() or path.is_absolute_path() or path.begins_with("/") or path.contains(":"):
		return false
	for part in path.replace("\\", "/").split("/"):
		if part == "..":
			return false
	return true


func check() -> void:
	_set_state(State.CHECKING, "업데이트 확인 중...")
	var http := HTTPRequest.new()
	http.timeout = 20.0
	add_child(http)
	var error := http.request(release_url, _headers(["Accept: application/vnd.github+json"]))
	if error != OK:
		http.queue_free()
		_fail("업데이트를 확인하지 못했습니다.")
		return
	var result: Array = await http.request_completed
	http.queue_free()
	var body: PackedByteArray = result[3]
	# 릴리스가 아직 하나도 없으면 404가 온다. 받을 것이 없는 것이므로 조용히 넘어간다.
	if int(result[0]) == HTTPRequest.RESULT_SUCCESS and int(result[1]) == 404:
		_set_state(State.UP_TO_DATE, "")
		return
	if int(result[0]) != HTTPRequest.RESULT_SUCCESS or int(result[1]) != 200:
		_fail("업데이트 서버에 연결하지 못했습니다.")
		return
	var release := parse_release(body.get_string_from_utf8(), asset_name)
	if release.is_empty():
		_fail("업데이트 정보를 읽지 못했습니다.")
		return
	latest_build = int(release["build"])
	if latest_build <= current_build:
		_set_state(State.UP_TO_DATE, "")
		return
	_download_release(str(release["url"]))


func _download_release(url: String) -> void:
	_set_state(State.DOWNLOADING, "새 버전(빌드 %d)을 받는 중..." % latest_build)
	DirAccess.make_dir_recursive_absolute(_global(STAGING_DIR))
	var zip_path := _global(STAGING_DIR.path_join(asset_name))
	_download = HTTPRequest.new()
	_download.timeout = 600.0
	_download.download_file = zip_path
	add_child(_download)
	var error := _download.request(url, _headers([]))
	if error != OK:
		_download.queue_free()
		_download = null
		_fail("새 버전을 받지 못했습니다.")
		return
	var result: Array = await _download.request_completed
	_download.queue_free()
	_download = null
	if int(result[0]) != HTTPRequest.RESULT_SUCCESS or int(result[1]) != 200:
		_fail("새 버전을 받지 못했습니다.")
		return
	var files_dir := _global(STAGING_DIR.path_join("files"))
	if not _extract(zip_path, files_dir):
		_fail("받은 파일이 손상되었습니다.")
		return
	DirAccess.remove_absolute(zip_path)
	_set_state(State.READY, "새 버전(빌드 %d)이 준비되었습니다." % latest_build)
	update_ready.emit()


func _process(_delta: float) -> void:
	if _download == null or _download.get_body_size() <= 0:
		return
	var percent := int(100.0 * _download.get_downloaded_bytes() / _download.get_body_size())
	status_changed.emit("새 버전(빌드 %d)을 받는 중... %d%%" % [latest_build, percent])


## 받아 둔 새 버전을 설치한다. 성공하면 게임을 끝내야 한다(설치 스크립트가 종료를 기다린다).
## relaunch가 true면 설치가 끝난 뒤 게임을 다시 실행한다.
func apply(relaunch: bool) -> Error:
	if state != State.READY:
		return ERR_UNAVAILABLE
	var script_path := _global(STAGING_DIR.path_join("apply_update.ps1"))
	var file := FileAccess.open(script_path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(_apply_script())
	file.close()
	var args := PackedStringArray([
		"-NoProfile", "-ExecutionPolicy", "Bypass", "-WindowStyle", "Hidden", "-File", script_path,
		"-ProcessId", str(OS.get_process_id()),
		"-Source", _global(STAGING_DIR.path_join("files")),
		"-Target", install_dir,
	])
	if relaunch:
		args.append_array(["-Relaunch", OS.get_executable_path()])
	if OS.create_process("powershell.exe", args) <= 0:
		return FAILED
	# 설치 스크립트는 한 번만 띄운다 (종료 버튼과 창 닫기가 겹쳐도).
	state = State.INSTALLING
	return OK


## 설치 스크립트. Windows PowerShell 5.1은 BOM 없는 파일을 시스템 코드 페이지로 읽으므로 영어로만 쓴다.
## 내용이 같은 파일은 건너뛴다. 콘솔판(Crossfield.console.exe)은 게임을 띄운 뒤에도 살아 있어서
## 덮어쓸 수 없는데, 빌드마다 같은 실행기라 바꿀 필요가 없다.
## 한 파일을 못 바꿔도 나머지는 계속 바꾸고, 못 바꾼 파일을 기록에 남긴다. 게임 본체를 못 바꿨으면
## 빌드 번호가 그대로라 다음에 켤 때 다시 받는다.
func _apply_script() -> String:
	return "\n".join([
		"param([int]$ProcessId, [string]$Source, [string]$Target, [string]$Relaunch = '')",
		"$log = Join-Path (Split-Path $Source -Parent) 'apply_update.log'",
		"$failed = @()",
		"try {",
		"  $proc = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue",
		"  if ($proc) { $proc.WaitForExit(30000) | Out-Null }",
		"  $files = Get-ChildItem -Path $Source -Recurse -File",
		"  foreach ($file in $files) {",
		"    $relative = $file.FullName.Substring($Source.Length).TrimStart('\\', '/')",
		"    $dest = Join-Path $Target $relative",
		"    if ((Test-Path -LiteralPath $dest) -and ((Get-FileHash -LiteralPath $dest).Hash -eq (Get-FileHash -LiteralPath $file.FullName).Hash)) { continue }",
		"    New-Item -ItemType Directory -Force -Path (Split-Path $dest -Parent) | Out-Null",
		"    $copied = $false",
		"    for ($i = 0; $i -lt 20 -and -not $copied; $i++) {",
		"      try { Copy-Item -LiteralPath $file.FullName -Destination $dest -Force -ErrorAction Stop; $copied = $true }",
		"      catch { Start-Sleep -Milliseconds 500 }",
		"    }",
		"    if (-not $copied) { $failed += $relative }",
		"  }",
		"  Remove-Item -LiteralPath $Source -Recurse -Force -ErrorAction SilentlyContinue",
		"  if ($failed.Count -eq 0) { \"ok $(Get-Date -Format o)\" | Out-File -FilePath $log }",
		"  else { \"partial $(Get-Date -Format o): $($failed -join ', ')\" | Out-File -FilePath $log }",
		"} catch {",
		"  \"failed $(Get-Date -Format o): $_\" | Out-File -FilePath $log",
		"}",
		"if ($Relaunch -ne '') { Start-Process -FilePath $Relaunch -WorkingDirectory $Target }",
		"",
	])


func _extract(zip_path: String, destination: String) -> bool:
	var reader := ZIPReader.new()
	if reader.open(zip_path) != OK:
		return false
	var files := reader.get_files()
	var wrote_any := false
	for entry in files:
		if entry.ends_with("/"):
			continue
		if not is_safe_entry(entry):
			reader.close()
			return false
		var target := destination.path_join(entry)
		DirAccess.make_dir_recursive_absolute(target.get_base_dir())
		var out := FileAccess.open(target, FileAccess.WRITE)
		if out == null:
			reader.close()
			return false
		out.store_buffer(reader.read_file(entry))
		out.close()
		wrote_any = true
	reader.close()
	return wrote_any


func _headers(extra: Array[String]) -> PackedStringArray:
	# GitHub API는 User-Agent가 없는 요청을 거절한다.
	var headers := PackedStringArray(["User-Agent: Crossfield-Updater"])
	headers.append_array(PackedStringArray(extra))
	return headers


func _set_state(new_state: State, message: String) -> void:
	state = new_state
	status_changed.emit(message)


func _fail(message: String) -> void:
	# 업데이트 실패는 게임을 막지 않는다. 메뉴에 한 줄로만 알린다.
	_set_state(State.FAILED, message)


func _global(path: String) -> String:
	return ProjectSettings.globalize_path(path)
