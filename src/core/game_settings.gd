class_name GameSettings
extends RefCounted
## 사용자 설정: 소리, 화면, 그래픽, 조작, 게임. user://settings.cfg에 저장한다.
##
## 값은 정적 변수라 어디서든 GameSettings.fov처럼 읽는다. 자동 로드 노드로 두지 않은 이유는
## 테스트 러너(--script)에서는 자동 로드가 없어도 기본값으로 그대로 돌아가게 하기 위함이다.
## 바꾼 값은 apply_*()로 엔진에 적용하고 save()로 저장한다.

## 입력 동작 목록. 자동 로드 이름(InputActions)은 정적 함수 안에서 쓸 수 없어서 스크립트를 직접 불러온다.
const Actions := preload("res://src/core/input_actions.gd")

## 창 모드
enum WindowMode { WINDOWED, BORDERLESS, FULLSCREEN }
## 안티에일리어싱
enum Antialiasing { OFF, FXAA, MSAA_2X, MSAA_4X }
## 그림자 품질
enum ShadowQuality { LOW, MEDIUM, HIGH }

## 소리 버스 이름과 메뉴에 보일 이름. default_bus_layout.tres와 같아야 한다.
const AUDIO_BUSES: Array[StringName] = [&"Master", &"Music", &"SFX", &"Voice", &"UI"]
const AUDIO_BUS_LABELS: Array[String] = ["전체 음량", "음악", "효과음", "음성", "인터페이스"]

## 창 크기 후보. 모니터보다 큰 것은 메뉴에서 뺀다.
const WINDOW_SIZES: Array[Vector2i] = [
	Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(3840, 2160),
]
## 최대 프레임 후보. 0은 제한 없음.
const MAX_FPS_CHOICES: Array[int] = [0, 30, 60, 120, 144, 165, 240]

## 기본 마우스 감도(픽셀당 라디안). 메뉴의 감도 값은 이것에 곱하는 배율이다.
const BASE_MOUSE_SENSITIVITY := 0.0025

## 입력을 바꿀 수 있는 동작과 메뉴에 보일 이름. 키보드 키와 마우스 버튼 모두 지정할 수 있다.
## 입력 코드: 양수는 물리 키 코드, 음수는 -(마우스 버튼 번호)다.
const REBINDABLE_ACTIONS: Array[StringName] = [
	Actions.MOVE_FORWARD, Actions.MOVE_BACK, Actions.MOVE_LEFT, Actions.MOVE_RIGHT,
	Actions.JUMP, Actions.SPRINT, Actions.CROUCH,
	Actions.FIRE, Actions.AIM, Actions.RELOAD,
	Actions.WEAPON_1, Actions.WEAPON_2, Actions.WEAPON_3, Actions.WEAPON_4, Actions.WEAPON_NEXT, Actions.WEAPON_PREV,
	Actions.INTERACT, Actions.SCAN, Actions.CAMERA_TOGGLE, Actions.FREE_LOOK, Actions.TOGGLE_VISOR,
]
const ACTION_LABELS := {
	Actions.MOVE_FORWARD: "앞으로",
	Actions.MOVE_BACK: "뒤로",
	Actions.MOVE_LEFT: "왼쪽",
	Actions.MOVE_RIGHT: "오른쪽",
	Actions.JUMP: "점프",
	Actions.SPRINT: "달리기",
	Actions.CROUCH: "웅크리기 / 슬라이딩",
	Actions.RELOAD: "재장전",
	Actions.WEAPON_1: "무기 1",
	Actions.WEAPON_2: "무기 2",
	Actions.WEAPON_3: "무기 3",
	Actions.WEAPON_4: "맨손",
	Actions.CAMERA_TOGGLE: "1인칭 / 3인칭 전환",
	Actions.INTERACT: "상호작용 (제압, 몸 들기)",
	Actions.FIRE: "공격",
	Actions.AIM: "조준",
	Actions.WEAPON_NEXT: "다음 무기",
	Actions.WEAPON_PREV: "이전 무기",
	Actions.FREE_LOOK: "자유 시야 (휠: 확대·축소)",
	Actions.SCAN: "스캔 (누르는 동안, 1~3: 퀵핵)",
	Actions.TOGGLE_VISOR: "바이저 쓰기 / 벗기",
}

## 저장 위치. 테스트는 사용자의 실제 설정을 건드리지 않도록 다른 파일로 바꾼다.
static var path := "user://settings.cfg"

# ---- 소리 (0~1) ----
static var volumes: Dictionary[StringName, float] = {}

# ---- 화면 ----
static var window_mode := WindowMode.WINDOWED
static var window_size := Vector2i(1280, 720)
static var vsync := true
static var max_fps := 0
## 메뉴와 HUD 글자 크기 배율
static var ui_scale := 1.0
## 3D 화면을 그리는 해상도 비율. 낮추면 빨라지고 흐려진다.
static var render_scale := 1.0
## 밝기 (1이 기본)
static var brightness := 1.0

# ---- 그래픽 ----
static var antialiasing := Antialiasing.FXAA
static var shadow_quality := ShadowQuality.MEDIUM

# ---- 조작 ----
static var mouse_sensitivity := 1.0
static var invert_y := false
## true면 키를 누를 때마다 켜고 끄는 토글, false면 누르고 있는 동안만
static var crouch_toggle := true
static var sprint_toggle := false
static var aim_toggle := false
static var free_look_toggle := false
## 기본 시야각(도). 달리기·슬라이딩 때는 여기에 더해지고, 조준하면 무기의 시야각으로 좁아진다.
static var fov := 80.0
## 동작별로 바꾼 입력 코드(양수는 키, 음수는 마우스 버튼). 없는 동작은 기본 입력을 쓴다.
static var key_overrides: Dictionary[StringName, int] = {}

# ---- 게임 ----
static var start_third_person := false
static var auto_update := true
## 캐릭터가 머리 장비(바이저)를 쓰고 있는지. 코옵에서도 남에게 그대로 보인다.
static var visor_on := true
## 에셋 키: 비공개 에셋 저장소(캐릭터 모델)를 읽는 GitHub 토큰. 비어 있으면 에셋을 받지 않는다(AssetUpdater).
static var asset_key := ""


static func reset_to_defaults() -> void:
	volumes = {&"Master": 1.0, &"Music": 0.8, &"SFX": 1.0, &"Voice": 1.0, &"UI": 0.8}
	window_mode = WindowMode.WINDOWED
	window_size = Vector2i(1280, 720)
	vsync = true
	max_fps = 0
	ui_scale = 1.0
	render_scale = 1.0
	brightness = 1.0
	antialiasing = Antialiasing.FXAA
	shadow_quality = ShadowQuality.MEDIUM
	mouse_sensitivity = 1.0
	invert_y = false
	crouch_toggle = true
	sprint_toggle = false
	aim_toggle = false
	free_look_toggle = false
	fov = 80.0
	key_overrides = {}
	start_third_person = false
	auto_update = true
	visor_on = true
	asset_key = ""


static func volume(bus: StringName) -> float:
	if volumes.is_empty():
		reset_to_defaults()
	return volumes.get(bus, 1.0)


## 마우스 이동(픽셀)을 시점 회전(라디안)으로 바꾼다. 감도와 상하 반전을 적용한다.
static func look_delta(mouse_relative: Vector2) -> Vector2:
	var delta := mouse_relative * BASE_MOUSE_SENSITIVITY * mouse_sensitivity
	if invert_y:
		delta.y = -delta.y
	return delta


# ---- 저장과 불러오기 ----

static func load_settings() -> void:
	reset_to_defaults()
	var config := ConfigFile.new()
	if config.load(path) != OK:
		return
	for bus in AUDIO_BUSES:
		volumes[bus] = clampf(float(config.get_value("audio", String(bus), volumes[bus])), 0.0, 1.0)
	window_mode = clampi(int(config.get_value("display", "window_mode", window_mode)), 0, WindowMode.size() - 1) as WindowMode
	var size: Variant = config.get_value("display", "window_size", window_size)
	if size is Vector2i:
		window_size = size
	vsync = bool(config.get_value("display", "vsync", vsync))
	max_fps = maxi(int(config.get_value("display", "max_fps", max_fps)), 0)
	ui_scale = clampf(float(config.get_value("display", "ui_scale", ui_scale)), 0.75, 2.0)
	render_scale = clampf(float(config.get_value("display", "render_scale", render_scale)), 0.5, 1.0)
	brightness = clampf(float(config.get_value("display", "brightness", brightness)), 0.5, 2.0)
	antialiasing = clampi(int(config.get_value("graphics", "antialiasing", antialiasing)), 0, Antialiasing.size() - 1) as Antialiasing
	shadow_quality = clampi(int(config.get_value("graphics", "shadow_quality", shadow_quality)), 0, ShadowQuality.size() - 1) as ShadowQuality
	mouse_sensitivity = clampf(float(config.get_value("controls", "mouse_sensitivity", mouse_sensitivity)), 0.1, 3.0)
	invert_y = bool(config.get_value("controls", "invert_y", invert_y))
	crouch_toggle = bool(config.get_value("controls", "crouch_toggle", crouch_toggle))
	sprint_toggle = bool(config.get_value("controls", "sprint_toggle", sprint_toggle))
	aim_toggle = bool(config.get_value("controls", "aim_toggle", aim_toggle))
	free_look_toggle = bool(config.get_value("controls", "free_look_toggle", free_look_toggle))
	fov = clampf(float(config.get_value("controls", "fov", fov)), 60.0, 110.0)
	if config.has_section("keys"):
		for action in REBINDABLE_ACTIONS:
			var code := int(config.get_value("keys", String(action), 0))
			if code != 0:
				key_overrides[action] = code
	start_third_person = bool(config.get_value("game", "start_third_person", start_third_person))
	auto_update = bool(config.get_value("game", "auto_update", auto_update))
	visor_on = bool(config.get_value("game", "visor_on", visor_on))
	asset_key = str(config.get_value("game", "asset_key", asset_key)).strip_edges()


## 다른 섹션(마지막 접속 주소 등)은 남겨 두고 설정 섹션만 다시 쓴다.
static func save() -> Error:
	var config := ConfigFile.new()
	config.load(path)
	for section: String in ["audio", "display", "graphics", "controls", "keys", "game"]:
		if config.has_section(section):
			config.erase_section(section)
	for bus in AUDIO_BUSES:
		config.set_value("audio", String(bus), volume(bus))
	config.set_value("display", "window_mode", window_mode)
	config.set_value("display", "window_size", window_size)
	config.set_value("display", "vsync", vsync)
	config.set_value("display", "max_fps", max_fps)
	config.set_value("display", "ui_scale", ui_scale)
	config.set_value("display", "render_scale", render_scale)
	config.set_value("display", "brightness", brightness)
	config.set_value("graphics", "antialiasing", antialiasing)
	config.set_value("graphics", "shadow_quality", shadow_quality)
	config.set_value("controls", "mouse_sensitivity", mouse_sensitivity)
	config.set_value("controls", "invert_y", invert_y)
	config.set_value("controls", "crouch_toggle", crouch_toggle)
	config.set_value("controls", "sprint_toggle", sprint_toggle)
	config.set_value("controls", "aim_toggle", aim_toggle)
	config.set_value("controls", "free_look_toggle", free_look_toggle)
	config.set_value("controls", "fov", fov)
	for action: StringName in key_overrides:
		config.set_value("keys", String(action), key_overrides[action])
	config.set_value("game", "start_third_person", start_third_person)
	config.set_value("game", "auto_update", auto_update)
	config.set_value("game", "visor_on", visor_on)
	config.set_value("game", "asset_key", asset_key)
	return config.save(path)


# ---- 적용 ----

static func apply_all(root: Window) -> void:
	apply_audio()
	apply_display(root)
	apply_graphics(root)
	apply_keys()


static func apply_audio() -> void:
	for bus in AUDIO_BUSES:
		var index := AudioServer.get_bus_index(bus)
		if index < 0:
			continue
		var value := volume(bus)
		AudioServer.set_bus_mute(index, value <= 0.0)
		AudioServer.set_bus_volume_db(index, linear_to_db(maxf(value, 0.0001)))


static func apply_display(root: Window) -> void:
	Engine.max_fps = max_fps
	root.content_scale_factor = ui_scale
	root.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if render_scale < 1.0 else Viewport.SCALING_3D_MODE_BILINEAR
	root.scaling_3d_scale = render_scale
	apply_brightness(root)
	# 화면이 없는 실행(테스트, 서버)에서는 창을 다루지 않는다.
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	match window_mode:
		WindowMode.FULLSCREEN:
			root.mode = Window.MODE_EXCLUSIVE_FULLSCREEN
		WindowMode.BORDERLESS:
			root.mode = Window.MODE_FULLSCREEN
		_:
			root.mode = Window.MODE_WINDOWED
			root.size = window_size
			# 바뀐 크기로 화면 가운데에 둔다.
			var screen := DisplayServer.window_get_current_screen()
			var area := DisplayServer.screen_get_usable_rect(screen)
			root.position = area.position + (area.size - window_size) / 2


## 지금 보이는 3D 월드의 환경에 밝기를 적용한다. 구역을 불러온 뒤에도 다시 부른다.
static func apply_brightness(viewport: Viewport) -> void:
	var world := viewport.find_world_3d()
	if world == null or world.environment == null:
		return
	world.environment.adjustment_enabled = true
	world.environment.adjustment_brightness = brightness


static func apply_graphics(root: Window) -> void:
	root.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if antialiasing == Antialiasing.FXAA else Viewport.SCREEN_SPACE_AA_DISABLED
	match antialiasing:
		Antialiasing.MSAA_2X:
			root.msaa_3d = Viewport.MSAA_2X
		Antialiasing.MSAA_4X:
			root.msaa_3d = Viewport.MSAA_4X
		_:
			root.msaa_3d = Viewport.MSAA_DISABLED
	var shadow_size: int = [2048, 4096, 8192][shadow_quality]
	RenderingServer.directional_shadow_atlas_set_size(shadow_size, true)
	root.positional_shadow_atlas_size = shadow_size / 2
	var filter: RenderingServer.ShadowQuality = [
		RenderingServer.SHADOW_QUALITY_HARD, RenderingServer.SHADOW_QUALITY_SOFT_LOW, RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM,
	][shadow_quality]
	RenderingServer.directional_soft_shadow_filter_set_quality(filter)
	RenderingServer.positional_soft_shadow_filter_set_quality(filter)


## 입력 설정을 InputMap에 적용한다. 바꾼 동작은 그 입력 하나만, 나머지는 기본 입력을 쓴다.
static func apply_keys() -> void:
	Actions.register_defaults()
	for action in REBINDABLE_ACTIONS:
		InputMap.action_erase_events(action)
		var codes: Array[int] = []
		if key_overrides.has(action):
			codes.append(key_overrides[action])
		else:
			for keycode: int in Actions.DEFAULT_KEYS.get(action, []):
				codes.append(keycode)
			for button: int in Actions.DEFAULT_MOUSE_BUTTONS.get(action, []):
				codes.append(-button)
		for code in codes:
			InputMap.action_add_event(action, event_from_code(code))


## 입력 코드로 입력 이벤트를 만든다 (양수는 키, 음수는 마우스 버튼).
static func event_from_code(code: int) -> InputEvent:
	if code < 0:
		var mouse := InputEventMouseButton.new()
		mouse.button_index = -code as MouseButton
		return mouse
	var key := InputEventKey.new()
	key.physical_keycode = code as Key
	return key


## 입력 이벤트의 입력 코드. 키도 마우스 버튼도 아니면 0.
static func code_of(event: InputEvent) -> int:
	var key := event as InputEventKey
	if key != null:
		return key.physical_keycode
	var mouse := event as InputEventMouseButton
	if mouse != null:
		return -mouse.button_index
	return 0


## 입력 코드의 이름 (메뉴 표시용)
static func code_label(code: int) -> String:
	if code < 0:
		match -code:
			MOUSE_BUTTON_LEFT:
				return "마우스 왼쪽"
			MOUSE_BUTTON_RIGHT:
				return "마우스 오른쪽"
			MOUSE_BUTTON_MIDDLE:
				return "마우스 가운데"
			MOUSE_BUTTON_WHEEL_UP:
				return "휠 위"
			MOUSE_BUTTON_WHEEL_DOWN:
				return "휠 아래"
			_:
				return "마우스 %d" % -code
	var keycode := code
	# 자판 배열에 맞는 이름을 보여 준다. 화면이 없는 실행(테스트)에서는 변환을 못 하므로 그대로 쓴다.
	if DisplayServer.get_name() != "headless":
		keycode = DisplayServer.keyboard_get_keycode_from_physical(code as Key)
	return OS.get_keycode_string(keycode as Key)


## 동작에 지금 묶인 입력 이름 (메뉴 표시용)
static func key_label(action: StringName) -> String:
	var names: PackedStringArray = []
	for event in InputMap.action_get_events(action):
		var code := code_of(event)
		if code != 0:
			names.append(code_label(code))
	return " / ".join(names) if not names.is_empty() else "(없음)"


## 이 입력을 이미 쓰는 다른 동작. 없으면 빈 이름.
static func action_using_key(code: int, except: StringName) -> StringName:
	for action in REBINDABLE_ACTIONS:
		if action == except:
			continue
		for event in InputMap.action_get_events(action):
			if code_of(event) == code:
				return action
	return &""
