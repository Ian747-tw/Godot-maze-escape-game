extends Node2D

@export var player_scene: PackedScene  # drag your Player.tscn here in Inspector

@onready var tilemap: TileMap = $Background

@onready var ui := $CanvasLayer/GameUI
@onready var msg := $CanvasLayer/GameUI/MessageLabel
@onready var hint := $CanvasLayer/GameUI/HintLabel

var game_ended := false
var player: CharacterBody2D

func _ready() -> void:
	get_tree().paused = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	ui.visible = false
	
	# Set gameplay nodes to PAUSABLE so they stop when the tree is paused
	# This prevents player/killer from moving during pause
	for child in get_children():
		if child is CanvasLayer:
			continue # UI should stay active
		child.process_mode = Node.PROCESS_MODE_PAUSABLE

	# 1) Make sure we have a player in the scene
	if has_node("Player"):
		player = $Player as CharacterBody2D
	else:
		if player_scene == null:
			push_error("Main.gd: player_scene is not assigned, and no Player node exists.")
			return
		player = player_scene.instantiate() as CharacterBody2D
		player.name = "Player"
		add_child(player)
		player.process_mode = Node.PROCESS_MODE_PAUSABLE

	# 2) Spawn player near the center of the used TileMap area
	#player.global_position = get_tilemap_used_rect_center_world()

func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("cancel"): # Esc by default
		get_tree().quit()

	if Input.is_action_just_pressed("restart"):
		get_tree().reload_current_scene()

	if game_ended:
		return

	# WIN condition
	if player.global_position.x >= 1935:
		_win()

func _physics_process(_delta: float) -> void:
	# 3) Clamp player inside painted tile area (basic test boundary)
	if player == null:
		return

	var rect_world := get_tilemap_used_rect_world()
	if rect_world.size != Vector2.ZERO:
		player.global_position.x = clamp(player.global_position.x, rect_world.position.x, rect_world.position.x + rect_world.size.x)
		player.global_position.y = clamp(player.global_position.y, rect_world.position.y, rect_world.position.y + rect_world.size.y)

# -------------------------
# Helpers
# -------------------------

func get_tilemap_used_rect_world() -> Rect2:
	# TileMap.get_used_rect() returns rect in *cell coords*
	var used := tilemap.get_used_rect()
	if used.size == Vector2i.ZERO:
		return Rect2(Vector2.ZERO, Vector2.ZERO)

	# Convert cell rect to world rect
	var tl_cell := used.position
	var br_cell := used.position + used.size

	var tl_world := tilemap.to_global(tilemap.map_to_local(tl_cell))
	var br_world := tilemap.to_global(tilemap.map_to_local(br_cell))

	# Ensure proper ordering
	var pos := Vector2(min(tl_world.x, br_world.x), min(tl_world.y, br_world.y))
	var end := Vector2(max(tl_world.x, br_world.x), max(tl_world.y, br_world.y))

	return Rect2(pos, end - pos)

func get_tilemap_used_rect_center_world() -> Vector2:
	var r := get_tilemap_used_rect_world()
	if r.size == Vector2.ZERO:
		return Vector2.ZERO
	return r.position + r.size * 0.5
	
func game_over() -> void:
	if game_ended:
		return

	game_ended = true
	ui.visible = true
	msg.text = "GAME OVER"
	hint.text = "Press R to Restart"
	hint.visible = true
	get_tree().paused = true

func _win() -> void:
	if game_ended:
		return

	game_ended = true
	ui.visible = true
	msg.text = "YOU WIN!!!"
	hint.text = "Press R to Restart"
	hint.visible = true
	get_tree().paused = true
