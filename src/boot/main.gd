extends Node
## 부팅 씬. 지금은 프로젝트 이름과 버전만 보여 주며, M1에서 메인 메뉴로 바뀐다.

var title_label: Label


func _ready() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	title_label = Label.new()
	title_label.text = "%s  v%s" % [
		ProjectSettings.get_setting("application/config/name"),
		ProjectSettings.get_setting("application/config/version"),
	]
	title_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	title_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	title_label.grow_vertical = Control.GROW_DIRECTION_BOTH
	title_label.add_theme_font_size_override("font_size", 48)
	layer.add_child(title_label)
