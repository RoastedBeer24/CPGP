class_name TrainingDummy
extends StaticBody3D
## 사격 연습용 허수아비. 머리와 몸통 판정이 있고, 쓰러지면 잠시 뒤 되살아난다.
## 판정과 부활은 호스트가 하고, 체력은 동기화된다.

@export var max_health := 100.0
@export var armor := 0.0
@export var respawn_delay := 2.0

var _respawn_left := 0.0

@onready var health: Health = $Health
@onready var body_mesh: Node3D = $Body
@onready var label: Label3D = $HealthLabel
@onready var hitboxes: Array[Hitbox] = [$HeadHitbox, $BodyHitbox]


func _ready() -> void:
	health.max_health = max_health
	health.armor = armor
	health.current = max_health
	health.died.connect(_on_died)
	health.revived.connect(_on_revived)


func _process(delta: float) -> void:
	label.text = "%d / %d%s" % [ceili(health.current), roundi(max_health), "  장갑 %d" % roundi(armor) if armor > 0.0 else ""]
	if _respawn_left > 0.0 and multiplayer.is_server():
		_respawn_left -= delta
		if _respawn_left <= 0.0:
			health.revive()


func _on_died(_info: DamageInfo) -> void:
	body_mesh.visible = false
	for hitbox in hitboxes:
		hitbox.set_deferred("collision_layer", 0)
	if multiplayer.is_server():
		_respawn_left = respawn_delay


func _on_revived() -> void:
	body_mesh.visible = true
	for hitbox in hitboxes:
		hitbox.set_deferred("collision_layer", Hitbox.LAYER)
