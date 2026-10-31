class_name CharacterScreen
extends Control
## 로비의 캐릭터 화면(C). 카메라가 원작 캐릭터 화면의 구도로 내 캐릭터를 비추고(Player.showcase), 오른쪽에
## 소개와 기술이 나온다. 캐릭터는 원작의 캐릭터 화면 동작으로 걸어 들어와 선다. 캐릭터를 누르면 반응하고,
## 무기 보기(W)를 누르면 왼손에 무기를 꺼내 보여 준다(카메라도 원작의 무기 보기 구도로 옮겨 간다).
## ◀ ▶(또는 A·D)로 캐릭터를 바꾸면 그 자리에서 새 캐릭터로 다시 나타난다(코옵에서도 모두에게 보인다).
## 휠로 얼굴 앞까지 다가가거나 물러나고, 마우스 오른쪽 버튼을 끌거나 Q·E로 캐릭터 둘레를 돈다.

signal closed

const PANEL_WIDTH := 460.0

var session: Session

var _name_label: Label
var _title_label: Label
var _description: Label
var _stats: Label
var _skills: Label
var _index_label: Label
var _weapon_button: Button
var _panel: PanelContainer
var _dragging := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_PASS
	visible = false
	var panel := PanelContainer.new()
	_panel = panel
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -PANEL_WIDTH - 32.0
	panel.offset_right = -32.0
	panel.offset_top = 32.0
	panel.offset_bottom = -32.0
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.07, 0.09, 0.82)
	style.border_color = Color(0.98, 0.84, 0.25, 0.9)
	style.border_width_left = 3
	style.content_margin_left = 24.0
	style.content_margin_right = 24.0
	style.content_margin_top = 20.0
	style.content_margin_bottom = 20.0
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 10)
	panel.add_child(rows)
	_title_label = _label(rows, 16, Color(0.98, 0.84, 0.25))
	_name_label = _label(rows, 34, Color.WHITE)
	_description = _label(rows, 16, Color(0.85, 0.87, 0.9))
	_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_stats = _label(rows, 17, Color(0.7, 0.95, 0.75))
	_skills = _label(rows, 15, Color(0.9, 0.9, 0.9))
	_skills.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_skills.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var switcher := HBoxContainer.new()
	switcher.alignment = BoxContainer.ALIGNMENT_CENTER
	switcher.add_theme_constant_override("separation", 16)
	rows.add_child(switcher)
	var previous := Button.new()
	previous.text = "◀"
	previous.custom_minimum_size = Vector2(64, 40)
	previous.pressed.connect(cycle.bind(-1))
	switcher.add_child(previous)
	_index_label = _label(switcher, 18, Color.WHITE)
	var next := Button.new()
	next.text = "▶"
	next.custom_minimum_size = Vector2(64, 40)
	next.pressed.connect(cycle.bind(1))
	switcher.add_child(next)
	_weapon_button = Button.new()
	_weapon_button.custom_minimum_size = Vector2(0, 40)
	_weapon_button.pressed.connect(toggle_weapon)
	rows.add_child(_weapon_button)
	var close := Button.new()
	close.text = "닫기 (C / Esc)"
	close.custom_minimum_size = Vector2(0, 40)
	close.pressed.connect(close_screen)
	rows.add_child(close)
	var hint := _label(self, 15, Color(1, 1, 1, 0.7))
	hint.text = "캐릭터 누르기: 반응   W: 무기 보기   휠: 가까이·멀리   마우스 오른쪽 끌기 또는 Q·E: 둘러보기   A·D: 캐릭터 바꾸기"
	hint.position = Vector2(32, 32)


func open_screen() -> void:
	var player := _player()
	if player == null:
		return
	visible = true
	player.input_blocked = true
	player.face_camera()
	player.showcase = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_refresh()


func close_screen() -> void:
	if not visible:
		return
	visible = false
	var player := _player()
	if player != null:
		player.input_blocked = false
		player.showcase = false
		player.showcase_weapon = false
	MouseLock.capture()
	closed.emit()


## 무기 보기를 켜거나 끈다: 캐릭터가 왼손에 무기를 꺼내 보여 주고, 끄면 거둔다.
func toggle_weapon() -> void:
	var player := _player()
	if player != null:
		player.showcase_weapon = not player.showcase_weapon
		_refresh()


## 캐릭터를 눌렀다: 반응하는 동작을 한다(무기를 보는 중에는 하지 않는다).
func poke() -> void:
	var player := _player()
	if player != null:
		player.showcase_pokes += 1


## 캐릭터를 앞(+1)이나 뒤(-1)로 바꾼다.
func cycle(step: int) -> void:
	var characters := Characters.all()
	var player := _player()
	if player == null or characters.is_empty():
		return
	var index := 0
	for i in characters.size():
		if characters[i].id == player.character_id:
			index = i
	var chosen := characters[wrapi(index + step, 0, characters.size())]
	GameSettings.character_id = chosen.id
	GameSettings.save()
	session.request_character(chosen.id)


func _process(delta: float) -> void:
	if not visible:
		return
	var player := _player()
	if player == null:
		return
	# 캐릭터를 바꾸면 새 플레이어로 다시 스폰된다(같은 자리, 같은 방향). 새 플레이어에도 캐릭터 화면 상태를 입히고
	# 카메라는 바로 원작 구도에 둔다.
	if not player.showcase:
		player.input_blocked = true
		player.showcase = true
		player.snap_showcase_camera()
	# 원작 구도는 캐릭터가 화면 가운데다. 소개 칸 왼쪽 빈 곳의 가운데에 보이게 옮긴다.
	var width := get_viewport_rect().size.x
	if width > 0.0:
		player.showcase_screen_shift = (_panel.get_global_rect().position.x * 0.5 - width * 0.5) / width
	var turn := 0.0
	if Input.is_physical_key_pressed(KEY_Q):
		turn -= 1.0
	if Input.is_physical_key_pressed(KEY_E):
		turn += 1.0
	player.showcase_yaw += turn * 1.6 * delta
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo:
		match key.physical_keycode:
			KEY_A, KEY_LEFT:
				cycle(-1)
			KEY_D, KEY_RIGHT:
				cycle(1)
			KEY_W:
				toggle_weapon()
			KEY_C, KEY_ESCAPE:
				close_screen()
		get_viewport().set_input_as_handled()
		return
	var button := event as InputEventMouseButton
	var player := _player()
	if button != null and player != null:
		if button.button_index == MOUSE_BUTTON_RIGHT:
			_dragging = button.pressed
		elif button.pressed and button.button_index == MOUSE_BUTTON_LEFT and not _panel.get_global_rect().has_point(button.position):
			poke()
		elif button.pressed and button.button_index == MOUSE_BUTTON_WHEEL_UP:
			player.zoom(-1)
		elif button.pressed and button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			player.zoom(1)
	var motion := event as InputEventMouseMotion
	if motion != null and _dragging and player != null:
		player.showcase_yaw -= motion.relative.x * 0.006


func _refresh() -> void:
	var player := _player()
	if player == null:
		return
	var character := Characters.find(player.character_id)
	var kit := player.kit
	_title_label.text = character.title
	_name_label.text = character.display_name
	_weapon_button.text = "무기 거두기 (W)" if player.showcase_weapon else "무기 보기 (W)"
	_description.text = character.description
	_stats.text = "체력 %d   공격력 %d   궁극기 에너지 %d" % [roundi(kit.max_health), roundi(kit.attack_power), roundi(kit.max_energy)]
	var lines: PackedStringArray = ["[왼쪽 클릭] 기본 공격 %d연속" % kit.basic_chain.size()]
	for attack: AttackData in [kit.basic_chain.back(), kit.dash_attack, kit.finisher, kit.plunge_start, kit.battle_skill, kit.ultimate]:
		if attack != null and not attack.description.is_empty():
			lines.append("%s\n    %s" % [attack.display_name, attack.description])
	_skills.text = "\n".join(lines)
	var characters := Characters.all()
	var index := 0
	for i in characters.size():
		if characters[i].id == player.character_id:
			index = i
	_index_label.text = "%d / %d" % [index + 1, characters.size()]


func _player() -> Player:
	return session.get_local_player() if session != null else null


static func _label(parent: Node, size: int, color: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("outline_size", 4)
	parent.add_child(label)
	return label
