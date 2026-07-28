extends Node2D
class_name Level

const LevelData = preload("res://scripts/level_data.gd")
var METEOR_HAMMER_SCENE: PackedScene
var RED_GHOST_SCENE: PackedScene
var RED_DEVIL_SCENE: PackedScene
var PALACE_ZOMBIE_SCENE: PackedScene
var FAT_DEMON_KING_SCENE: PackedScene
var BOSS_SCENE: PackedScene
const PICKUP_SCENE = preload("res://scenes/pickup.tscn")
const PLAYER_SCENE = preload("res://scenes/player.tscn")
const FLOATING_PLATFORM_SCRIPT = preload("res://scripts/floating_platform.gd")
const FDK_MECHANISM_TEXTURE := "res://assets/sprites/Chapter3/Mechanism.png"
const FDK_IRON_BALL_TEXTURE := "res://assets/sprites/Chapter3/IronBall.png"
const FDK_IRON_BALL_PREVIEW_SCALE := 0.55
const FDK_IRON_BALL_PREVIEW_RADIUS := 39.0
const FDK_MECHANISM_PIVOT_CROSS_SIZE := 18.0
const FDK_MECHANISM_PIVOT_CROSS_WIDTH := 3.0
const STAGE_BGM_PATHS := {
	1: "res://assets/audio/Chapter1_BGM.mp3",
	2: "res://assets/audio/Chapter2_BGM.mp3",
	3: "res://assets/audio/Chapter3_BGM.mp3",
	4: "res://assets/audio/ChapterBoss_BGM.mp3",
}
const ENEMY_SCENE_PATHS := [
	"res://scenes/enemy_meteor_hammer.tscn",
	"res://scenes/enemy_red_ghost.tscn",
	"res://scenes/enemy_red_devil.tscn",
	"res://scenes/enemy_palace_zombie.tscn",
	"res://scenes/enemy_fat_demon_king.tscn",
	"res://scenes/enemy_boss.tscn",
]
const PASS_EFFECT_AUDIO_PATH := "res://assets/audio/PassEffect.mp3"
const PASS_EFFECT_STAGE_CONFIGS := {
	1: {
		"frame_dir": "res://assets/sprites/PassEffect/PassEffect_Chapter1",
		"frame_prefix": "PassEffect_Chapter1_",
	},
	2: {
		"frame_dir": "res://assets/sprites/PassEffect/PassEffect_Chapter2",
		"frame_prefix": "PassEffect_Chapter2_",
	},
	3: {
		"frame_dir": "res://assets/sprites/PassEffect/PassEffect_Chapter3",
		"frame_prefix": "PassEffect_Chapter3_",
	},
	4: {
		"frame_dir": "res://assets/sprites/PassEffect/PassEffect_ChapterBoss",
		"frame_prefix": "PassEffect_ChapterBoss_",
	},
}
const PASS_EFFECT_FRAME_COUNT := 97
const PASS_EFFECT_FALLBACK_FPS := 24.0
const PASS_EFFECT_BLACK_SCREEN_TIME := 0.8
const NEXT_STAGE_PRELOAD_BLACK_TIMEOUT := 3.0
# ChapterBoss 通关后的游戏结束动画（EndEffect）
const END_EFFECT_FRAME_DIR := "res://assets/sprites/EndEffect"
const END_EFFECT_FRAME_PREFIX := "EndEffect_Base_"
const END_EFFECT_FRAME_FIRST_INDEX := 1
const END_EFFECT_FRAME_COUNT := 23
const END_EFFECT_WORD_PATH := "res://assets/sprites/EndEffect/EndEffect_Word.png"
const END_EFFECT_AUDIO_PATH := "res://assets/audio/EndEffect.mp3"
const END_EFFECT_FPS := PASS_EFFECT_FALLBACK_FPS / 2.0 * 0.8
const END_EFFECT_BLACK_FADE_TIME := 1.0
const END_EFFECT_WORD_FADE_TIME := 4.0
const END_EFFECT_WORD_FADE_FPS := PASS_EFFECT_FALLBACK_FPS
# EndEffect 播放 5 秒后，在画面底部显示返回开始界面的提示文字。
const END_EFFECT_PROMPT_DELAY := 5.0
# 提示文字以透明度 0% → 100% 在 3 秒内逐渐呈现。
const END_EFFECT_PROMPT_FADE_TIME := 3.0
const END_EFFECT_PROMPT_FADE_FPS := PASS_EFFECT_FALLBACK_FPS
const END_EFFECT_PROMPT_TEXT := "按回车键回到开始界面"
const ACTIVE_BALL_GROUP := "active_ghost_balls"
static var _fdk_mechanism_texture_cache: Texture2D = null

@export var stage_number: int = 1
@export var time_limit: float = 90.0

const TILE_SOURCES := {"#": 0, ".": 1, "=": 2}
const NOGO_CHAR := "X"
const PICKUP_TYPES := {}

var time_remaining: float
var enemies_remaining: int = 0
var level_complete: bool = false
var ready_done: bool = false
var spawn_pos: Vector2 = Vector2(100, 500)
var bgm_player: AudioStreamPlayer = null
var _pass_effect_frames: Array[Texture2D] = []
var _pass_effect_audio_stream: AudioStream = null
var _pass_effect_assets_loading: bool = false
# 退出 / 切场景收尾标志：置位后所有异步资源加载协程立即停止 await，避免被
# 挂起的协程在进程退出时残留 GDScript 函数状态（RefCounted），触发
# "ObjectDB instances leaked at exit"。
var _tearing_down: bool = false
var _chapter3_mechanism_preview: CanvasLayer = null
var _pass_effect_layer: CanvasLayer = null
var _pass_effect_frame_view: TextureRect = null
var _pass_effect_audio_player: AudioStreamPlayer = null
var _end_effect_frames: Array[Texture2D] = []
var _end_effect_word_texture: Texture2D = null
var _end_effect_layer: CanvasLayer = null
var _end_effect_frame_view: TextureRect = null
var _end_effect_word_view: TextureRect = null
var _end_effect_audio_player: AudioStreamPlayer = null
var _end_effect_prompt_label: Label = null
var _end_effect_can_return: bool = false

@onready var tile_map: TileMapLayer = $TileMap
@onready var nogo_map: TileMapLayer = $NoGoMap
@onready var enemy_container: Node2D = $Enemies
@onready var pickup_container: Node2D = $Pickups
@onready var player_container: Node2D = $PlayerHolder
@onready var ui: CanvasLayer = $UI
@onready var platform_container: Node2D = $FloatingPlatforms

func _ready() -> void:
	add_to_group("level")
	# Lazy-load enemy scenes to avoid preload()-time script compilation race
	# (enemy.gd references CharTuning autoload; preload may run before autoloads register)
	METEOR_HAMMER_SCENE = GameState.load_transition_or_file("res://scenes/enemy_meteor_hammer.tscn") as PackedScene
	RED_GHOST_SCENE = GameState.load_transition_or_file("res://scenes/enemy_red_ghost.tscn") as PackedScene
	RED_DEVIL_SCENE = GameState.load_transition_or_file("res://scenes/enemy_red_devil.tscn") as PackedScene
	PALACE_ZOMBIE_SCENE = GameState.load_transition_or_file("res://scenes/enemy_palace_zombie.tscn") as PackedScene
	FAT_DEMON_KING_SCENE = GameState.load_transition_or_file("res://scenes/enemy_fat_demon_king.tscn") as PackedScene
	BOSS_SCENE = GameState.load_transition_or_file("res://scenes/enemy_boss.tscn") as PackedScene
	_setup_shared_chapter_bg()
	time_remaining = time_limit
	GameState.current_stage = stage_number
	GameState.stage_changed.emit(stage_number)
	_build_level()
	_spawn_chapter3_mechanism_preview()
	tile_map.visible = false
	ready_done = true
	_prepare_pass_effect_assets()
	# 延后一帧再放 BGM（让首帧渲染先完成，避免开场卡顿叠加音频解码）。
	# 不用 `await RenderingServer.frame_post_draw`：等待引擎级 server 信号会创建一个
	# 连到 RenderingServer 的一次性信号 awaiter（RefCounted），若本关在该帧前被释放
	# （切场景 / 退出），awaiter 与 "frame_post_draw" StringName 会残留，触发
	# "ObjectDB instances leaked at exit" / "Orphan StringName"。改用挂在本节点下、
	# 随节点一起销毁的 Timer（GameState.wait），生命周期受控、无残留。
	await GameState.wait(self, 0.0)
	if is_inside_tree():
		_play_stage_bgm()

# 关卡动画背景（Background_b）复用 GameState 常驻的共享 SpriteFrames。
# 22 张 1920×1080 背景帧不再内嵌在各关 .tscn 里逐关卸载/重载，切关时直接命中缓存，
# 消除单线程 Web 下切场景那一帧的解码/上传卡顿。
func _setup_shared_chapter_bg() -> void:
	var bg := get_node_or_null("Background_b") as AnimatedSprite2D
	if bg == null:
		return
	var frames := GameState.get_shared_chapter_bg_frames()
	if frames == null or frames.get_frame_count(GameState.CHAPTER_BG_ANIM_NAME) == 0:
		return
	bg.sprite_frames = frames
	bg.play(GameState.CHAPTER_BG_ANIM_NAME)

func _exit_tree() -> void:
	if CharTuning.tuning_changed.is_connected(_apply_chapter3_mechanism_preview_tuning):
		CharTuning.tuning_changed.disconnect(_apply_chapter3_mechanism_preview_tuning)
	# 切场景时把本关 AnimatedSprite2D 对共享 SpriteFrames 的引用解除，避免节点销毁流程中
	# 误连带释放常驻缓存；SpriteFrames 本体由 GameState 持有、跨关常驻。
	var bg := get_node_or_null("Background_b") as AnimatedSprite2D
	if bg != null:
		bg.sprite_frames = null
	release_cached_resources_for_quit()

func release_cached_resources_for_quit() -> void:
	_tearing_down = true
	_pass_effect_assets_loading = false
	if is_instance_valid(_pass_effect_frame_view):
		_pass_effect_frame_view.texture = null
	_pass_effect_frame_view = null
	if is_instance_valid(_pass_effect_audio_player):
		_pass_effect_audio_player.stop()
		_pass_effect_audio_player.stream = null
	_pass_effect_audio_player = null
	_pass_effect_layer = null
	_pass_effect_frames.clear()
	_pass_effect_audio_stream = null
	if is_instance_valid(_end_effect_frame_view):
		_end_effect_frame_view.texture = null
	_end_effect_frame_view = null
	if is_instance_valid(_end_effect_word_view):
		_end_effect_word_view.texture = null
	_end_effect_word_view = null
	_end_effect_layer = null
	_end_effect_frames.clear()
	_end_effect_word_texture = null
	if is_instance_valid(_end_effect_audio_player):
		_end_effect_audio_player.stop()
		_end_effect_audio_player.stream = null
	_end_effect_audio_player = null
	if is_instance_valid(bgm_player):
		bgm_player.stop()
		bgm_player.stream = null
	bgm_player = null

func _play_stage_bgm() -> void:
	if not STAGE_BGM_PATHS.has(stage_number):
		return
	var bgm_path: String = STAGE_BGM_PATHS[stage_number]
	var stream := GameState.load_transition_or_file(bgm_path) as AudioStream
	if stream == null:
		push_warning("Stage %d BGM not found: %s" % [stage_number, bgm_path])
		return
	if stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true
	bgm_player = AudioStreamPlayer.new()
	bgm_player.name = "Stage%dBGM" % stage_number
	bgm_player.stream = stream
	add_child(bgm_player)
	bgm_player.play()
	GameState.clear_transition_resource_cache()

func _spawn_chapter3_mechanism_preview() -> void:
	if stage_number != 3:
		return
	_chapter3_mechanism_preview = CanvasLayer.new()
	_chapter3_mechanism_preview.name = "Chapter3MechanismPreview"
	_chapter3_mechanism_preview.layer = 90
	var center_node := Node2D.new()
	center_node.name = "ScreenCenter"
	var pivot_node := Node2D.new()
	pivot_node.name = "MechanismPivot"
	var sprite_node := Sprite2D.new()
	sprite_node.name = "MechanismSprite"
	sprite_node.texture = _load_fdk_mechanism_texture()
	sprite_node.z_index = 100
	pivot_node.add_child(sprite_node)
	# 静止铁球预览：停在机关平台右侧（与运行时机关展示一致）
	var rest_ball := Sprite2D.new()
	rest_ball.name = "RestIronBall"
	rest_ball.texture = GameState.load_transition_or_file(FDK_IRON_BALL_TEXTURE) as Texture2D
	rest_ball.scale = Vector2(FDK_IRON_BALL_PREVIEW_SCALE, FDK_IRON_BALL_PREVIEW_SCALE)
	rest_ball.z_index = 102
	pivot_node.add_child(rest_ball)
	var pivot_cross := Node2D.new()
	pivot_cross.name = "MechanismPivotCross"
	pivot_cross.z_index = 101
	var cross_col := Color(1.0, 0.15, 0.15, 0.95)
	var cross_half := FDK_MECHANISM_PIVOT_CROSS_SIZE
	var cross_h := Line2D.new()
	cross_h.name = "CrossHorizontal"
	cross_h.points = PackedVector2Array([Vector2(-cross_half, 0.0), Vector2(cross_half, 0.0)])
	cross_h.width = FDK_MECHANISM_PIVOT_CROSS_WIDTH
	cross_h.default_color = cross_col
	pivot_cross.add_child(cross_h)
	var cross_v := Line2D.new()
	cross_v.name = "CrossVertical"
	cross_v.points = PackedVector2Array([Vector2(0.0, -cross_half), Vector2(0.0, cross_half)])
	cross_v.width = FDK_MECHANISM_PIVOT_CROSS_WIDTH
	cross_v.default_color = cross_col
	pivot_cross.add_child(cross_v)
	pivot_node.add_child(pivot_cross)
	center_node.add_child(pivot_node)
	_chapter3_mechanism_preview.add_child(center_node)
	add_child(_chapter3_mechanism_preview)
	_apply_chapter3_mechanism_preview_tuning()
	CharTuning.tuning_changed.connect(_apply_chapter3_mechanism_preview_tuning)

func _apply_chapter3_mechanism_preview_tuning() -> void:
	if _chapter3_mechanism_preview == null or not is_instance_valid(_chapter3_mechanism_preview):
		return
	# 预览仅作为 F1 调参的摆放辅助：面板打开时才显示（倾斜角、铁球静止展示）。
	# 正常游戏中机关默认平行(0°)，由胖魔王 FatDemonKing_Attack1 触发倾斜与铁球滚落。
	var tuning_panel := get_tree().get_first_node_in_group("tuning_panel")
	_chapter3_mechanism_preview.visible = tuning_panel != null and tuning_panel.visible
	if not _chapter3_mechanism_preview.visible:
		return
	var center_node := _chapter3_mechanism_preview.get_node_or_null("ScreenCenter") as Node2D
	if center_node == null:
		return
	center_node.position = get_viewport().get_visible_rect().size * 0.5
	var pivot_node := center_node.get_node_or_null("MechanismPivot") as Node2D
	if pivot_node == null:
		return
	pivot_node.position = Vector2(CharTuning.fdk_mechanism_pivot_x, CharTuning.fdk_mechanism_pivot_y)
	pivot_node.rotation_degrees = CharTuning.fdk_mechanism_rotation
	_update_chapter3_mechanism_pivot_cross(pivot_node)
	var sprite_node := pivot_node.get_node_or_null("MechanismSprite") as Sprite2D
	if sprite_node == null:
		return
	sprite_node.position = Vector2(CharTuning.fdk_mechanism_pos_x, CharTuning.fdk_mechanism_pos_y) - pivot_node.position
	var s: float = max(0.01, CharTuning.fdk_mechanism_scale)
	sprite_node.scale = Vector2(s, s)
	sprite_node.offset = Vector2.ZERO
	# 静止铁球预览：停在机关平台左侧（贴图左端附近、表面之上），与运行时一致——倾斜后从左侧斜面滑下
	# 铁球美术大小跟随 F1 的“铁球美术大小”实时调整。
	var rest_ball := pivot_node.get_node_or_null("RestIronBall") as Sprite2D
	if rest_ball != null and sprite_node.texture != null:
		var ball_scale: float = max(0.01, CharTuning.fdk_ball_scale)
		rest_ball.scale = Vector2(ball_scale, ball_scale)
		var half_w := sprite_node.texture.get_width() * 0.5 * s
		var ball_r := FDK_IRON_BALL_PREVIEW_RADIUS * ball_scale
		var rest_offset := Vector2(CharTuning.fdk_ball_rest_offset_x, CharTuning.fdk_ball_rest_offset_y)
		rest_ball.position = sprite_node.position + Vector2(-half_w * 0.7, -ball_r) + rest_offset

func refresh_chapter3_mechanism_preview_debug() -> void:
	_apply_chapter3_mechanism_preview_tuning()

func _update_chapter3_mechanism_pivot_cross(pivot_node: Node2D) -> void:
	var pivot_cross := pivot_node.get_node_or_null("MechanismPivotCross") as Node2D
	if pivot_cross == null:
		return
	var tuning_panel := get_tree().get_first_node_in_group("tuning_panel")
	pivot_cross.visible = tuning_panel != null and tuning_panel.visible

func _get_viewport_center_global() -> Vector2:
	var camera := get_viewport().get_camera_2d()
	if camera != null:
		return camera.get_screen_center_position()
	var screen_center := get_viewport().get_visible_rect().size * 0.5
	return get_viewport().get_canvas_transform().affine_inverse() * screen_center

static func _load_fdk_mechanism_texture() -> Texture2D:
	if _fdk_mechanism_texture_cache != null:
		return _fdk_mechanism_texture_cache
	_fdk_mechanism_texture_cache = GameState.load_transition_or_file(FDK_MECHANISM_TEXTURE) as Texture2D
	if _fdk_mechanism_texture_cache == null:
		push_warning("Failed to load Chapter3 mechanism PNG: %s" % FDK_MECHANISM_TEXTURE)
		return null
	return _fdk_mechanism_texture_cache

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
	_spawn_floating_platforms()

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
	elif ch == "F":
		# 第 3 关（chapter3）的唯一通关条件是消灭胖魔王，即便场上还有其他敌人。
		# 因此胖魔王死亡时直接触发通关，而不依赖 enemies_remaining 归零。
		var fdk_is_win_target := stage_number == 3
		_spawn_enemy(FAT_DEMON_KING_SCENE, world_pos, fdk_is_win_target)
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

func _spawn_enemy(scene: PackedScene, pos: Vector2, is_win_target: bool = false) -> void:
	var e = scene.instantiate()
	e.position = pos
	enemy_container.add_child(e)
	enemies_remaining += 1
	e.tree_exited.connect(_on_enemy_removed)
	# 通关目标敌人（如 chapter3 的胖魔王）：其死亡直接触发通关，无视其他残余敌人。
	if is_win_target:
		e.tree_exited.connect(_on_win_target_removed)

func _spawn_floating_platforms() -> void:
	if platform_container == null:
		return
	for data in LevelData.FLOATING_PLATFORMS.get(stage_number, []):
		var platform := FLOATING_PLATFORM_SCRIPT.new()
		platform.configure(data)
		platform_container.add_child(platform)

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
	# 召唤的敌人出现后头 1 秒内不对钟馗造成接触伤害（给玩家反应空间）
	if "contact_damage_delay_t" in e and "SUMMON_CONTACT_DAMAGE_DELAY" in e:
		e.contact_damage_delay_t = e.SUMMON_CONTACT_DAMAGE_DELAY
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
				_append_platform_record(grid, run_start, x - 1, y)
				run_start = -1
		if run_start >= 0:
			_append_platform_record(grid, run_start, row.length() - 1, y)

# 判断网格 (x, y) 处是否为"实心碰撞"格：地面 "#"、平台 "="、以及禁行墙 "X"
# 都在 tileset physics_layer_0（碰撞层 1）上有碰撞体，会挡住敌人。
# 越界视为无碰撞（空）。
func _is_solid_tile(grid: Array, x: int, y: int) -> bool:
	if y < 0 or y >= grid.size():
		return false
	var row: String = grid[y]
	if x < 0 or x >= row.length():
		return false
	var ch := row[x]
	return TILE_SOURCES.has(ch) or ch == NOGO_CHAR

func _append_platform_record(grid: Array, x0: int, x1: int, y: int) -> void:
	if x1 - x0 < 1:
		return  # 与 _collect_platform_run 一致：至少 2 格宽
	# 平台站立面是平台行上方一格（surface_row = y-1）。
	# 若该行的最左 / 最右若干格被实心墙（如 chapter3 中层平台左端那根竖墙）占据，
	# 敌人会卡在墙与平台地面之间的夹角里 ──「插在平台左侧」。
	# 因此把 x0 / x1 向内收，跳过站立面上被墙占据的边缘格，使 left_x / right_x
	# 反映真正可行走的范围。所有消费 get_platforms() 的逻辑（含胖魔王 Attack3 召唤落点）
	# 都因此自动避开墙角。
	var surface_row := y - 1
	var walk_x0 := x0
	var walk_x1 := x1
	while walk_x0 <= walk_x1 and _is_solid_tile(grid, walk_x0, surface_row):
		walk_x0 += 1
	while walk_x1 >= walk_x0 and _is_solid_tile(grid, walk_x1, surface_row):
		walk_x1 -= 1
	if walk_x1 - walk_x0 < 1:
		return  # 收缩后不足 2 格宽，无可站立空间
	var width_tiles := walk_x1 - walk_x0 + 1
	var cap: int = clamp(width_tiles / PLATFORM_CAPACITY_TILES_PER_SLOT,
		PLATFORM_CAPACITY_MIN, PLATFORM_CAPACITY_MAX)
	var top_y := float(y - 1) * TILE_PX + TILE_PX / 2.0
	var left_x := float(walk_x0) * TILE_PX + TILE_PX / 2.0
	var right_x := float(walk_x1) * TILE_PX + TILE_PX / 2.0
	var center_x := (left_x + right_x) * 0.5
	_platforms_cache.append({
		"id": _platforms_cache.size(),
		"row": y,
		"x0": walk_x0,
		"x1": walk_x1,
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
	# 开发用：按 N 直接跳过当前关卡。
	# - ChapterBoss 关卡（有 EndEffect）：直接跳到游戏结束动画 EndEffect。
	# - 其它关卡：走与正常通关相同的 _on_stage_clear() 流程，但不播放通关 PassEffect。
	if Input.is_action_just_pressed("skip_level"):
		if _has_end_effect_for_stage():
			_skip_to_end_effect()
		else:
			_on_stage_clear(true)

func _input(event: InputEvent) -> void:
	# EndEffect 播放 5 秒后，按回车键回到开始界面。
	if _end_effect_can_return and event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		_end_effect_can_return = false
		GameState.goto_main_menu()

func _on_enemy_removed() -> void:
	enemies_remaining -= 1
	if not is_inside_tree():
		return
	if enemies_remaining <= 0 and not level_complete and ready_done:
		_on_stage_clear()

# 通关目标敌人（chapter3 胖魔王）被消灭：立即通关，即便场上仍有其他敌人。
func _on_win_target_removed() -> void:
	if not is_inside_tree():
		return
	if not level_complete and ready_done:
		_on_stage_clear()

func on_boss_defeated() -> void:
	if level_complete:
		return
	# ChapterBoss 的通关动画要紧跟 Boss 死亡动画结束播放，因此不再等待场上 active balls。
	_on_stage_clear(false, true)

# 开发用：在 ChapterBoss 关卡按 N 直接跳到游戏结束动画 EndEffect，
# 跳过通关 PassEffect、不等待场上 active balls。
func _skip_to_end_effect() -> void:
	if level_complete:
		return
	level_complete = true
	GameState.mark_level_cleared()
	await _play_end_effect()

func _on_time_up() -> void:
	if level_complete:
		return
	level_complete = true
	GameState.goto_game_over()

func _on_stage_clear(skip_pass_effect: bool = false, skip_active_ball_wait: bool = false) -> void:
	if level_complete:
		return
	level_complete = true
	# 进入通关流程后屏蔽延迟触发的 game_over（如玩家葫芦持有敌人，通关动画期间
	# hold_timer 超时引爆），避免动画播完后被错误切到 GAME OVER 而非下一关。
	GameState.mark_level_cleared()
	GameState.add_score(int(time_remaining) * 10)
	# 趁通关动画/黑场这段主线程相对空闲的时间，提前线程预加载下一关需要同步 load 的
	# 重资源（尤其是 Boss 关 150+ 张序列帧）。否则切场景那一帧会被同步加载阻塞而卡顿。
	_preload_next_stage_assets()
	if not skip_active_ball_wait:
		await _wait_for_active_balls_to_finish()
	if skip_pass_effect:
		pass
	elif _has_pass_effect_for_stage():
		await _play_pass_effect()
		# ChapterBoss 通关后紧接播放游戏结束动画（永久循环，不再切换场景）。
		if _has_end_effect_for_stage():
			await _play_end_effect()
			return
		await _show_pass_effect_black_screen(stage_number + 1)
	else:
		await GameState.wait(self, 1.5)
	var next_stage := stage_number + 1
	GameState.current_stage = stage_number
	if GameState.advance_stage() and GameState.current_stage == next_stage:
		# 切场景是同步的——先把已预加载的下一关场景与重资源取回（注销线程加载请求并写入
		# 过渡缓存 / Boss 静态缓存），确保下一关 _ready 的 load() 命中缓存。
		var packed := _collect_next_stage_assets(next_stage)
		GameState.goto_stage(next_stage, packed)
	else:
		GameState.goto_victory()

# 判断指定关卡是否包含 Boss（地图中存在 'B' 标记）。
static func _stage_has_boss(stage: int) -> bool:
	var grid: Array = LevelData.LEVELS.get(stage, [])
	for row in grid:
		if String(row).find("B") != -1:
			return true
	return false

# 返回下一关 _ready() 会立刻同步 load 的资源路径。通关动画期间先请求这些资源，
# 到新关 _ready() 时通过 GameState 的过渡缓存或 ResourceLoader 缓存直接命中。
static func get_stage_preload_resource_paths(stage: int) -> Array[String]:
	var paths: Array[String] = []
	for path in ENEMY_SCENE_PATHS:
		paths.append(str(path))
	if STAGE_BGM_PATHS.has(stage):
		paths.append(str(STAGE_BGM_PATHS[stage]))
	if stage == 3:
		paths.append(FDK_MECHANISM_TEXTURE)
		paths.append(FDK_IRON_BALL_TEXTURE)
	if _stage_has_boss(stage):
		for path in Boss.get_preload_resource_paths():
			paths.append(str(path))
	return _dedupe_paths(paths)

static func _dedupe_paths(paths: Array[String]) -> Array[String]:
	var seen := {}
	var deduped: Array[String] = []
	for path in paths:
		if seen.has(path):
			continue
		seen[path] = true
		deduped.append(path)
	return deduped

# 在切到下一关之前，提前发起下一关场景与重资源的线程预加载（非阻塞）。
# 通关动画/黑场期间后台线程完成加载，避免切场景那一帧同步解包关卡背景与 150+ 张贴图。
func _preload_next_stage_assets() -> void:
	var next_stage := stage_number + 1
	if not GameState.has_stage(next_stage):
		return
	GameState.request_threaded_load(GameState.get_stage_scene_path(next_stage))
	for path in get_stage_preload_resource_paths(next_stage):
		GameState.request_threaded_load(path)

# 切场景前把预加载结果取回：注销 GameState 的待取回登记（避免 RefCounted 残留），
# 并将资源登记到 Boss 静态缓存以持有引用。资源随之进入 ResourceLoader 缓存，
# 下一关 Boss._ready() 里的 load() 即可即时命中而不再读盘解码。
func _collect_next_stage_assets(next_stage: int) -> PackedScene:
	var scene_path := GameState.get_stage_scene_path(next_stage)
	var packed := GameState.take_threaded_load(scene_path) as PackedScene

	var boss_paths := {}
	if _stage_has_boss(next_stage):
		for path in Boss.get_preload_resource_paths():
			boss_paths[path] = true

	for path in get_stage_preload_resource_paths(next_stage):
		var res := GameState.take_threaded_load(path)
		if res != null:
			GameState.hold_transition_resource(path, res)
			if boss_paths.has(path):
				Boss.register_preloaded(path, res)
	return packed

func _next_stage_assets_done(next_stage: int) -> bool:
	if not GameState.has_stage(next_stage):
		return true
	if not _threaded_path_done(GameState.get_stage_scene_path(next_stage)):
		return false
	for path in get_stage_preload_resource_paths(next_stage):
		if not _threaded_path_done(path):
			return false
	return true

func _threaded_path_done(path: String) -> bool:
	if not GameState.has_pending_threaded_load(path):
		return true
	var status := ResourceLoader.load_threaded_get_status(path)
	return status != ResourceLoader.THREAD_LOAD_IN_PROGRESS

func _play_pass_effect() -> void:
	if is_instance_valid(bgm_player) and bgm_player.playing:
		bgm_player.stop()

	await _ensure_pass_effect_assets_ready()
	var frames := _pass_effect_frames
	var audio_stream := _pass_effect_audio_stream
	if frames.is_empty():
		push_warning("Pass effect frames not found in %s" % _get_pass_effect_frame_dir())
		await GameState.wait(self, 1.5)
		return

	var layer := CanvasLayer.new()
	layer.name = "PassEffectLayer"
	layer.layer = 100
	add_child(layer)
	_pass_effect_layer = layer

	var frame_view := TextureRect.new()
	frame_view.name = "PassEffectFrame"
	frame_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	frame_view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	frame_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(frame_view)
	_pass_effect_frame_view = frame_view

	var audio_player := AudioStreamPlayer.new()
	audio_player.name = "PassEffectAudio"
	if audio_stream != null:
		audio_player.stream = audio_stream
	layer.add_child(audio_player)
	_pass_effect_audio_player = audio_player
	if audio_player.stream != null:
		audio_player.play()
	else:
		push_warning("Pass effect audio not found: %s" % PASS_EFFECT_AUDIO_PATH)

	var duration := _get_pass_effect_duration(audio_player.stream)
	var frame_time := duration / float(frames.size())
	var frame_index := 0
	while frame_index < frames.size() and is_inside_tree():
		frame_view.texture = frames[frame_index]
		await GameState.wait(self, frame_time)
		frame_index += 1

	if is_instance_valid(audio_player) and audio_player.playing:
		await audio_player.finished
	if is_instance_valid(frame_view):
		frame_view.texture = null
	if is_instance_valid(audio_player):
		audio_player.stream = null
	if is_instance_valid(layer):
		layer.queue_free()
	_pass_effect_frame_view = null
	_pass_effect_audio_player = null
	_pass_effect_layer = null

func play_pass_effect_for_game_over() -> void:
	await _play_pass_effect()

func lock_for_game_over() -> void:
	level_complete = true

func _show_pass_effect_black_screen(next_stage: int = -1) -> void:
	if not is_inside_tree():
		return

	var layer := CanvasLayer.new()
	layer.name = "PassEffectBlackScreenLayer"
	layer.layer = 101
	add_child(layer)

	var black_screen := ColorRect.new()
	black_screen.name = "PassEffectBlackScreen"
	black_screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	black_screen.color = Color.BLACK
	black_screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(black_screen)

	var elapsed := 0.0
	while is_inside_tree():
		var min_time_done := elapsed >= PASS_EFFECT_BLACK_SCREEN_TIME
		var next_stage_done := next_stage < 1 or _next_stage_assets_done(next_stage)
		var preload_wait_expired := elapsed >= PASS_EFFECT_BLACK_SCREEN_TIME + NEXT_STAGE_PRELOAD_BLACK_TIMEOUT
		if min_time_done and (next_stage_done or preload_wait_expired):
			return
		await GameState.wait(self, 0.05)
		elapsed += 0.05

func _play_end_effect() -> void:
	if is_instance_valid(bgm_player) and bgm_player.playing:
		bgm_player.stop()

	await _ensure_end_effect_assets_ready()
	var frames := _end_effect_frames
	if frames.is_empty():
		push_warning("End effect frames not found in %s" % END_EFFECT_FRAME_DIR)
		return

	var end_effect_stream := load(END_EFFECT_AUDIO_PATH) as AudioStream
	if end_effect_stream != null:
		if end_effect_stream is AudioStreamMP3:
			(end_effect_stream as AudioStreamMP3).loop = true
		_end_effect_audio_player = AudioStreamPlayer.new()
		_end_effect_audio_player.name = "EndEffectBGM"
		_end_effect_audio_player.stream = end_effect_stream
		add_child(_end_effect_audio_player)
		_end_effect_audio_player.play()
	else:
		push_warning("EndEffect.mp3 not found: %s" % END_EFFECT_AUDIO_PATH)

	var layer := CanvasLayer.new()
	layer.name = "EndEffectLayer"
	layer.layer = 102
	add_child(layer)
	_end_effect_layer = layer

	# 序列帧画面（底层）
	var frame_view := TextureRect.new()
	frame_view.name = "EndEffectFrame"
	frame_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	frame_view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	frame_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame_view.texture = frames[0]
	layer.add_child(frame_view)
	_end_effect_frame_view = frame_view

	# 文字层（叠在序列帧之上，居中显示）
	var word_view := TextureRect.new()
	word_view.name = "EndEffectWord"
	word_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	word_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	word_view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	word_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	word_view.texture = _end_effect_word_texture
	word_view.modulate = Color(1.0, 1.0, 1.0, 0.0)
	layer.add_child(word_view)
	_end_effect_word_view = word_view

	# 黑场层（叠在最上，用于第一遍由黑到亮的渐变）
	var black_screen := ColorRect.new()
	black_screen.name = "EndEffectBlackScreen"
	black_screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	black_screen.color = Color.BLACK
	black_screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(black_screen)

	# 提示文字层（叠在最上，初始隐藏，播放 5 秒后显示）。
	# 字号/描边与开始界面 LoadingLabel 保持一致。
	var prompt_label := Label.new()
	prompt_label.name = "EndEffectPrompt"
	prompt_label.text = END_EFFECT_PROMPT_TEXT
	prompt_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	prompt_label.offset_left = -360.0
	prompt_label.offset_right = -16.0
	prompt_label.offset_top = -48.0
	prompt_label.offset_bottom = -8.0
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	prompt_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	prompt_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	prompt_label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	prompt_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	prompt_label.add_theme_constant_override("outline_size", 5)
	prompt_label.add_theme_font_size_override("font_size", 28)
	prompt_label.visible = false
	prompt_label.modulate = Color(1.0, 1.0, 1.0, 0.0)
	layer.add_child(prompt_label)
	_end_effect_prompt_label = prompt_label

	# 5 秒后显示提示文字并允许按回车返回开始界面。
	_start_end_effect_prompt_timer()

	var frame_time := 1.0 / END_EFFECT_FPS
	var frame_index := 0

	# 第一遍：黑场（1秒内由全黑渐变到正常亮度），序列帧同步循环播放。
	var elapsed := 0.0
	while elapsed < END_EFFECT_BLACK_FADE_TIME and is_inside_tree():
		if _tearing_down or frames.is_empty():
			return
		var alpha: float = clampf(1.0 - elapsed / END_EFFECT_BLACK_FADE_TIME, 0.0, 1.0)
		black_screen.color = Color(0.0, 0.0, 0.0, alpha)
		frame_view.texture = frames[frame_index]
		await GameState.wait(self, frame_time)
		if _tearing_down or frames.is_empty():
			return
		elapsed += frame_time
		frame_index = (frame_index + 1) % frames.size()
	if not is_inside_tree():
		return
	black_screen.color = Color(0.0, 0.0, 0.0, 0.0)

	# 黑场结束后：EndEffect_Word.png 在 4 秒内丝滑地从透明度 0% → 100% 显现，
	# 文字层以 24fps 单独更新，不受 EndEffect_Base 序列帧速率影响；
	# 序列帧仍按自身速率（END_EFFECT_FPS）独立循环播放。
	elapsed = 0.0
	var word_step := 1.0 / END_EFFECT_WORD_FADE_FPS
	var frame_accumulator := 0.0
	while elapsed < END_EFFECT_WORD_FADE_TIME and is_inside_tree():
		if _tearing_down or frames.is_empty():
			return
		var word_alpha: float = clampf(elapsed / END_EFFECT_WORD_FADE_TIME, 0.0, 1.0)
		word_view.modulate = Color(1.0, 1.0, 1.0, word_alpha)
		frame_view.texture = frames[frame_index]
		await GameState.wait(self, word_step)
		if _tearing_down or frames.is_empty():
			return
		elapsed += word_step
		# 序列帧按自身帧率推进，与文字渐变解耦。
		frame_accumulator += word_step
		while frame_accumulator >= frame_time:
			if frames.is_empty():
				return
			frame_accumulator -= frame_time
			frame_index = (frame_index + 1) % frames.size()
	if not is_inside_tree():
		return
	word_view.modulate = Color(1.0, 1.0, 1.0, 1.0)

	# 后续：序列帧永久循环，Word 恒显，不再黑场也不再渐变。
	while is_inside_tree():
		if _tearing_down or frames.is_empty():
			return
		frame_view.texture = frames[frame_index]
		await GameState.wait(self, frame_time)
		if _tearing_down or frames.is_empty():
			return
		frame_index = (frame_index + 1) % frames.size()

func _start_end_effect_prompt_timer() -> void:
	await GameState.wait(self, END_EFFECT_PROMPT_DELAY)
	if not is_inside_tree():
		return
	# 提示文字以透明度 0% → 100% 在 3 秒内逐渐呈现。
	if is_instance_valid(_end_effect_prompt_label):
		_end_effect_prompt_label.modulate = Color(1.0, 1.0, 1.0, 0.0)
		_end_effect_prompt_label.visible = true
		var fade_step := 1.0 / END_EFFECT_PROMPT_FADE_FPS
		var elapsed := 0.0
		while elapsed < END_EFFECT_PROMPT_FADE_TIME and is_inside_tree() and is_instance_valid(_end_effect_prompt_label):
			var alpha: float = clampf(elapsed / END_EFFECT_PROMPT_FADE_TIME, 0.0, 1.0)
			_end_effect_prompt_label.modulate = Color(1.0, 1.0, 1.0, alpha)
			await GameState.wait(self, fade_step)
			elapsed += fade_step
		if is_instance_valid(_end_effect_prompt_label):
			_end_effect_prompt_label.modulate = Color(1.0, 1.0, 1.0, 1.0)
	_end_effect_can_return = true

func _has_end_effect_for_stage() -> bool:
	return _has_pass_effect_for_stage() and stage_number == 4

func _get_end_effect_frame_path(index: int) -> String:
	return "%s/%s%02d.jpg" % [
		END_EFFECT_FRAME_DIR,
		END_EFFECT_FRAME_PREFIX,
		END_EFFECT_FRAME_FIRST_INDEX + index,
	]

func _ensure_end_effect_assets_ready() -> void:
	if _end_effect_word_texture == null:
		_end_effect_word_texture = _load_texture_from_path(END_EFFECT_WORD_PATH)
		if _end_effect_word_texture == null:
			push_warning("End effect word texture not found: %s" % END_EFFECT_WORD_PATH)
	if _end_effect_frames.size() == END_EFFECT_FRAME_COUNT:
		return
	_end_effect_frames.clear()
	for i in range(END_EFFECT_FRAME_COUNT):
		var frame_path := _get_end_effect_frame_path(i)
		var texture := _load_texture_from_path(frame_path)
		if texture == null:
			push_warning("Missing end effect frame: %s" % frame_path)
			_end_effect_frames.clear()
			return
		_end_effect_frames.append(texture)

func _load_pass_effect_frames() -> Array[Texture2D]:
	var frames: Array[Texture2D] = []
	for i in range(PASS_EFFECT_FRAME_COUNT):
		var frame_path := _get_pass_effect_frame_path(i)
		var texture := _load_texture_from_path(frame_path)
		if texture == null:
			push_warning("Missing pass effect frame: %s" % frame_path)
			return frames
		frames.append(texture)
	return frames

func _load_texture_from_path(path: String) -> Texture2D:
	return load(path) as Texture2D

func _get_pass_effect_duration(stream: AudioStream) -> float:
	if stream != null and stream.get_length() > 0.0:
		return stream.get_length()
	return float(PASS_EFFECT_FRAME_COUNT) / PASS_EFFECT_FALLBACK_FPS

func _prepare_pass_effect_assets() -> void:
	if not _has_pass_effect_for_stage():
		return
	GameState.request_threaded_load(PASS_EFFECT_AUDIO_PATH)
	for i in range(PASS_EFFECT_FRAME_COUNT):
		GameState.request_threaded_load(_get_pass_effect_frame_path(i))
	call_deferred("_cache_pass_effect_assets_async")

func _cache_pass_effect_assets_async() -> void:
	await _ensure_pass_effect_assets_ready()

func _ensure_pass_effect_assets_ready() -> void:
	if not _has_pass_effect_for_stage():
		return
	while _pass_effect_assets_loading:
		if _tearing_down or not is_inside_tree():
			return
		await get_tree().process_frame
	if _pass_effect_audio_stream != null and _pass_effect_frames.size() == PASS_EFFECT_FRAME_COUNT:
		return

	_pass_effect_assets_loading = true
	if _pass_effect_audio_stream == null:
		_pass_effect_audio_stream = await _get_threaded_audio(PASS_EFFECT_AUDIO_PATH)
	if _pass_effect_frames.size() == PASS_EFFECT_FRAME_COUNT:
		_pass_effect_assets_loading = false
		return

	_pass_effect_frames.clear()
	for i in range(PASS_EFFECT_FRAME_COUNT):
		var frame_path := _get_pass_effect_frame_path(i)
		var status := ResourceLoader.load_threaded_get_status(frame_path)
		while status == ResourceLoader.THREAD_LOAD_IN_PROGRESS and is_inside_tree():
			if _tearing_down:
				_pass_effect_assets_loading = false
				return
			await get_tree().process_frame
			status = ResourceLoader.load_threaded_get_status(frame_path)

		var texture: Texture2D = null
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			texture = GameState.take_threaded_load(frame_path) as Texture2D
		if texture == null:
			texture = _load_texture_from_path(frame_path)
		if texture == null:
			push_warning("Missing pass effect frame: %s" % frame_path)
			_pass_effect_frames.clear()
			_pass_effect_assets_loading = false
			return
		_pass_effect_frames.append(texture)
	_pass_effect_assets_loading = false

func _get_threaded_audio(path: String) -> AudioStream:
	var status := ResourceLoader.load_threaded_get_status(path)
	while status == ResourceLoader.THREAD_LOAD_IN_PROGRESS and is_inside_tree():
		if _tearing_down:
			return null
		await get_tree().process_frame
		status = ResourceLoader.load_threaded_get_status(path)
	if status == ResourceLoader.THREAD_LOAD_LOADED:
		return GameState.take_threaded_load(path) as AudioStream
	return load(path) as AudioStream

func _get_pass_effect_frame_path(index: int) -> String:
	return "%s/%s%02d.jpg" % [
		_get_pass_effect_frame_dir(),
		_get_pass_effect_frame_prefix(),
		index,
	]

func _has_pass_effect_for_stage() -> bool:
	return PASS_EFFECT_STAGE_CONFIGS.has(stage_number)

func _get_pass_effect_frame_dir() -> String:
	var config: Dictionary = PASS_EFFECT_STAGE_CONFIGS.get(stage_number, {})
	return config.get("frame_dir", "")

func _get_pass_effect_frame_prefix() -> String:
	var config: Dictionary = PASS_EFFECT_STAGE_CONFIGS.get(stage_number, {})
	return config.get("frame_prefix", "")

func _wait_for_active_balls_to_finish() -> void:
	while is_inside_tree():
		var balls := get_tree().get_nodes_in_group(ACTIVE_BALL_GROUP)
		if balls.is_empty():
			return
		await balls[0].tree_exited

func get_spawn_pos() -> Vector2:
	return spawn_pos
