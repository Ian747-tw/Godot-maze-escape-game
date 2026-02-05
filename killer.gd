extends CharacterBody2D
class_name Killer

enum State { PATROL, INVESTIGATE, SEARCH, CHASE }

@export var speed_patrol := 90.0
@export var speed_investigate := 120.0
@export var speed_chase := 170.0
@export var react_threshold := 0.008
@export var memory_time := 4.0
@export var vision_range := 220.0
@export var chase_lost_time := 1.2
@export var search_radius := 90.0
@export var search_points := 6
@export var door_open_distance := 70.0
@export var door_open_cooldown := 0.35
@export var arrive_slow_radius: float = 36.0
@export var stuck_seconds: float = 0.35
@export var stuck_move_eps: float = 1.0
@export var memory_decay_per_sec: float = 0.8
@export var min_switch_ratio: float = 0.55
@export var door_priority: float = 2000.0
@export var run_priority: float = 2000.0
@export var walk_priority: float = 10.0

@onready var agent: NavigationAgent2D = $NavigationAgent2D
@onready var head: Node2D = $Head
@onready var vision_ray: RayCast2D = $Head/VisionRay
@onready var door_ray: RayCast2D = $DoorRay

var state: State = State.PATROL
var player: Node2D = null
var last_heard_pos := Vector2.ZERO
var last_heard_strength := 0.0
var heard_timer := 0.0
var chase_timer := 0.0
var _search_pts: Array[Vector2] = []
var _search_index := 0
var _door_cd := 0.0
var _stuck_time: float = 0.0
var _last_pos: Vector2 = Vector2.ZERO

func _ready() -> void:
	add_to_group("killer")
	player = get_tree().get_first_node_in_group("player_") as Node2D
	agent.path_desired_distance = 6.0
	agent.target_desired_distance = 8.0
	$CatchArea.body_entered.connect(_on_catch)
	vision_ray.target_position = Vector2(vision_range, 0)
	SoundSystem.sound_emitted.connect(_on_sound)

func _physics_process(delta: float) -> void:
	_update_timers(delta)
	_update_vision()
	_update_state()
	_update_head(delta)
	_try_open_door()
	_move(delta)

func game_over() -> void:
	if get_parent().has_method("game_over"):
		get_parent().game_over()
	else:
		get_tree().paused = true

func _on_catch(body: Node) -> void:
	if body.is_in_group("player_"):
		game_over()

func _update_timers(delta: float) -> void:
	if heard_timer > 0.0:
		heard_timer = max(heard_timer - delta, 0.0)
	if chase_timer > 0.0:
		chase_timer = max(chase_timer - delta, 0.0)
	if _door_cd > 0.0:
		_door_cd = max(_door_cd - delta, 0.0)
	if last_heard_strength > 0.0:
		last_heard_strength = max(0.0, last_heard_strength - memory_decay_per_sec * delta)

func _on_sound(pos: Vector2, loud: float, kind: String, src: Node) -> void:
	if src == self:
		return

	var d: float = global_position.distance_to(pos)
	var priority: float = walk_priority
	if kind == "door":
		priority = door_priority
	elif kind == "run":
		priority = run_priority
	elif kind == "walk":
		priority = walk_priority
	elif kind == "footstep":
		priority = walk_priority

	var perceived: float = (loud * priority) / (d * d + 1.0)
	if perceived < react_threshold:
		return

	last_heard_pos = pos
	last_heard_strength = perceived
	heard_timer = memory_time

	if state == State.CHASE and chase_timer > 0.0:
		return

	_search_pts.clear()
	_search_index = 0
	state = State.INVESTIGATE
	agent.target_position = last_heard_pos

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

func _update_state() -> void:
	match state:
		State.PATROL:
			if heard_timer > 0.0:
				state = State.INVESTIGATE
				agent.target_position = last_heard_pos
			elif agent.is_navigation_finished():
				agent.target_position = _random_nav()

		State.INVESTIGATE:
			if agent.is_navigation_finished():
				_start_search()
			if heard_timer <= 0.0:
				state = State.PATROL
				last_heard_strength = 0.0

		State.SEARCH:
			if heard_timer <= 0.0:
				state = State.PATROL
				last_heard_strength = 0.0
				return
			if agent.is_navigation_finished():
				_search_index += 1
				if _search_index >= _search_pts.size():
					state = State.INVESTIGATE
					agent.target_position = last_heard_pos
				else:
					agent.target_position = _search_pts[_search_index]

		State.CHASE:
			if chase_timer <= 0.0:
				if heard_timer > 0.0:
					state = State.INVESTIGATE
					agent.target_position = last_heard_pos
				else:
					state = State.PATROL

func _update_head(delta: float) -> void:
	var target := head.rotation
	if state == State.CHASE and player:
		target = (player.global_position - global_position).angle()
	elif (state == State.INVESTIGATE or state == State.SEARCH) and heard_timer > 0.0:
		target = (last_heard_pos - global_position).angle()
	elif velocity.length() > 5.0:
		target = velocity.angle()

	head.rotation = lerp_angle(head.rotation, target, 8.0 * delta)

func _try_open_door(force: bool = false) -> void:
	var dir_global: Vector2 = Vector2.ZERO
	if not agent.is_navigation_finished():
		var next_pos: Vector2 = agent.get_next_path_position()
		var to_next: Vector2 = next_pos - global_position
		if to_next.length() > 0.5:
			dir_global = to_next.normalized()
	if dir_global == Vector2.ZERO and state == State.CHASE and player:
		var to_p: Vector2 = player.global_position - global_position
		if to_p.length() > 0.5:
			dir_global = to_p.normalized()
	if dir_global == Vector2.ZERO and velocity.length() > 0.5:
		dir_global = velocity.normalized()
	if dir_global == Vector2.ZERO or (not force and velocity.length() < 5.0 and state != State.CHASE):
		return

	door_ray.position = dir_global * 10.0
	var dir_local: Vector2 = door_ray.global_transform.basis_xform_inv(dir_global).normalized()
	door_ray.target_position = dir_local * door_open_distance
	door_ray.force_raycast_update()

	if door_ray.is_colliding():
		var n: Node = door_ray.get_collider()
		while n != null and not (n is Door):
			n = n.get_parent()
		if n is Door and not n.is_open:
			n.open_away_from(self)

func _move(delta: float) -> void:
	var max_speed: float = speed_patrol
	if state == State.INVESTIGATE or state == State.SEARCH:
		max_speed = speed_investigate
	elif state == State.CHASE:
		max_speed = speed_chase

	if agent.is_navigation_finished():
		velocity = Vector2.ZERO
		move_and_slide()
		_reset_stuck()
		return

	var next_pos: Vector2 = agent.get_next_path_position()
	var to_next: Vector2 = next_pos - global_position
	var dist: float = to_next.length()

	if dist < 0.8:
		velocity = Vector2.ZERO
		move_and_slide()
		_reset_stuck()
		return

	var desired_speed: float = max_speed
	if dist < arrive_slow_radius:
		desired_speed = clamp(max_speed * (dist / arrive_slow_radius), 30.0, max_speed)

	velocity = (to_next / dist) * desired_speed
	move_and_slide()

	var moved: float = global_position.distance_to(_last_pos)
	_last_pos = global_position
	if desired_speed > 40.0 and moved < stuck_move_eps:
		_stuck_time += delta
	else:
		_stuck_time = 0.0
	if _stuck_time >= stuck_seconds:
		_handle_stuck()

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
	_try_open_door(true)
	var side := Vector2(-velocity.y, velocity.x).normalized()
	global_position += side * 1.5
	if state == State.CHASE and player:
		agent.target_position = player.global_position
	elif state == State.INVESTIGATE:
		agent.target_position = last_heard_pos
	else:
		agent.target_position += Vector2(randf_range(-4,4), randf_range(-4,4))
