class_name SettingsMenu
extends CanvasLayer
## 설정 화면. 메인 메뉴와 일시정지 메뉴에서 연다.
## 바꾼 값은 바로 적용하고, 닫을 때 저장한다. 항목이 많아 씬 파일 대신 코드로 만든다.
## 키 바꾸기: 버튼을 누른 뒤 원하는 키를 누른다. Esc는 취소, 다른 동작이 쓰던 키면 그 동작과 맞바꾼다.

signal closed

const LABEL_WIDTH := 240.0
const CONTROL_WIDTH := 320.0
## 소리 크기를 바꿀 때 들려주는 확인음
const PREVIEW_HZ := 660.0
const PREVIEW_SECONDS := 0.15

var _panel: PanelContainer
var _tabs: TabContainer
var _close_button: Button
var _preview: AudioStreamPlayer
var _rebinding_action := &""
var _rebinding_button: Button
var _key_buttons: Dictionary[StringName, Button] = {}
var _window_size_row: Control


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	_preview = AudioStreamPlayer.new()
	_preview.stream = _make_preview_tone()
	add_child(_preview)
	_build()
	hide()


func open() -> void:
	_rebuild_tabs()
	_fit_panel()
	show()
	_close_button.grab_focus()


func close() -> void:
	_cancel_rebind()
	GameSettings.save()
	hide()
	closed.emit()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	# 입력을 바꾸는 중에는 마우스 버튼도 받는다 (공격, 조준 등을 마우스 버튼에 둘 수 있게).
	var mouse := event as InputEventMouseButton
	if mouse != null and mouse.pressed and _rebinding_action != &"":
		_finish_rebind(GameSettings.code_of(mouse))
		get_viewport().set_input_as_handled()
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if _rebinding_action != &"":
		if key.physical_keycode == KEY_ESCAPE:
			_cancel_rebind()
		else:
			_finish_rebind(key.physical_keycode)
		get_viewport().set_input_as_handled()
	elif key.physical_keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()


# ---- 화면 구성 ----

func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.75)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	_panel = panel
	# 기본 패널은 반투명이라 뒤의 메뉴 글자가 비쳐 보인다. 불투명한 배경을 쓴다.
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.05, 0.09)
	style.border_color = Color(1, 0.25, 0.7, 0.6)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

	var margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	panel.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	margin.add_child(column)

	var title := Label.new()
	title.text = "설정"
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(1, 0.25, 0.7))
	column.add_child(title)

	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_tabs)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation", 12)
	column.add_child(buttons)
	var reset := Button.new()
	reset.text = "기본값으로"
	reset.pressed.connect(_on_reset_pressed)
	buttons.add_child(reset)
	_close_button = Button.new()
	_close_button.text = "닫기"
	_close_button.custom_minimum_size.x = 120
	_close_button.pressed.connect(close)
	buttons.add_child(_close_button)


## 탭 내용을 지금 설정값으로 다시 만든다 (열 때, 기본값으로 되돌릴 때).
func _rebuild_tabs() -> void:
	var current := _tabs.current_tab
	for child in _tabs.get_children():
		_tabs.remove_child(child)
		child.queue_free()
	_key_buttons.clear()
	_add_tab("소리", _build_audio)
	_add_tab("화면", _build_display)
	_add_tab("그래픽", _build_graphics)
	_add_tab("조작", _build_controls)
	_add_tab("게임", _build_game)
	_tabs.current_tab = clampi(current, 0, _tabs.get_tab_count() - 1)


func _add_tab(title: String, fill: Callable) -> void:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var padding := MarginContainer.new()
	padding.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side: String in ["left", "right", "top", "bottom"]:
		padding.add_theme_constant_override("margin_" + side, 12)
	scroll.add_child(padding)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 10)
	padding.add_child(rows)
	_tabs.add_child(scroll)
	fill.call(rows)


func _build_audio(rows: VBoxContainer) -> void:
	for i in GameSettings.AUDIO_BUSES.size():
		var bus := GameSettings.AUDIO_BUSES[i]
		_add_slider(rows, GameSettings.AUDIO_BUS_LABELS[i], GameSettings.volume(bus) * 100.0, 0.0, 100.0, 1.0, "%d%%",
			func(value: float) -> void:
				GameSettings.volumes[bus] = value / 100.0
				GameSettings.apply_audio(),
			func() -> void: _play_preview(bus))
	_add_note(rows, "아직 게임에 소리가 없습니다. 조절할 때 나는 확인음으로 크기를 들어 볼 수 있습니다.")


func _build_display(rows: VBoxContainer) -> void:
	_add_options(rows, "창 모드", ["창", "테두리 없는 전체 화면", "전체 화면"], GameSettings.window_mode,
		func(index: int) -> void:
			GameSettings.window_mode = index as GameSettings.WindowMode
			_window_size_row.visible = index == GameSettings.WindowMode.WINDOWED
			_apply_display())
	var sizes := _available_window_sizes()
	var labels: Array[String] = []
	for size in sizes:
		labels.append("%d × %d" % [size.x, size.y])
	_window_size_row = _add_options(rows, "창 크기", labels, maxi(sizes.find(GameSettings.window_size), 0),
		func(index: int) -> void:
			GameSettings.window_size = sizes[index]
			_apply_display())
	_window_size_row.visible = GameSettings.window_mode == GameSettings.WindowMode.WINDOWED
	_add_check(rows, "수직 동기화 (화면 찢어짐 방지)", GameSettings.vsync,
		func(on: bool) -> void:
			GameSettings.vsync = on
			_apply_display())
	var fps_labels: Array[String] = []
	for fps in GameSettings.MAX_FPS_CHOICES:
		fps_labels.append("제한 없음" if fps == 0 else "%d" % fps)
	_add_options(rows, "최대 프레임", fps_labels, maxi(GameSettings.MAX_FPS_CHOICES.find(GameSettings.max_fps), 0),
		func(index: int) -> void:
			GameSettings.max_fps = GameSettings.MAX_FPS_CHOICES[index]
			_apply_display())
	_add_slider(rows, "글자·메뉴 크기", GameSettings.ui_scale * 100.0, 75.0, 200.0, 5.0, "%d%%",
		func(value: float) -> void:
			GameSettings.ui_scale = value / 100.0
			_apply_display())
	_add_slider(rows, "밝기", GameSettings.brightness * 100.0, 50.0, 200.0, 5.0, "%d%%",
		func(value: float) -> void:
			GameSettings.brightness = value / 100.0
			GameSettings.apply_brightness(get_viewport()))


func _build_graphics(rows: VBoxContainer) -> void:
	_add_slider(rows, "렌더링 해상도", GameSettings.render_scale * 100.0, 50.0, 100.0, 5.0, "%d%%",
		func(value: float) -> void:
			GameSettings.render_scale = value / 100.0
			_apply_display())
	_add_note(rows, "낮추면 프레임이 오르고 3D 화면이 조금 흐려집니다. 메뉴와 글자는 그대로입니다.")
	_add_options(rows, "안티에일리어싱 (계단 현상 줄이기)", ["끄기", "FXAA (가벼움)", "MSAA 2배", "MSAA 4배"], GameSettings.antialiasing,
		func(index: int) -> void:
			GameSettings.antialiasing = index as GameSettings.Antialiasing
			GameSettings.apply_graphics(get_tree().root))
	_add_options(rows, "그림자 품질", ["낮음", "보통", "높음"], GameSettings.shadow_quality,
		func(index: int) -> void:
			GameSettings.shadow_quality = index as GameSettings.ShadowQuality
			GameSettings.apply_graphics(get_tree().root))
	_add_options(rows, "이펙트 양", ["낮음", "보통", "높음"], GameSettings.effect_quality,
		func(index: int) -> void: GameSettings.effect_quality = index as GameSettings.EffectQuality)
	_add_note(rows, "스킬·궁극기 이펙트의 파티클 수입니다. 궁극기에서 프레임이 떨어지면 낮추세요(다음 이펙트부터 바뀝니다).")


func _build_controls(rows: VBoxContainer) -> void:
	_add_slider(rows, "마우스 감도", GameSettings.mouse_sensitivity * 100.0, 10.0, 300.0, 5.0, "%d%%",
		func(value: float) -> void: GameSettings.mouse_sensitivity = value / 100.0)
	_add_check(rows, "마우스 상하 반전", GameSettings.invert_y,
		func(on: bool) -> void: GameSettings.invert_y = on)
	_add_slider(rows, "시야각 (FOV)", GameSettings.fov, 50.0, 100.0, 1.0, "%d°",
		func(value: float) -> void: GameSettings.fov = value)
	_add_check(rows, "자유 시점을 눌러서 켜고 끄기 (끄면 누르고 있는 동안만)", GameSettings.free_view_toggle,
		func(on: bool) -> void: GameSettings.free_view_toggle = on)
	_add_check(rows, "걷기를 눌러서 켜고 끄기 (끄면 누르고 있는 동안만)", GameSettings.walk_toggle,
		func(on: bool) -> void: GameSettings.walk_toggle = on)

	var header := Label.new()
	header.text = "키 설정"
	header.add_theme_color_override("font_color", Color(0.4, 0.85, 1))
	rows.add_child(header)
	for action in GameSettings.REBINDABLE_ACTIONS:
		var button := Button.new()
		button.custom_minimum_size.x = CONTROL_WIDTH
		button.text = GameSettings.key_label(action)
		button.pressed.connect(_start_rebind.bind(action, button))
		_key_buttons[action] = button
		_add_row(rows, str(GameSettings.ACTION_LABELS[action]), button)
	_add_note(rows, "버튼을 누른 뒤 키보드 키나 마우스 버튼을 누르면 바뀝니다. 다른 동작이 쓰던 입력이면 서로 맞바꿉니다. "
		+ "궁극기는 배틀 스킬 키를 길게 눌러도 나갑니다. 마우스 휠로 카메라 거리를 바꿉니다.")


func _build_game(rows: VBoxContainer) -> void:
	var characters := Characters.all()
	var names: Array[String] = []
	var current := 0
	for i in characters.size():
		names.append(characters[i].display_name)
		if characters[i].id == GameSettings.character_id:
			current = i
	_add_options(rows, "캐릭터", names, current,
		func(index: int) -> void: GameSettings.character_id = characters[index].id)
	_add_options(rows, "보이스 언어", GameSettings.VOICE_LANGUAGE_LABELS, maxi(GameSettings.VOICE_LANGUAGES.find(GameSettings.voice_language), 0),
		func(index: int) -> void: GameSettings.voice_language = GameSettings.VOICE_LANGUAGES[index])
	_add_check(rows, "바이저 쓰기", GameSettings.visor_on,
		func(on: bool) -> void: GameSettings.visor_on = on)
	_add_check(rows, "자동 업데이트", GameSettings.auto_update,
		func(on: bool) -> void: GameSettings.auto_update = on)
	_add_text(rows, "에셋 키", GameSettings.asset_key, "비공개 에셋 저장소의 GitHub 토큰",
		func(text: String) -> void: GameSettings.asset_key = text.strip_edges())
	_add_note(rows, "자동 업데이트는 게임 실행 파일과 캐릭터 모델을 받습니다. 캐릭터 모델은 공개할 수 없어서 비공개 저장소에 두고, "
		+ "에셋 키가 있어야 받습니다. 바이저는 게임 중에 H 키로도 쓰고 벗습니다. 캐릭터는 다음 판부터, "
		+ "자동 업데이트와 에셋 키는 다음에 켤 때부터 적용됩니다.")


# ---- 줄 만들기 ----

func _add_row(rows: VBoxContainer, title: String, control: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var label := Label.new()
	label.text = title
	label.custom_minimum_size.x = LABEL_WIDTH
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(label)
	row.add_child(control)
	rows.add_child(row)
	return row


func _add_slider(rows: VBoxContainer, title: String, value: float, min_value: float, max_value: float, step: float,
		value_format: String, changed: Callable, released: Callable = Callable()) -> HBoxContainer:
	var box := HBoxContainer.new()
	var slider := HSlider.new()
	slider.min_value = min_value
	slider.max_value = max_value
	slider.step = step
	slider.value = value
	slider.custom_minimum_size.x = CONTROL_WIDTH - 70.0
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var shown := Label.new()
	shown.custom_minimum_size.x = 64
	shown.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	shown.text = value_format % roundi(value)
	slider.value_changed.connect(func(new_value: float) -> void:
		shown.text = value_format % roundi(new_value)
		changed.call(new_value))
	if released.is_valid():
		slider.drag_ended.connect(func(_changed: bool) -> void: released.call())
	box.add_child(slider)
	box.add_child(shown)
	return _add_row(rows, title, box)


func _add_options(rows: VBoxContainer, title: String, labels: Array[String], selected: int, changed: Callable) -> HBoxContainer:
	var options := OptionButton.new()
	options.custom_minimum_size.x = CONTROL_WIDTH
	for label in labels:
		options.add_item(label)
	options.selected = selected
	options.item_selected.connect(func(index: int) -> void: changed.call(index))
	return _add_row(rows, title, options)


func _add_check(rows: VBoxContainer, title: String, on: bool, changed: Callable) -> HBoxContainer:
	var check := CheckButton.new()
	check.button_pressed = on
	check.toggled.connect(func(pressed: bool) -> void: changed.call(pressed))
	return _add_row(rows, title, check)


## 글을 넣는 칸. 비밀 값(에셋 키)이라 입력한 글자를 가린다.
func _add_text(rows: VBoxContainer, title: String, value: String, placeholder: String, changed: Callable) -> HBoxContainer:
	var field := LineEdit.new()
	field.custom_minimum_size.x = CONTROL_WIDTH
	field.text = value
	field.placeholder_text = placeholder
	field.secret = true
	field.text_changed.connect(func(text: String) -> void: changed.call(text))
	return _add_row(rows, title, field)


func _add_note(rows: VBoxContainer, text: String) -> void:
	var note := Label.new()
	note.text = text
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size.x = LABEL_WIDTH + CONTROL_WIDTH
	note.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
	note.add_theme_font_size_override("font_size", 14)
	rows.add_child(note)


# ---- 동작 ----

func _apply_display() -> void:
	GameSettings.apply_display(get_tree().root)
	_fit_panel()


## 창이 작거나 글자를 키워도 패널이 화면 밖으로 나가지 않게 한다. 넘치는 내용은 탭 안에서 스크롤된다.
func _fit_panel() -> void:
	var visible_size := get_viewport().get_visible_rect().size
	_panel.custom_minimum_size = Vector2(
		minf(LABEL_WIDTH + CONTROL_WIDTH + 140.0, visible_size.x - 32.0),
		minf(520.0, visible_size.y - 32.0))


func _available_window_sizes() -> Array[Vector2i]:
	var screen := DisplayServer.screen_get_size(DisplayServer.window_get_current_screen())
	var fits: Array[Vector2i] = []
	for size in GameSettings.WINDOW_SIZES:
		if screen.x <= 0 or (size.x <= screen.x and size.y <= screen.y):
			fits.append(size)
	if not fits.has(GameSettings.window_size):
		fits.append(GameSettings.window_size)
	return fits


func _on_reset_pressed() -> void:
	_cancel_rebind()
	GameSettings.reset_to_defaults()
	GameSettings.apply_all(get_tree().root)
	_rebuild_tabs()


func _start_rebind(action: StringName, button: Button) -> void:
	_cancel_rebind()
	_rebinding_action = action
	_rebinding_button = button
	button.text = "키나 마우스 버튼을 누르세요 (Esc: 취소)"


func _finish_rebind(code: int) -> void:
	var action := _rebinding_action
	# 다른 동작이 이미 쓰는 입력이면 그 동작에 원래 입력을 넘겨줘 서로 맞바꾼다.
	var other := GameSettings.action_using_key(code, action)
	var previous := _first_key(action)
	if other != &"" and previous != 0:
		GameSettings.key_overrides[other] = previous
	GameSettings.key_overrides[action] = code
	GameSettings.apply_keys()
	_rebinding_action = &""
	_rebinding_button = null
	for bound: StringName in _key_buttons:
		_key_buttons[bound].text = GameSettings.key_label(bound)


func _cancel_rebind() -> void:
	if _rebinding_button != null:
		_rebinding_button.text = GameSettings.key_label(_rebinding_action)
	_rebinding_action = &""
	_rebinding_button = null


func _first_key(action: StringName) -> int:
	for event in InputMap.action_get_events(action):
		var code := GameSettings.code_of(event)
		if code != 0:
			return code
	return 0


# ---- 확인음 ----

func _play_preview(bus: StringName) -> void:
	_preview.bus = bus
	_preview.play()


static func _make_preview_tone() -> AudioStreamWAV:
	var rate := 22050
	var count := int(rate * PREVIEW_SECONDS)
	var data := PackedByteArray()
	data.resize(count * 2)
	for i in count:
		# 끝이 뚝 끊기지 않도록 점점 작아지게 한다.
		var fade := 1.0 - float(i) / count
		var sample := sin(TAU * PREVIEW_HZ * i / rate) * 0.4 * fade
		data.encode_s16(i * 2, int(sample * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.data = data
	return stream
