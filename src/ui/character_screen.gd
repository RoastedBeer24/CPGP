class_name CharacterScreen
extends Control
## 로비의 캐릭터 화면(C). 카메라가 원작 캐릭터 화면의 구도로 내 캐릭터를 비추고(Player.showcase), 오른쪽에
## 소개·무기·기술이 나온다. 캐릭터는 원작의 캐릭터 화면 동작으로 걸어 들어와 선다. 캐릭터를 누르면 반응하고,
## 무기 보기(W)를 누르면 무기를 꺼내 보여 준다(카메라도 원작의 무기 보기 구도로 옮겨 간다).
## 아래쪽에 고를 수 있는 캐릭터의 아이콘이 나란히 있다(오버워치 영웅 고르기처럼). 누르면 그 자리에서 새 캐릭터로
## 다시 나타난다(코옵에서도 모두에게 보인다). 무기는 원작처럼 그 캐릭터의 무기군 안에서 고른다.
## 휠로 얼굴 앞까지 다가가거나 물러나고, 마우스 오른쪽 버튼을 끌거나 Q·E로 캐릭터 둘레를 돈다.

signal closed

const PANEL_WIDTH := 460.0
## 캐릭터 아이콘 한 칸의 크기(px)
const ICON_SIZE := 96.0
const GOLD := Color(0.98, 0.84, 0.25)

var session: Session

var _name_label: Label
var _title_label: Label
var _description: Label
var _stats: Label
var _skills: Label
var _weapon_list: VBoxContainer
var _weapon_button: Button
var _panel: PanelContainer
var _roster: HBoxContainer
var _dragging := false
## 마지막으로 그린 캐릭터와 무기 (바뀔 때만 목록을 다시 만든다)
var _shown_character := &""
var _shown_weapon := &""


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
	style.border_color = Color(GOLD, 0.9)
	style.border_width_left = 3
	style.content_margin_left = 24.0
	style.content_margin_right = 24.0
	style.content_margin_top = 20.0
	style.content_margin_bottom = 20.0
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 8)
	panel.add_child(rows)
	_title_label = _label(rows, 16, GOLD)
	_name_label = _label(rows, 34, Color.WHITE)
	_description = _label(rows, 15, Color(0.85, 0.87, 0.9))
	_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_stats = _label(rows, 16, Color(0.7, 0.95, 0.75))
	var weapon_header := _label(rows, 16, GOLD)
	weapon_header.text = "무기"
	_weapon_list = VBoxContainer.new()
	_weapon_list.add_theme_constant_override("separation", 4)
	rows.add_child(_weapon_list)
	_weapon_button = Button.new()
	_weapon_button.custom_minimum_size = Vector2(0, 36)
	_weapon_button.pressed.connect(toggle_weapon)
	rows.add_child(_weapon_button)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	rows.add_child(scroll)
	_skills = _label(scroll, 14, Color(0.9, 0.9, 0.9))
	_skills.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_skills.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var close := Button.new()
	close.text = "닫기 (C / Esc)"
	close.custom_minimum_size = Vector2(0, 36)
	close.pressed.connect(close_screen)
	rows.add_child(close)
	# 아래쪽: 캐릭터 아이콘 줄(소개 칸 왼쪽 빈 곳의 가운데). 뒤에 아래로 갈수록 짙어지는 띠를 깐다.
	var band := TextureRect.new()
	var fade := Gradient.new()
	fade.set_color(0, Color(0, 0, 0, 0.0))
	fade.set_color(1, Color(0, 0, 0, 0.6))
	var fade_texture := GradientTexture2D.new()
	fade_texture.gradient = fade
	fade_texture.fill_from = Vector2(0, 0)
	fade_texture.fill_to = Vector2(0, 1)
	band.texture = fade_texture
	band.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	band.stretch_mode = TextureRect.STRETCH_SCALE
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	band.anchor_top = 1.0
	band.anchor_bottom = 1.0
	band.anchor_right = 1.0
	band.offset_top = -ICON_SIZE - 110.0
	add_child(band)
	_roster = HBoxContainer.new()
	_roster.alignment = BoxContainer.ALIGNMENT_CENTER
	_roster.add_theme_constant_override("separation", 14)
	_roster.anchor_top = 1.0
	_roster.anchor_bottom = 1.0
	_roster.anchor_right = 1.0
	_roster.offset_left = 32.0
	_roster.offset_right = -PANEL_WIDTH - 64.0
	_roster.offset_top = -ICON_SIZE - 64.0
	_roster.offset_bottom = -24.0
	add_child(_roster)
	var hint := _label(self, 15, Color(1, 1, 1, 0.7))
	hint.text = "아이콘을 눌러 캐릭터 바꾸기   캐릭터 누르기: 반응   W: 무기 보기   휠: 가까이·멀리   마우스 오른쪽 끌기 또는 Q·E: 둘러보기"
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
	_shown_character = &""
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


## 무기 보기를 켜거나 끈다: 캐릭터가 무기를 꺼내 보여 주고, 끄면 거둔다.
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


## 캐릭터를 고른다(아이콘을 누름). 그 자리에서 새 캐릭터로 다시 나타난다.
func choose(character_id: StringName) -> void:
	var player := _player()
	if player == null or player.character_id == character_id:
		return
	GameSettings.character_id = character_id
	GameSettings.save()
	session.request_character(character_id)


## 캐릭터를 앞(+1)이나 뒤(-1)로 바꾼다 (← → 키).
func cycle(step: int) -> void:
	var characters := Characters.all()
	var player := _player()
	if player == null or characters.is_empty():
		return
	var index := 0
	for i in characters.size():
		if characters[i].id == player.character_id:
			index = i
	choose(characters[wrapi(index + step, 0, characters.size())].id)


## 무기를 고른다(그 캐릭터의 무기군 안에서). 무기 보기 중이면 새 무기를 바로 보여 준다.
func choose_weapon(weapon_id: StringName) -> void:
	var player := _player()
	if player != null and player.set_weapon(weapon_id):
		_refresh()


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
			KEY_LEFT:
				cycle(-1)
			KEY_RIGHT:
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
		elif button.pressed and button.button_index == MOUSE_BUTTON_LEFT and not _panel.get_global_rect().has_point(button.position) \
				and not _roster.get_global_rect().has_point(button.position):
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
	_weapon_button.text = "무기 거두기 (W)" if player.showcase_weapon else "무기 보기 (W)"
	var weapon := player.weapon()
	var weapon_id := weapon.id if weapon != null else &""
	if character.id == _shown_character and weapon_id == _shown_weapon:
		return
	_shown_character = character.id
	_shown_weapon = weapon_id
	_title_label.text = character.title
	_name_label.text = character.display_name
	_description.text = character.description
	var attack := kit.attack_power * (1.0 + (weapon.attack_bonus if weapon != null else 0.0))
	_stats.text = "체력 %d   공격력 %d   궁극기 에너지 %d" % [roundi(kit.max_health), roundi(attack), roundi(kit.max_energy)]
	var lines: PackedStringArray = ["[왼쪽 클릭] 기본 공격 %d연속" % kit.basic_chain.size()]
	for skill: AttackData in [kit.basic_chain.back(), kit.dash_attack, kit.finisher, kit.plunge_start, kit.battle_skill, kit.ultimate]:
		if skill != null and not skill.description.is_empty():
			lines.append("%s\n    %s" % [skill.display_name, skill.description])
	_skills.text = "\n".join(lines)
	_build_weapons(character, weapon_id)
	_build_roster(character.id)


## 그 캐릭터의 무기군에 맞는 무기 목록. 지금 든 무기가 눌려 있다.
func _build_weapons(character: CharacterData, current: StringName) -> void:
	for child in _weapon_list.get_children():
		child.queue_free()
	for weapon in Weapons.of_type(character.weapon_type):
		var button := Button.new()
		button.toggle_mode = true
		button.button_pressed = weapon.id == current
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size = Vector2(0, 34)
		var bonus := "  공격력 +%d%%" % roundi(weapon.attack_bonus * 100.0) if weapon.attack_bonus > 0.0 else ""
		var equipped := "   (장착 중)" if weapon.id == current else ""
		button.text = "%s  %s%s%s" % ["★".repeat(weapon.rarity), weapon.display_name, bonus, equipped]
		button.tooltip_text = weapon.description
		button.add_theme_color_override("font_pressed_color", GOLD)
		button.add_theme_color_override("font_hover_pressed_color", GOLD)
		button.pressed.connect(choose_weapon.bind(weapon.id))
		_weapon_list.add_child(button)


## 아래쪽 캐릭터 아이콘 줄. 고른 캐릭터는 금색 테두리로 크게 보인다. 아이콘 그림이 없으면 이름 첫 글자를 쓴다.
func _build_roster(current: StringName) -> void:
	for child in _roster.get_children():
		child.queue_free()
	for character in Characters.all():
		var chosen := character.id == current
		var tile := VBoxContainer.new()
		tile.alignment = BoxContainer.ALIGNMENT_END
		tile.add_theme_constant_override("separation", 4)
		var button := Button.new()
		var side := ICON_SIZE * (1.12 if chosen else 1.0)
		button.custom_minimum_size = Vector2(side, side)
		button.tooltip_text = character.display_name
		button.focus_mode = Control.FOCUS_NONE
		var look := character.appearance()
		var icon := look.icon() if look != null else null
		# 초상화는 배경이 투명하고 머리카락이 어두워서 밝은 바탕에 얹는다(고른 캐릭터는 금빛 바탕).
		var frame := StyleBoxFlat.new()
		if icon != null:
			frame.bg_color = Color(0.98, 0.9, 0.62) if chosen else Color(0.78, 0.8, 0.84)
		else:
			frame.bg_color = Color(0.1, 0.11, 0.14, 0.9)
		frame.border_color = GOLD if chosen else Color(1, 1, 1, 0.35)
		frame.set_border_width_all(4 if chosen else 2)
		frame.set_corner_radius_all(8)
		for state: String in ["normal", "hover", "pressed", "focus"]:
			button.add_theme_stylebox_override(state, frame)
		if icon != null:
			var picture := TextureRect.new()
			picture.texture = icon
			picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			picture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			picture.offset_left = 4
			picture.offset_top = 4
			picture.offset_right = -4
			picture.offset_bottom = -4
			picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
			button.add_child(picture)
		else:
			button.text = character.display_name.left(1)
			button.add_theme_font_size_override("font_size", 40)
		button.pressed.connect(choose.bind(character.id))
		tile.add_child(button)
		var caption := _label(tile, 15, GOLD if chosen else Color(1, 1, 1, 0.85))
		caption.text = character.display_name
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_roster.add_child(tile)


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
