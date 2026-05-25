extends Node2D
class_name Level

const LevelData = preload("res://scripts/level_data.gd")
const METEOR_HAMMER_SCENE = preload("res://scenes/enemy_meteor_hammer.tscn")
const RED_GHOST_SCENE = preload("res://scenes/enemy_red_ghost.tscn")
const RED_DEVIL_SCENE = preload("res://scenes/enemy_red_devil.tscn")
const PALACE_ZOMBIE_SCENE = preload("res://scenes/enemy_palace_zombie.tscn")
const PICKUP_SCENE = preload("res://scenes/pickup.tscn")
const PLAYER_SCENE = preload("res://scenes/player.tscn")

@export var stage_number: int = 1
@export var time_limit: float = 90.0

const TILE_SOURCES := {"#": 0, ".": 1, "=": 2}
const NOGO_CHAR := "X"
const PICKUP_TYPES := {"a": 0, "c": 1, "r": 2, "h": 3}

var time_remaining: float
var enemies_remaining: int = 0
var level_complete: bool = false
var ready_done: bool = false
var spawn_pos: Vector2 = Vector2(100, 500)

@onready var tile_map: TileMapLayer = $TileMap
@onready var nogo_map: TileMapLayer = $NoGoMap
@onready var enemy_container: Node2D = $Enemies
@onready var pickup_container: Node2D = $Pickups
@onready var player_container: Node2D = $PlayerHolder
@onready var ui: CanvasLayer = $UI

func _ready() -> void:
	time_remaining = time_limit
	GameState.current_stage = stage_number
	GameState.stage_changed.emit(stage_number)
	_build_level()
	tile_map.visible = false
	ready_done = true

const TILE_PX := 10

func _build_level() -> void:
	var processed = {}
	var grid: Array = LevelData.LEVELS.get(stage_number, LevelData.LEVELS[1])
	for y in range(grid.size()):
		var row: String = grid[y]
		for x in range(row.length()):
			var pos_vec = Vector2i(x, y)
			if processed.has(pos_vec):
				continue
			
			var ch := row[x]
			if ch == " ":
				continue
				
			if ch == NOGO_CHAR:
				# Place no-go zone on separate invisible collision layer
				nogo_map.set_cell(pos_vec, 1, Vector2i(0, 0), 0)
			elif TILE_SOURCES.has(ch):
				tile_map.set_cell(pos_vec, TILE_SOURCES[ch], Vector2i(0, 0), 0)
			else:
				var blob_cells = _flood_fill(grid, x, y, ch, processed)
				var min_x = blob_cells[0].x
				var max_x = blob_cells[0].x
				var min_y = blob_cells[0].y
				var max_y = blob_cells[0].y
				for c in blob_cells:
					min_x = min(min_x, c.x)
					max_x = max(max_x, c.x)
					min_y = min(min_y, c.y)
					max_y = max(max_y, c.y)
				var center_x = (min_x + max_x) / 2.0
				# Spawn at top of blob so enemies don't clip into ground below
				var spawn_y = float(min_y)
				_spawn_entity(ch, Vector2(center_x * TILE_PX + TILE_PX / 2.0, spawn_y * TILE_PX + TILE_PX / 2.0))

func _flood_fill(grid: Array, start_x: int, start_y: int, ch: String, processed: Dictionary) -> Array:
	var result = []
	var stack = [Vector2i(start_x, start_y)]
	while stack.size() > 0:
		var curr = stack.pop_back()
		if processed.has(curr):
			continue
		if curr.y < 0 or curr.y >= grid.size() or curr.x < 0 or curr.x >= grid[curr.y].length():
			continue
		if grid[curr.y][curr.x] != ch:
			continue
		processed[curr] = true
		result.append(curr)
		stack.append(Vector2i(curr.x + 1, curr.y))
		stack.append(Vector2i(curr.x - 1, curr.y))
		stack.append(Vector2i(curr.x, curr.y + 1))
		stack.append(Vector2i(curr.x, curr.y - 1))
	return result

func _spawn_entity(ch: String, world_pos: Vector2) -> void:
	if ch == "P":
		spawn_pos = Vector2(world_pos.x, world_pos.y - TILE_PX / 2)
		var p = PLAYER_SCENE.instantiate()
		p.position = spawn_pos
		player_container.add_child(p)
		
		# Create an invisible blocker around the spawn point for enemies
		var blocker = StaticBody2D.new()
		blocker.collision_layer = 32 # Layer 6: EnemyBlocker
		blocker.collision_mask = 0
		var shape = CollisionShape2D.new()
		var rect = RectangleShape2D.new()
		rect.size = Vector2(100, 150)
		shape.shape = rect
		blocker.add_child(shape)
		blocker.position = spawn_pos
		add_child(blocker)
	elif ch == "M":
		_spawn_enemy(METEOR_HAMMER_SCENE, world_pos)
	elif ch == "R":
		_spawn_enemy(RED_GHOST_SCENE, world_pos)
	elif ch == "D":
		_spawn_enemy(RED_DEVIL_SCENE, world_pos)
	elif ch == "Z":
		_spawn_enemy(PALACE_ZOMBIE_SCENE, world_pos)
	elif PICKUP_TYPES.has(ch):
		var pickup = PICKUP_SCENE.instantiate()
		pickup.position = world_pos
		pickup.pickup_type = PICKUP_TYPES[ch]
		pickup_container.add_child(pickup)

func _spawn_enemy(scene: PackedScene, pos: Vector2) -> void:
	var e = scene.instantiate()
	e.position = pos
	enemy_container.add_child(e)
	enemies_remaining += 1
	e.tree_exited.connect(_on_enemy_removed)

func _process(delta: float) -> void:
	if not ready_done or level_complete:
		return
	time_remaining = max(0.0, time_remaining - delta)
	if ui.has_method("update_time"):
		ui.update_time(time_remaining)
	if time_remaining <= 0.0:
		_on_time_up()
		return
	if Input.is_action_just_pressed("restart"):
		get_tree().reload_current_scene()
	if Input.is_action_just_pressed("toggle_tiles"):
		tile_map.visible = not tile_map.visible
		nogo_map.modulate.a = 0.5 if nogo_map.modulate.a == 0.0 else 0.0

func _on_enemy_removed() -> void:
	enemies_remaining -= 1
	if not is_inside_tree():
		return
	if enemies_remaining <= 0 and not level_complete and ready_done:
		_on_stage_clear()

func _on_time_up() -> void:
	get_tree().reload_current_scene()

func _on_stage_clear() -> void:
	if level_complete:
		return
	level_complete = true
	GameState.add_score(int(time_remaining) * 10)
	await get_tree().create_timer(1.5).timeout
	if GameState.advance_stage():
		GameState.goto_stage(GameState.current_stage)
	else:
		GameState.goto_victory()

func get_spawn_pos() -> Vector2:
	return spawn_pos
