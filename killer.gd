extends CharacterBody2D
class_name Killer

@export var speed_patrol := 90.0
@export var speed_investigate := 120.0
@export var speed_chase := 170.0

# Hearing
@export var react_threshold := 0.008
@export var memory_time := 4.0

# Vision / Chase
@export var vision_range := 220.0
@export var chase_lost_time := 1.2

# Search
@export var search_radius := 90.0
@export var search_points := 6

# Door handling
@export var door_open_distance := 70.0
@export var door_open_cooldown := 0.35

var _stuck_time: float = 0.0
var _last_pos: Vector2 = Vector2.ZERO

@export var arrive_slow_radius: float = 36.0   # slow down near corners/targets
@export var stuck_seconds: float = 0.35        # how long before we call it "stuck"
@export var stuck_move_eps: float = 1.0        # pixels moved to count as "moving"

@onready var agent: NavigationAgent2D = $NavigationAgent2D
@onready var head: Node2D = $Head
@onready var vision_ray: RayCast2D = $Head/VisionRay
@onready var door_ray: RayCast2D = $DoorRay

enum State { PATROL, INVESTIGATE, SEARCH, CHASE }
var state: State = State.PATROL

var player: Node2D = null

var last_heard_pos := Vector2.ZERO
var last_heard_strength := 0.0
var heard_timer := 0.0
var chase_timer := 0.0
@export var memory_decay_per_sec: float = 0.8   # 0.4~0.8 good
@export var min_switch_ratio: float = 0.55       # new sound must be >= 55% of current memory
@export var door_priority: float = 2000.0
@export var run_priority: float = 2000.0
@export var walk_priority: float = 10.0


var _search_pts: Array[Vector2] = []
var _search_index := 0

var _door_cd := 0.0

func _on_catch(body: Node) -> void:
	print("Caught:", body.name, "groups:", body.get_groups())
	if body.is_in_group("player_"):
		game_over()

func game_over() -> void:
	get_tree().paused = true
	print("GAME OVER")


func _ready() -> void:
	add_to_group("killer")
	player = get_tree().get_first_node_in_group("player_") as Node2D
	
	# Smooth navigation for 1-tile hallways (8px)
	agent.path_desired_distance = 6.0
	agent.target_desired_distance = 8.0


	$CatchArea.body_entered.connect(_on_catch)
	
	# Vision ray length
	vision_ray.target_position = Vector2(vision_range, 0)

	# Sound bus
	SoundSystem.sound_emitted.connect(_on_sound)

func _physics_process(delta: float) -> void:
	_update_timers(delta)
	_update_vision()
	_update_state()
	_update_head(delta)

	_try_open_door()      # now opens even during chase
	_move(delta)               # clamped movement prevents wall-sticking

# ---------------------------
# Timers
# ---------------------------
func _update_timers(delta: float) -> void:
	if heard_timer > 0.0:
		heard_timer = max(heard_timer - delta, 0.0)
	if chase_timer > 0.0:
		chase_timer = max(chase_timer - delta, 0.0)
	if _door_cd > 0.0:
		_door_cd = max(_door_cd - delta, 0.0)

	# decay hearing “confidence” so new sounds can override old ones
	if last_heard_strength > 0.0:
		last_heard_strength = max(0.0, last_heard_strength - memory_decay_per_sec * delta)


# ---------------------------
# Hearing
# ---------------------------
func _on_sound(pos: Vector2, loud: float, kind: String, src: Node) -> void:
	if src == self:
		return

	var d: float = global_position.distance_to(pos)

	# Priority by kind (use your variables)
	var priority: float = walk_priority
	if kind == "door":
		priority = door_priority
	elif kind == "run":
		priority = run_priority
	elif kind == "walk":
		priority = walk_priority
	elif kind == "footstep":
		# if you still emit "footstep", treat it like walk (or change your player to emit run/walk)
		priority = walk_priority

	# Perceived loudness with priority weight
	var perceived: float = (loud * priority) / (d * d + 1.0)
	
	# DEBUG PRINT
	print("HEAR kind=", kind,
		" loud=", loud,
		" d=", d,
		" perceived=", "%.8f" % perceived,
		" react_threshold=", "%.8f" % react_threshold,
		" loud_type=", typeof(loud)
	)
		
	# Threshold: only then do we "care" and leave patrol/search
	if perceived < react_threshold:
		return

	# Latest valid sound always wins (no comparison to last sound)
	last_heard_pos = pos
	last_heard_strength = perceived
	heard_timer = memory_time

	# If currently SEEING player, stay in chase, but keep last_heard_pos as backup
	if state == State.CHASE and chase_timer > 0.0:
		return

	# Interrupt search immediately and investigate newest sound
	_search_pts.clear()
	_search_index = 0

	state = State.INVESTIGATE
	agent.target_position = last_heard_pos


# ---------------------------
# Vision (LoS)
# ---------------------------
func _update_vision() -> void:
	if player == null:
		return

	var to_p := player.global_position - global_position
	if to_p.length() < 2.0:
		return

	head.rotation = to_p.angle()
	vision_ray.force_raycast_update()

	var sees := false
	if vision_ray.is_colliding():
		var c := vision_ray.get_collider()
		if c and c.is_in_group("player"):
			sees = true

	if sees:
		state = State.CHASE
		chase_timer = chase_lost_time
		agent.target_position = player.global_position
	elif state == State.CHASE and chase_timer > 0.0:
		agent.target_position = player.global_position

# ---------------------------
# State machine
# ---------------------------
func _update_state() -> void:
	match state:
		State.PATROL:
			# If we have a recent valid sound, investigate it
			if heard_timer > 0.0:
				state = State.INVESTIGATE
				agent.target_position = last_heard_pos
			elif agent.is_navigation_finished():
				agent.target_position = _random_nav()

		State.INVESTIGATE:
			# If we reached the sound source, start searching around it
			if agent.is_navigation_finished():
				_start_search()

			# If memory expires while investigating, go back to patrol
			if heard_timer <= 0.0:
				state = State.PATROL
				last_heard_strength = 0.0

		State.SEARCH:
			# If memory expires during search, stop searching and patrol
			if heard_timer <= 0.0:
				state = State.PATROL
				last_heard_strength = 0.0
				return

			# Otherwise follow search points
			if agent.is_navigation_finished():
				_search_index += 1
				if _search_index >= _search_pts.size():
					# Finished the loop, but if sound memory still exists, re-investigate center
					state = State.INVESTIGATE
					agent.target_position = last_heard_pos
				else:
					agent.target_position = _search_pts[_search_index]

		State.CHASE:
			# If chase timer expired, ALWAYS investigate last valid sound if exists
			if chase_timer <= 0.0:
				if heard_timer > 0.0:
					state = State.INVESTIGATE
					agent.target_position = last_heard_pos
				else:
					state = State.PATROL


# ---------------------------
# Head (hearing direction)
# ---------------------------
func _update_head(delta: float) -> void:
	var target := head.rotation

	if state == State.CHASE and player:
		target = (player.global_position - global_position).angle()
	elif (state == State.INVESTIGATE or state == State.SEARCH) and heard_timer > 0.0:
		target = (last_heard_pos - global_position).angle()
	elif velocity.length() > 5.0:
		target = velocity.angle()

	head.rotation = lerp_angle(head.rotation, target, 8.0 * delta)

# ---------------------------
# Door opening (reliable)
# ---------------------------
func _try_open_door(force: bool = false) -> void:
	# If your DoorRay is a child of Killer, its cast is in LOCAL space.
	# We'll compute a good GLOBAL direction and convert it to local.

	var dir_global: Vector2 = Vector2.ZERO

	# 1) Prefer navigation direction (works even if velocity is low)
	if not agent.is_navigation_finished():
		var next_pos: Vector2 = agent.get_next_path_position()
		var to_next: Vector2 = next_pos - global_position
		if to_next.length() > 0.5:
			dir_global = to_next.normalized()

	# 2) If chasing and nav is weird, try directly toward player
	if dir_global == Vector2.ZERO and state == State.CHASE and player:
		var to_p: Vector2 = player.global_position - global_position
		if to_p.length() > 0.5:
			dir_global = to_p.normalized()

	# 3) Fallback to current velocity direction
	if dir_global == Vector2.ZERO and velocity.length() > 0.5:
		dir_global = velocity.normalized()

	# Nothing to do
	if dir_global == Vector2.ZERO:
		return

	# Don't spam door opening unless forced or we're trying to move
	if not force and velocity.length() < 5.0 and state != State.CHASE:
		return

	# ---- IMPORTANT: start the ray a bit forward so it doesn't start inside our collider ----
	# If DoorRay is positioned at (0,0), set it in the editor to be slightly in front of the killer
	# OR we can do it here by moving the ray node temporarily.
	# We'll do it here safely:
	var ray_offset_forward: float = 10.0
	door_ray.position = dir_global * ray_offset_forward

	# Convert global dir to DoorRay local target_position
	var dir_local: Vector2 = door_ray.global_transform.basis_xform_inv(dir_global).normalized()
	door_ray.target_position = dir_local * door_open_distance
	door_ray.force_raycast_update()

	if not door_ray.is_colliding():
		return

	var col: Object = door_ray.get_collider()
	if col == null:
		return

	# Walk up parents until we find Door
	var n: Node = col as Node
	while n != null and not (n is Door):
		n = n.get_parent()

	if n is Door:
		var d: Door = n
		if not d.is_open:
			d.open_away_from(self)

# ---------------------------
# Movement (clamped to avoid wall sticking)
# ---------------------------
func _move(delta: float) -> void:
	# ---------------------------
	# Pick speed by state
	# ---------------------------
	var max_speed: float = speed_patrol
	if state == State.INVESTIGATE or state == State.SEARCH:
		max_speed = speed_investigate
	elif state == State.CHASE:
		max_speed = speed_chase

	# ---------------------------
	# No path → stop cleanly
	# ---------------------------
	if agent.is_navigation_finished():
		velocity = Vector2.ZERO
		move_and_slide()
		_reset_stuck()
		return

	# ---------------------------
	# Steering target
	# ---------------------------
	var next_pos: Vector2 = agent.get_next_path_position()
	var to_next: Vector2 = next_pos - global_position
	var dist: float = to_next.length()

	if dist < 0.8:
		velocity = Vector2.ZERO
		move_and_slide()
		_reset_stuck()
		return

	# ---------------------------
	# ARRIVE behavior (corner-safe)
	# ---------------------------
	var desired_speed: float = max_speed
	if dist < arrive_slow_radius:
		desired_speed = max_speed * (dist / arrive_slow_radius)
		desired_speed = clamp(desired_speed, 30.0, max_speed)

	var desired_vel: Vector2 = (to_next / dist) * desired_speed

	# ---------------------------
	# Apply velocity
	# ---------------------------
	if agent.avoidance_enabled:
		agent.set_velocity(desired_vel)
		velocity = agent.get_velocity()
	else:
		velocity = desired_vel

	move_and_slide()

	# ---------------------------
	# STUCK DETECTION
	# ---------------------------
	var moved: float = global_position.distance_to(_last_pos)
	_last_pos = global_position

	if desired_speed > 40.0 and moved < stuck_move_eps:
		_stuck_time += delta
	else:
		_stuck_time = 0.0

	if _stuck_time >= stuck_seconds:
		_handle_stuck()



# ---------------------------
# Helpers
# ---------------------------
func _start_search() -> void:
	state = State.SEARCH
	_search_pts.clear()
	_search_index = 0

	var nav_map: RID = agent.get_navigation_map()
	var center: Vector2 = last_heard_pos

	for i in range(search_points):
		var a: float = TAU * float(i) / float(search_points)
		var raw: Vector2 = center + Vector2(cos(a), sin(a)) * search_radius
		_search_pts.append(NavigationServer2D.map_get_closest_point(nav_map, raw))

	_search_pts.append(NavigationServer2D.map_get_closest_point(nav_map, center))
	agent.target_position = _search_pts[0]



func _random_nav() -> Vector2:
	return global_position + Vector2(randf_range(-200, 200), randf_range(-200, 200))

func _reset_stuck() -> void:
	_stuck_time = 0.0
	_last_pos = global_position


func _handle_stuck() -> void:
	_stuck_time = 0.0

	# Try opening door EVEN if barely moving
	_try_open_door(true)

	# Small lateral nudge to escape corner lock
	var side := Vector2(-velocity.y, velocity.x).normalized()
	global_position += side * 1.5

	# Hard repath (this actually forces a recompute)
	if state == State.CHASE and player:
		agent.target_position = player.global_position
	elif state == State.INVESTIGATE:
		agent.target_position = last_heard_pos
	else:
		agent.target_position = agent.target_position + Vector2(randf_range(-4,4), randf_range(-4,4))
