class_name RewardPanel
extends Control
## 방을 깬 뒤 보상(강화) 고르기. 카드 세 장 중 하나를 누르거나 1·2·3 키로 고른다.
## 고르는 동안에는 캐릭터가 움직이지 않는다(1 키가 배틀 스킬로 나가지 않게).

signal chosen(reward: RewardData)

const CARD_SIZE := Vector2(300, 190)

var _cards: Array[Button] = []
var _offers: Array[RewardData] = []
var _title: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.45)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 24)
	center.add_child(rows)
	_title = Label.new()
	_title.text = "보상을 하나 고르세요 (1 · 2 · 3)"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 30)
	_title.add_theme_color_override("font_color", Color(0.98, 0.84, 0.25))
	rows.add_child(_title)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	rows.add_child(row)
	for i in 3:
		var card := Button.new()
		card.custom_minimum_size = CARD_SIZE
		card.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		card.add_theme_font_size_override("font_size", 20)
		card.pressed.connect(_choose.bind(i))
		row.add_child(card)
		_cards.append(card)


## 후보를 보여 준다.
func show_offers(offers: Array[RewardData]) -> void:
	_offers = offers
	for i in _cards.size():
		var card := _cards[i]
		card.visible = i < offers.size()
		if card.visible:
			card.text = "%d. %s\n\n%s" % [i + 1, offers[i].title, offers[i].description]
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.physical_keycode:
		KEY_1:
			_choose(0)
		KEY_2:
			_choose(1)
		KEY_3:
			_choose(2)
		_:
			return
	get_viewport().set_input_as_handled()


func _choose(index: int) -> void:
	if not visible or index >= _offers.size():
		return
	visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	chosen.emit(_offers[index])
