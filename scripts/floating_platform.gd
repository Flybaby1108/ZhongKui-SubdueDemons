extends AnimatableBody2D
class_name FloatingPlatform

const DEFAULT_TEXTURE_PATH := "res://assets/sprites/Chapter2/Chapter2_Platform1_01.png"
const LEGACY_TEXTURE_PATH := "res://assets/sprites/Chapter2/Chapter2_Platform1.png"
const PLATFORM2_DEFAULT_TEXTURE_PATH := "res://assets/sprites/Chapter2/Chapter2_Platform2_01.png"
const PLATFORM2_LEGACY_TEXTURE_PATH := "res://assets/sprites/Chapter2/Chapter2_Platform2.png"
const COLLISION_CELL_PX := 10.0
const PLATFORM1_BASE_SIZE := Vector2(542, 254)
const PLATFORM2_BASE_SIZE := Vector2(452, 316)
const PLATFORM1_SPIKE_FRAME_PATHS := [
	"res://assets/sprites/Chapter2/Chapter2_Platform1_01.png",
	"res://assets/sprites/Chapter2/Chapter2_Platform1_02.png",
	"res://assets/sprites/Chapter2/Chapter2_Platform1_03.png",
]
const PLATFORM2_SPIKE_FRAME_PATHS := [
	"res://assets/sprites/Chapter2/Chapter2_Platform2_01.png",
	"res://assets/sprites/Chapter2/Chapter2_Platform2_02.png",
	"res://assets/sprites/Chapter2/Chapter2_Platform2_03.png",
]
const SPIKE_WAIT_TIME := 3.0
const SPIKE_GROW_TIME := 0.3
const SPIKE_ACTIVE_TIME := 3.0
const SPIKE_RETRACT_TIME := 0.3
const SPIKE_DAMAGE_COOLDOWN_FRAMES := 90

@export var texture_path: String = DEFAULT_TEXTURE_PATH
@export var move_left: float = 0.0
@export var move_right: float = 0.0
@export var move_up: float = 0.0
@export var move_down: float = 0.0
@export var move_speed: float = 80.0
@export var collision_cells: Array[Vector2i] = []

var _origin: Vector2
var _direction: int = 1
var _sprite: Sprite2D
var _texture_size := PLATFORM1_BASE_SIZE
var _collision_texture_size := PLATFORM1_BASE_SIZE
var _spike_textures: Array[Texture2D] = []
var _spike_state := "waiting"
var _spike_timer := 0.0
var _spikes_active := false
var _damage_area: Area2D
var _damage_shape: CollisionShape2D
var _damage_frame: int = -1000
var _damaged_players_this_cycle: Dictionary = {}

func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	sync_to_physics = true
	_origin = position
	_build_sprite()
	_build_collision()
	_build_damage_area()

func configure(data: Dictionary) -> void:
	texture_path = data.get("texture_path", DEFAULT_TEXTURE_PATH)
	if texture_path == LEGACY_TEXTURE_PATH:
		texture_path = DEFAULT_TEXTURE_PATH
	elif texture_path == PLATFORM2_LEGACY_TEXTURE_PATH:
		texture_path = PLATFORM2_DEFAULT_TEXTURE_PATH
	position = data.get("position", position)
	scale = data.get("scale", Vector2.ONE)
	move_left = float(data.get("move_left", 0.0))
	move_right = float(data.get("move_right", 0.0))
	move_up = float(data.get("move_up", 0.0))
	move_down = float(data.get("move_down", 0.0))
	move_speed = float(data.get("speed", data.get("move_speed", move_speed)))
	collision_cells.clear()
	for cell in data.get("collision_cells", []):
		if cell is Vector2i:
			collision_cells.append(cell)
		elif cell is Vector2:
			collision_cells.append(Vector2i(int(cell.x), int(cell.y)))

func _physics_process(delta: float) -> void:
	_tick_movement(delta)
	_tick_spikes(delta)
	_damage_players_on_spikes()

func _build_sprite() -> void:
	_load_spike_textures()
	var tex := _spike_textures[0] if _is_spike_platform() and not _spike_textures.is_empty() else load(texture_path) as Texture2D
	if tex != null:
		_texture_size = tex.get_size()
	_collision_texture_size = _get_platform_base_size()
	_sprite = Sprite2D.new()
	_sprite.name = "Sprite"
	_sprite.texture = tex
	_sprite.centered = true
	if _is_spike_platform():
		_sprite.position.y = (_collision_texture_size.y - _texture_size.y) * 0.5
	add_child(_sprite)

func _load_spike_textures() -> void:
	_spike_textures.clear()
	for path in _get_spike_frame_paths():
		var tex := load(path) as Texture2D
		if tex != null:
			_spike_textures.append(tex)

func _get_spike_frame_paths() -> Array:
	if texture_path == DEFAULT_TEXTURE_PATH or texture_path in PLATFORM1_SPIKE_FRAME_PATHS:
		return PLATFORM1_SPIKE_FRAME_PATHS
	if texture_path == PLATFORM2_DEFAULT_TEXTURE_PATH or texture_path in PLATFORM2_SPIKE_FRAME_PATHS:
		return PLATFORM2_SPIKE_FRAME_PATHS
	return []

func _is_spike_platform() -> bool:
	return not _get_spike_frame_paths().is_empty()

func _get_platform_base_size() -> Vector2:
	if texture_path == DEFAULT_TEXTURE_PATH or texture_path in PLATFORM1_SPIKE_FRAME_PATHS:
		return PLATFORM1_BASE_SIZE
	if texture_path == PLATFORM2_DEFAULT_TEXTURE_PATH or texture_path in PLATFORM2_SPIKE_FRAME_PATHS:
		return PLATFORM2_BASE_SIZE
	return _texture_size

func _build_collision() -> void:
	if collision_cells.is_empty():
		return
	var cells_by_row: Dictionary = {}
	for cell in collision_cells:
		if not cells_by_row.has(cell.y):
			cells_by_row[cell.y] = []
		cells_by_row[cell.y].append(cell.x)

	for row in cells_by_row.keys():
		var xs: Array = cells_by_row[row]
		xs.sort()
		var run_start: int = xs[0]
		var last_x: int = xs[0]
		for i in range(1, xs.size()):
			var x: int = xs[i]
			if x == last_x + 1:
				last_x = x
			else:
				_add_collision_run(run_start, last_x, int(row))
				run_start = x
				last_x = x
		_add_collision_run(run_start, last_x, int(row))

func _add_collision_run(x0: int, x1: int, row: int) -> void:
	var shape := RectangleShape2D.new()
	shape.size = Vector2(float(x1 - x0 + 1) * COLLISION_CELL_PX, COLLISION_CELL_PX)
	var collision := CollisionShape2D.new()
	collision.shape = shape
	collision.position = Vector2(
		(float(x0 + x1 + 1) * 0.5 * COLLISION_CELL_PX) - _collision_texture_size.x * 0.5,
		(float(row) + 0.5) * COLLISION_CELL_PX - _collision_texture_size.y * 0.5
	)
	add_child(collision)

func _tick_movement(delta: float) -> void:
	if move_speed <= 0.0 or (move_left <= 0.0 and move_right <= 0.0 and move_up <= 0.0 and move_down <= 0.0):
		return
	var target := _origin + Vector2(
		move_right if _direction > 0 else -move_left,
		move_down if _direction > 0 else -move_up
	)
	position = position.move_toward(target, move_speed * delta)
	if position.is_equal_approx(target):
		_direction *= -1

func _tick_spikes(delta: float) -> void:
	if not _is_spike_platform() or _spike_textures.size() < 3:
		return
	_spike_timer += delta
	match _spike_state:
		"waiting":
			_set_spike_frame(0)
			_spikes_active = false
			if _spike_timer >= SPIKE_WAIT_TIME:
				_spike_state = "growing"
				_spike_timer = 0.0
		"growing":
			_spikes_active = false
			_set_spike_frame(_spike_anim_frame(_spike_timer, SPIKE_GROW_TIME, false))
			if _spike_timer >= SPIKE_GROW_TIME:
				_spike_state = "active"
				_spike_timer = 0.0
				_spikes_active = true
				_damaged_players_this_cycle.clear()
				_set_spike_frame(2)
		"active":
			_spikes_active = true
			_set_spike_frame(2)
			if _spike_timer >= SPIKE_ACTIVE_TIME:
				_spike_state = "retracting"
				_spike_timer = 0.0
		"retracting":
			_spikes_active = false
			_set_spike_frame(_spike_anim_frame(_spike_timer, SPIKE_RETRACT_TIME, true))
			if _spike_timer >= SPIKE_RETRACT_TIME:
				_spike_state = "waiting"
				_spike_timer = 0.0
				_damaged_players_this_cycle.clear()
				_set_spike_frame(0)

func _spike_anim_frame(timer: float, duration: float, reverse: bool) -> int:
	var frame_count := _spike_textures.size()
	var progress: float = clamp(timer / max(duration, 0.001), 0.0, 0.999)
	var frame := int(floor(progress * float(frame_count)))
	return frame_count - 1 - frame if reverse else frame

func _set_spike_frame(frame: int) -> void:
	if _sprite == null or _spike_textures.is_empty():
		return
	_sprite.texture = _spike_textures[clampi(frame, 0, _spike_textures.size() - 1)]

func _build_damage_area() -> void:
	if not _is_spike_platform() or collision_cells.is_empty():
		return
	var bounds := _get_collision_cell_bounds()
	if bounds.size == Vector2.ZERO:
		return
	_damage_area = Area2D.new()
	_damage_area.name = "SpikeDamageArea"
	_damage_area.collision_layer = 0
	_damage_area.collision_mask = 2
	_damage_area.monitoring = true
	_damage_area.monitorable = false
	_damage_shape = CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(bounds.size.x * COLLISION_CELL_PX, 32.0)
	_damage_shape.shape = shape
	_damage_shape.position = Vector2(
		(bounds.position.x + bounds.size.x * 0.5) * COLLISION_CELL_PX - _collision_texture_size.x * 0.5,
		bounds.position.y * COLLISION_CELL_PX - _collision_texture_size.y * 0.5 - 6.0
	)
	_damage_area.add_child(_damage_shape)
	add_child(_damage_area)

func _get_collision_cell_bounds() -> Rect2:
	if collision_cells.is_empty():
		return Rect2()
	var min_x := collision_cells[0].x
	var max_x := collision_cells[0].x
	var min_y := collision_cells[0].y
	var max_y := collision_cells[0].y
	for cell in collision_cells:
		min_x = min(min_x, cell.x)
		max_x = max(max_x, cell.x)
		min_y = min(min_y, cell.y)
		max_y = max(max_y, cell.y)
	return Rect2(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1)

func _damage_players_on_spikes() -> void:
	if not _spikes_active or _damage_area == null:
		return
	var current_frame := Engine.get_physics_frames()
	if current_frame - _damage_frame < SPIKE_DAMAGE_COOLDOWN_FRAMES:
		return
	for body in _damage_area.get_overlapping_bodies():
		if body is Player and body.is_on_floor() and body.get_slide_collision_count() > 0:
			for i in range(body.get_slide_collision_count()):
				var collision: KinematicCollision2D = body.get_slide_collision(i)
				if collision.get_collider() == self and collision.get_normal().dot(Vector2.UP) > 0.7:
					_hurt_player(body, current_frame)
					return

func _hurt_player(player: Player, current_frame: int) -> void:
	if player.invincible or GameState.lives <= 0:
		return
	var player_id := player.get_instance_id()
	if _damaged_players_this_cycle.has(player_id):
		return
	if current_frame - player.last_damage_frame < SPIKE_DAMAGE_COOLDOWN_FRAMES:
		return
	_damage_frame = current_frame
	_damaged_players_this_cycle[player_id] = true
	player.last_damage_frame = current_frame
	player.invincible = true
	player.invincible_timer = Player.HURT_INVINCIBLE_TIME
	player.take_damage()
