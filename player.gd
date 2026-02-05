extends CharacterBody2D

# -------------------------
# Movement settings
# -------------------------
@export var walk_speed: float = 120.0
@export var run_speed: float = 220.0

# -------------------------
# State
# -------------------------
var move_dir: Vector2 = Vector2.ZERO
var last_facing_dir: Vector2 = Vector2.RIGHT
# -------- Sound settings
@export var footstep_interval_walk := 0.55
@export var footstep_interval_run := 0.28

@export var loudness_walk := 0.35
@export var loudness_run := 2.0

var _won := false

var _footstep_t := 0.0

# -------------------------
# Nodes
# -------------------------
@onready var flashlight: PointLight2D = $Flashlight
@onready var interaction_ray: RayCast2D = $InteractionRay

# -------------------------
# Physics loop
# -------------------------
func _physics_process(delta: float) -> void:
	if not _won and global_position.x >= 1935.0:
		_won = true
		win()
	handle_input()
	move_player()
	rotate_flashlight()
	rotate_interaction_ray()
	_emit_footsteps(delta)

# -------------------------
# Input
# -------------------------
func handle_input() -> void:
	move_dir = Vector2(
		Input.get_action_strength("right") - Input.get_action_strength("left"),
		Input.get_action_strength("down") - Input.get_action_strength("up")
	)

	if move_dir != Vector2.ZERO:
		move_dir = move_dir.normalized()
		last_facing_dir = move_dir

# -------------------------
# Movement
# -------------------------
func move_player() -> void:
	var speed := run_speed if Input.is_action_pressed("run") else walk_speed
	velocity = move_dir * speed
	move_and_slide()

# -------------------------
# Flashlight rotation
# -------------------------
func rotate_flashlight() -> void:
	flashlight.rotation = last_facing_dir.angle()

# -------------------------
# Interaction ray rotation
# -------------------------
func rotate_interaction_ray() -> void:
	interaction_ray.rotation = last_facing_dir.angle()

# -------------------------
# emit footsteps
# ------------------------- 
func _emit_footsteps(delta: float) -> void:
	if velocity.length() < 5.0:
		_footstep_t = 0.0
		return

	var running := Input.is_action_pressed("run")
	var interval: float = footstep_interval_run if running else footstep_interval_walk
	var loud: float = loudness_run if running else loudness_walk
	var kind: String = "run" if running else "walk"   # ✅ important

	_footstep_t += delta
	if _footstep_t >= interval:
		_footstep_t = 0.0
		SoundSystem.emit_sound(global_position, loud, kind, self)
	
func win() -> void:
	get_tree().paused = true
	print("YOU WIN")
