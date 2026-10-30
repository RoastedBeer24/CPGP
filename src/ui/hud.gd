class_name Hud
extends CanvasLayer
## 게임 화면 위의 정보. 코드로 만든다.
##   - 왼쪽 아래: 내 캐릭터 이름과 체력
##   - 오른쪽 아래: SP(100마다 한 칸, 세 칸), 배틀 스킬, 궁극기 에너지, 회피 안내
##   - 위 가운데: 웨이브와 남은 적, 큰 알림(웨이브 시작, 완벽한 회피, 경직, 방 정리, 전멸)
##   - 왼쪽 위: 동료의 체력(쓰러지면 일으킨 정도)
##   - 적 머리 위: 체력과 경직 게이지, 원석 결정 표시, 경직되면 처형 안내 (HudOverlay가 그린다)
##   - 맞으면 화면 가장자리가 붉게 번쩍인다. F3은 디버그 정보.

const HP_COLOR := Color(0.4, 0.92, 0.5)
const HP_LOW_COLOR := Color(0.96, 0.32, 0.26)
const SP_COLOR := Color(0.98, 0.82, 0.2)
const ENERGY_COLOR := Color(0.45, 0.85, 1.0)
const DIM_COLOR := Color(1, 1, 1, 0.35)
const BANNER_TIME := 2.0
const SP_SEGMENT := 100.0

var session: Session

var name_label: Label
var health_label: Label
var health_bar: ProgressBar
var sp_bars: Array[ProgressBar] = []
var skill_label: Label
var ultimate_label: Label
var ultimate_bar: ProgressBar
var wave_label: Label
var banner_label: Label
var prompt_label: Label
var down_label: Label
var debug_label: Label
var damage_flash: ColorRect
var team_box: VBoxContainer
var overlay: HudOverlay

var _player: Player
var _room: CombatRoom
var _banner_left := 0.0
var _flash := 0.0
var _team_rows: Dictionary[Player, Array] = {}


func _ready() -> void:
	damage_flash = ColorRect.new()
	damage_flash.name = "DamageFlash"
	damage_flash.color = Color(0.9, 0.1, 0.05, 0.0)
	damage_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	damage_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(damage_flash)

	overlay = HudOverlay.new()
	overlay.name = "Overlay"
	overlay.hud = self
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay)

	# 왼쪽 아래: 이름과 체력
	var health_box := VBoxContainer.new()
	health_box.name = "HealthBox"
	health_box.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	health_box.position = Vector2(32, -110)
	health_box.custom_minimum_size = Vector2(340, 0)
	add_child(health_box)
	health_box.anchor_top = 1.0
	health_box.anchor_bottom = 1.0
	health_box.offset_top = -100.0
	health_box.offset_left = 32.0
	name_label = _label(22, Color(1, 1, 1))
	health_box.add_child(name_label)
	health_bar = _bar(Vector2(340, 16), HP_COLOR)
	health_box.add_child(health_bar)
	health_label = _label(18, Color(0.9, 0.95, 0.9))
	health_box.add_child(health_label)

	# 오른쪽 아래: SP, 스킬, 궁극기
	var skill_box := VBoxContainer.new()
	skill_box.name = "SkillBox"
	skill_box.anchor_left = 1.0
	skill_box.anchor_right = 1.0
	skill_box.anchor_top = 1.0
	skill_box.anchor_bottom = 1.0
	skill_box.offset_left = -360.0
	skill_box.offset_right = -32.0
	skill_box.offset_top = -150.0
	skill_box.offset_bottom = -24.0
	skill_box.alignment = BoxContainer.ALIGNMENT_END
	add_child(skill_box)
	var sp_row := HBoxContainer.new()
	sp_row.add_theme_constant_override("separation", 6)
	skill_box.add_child(sp_row)
	for i in 3:
		var segment := _bar(Vector2(104, 10), SP_COLOR)
		segment.max_value = SP_SEGMENT
		sp_row.add_child(segment)
		sp_bars.append(segment)
	skill_label = _label(20, Color(1, 1, 1))
	skill_box.add_child(skill_label)
	ultimate_label = _label(20, Color(1, 1, 1))
	skill_box.add_child(ultimate_label)
	ultimate_bar = _bar(Vector2(0, 8), ENERGY_COLOR)
	skill_box.add_child(ultimate_bar)
	var hint := _label(15, Color(1, 1, 1, 0.65))
	hint.text = "클릭 공격 · Shift 회피 · 휠 클릭 대상 고정"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	skill_box.add_child(hint)

	# 위 가운데: 웨이브와 큰 알림
	wave_label = _label(22, Color(1, 1, 1))
	wave_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	wave_label.offset_left = -300.0
	wave_label.offset_right = 300.0
	wave_label.offset_top = 18.0
	wave_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(wave_label)
	banner_label = _label(40, Color(1, 0.86, 0.3))
	banner_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	banner_label.offset_left = -500.0
	banner_label.offset_right = 500.0
	banner_label.offset_top = 120.0
	banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(banner_label)

	# 가운데 아래: 동료 일으키기 안내
	prompt_label = _label(22, Color(1, 0.9, 0.4))
	prompt_label.set_anchors_preset(Control.PRESET_CENTER)
	prompt_label.offset_left = -300.0
	prompt_label.offset_right = 300.0
	prompt_label.offset_top = 90.0
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(prompt_label)
	down_label = _label(30, Color(1, 0.5, 0.45))
	down_label.set_anchors_preset(Control.PRESET_CENTER)
	down_label.offset_left = -500.0
	down_label.offset_right = 500.0
	down_label.offset_top = -40.0
	down_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(down_label)

	# 왼쪽 위: 동료
	team_box = VBoxContainer.new()
	team_box.name = "TeamBox"
	team_box.position = Vector2(24, 24)
	add_child(team_box)

	debug_label = _label(16, Color(0.8, 1, 0.8))
	debug_label.position = Vector2(24, 160)
	debug_label.visible = false
	add_child(debug_label)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(InputActions.DEBUG_OVERLAY):
		debug_label.visible = not debug_label.visible


func local_player() -> Player:
	return _player


func room() -> CombatRoom:
	return _room


func show_banner(text: String) -> void:
	banner_label.text = text
	_banner_left = BANNER_TIME


func _process(delta: float) -> void:
	_bind()
	_banner_left = maxf(_banner_left - delta, 0.0)
	banner_label.modulate.a = clampf(_banner_left / 0.4, 0.0, 1.0)
	_flash = maxf(_flash - delta * 2.5, 0.0)
	damage_flash.color.a = _flash * 0.35
	if _player == null:
		return
	_update_self()
	_update_room()
	_update_team()
	_update_prompt()
	if debug_label.visible:
		debug_label.text = "FPS %d\n상태 %s  동작 %s\n속도 %.1f  SP %.0f  에너지 %.0f\n몸 %s" % [
			Engine.get_frames_per_second(), Player.State.keys()[_player.state], _player.action_id,
			_player.horizontal_speed(), _player.sp, _player.energy, _player.body.dominant_animation()]
	overlay.queue_redraw()


## 내 플레이어와 전투 방을 찾고 신호를 잇는다(새 판마다 바뀐다).
func _bind() -> void:
	var mine := session.get_local_player() if session != null else null
	if mine != _player:
		_player = mine
		if _player != null:
			_player.perfect_dodged.connect(func() -> void: show_banner("완벽한 회피!"))
			_player.got_hit.connect(_on_got_hit)
			_player.skill_denied.connect(func(reason: String) -> void: show_banner(reason))
			_player.hit_confirmed.connect(_on_hit_confirmed)
			var character := Characters.find(_player.character_id)
			name_label.text = character.display_name if character != null else ""
	var zone := session.zone() as CombatRoom if session != null else null
	if zone != _room:
		_room = zone
		if _room != null:
			_room.phase_changed.connect(_on_phase_changed)


func _update_self() -> void:
	var health := _player.health
	health_bar.max_value = health.max_health
	health_bar.value = health.current
	_tint(health_bar, HP_LOW_COLOR if health.ratio() < 0.3 else HP_COLOR)
	health_label.text = "%d / %d" % [ceili(health.current), roundi(health.max_health)]
	var kit := _player.kit
	for i in sp_bars.size():
		sp_bars[i].value = clampf(_player.sp - SP_SEGMENT * i, 0.0, SP_SEGMENT)
	var skill_cost := kit.battle_skill.sp_cost if kit.battle_skill != null else 0.0
	var skill_ready := _player.sp >= skill_cost
	skill_label.text = "[1] %s   SP %d" % [kit.battle_skill.display_name if kit.battle_skill != null else "", roundi(skill_cost)]
	skill_label.modulate = Color.WHITE if skill_ready else DIM_COLOR
	ultimate_bar.max_value = kit.max_energy
	ultimate_bar.value = _player.energy
	var ready := _player.ultimate_ready()
	ultimate_label.text = "[Q / 1 길게] %s   %s" % [kit.ultimate.display_name if kit.ultimate != null else "",
		"준비됨!" if ready else "%d%%" % roundi(100.0 * _player.energy / maxf(kit.max_energy, 1.0))]
	ultimate_label.modulate = Color(1, 0.9, 0.45) if ready else Color.WHITE
	if not _player.is_alive():
		down_label.text = "쓰러졌습니다" + ("\n동료가 일으켜 줄 때까지 기다리세요 (%d%%)" % roundi(_player.health.revive_progress * 100.0) if not _solo() else "")
	else:
		down_label.text = ""


func _update_room() -> void:
	if _room == null:
		wave_label.text = ""
		return
	match _room.phase:
		CombatRoom.Phase.WAITING:
			wave_label.text = "전투 준비"
		CombatRoom.Phase.FIGHTING, CombatRoom.Phase.BETWEEN:
			wave_label.text = "웨이브 %d / %d   ·   남은 적 %d" % [_room.wave, _room.wave_count(), _room.enemies_left]
		CombatRoom.Phase.CLEARED:
			wave_label.text = "방 정리 완료"
		CombatRoom.Phase.FAILED:
			wave_label.text = "전멸"


func _update_team() -> void:
	var mates: Array[Player] = []
	for mate in Roster.players(_player):
		if mate != _player:
			mates.append(mate)
	for mate: Player in _team_rows.keys():
		if not mates.has(mate) or not is_instance_valid(mate):
			for control: Control in _team_rows[mate]:
				control.queue_free()
			_team_rows.erase(mate)
	for mate in mates:
		if not _team_rows.has(mate):
			var label := _label(16, Color.WHITE)
			var bar := _bar(Vector2(200, 8), HP_COLOR)
			team_box.add_child(label)
			team_box.add_child(bar)
			_team_rows[mate] = [label, bar]
		var row: Array = _team_rows[mate]
		var label := row[0] as Label
		var bar := row[1] as ProgressBar
		var character := Characters.find(mate.character_id)
		var name := character.display_name if character != null else "동료"
		if mate.is_alive():
			label.text = name
			bar.max_value = mate.health.max_health
			bar.value = mate.health.current
			_tint(bar, HP_COLOR)
		else:
			label.text = "%s — 쓰러짐 (일으키기 %d%%)" % [name, roundi(mate.health.revive_progress * 100.0)]
			bar.max_value = 1.0
			bar.value = mate.health.revive_progress
			_tint(bar, SP_COLOR)


func _update_prompt() -> void:
	var downed := _downed_mate_nearby()
	if downed != null and _player.is_alive():
		prompt_label.text = "[F] 누르고 있으면 동료를 일으킵니다 (%d%%)" % roundi(downed.health.revive_progress * 100.0)
	else:
		prompt_label.text = ""


func _downed_mate_nearby() -> Player:
	for mate in Roster.players(_player):
		if mate != _player and not mate.is_alive() and mate.global_position.distance_to(_player.global_position) <= Player.REVIVE_RANGE:
			return mate
	return null


func _solo() -> bool:
	return session != null and session.mode == Session.Mode.SINGLE


func _on_got_hit(heavy: bool) -> void:
	_flash = 1.0 if heavy else 0.6


func _on_hit_confirmed(_position: Vector3, _amount: float, flags: int) -> void:
	if flags & Player.HIT_SHATTER:
		show_banner("결정 파쇄!")
	elif flags & Player.HIT_BREAK:
		show_banner("경직! 가까이서 공격하면 처형")


func _on_phase_changed(phase: CombatRoom.Phase) -> void:
	match phase:
		CombatRoom.Phase.FIGHTING:
			show_banner("웨이브 %d" % _room.wave)
		CombatRoom.Phase.CLEARED:
			show_banner("방 정리 완료!")
		CombatRoom.Phase.FAILED:
			show_banner("전멸 — 잠시 뒤 처음부터 다시 합니다")


static func _label(size: int, color: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("outline_size", 6)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


static func _bar(size: Vector2, color: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.custom_minimum_size = size
	bar.show_percentage = false
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var back := StyleBoxFlat.new()
	back.bg_color = Color(0, 0, 0, 0.55)
	back.set_corner_radius_all(2)
	bar.add_theme_stylebox_override("background", back)
	_tint(bar, color)
	return bar


static func _tint(bar: ProgressBar, color: Color) -> void:
	var fill := bar.get_theme_stylebox("fill") as StyleBoxFlat
	if fill == null or not bar.has_theme_stylebox_override("fill"):
		fill = StyleBoxFlat.new()
		fill.set_corner_radius_all(2)
		bar.add_theme_stylebox_override("fill", fill)
	fill.bg_color = color
