class_name Hud
extends CanvasLayer
## 게임 화면 위의 정보: 조준점과 명중 표시, 체력, 무기와 탄약, 피격 효과, 사망 화면, F3 디버그 표시,
## 상호작용 안내("F: 제압" 등), RAM, 스캔 화면, 퀵핵 업로드와 역해킹 경고.

const HIT_MARKER_TIME := 0.15
const HIT_COLOR := Color(1, 1, 1)
const HEADSHOT_COLOR := Color(1, 0.85, 0.2)
const KILL_COLOR := Color(1, 0.25, 0.25)
const CROSSHAIR_COLOR := Color(0.3, 0.95, 1, 0.9)

var session: Session

var _player: Player
var _last_health := -1.0
var _hit_marker_left := 0.0
var _damage_flash := 0.0
var _dead_time := 0.0
var _prompt_label: Label
var _ram_bar: ProgressBar
var _ram_label: Label
var _upload_label: Label
var _warning_label: Label
var _scan: ScanOverlay

@onready var crosshair: ColorRect = $Crosshair
@onready var hit_marker: Control = %HitMarker
@onready var debug_label: Label = %DebugLabel
@onready var health_bar: ProgressBar = %HealthBar
@onready var health_label: Label = %HealthLabel
@onready var weapon_label: Label = %WeaponLabel
@onready var ammo_label: Label = %AmmoLabel
@onready var damage_flash: ColorRect = %DamageFlash
@onready var death_overlay: Control = %DeathOverlay
@onready var death_label: Label = %DeathLabel


func _ready() -> void:
	# 조준점 바로 아래에 상호작용 안내를 띄운다.
	_prompt_label = Label.new()
	_prompt_label.name = "PromptLabel"
	_prompt_label.set_anchors_preset(Control.PRESET_CENTER)
	_prompt_label.offset_left = -200.0
	_prompt_label.offset_right = 200.0
	_prompt_label.offset_top = 36.0
	_prompt_label.offset_bottom = 70.0
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_label.add_theme_font_size_override("font_size", 22)
	_prompt_label.add_theme_color_override("font_color", Color(1, 0.9, 0.4))
	_prompt_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_prompt_label.add_theme_constant_override("outline_size", 6)
	add_child(_prompt_label)
	_build_hacking_hud()
	debug_label.hide()
	hit_marker.hide()
	death_overlay.hide()
	damage_flash.color.a = 0.0


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed(InputActions.DEBUG_OVERLAY):
		debug_label.visible = not debug_label.visible


func _process(delta: float) -> void:
	var player := session.get_local_player() if session != null else null
	if player != _player:
		_attach(player)
	if _player == null:
		return
	_update_health(delta)
	_update_weapon()
	_update_hit_marker(delta)
	_prompt_label.text = _player.interactor.prompt
	_update_hacking()
	if debug_label.visible:
		_update_debug()


func _build_hacking_hud() -> void:
	_scan = ScanOverlay.new()
	_scan.name = "ScanOverlay"
	add_child(_scan)
	# RAM 막대: 체력 막대 위
	# 왼쪽 아래 기준 위치(offset)로 둔다. position을 쓰면 화면 크기에 따라 엉뚱한 곳에 뜬다.
	_ram_label = _hud_label(20, Color(0.3, 0.95, 1))
	_ram_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_ram_label.offset_left = 24.0
	_ram_label.offset_right = 260.0
	_ram_label.offset_top = -122.0
	_ram_label.offset_bottom = -94.0
	_ram_bar = ProgressBar.new()
	_ram_bar.show_percentage = false
	_ram_bar.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_ram_bar.offset_left = 24.0
	_ram_bar.offset_right = 224.0
	_ram_bar.offset_top = -92.0
	_ram_bar.offset_bottom = -82.0
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.2, 0.85, 1)
	_ram_bar.add_theme_stylebox_override("fill", fill)
	add_child(_ram_bar)
	# 업로드 진행: 조준점 아래, 상호작용 안내보다 아래
	_upload_label = _hud_label(20, Color(0.3, 0.95, 1))
	_upload_label.set_anchors_preset(Control.PRESET_CENTER)
	_upload_label.offset_left = -300.0
	_upload_label.offset_right = 300.0
	_upload_label.offset_top = 80.0
	_upload_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# 역해킹 경고: 화면 위쪽 가운데
	_warning_label = _hud_label(26, Color(1, 0.25, 0.3))
	_warning_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_warning_label.offset_left = -400.0
	_warning_label.offset_right = 400.0
	_warning_label.offset_top = 60.0
	_warning_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func _hud_label(font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 6)
	add_child(label)
	return label


func _update_hacking() -> void:
	var deck := _player.cyberdeck
	_scan.player = _player
	_ram_bar.max_value = deck.max_ram
	_ram_bar.value = deck.ram
	_ram_label.text = "RAM %d / %d" % [floori(deck.ram), int(deck.max_ram)]
	if deck.upload_progress > 0.0:
		var filled := int(deck.upload_progress * 20.0)
		_upload_label.text = "업로드 중: %s  [%s%s]" % [deck.upload_label, "■".repeat(filled), "□".repeat(20 - filled)]
	else:
		_upload_label.text = ""
	if deck.incoming_progress > 0.0:
		_warning_label.text = "역해킹 감지! %d%%  — 넷러너의 시야에서 벗어나거나 공격하세요" % int(deck.incoming_progress * 100.0)
	else:
		_warning_label.text = ""


func _attach(player: Player) -> void:
	if _player != null and is_instance_valid(_player):
		_player.weapons.hit_confirmed.disconnect(_on_hit_confirmed)
	_player = player
	_last_health = -1.0
	if _player != null:
		_player.weapons.hit_confirmed.connect(_on_hit_confirmed)


func _update_health(delta: float) -> void:
	var health := _player.health
	health_bar.max_value = health.max_health
	health_bar.value = health.current
	health_label.text = "%d" % ceili(health.current)
	# 체력은 호스트에서 동기화되므로, 값이 줄어든 것을 보고 피격을 알아챈다.
	if _last_health >= 0.0 and health.current < _last_health:
		_damage_flash = clampf((_last_health - health.current) / 30.0, 0.25, 0.6)
	_last_health = health.current
	_damage_flash = move_toward(_damage_flash, 0.0, delta * 1.5)
	damage_flash.color.a = _damage_flash

	var dead := not health.is_alive()
	death_overlay.visible = dead
	crosshair.visible = not dead and not _player.free_look
	if dead:
		_dead_time += delta
		var left := maxf(Session.RESPAWN_DELAY - _dead_time, 0.0)
		death_label.text = "사망했습니다\n%d초 후 시작 지점에서 다시 시작합니다" % ceili(left)
	else:
		_dead_time = 0.0


func _update_weapon() -> void:
	var weapons := _player.weapons
	var weapon := weapons.current_weapon()
	weapon_label.text = "%d  %s" % [weapons.current_index + 1, weapon.display_name]
	if weapon.is_melee():
		ammo_label.text = "근접"
	elif weapons.reloading:
		ammo_label.text = "재장전 중..."
	else:
		ammo_label.text = "%d / %d" % [weapons.ammo_in_magazine(), weapon.magazine_size]


func _update_hit_marker(delta: float) -> void:
	_hit_marker_left -= delta
	hit_marker.visible = _hit_marker_left > 0.0


func _on_hit_confirmed(_position: Vector3, _amount: float, headshot: bool, killed: bool) -> void:
	_hit_marker_left = HIT_MARKER_TIME * (2.0 if killed else 1.0)
	var color := KILL_COLOR if killed else (HEADSHOT_COLOR if headshot else HIT_COLOR)
	hit_marker.modulate = color


func _update_debug() -> void:
	debug_label.text = "상태 %s | 속도 %.1f m/s | 웅크림 %s | FPS %d | 인원 %d" % [
		Player.State.keys()[_player.state],
		_player.horizontal_speed(),
		"예" if _player.crouched else "아니오",
		Engine.get_frames_per_second(),
		session.players.get_child_count(),
	]
