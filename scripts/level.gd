extends Node2D
class_name Level

const LevelData = preload("res://scripts/level_data.gd")
var METEOR_HAMMER_SCENE: PackedScene
var RED_GHOST_SCENE: PackedScene
var RED_DEVIL_SCENE: PackedScene
var PALACE_ZOMBIE_SCENE: PackedScene
var BOSS_SCENE: PackedScene
const PICKUP_SCENE = preload("res://scenes/pickup.tscn")
const PLAYER_SCENE = preload("res://scenes/player.tscn")

@export var stage_number: int = 1
@export var time_limit: float = 90.0

const TILE_SOURCES := {"#": 0, ".": 1, "=": 2}
const NOGO_CHAR := "X"
const PICKUP_TYPES := {"r": 2}

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
	# Lazy-load enemy scenes to avoid preload()-time script compilation race
	# (enemy.gd references CharTuning autoload; preload may run before autoloads register)
	METEOR_HAMMER_SCENE = load("res://scenes/enemy_meteor_hammer.tscn")
	RED_GHOST_SCENE = load("res://scenes/enemy_red_ghost.tscn")
	RED_DEVIL_SCENE = load("res://scenes/enemy_red_devil.tscn")
	PALACE_ZOMBIE_SCENE = load("res://scenes/enemy_palace_zombie.tscn")
	BOSS_SCENE = load("res://scenes/enemy_boss.tscn")
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
	elif ch == "B":
		# Boss 使用独立 20 血机制；死亡时主动通知关卡通关，不计入普通小怪计数。
		var b = BOSS_SCENE.instantiate()
		b.position = world_pos
		enemy_container.add_child(b)
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

# Boss 技能召唤敌人时调用：实例化敌人但**不**计入 enemies_remaining。
# 召唤的杂兵不应阻塞通关条件（否则玩家清完 BBBBBB 仍卡死），
# 也不连 tree_exited，避免负数计数干扰 _on_stage_clear。
# 给召唤的敌人加一个短暂"豁免期"（summon_invuln_t）：避免被场上残留的
# ball（玩家投掷的翻滚攻击物，存活 2s）在 spawn 那一帧 body_entered 信号
# 同时触发 die() 抹掉 ── 这会让玩家看到"Boss 出招了但敌人没出现"。
func spawn_summoned_enemy(scene: PackedScene, pos: Vector2) -> Node:
	var e = scene.instantiate()
	e.position = pos
	enemy_container.add_child(e)
	if "summon_invuln_t" in e and "SUMMON_INVULN_TIME" in e:
		e.summon_invuln_t = e.SUMMON_INVULN_TIME
	return e

# 返回 Boss 关卡可作为召唤落点的若干平台顶部世界坐标。
# 数据来源：直接扫描 LevelData.LEVELS[stage_number] 网格，
# 收集所有由 TILE_SOURCES 字符（"#" / "." / "="）构成的水平连续段，
# 每段取中点 X、段所在行的"上一格"中心 Y（让敌人站在平台上而非陷进去）。
# 至少 2 格宽才认作"可站立平台"，避免把孤立 tile 算进去。
func get_platform_spawn_points() -> Array:
	var points: Array = []
	var grid: Array = LevelData.LEVELS.get(stage_number, [])
	for y in range(grid.size()):
		var row: String = grid[y]
		var run_start := -1
		for x in range(row.length()):
			var ch := row[x]
			var is_tile := TILE_SOURCES.has(ch)
			if is_tile and run_start < 0:
				run_start = x
			elif not is_tile and run_start >= 0:
				_collect_platform_run(points, run_start, x - 1, y)
				run_start = -1
		if run_start >= 0:
			_collect_platform_run(points, run_start, row.length() - 1, y)
	return points

func _collect_platform_run(points: Array, x0: int, x1: int, y: int) -> void:
	if x1 - x0 < 1:
		return  # 至少 2 格宽
	var center_x := (x0 + x1) / 2.0
	# 站在平台上：Y 取平台行上方一格的中心
	var spawn_y := float(y - 1)
	points.append(Vector2(
		center_x * TILE_PX + TILE_PX / 2.0,
		spawn_y * TILE_PX + TILE_PX / 2.0
	))

# ───────── 平台拓扑数据：用于敌人"换平台"决策 ─────────
# 每个平台一条记录：{
#   id: int,                 # 唯一编号（在该关卡内）
#   row: int,                # tile 网格行号（平台 tile 所在 y）
#   x0: int, x1: int,        # tile 网格列起止（inclusive）
#   width_tiles: int,        # x1-x0+1
#   capacity: int,           # 自适应容量（按宽度推导）
#   top_y: float,            # 站立面的世界 Y（tile 上方一格中心）
#   left_x: float, right_x: float,  # 站立面的世界 X 范围（含半 tile 边距）
#   center_x: float,         # 站立面世界 X 中心
# }
# 缓存一次构建即可：关卡 ASCII grid 在运行时不变。
var _platforms_cache: Array = []

# 容量计算系数：长度自适应。
# 每 PLATFORM_CAPACITY_TILES_PER_SLOT 格 tile 容纳 1 只敌人，至少 1，最多 PLATFORM_CAPACITY_MAX。
# 例：6 格 → 1 只；12 格 → 2 只；30 格 → 5 只。
const PLATFORM_CAPACITY_TILES_PER_SLOT := 6
const PLATFORM_CAPACITY_MIN := 1
const PLATFORM_CAPACITY_MAX := 5

func get_platforms() -> Array:
	if not _platforms_cache.is_empty():
		return _platforms_cache
	_build_platforms_cache()
	return _platforms_cache

func _build_platforms_cache() -> void:
	_platforms_cache.clear()
	var grid: Array = LevelData.LEVELS.get(stage_number, [])
	for y in range(grid.size()):
		var row: String = grid[y]
		var run_start := -1
		for x in range(row.length()):
			var ch := row[x]
			var is_tile := TILE_SOURCES.has(ch)
			if is_tile and run_start < 0:
				run_start = x
			elif not is_tile and run_start >= 0:
				_append_platform_record(run_start, x - 1, y)
				run_start = -1
		if run_start >= 0:
			_append_platform_record(run_start, row.length() - 1, y)

func _append_platform_record(x0: int, x1: int, y: int) -> void:
	if x1 - x0 < 1:
		return  # 与 _collect_platform_run 一致：至少 2 格宽
	var width_tiles := x1 - x0 + 1
	var cap: int = clamp(width_tiles / PLATFORM_CAPACITY_TILES_PER_SLOT,
		PLATFORM_CAPACITY_MIN, PLATFORM_CAPACITY_MAX)
	var top_y := float(y - 1) * TILE_PX + TILE_PX / 2.0
	var left_x := float(x0) * TILE_PX + TILE_PX / 2.0
	var right_x := float(x1) * TILE_PX + TILE_PX / 2.0
	var center_x := (left_x + right_x) * 0.5
	_platforms_cache.append({
		"id": _platforms_cache.size(),
		"row": y,
		"x0": x0,
		"x1": x1,
		"width_tiles": width_tiles,
		"capacity": cap,
		"top_y": top_y,
		"left_x": left_x,
		"right_x": right_x,
		"center_x": center_x,
	})

# 根据世界坐标找到敌人当前所在的平台（脚下站立的那一行）。
# 匹配规则：站立面 Y 接近 enemy.global_position.y（容差 PLATFORM_Y_TOLERANCE），
# 且 enemy.x 落在 [left_x - half_tile, right_x + half_tile] 内。
# 找不到则返回 null（敌人正在空中或超出已知平台）。
const PLATFORM_Y_TOLERANCE := 12.0  # 站立面与敌人脚部 Y 的允许误差（像素）

func find_platform_for(world_pos: Vector2) -> Variant:
	var half := float(TILE_PX) * 0.5
	for p in get_platforms():
		if abs(world_pos.y - p["top_y"]) > PLATFORM_Y_TOLERANCE:
			continue
		if world_pos.x < p["left_x"] - half or world_pos.x > p["right_x"] + half:
			continue
		return p
	return null

# 统计当前各平台上"活着的、非捕获、非空中"敌人数量。
# 返回 { platform_id: int -> count: int }
func count_enemies_on_platforms() -> Dictionary:
	var counts: Dictionary = {}
	for p in get_platforms():
		counts[p["id"]] = 0
	if not is_instance_valid(enemy_container):
		return counts
	for child in enemy_container.get_children():
		if not (child is CharacterBody2D):
			continue
		# 跳过被吸/死亡/飞行/换平台中的敌人
		if "is_captured" in child and child.is_captured:
			continue
		if "dying" in child and child.dying:
			continue
		if "is_in_flight" in child and child.is_in_flight:
			continue
		if "is_hopping" in child and child.is_hopping:
			continue
		var p_data = find_platform_for(child.global_position)
		if p_data != null:
			counts[p_data["id"]] = counts[p_data["id"]] + 1
	return counts

# 给定"当前平台"和实时敌人计数，找一个"空旷"的最近平台。
# 空旷定义：count < capacity（按容量留出余量；若需要严格空旷，调用方自行加强 ）。
# "最近"以平台中心点欧氏距离衡量。返回 platform 字典或 null。
# from_platform 可为 null（敌人在空中），此时以 from_world_pos 为参照。
# 注：当前 HOP 机制改为随机平台后，此函数已不被敌人 HOP 调用，保留以备其他用途。
func find_nearest_empty_platform(from_world_pos: Vector2, from_platform_id: int,
		counts: Dictionary) -> Variant:
	var best: Variant = null
	var best_dist := INF
	for p in get_platforms():
		if p["id"] == from_platform_id:
			continue
		var c: int = counts.get(p["id"], 0)
		if c >= p["capacity"]:
			continue
		# 用站立面中心点估算距离（X 用 center_x，Y 用 top_y）
		var ref := Vector2(p["center_x"], p["top_y"])
		var d := from_world_pos.distance_squared_to(ref)
		if d < best_dist:
			best_dist = d
			best = p
	return best

# 从所有平台中随机选取一个不等于 from_platform_id 的平台。
# 不再考虑容量/拥挤状态——任何其他平台都可作为目标。
# 若除了当前平台外没有其他平台可选，返回 null。
func pick_random_other_platform(from_platform_id: int) -> Variant:
	var candidates: Array = []
	for p in get_platforms():
		if p["id"] == from_platform_id:
			continue
		candidates.append(p)
	if candidates.is_empty():
		return null
	return candidates[randi() % candidates.size()]

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
	# 开发用：按 N 直接跳过当前关卡，进入下一关（或胜利画面）。
	# 走与正常通关相同的 _on_stage_clear() 流程，确保 GameState
	# 阶段推进 / 加分 / 场景切换都按既定路径执行。
	if Input.is_action_just_pressed("skip_level"):
		_on_stage_clear()

func _on_enemy_removed() -> void:
	enemies_remaining -= 1
	if not is_inside_tree():
		return
	if enemies_remaining <= 0 and not level_complete and ready_done:
		_on_stage_clear()

func on_boss_defeated() -> void:
	if level_complete:
		return
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
