extends Node2D
class_name Door

@export var open_speed: float = 10.0
@export var locked: bool = false
@export var starts_open: bool = false
@export var play_sfx: bool = true
@export var door_width_px := 8.0
@export var open_angle_deg := 90.0

@onready var hinge: Node2D = $Hinge
@onready var door_col: CollisionShape2D = $Hinge/DoorBody/DoorCollision
@onready var area: Area2D = $Hinge/InteractArea
@onready var occluder: LightOccluder2D = $Hinge/DoorOccluder
@onready var sfx: AudioStreamPlayer2D = $DoorSfx if has_node("DoorSfx") else null

var is_open := false
var _target_rot := 0.0
var _player_in_range := false
var _last_interactor: Node2D = null

func _ready() -> void:
	area.body_entered.connect(_on_area_body_entered)
	area.body_exited.connect(_on_area_body_exited)
	is_open = starts_open
	_target_rot = hinge.rotation if is_open else 0.0
	_apply_collision_and_light()
	hinge.rotation = _target_rot

func _process(delta: float) -> void:
	hinge.rotation = lerp_angle(hinge.rotation, _target_rot, open_speed * delta)

func _unhandled_input(event: InputEvent) -> void:
	if locked or not _player_in_range:
		return
	if event.is_action_pressed("interact"):
		toggle(_last_interactor)

func _on_area_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		_player_in_range = true
		_last_interactor = body

func _on_area_body_exited(body: Node) -> void:
	if body.is_in_group("player") and body == _last_interactor:
		_player_in_range = false
		_last_interactor = null

func toggle(interactor: Node2D) -> void:
	if is_open:
		close(interactor)
	else:
		open_away_from(interactor)
	_emit_door_sound_only_if_player(interactor)

func open_away_from(interactor: Node2D) -> void:
	if locked or interactor == null or is_open:
		return

	is_open = true
	var local_normal := Vector2.RIGHT
	var global_normal := global_transform.basis_xform(local_normal).normalized()
	var to_interactor := (interactor.global_position - hinge.global_position).normalized()
	var s := signf(global_normal.dot(to_interactor))
	if s == 0: s = 1
	_target_rot = deg_to_rad(open_angle_deg * s)

	_apply_collision_and_light()
	_emit_door_sound_only_if_player(interactor)

func close(interactor: Node2D = null) -> void:
	if not is_open:
		return
	is_open = false
	_target_rot = 0.0
	_apply_collision_and_light()
	_emit_door_sound_only_if_player(interactor)

func _apply_collision_and_light() -> void:
	if door_col:
		door_col.set_deferred("disabled", is_open)
	if occluder:
		occluder.visible = not is_open
	if play_sfx and sfx and sfx.stream:
		sfx.play()

func _emit_door_sound_only_if_player(interactor: Node) -> void:
	if interactor != null and interactor.is_in_group("player"):
		SoundSystem.emit_sound(global_position, 2.0, "door", interactor)
