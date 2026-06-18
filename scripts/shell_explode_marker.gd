extends Node2D
# 炮弹爆炸高度/位置可视化标记（橙红色十字光标 + 预览圆环）。
# 显示炮弹将要在哪个世界 Y 消失/爆炸：钟馗当前停留平台的站立面 Y
# 再叠加 F1 调参的 CharTuning.shell_explode_offset_y 偏移。
# 圆环半径随 CharTuning.shell_explode_scale 变化，用来预览爆炸大小。
# 仅在 F1 调参面板打开时显示；z_index 高于爆炸特效（爆炸 z_index=80），显示在其前层。
#
# 用世界坐标自行定位（top_level=true），每帧把自身 global_position 对齐到
# (钟馗 X, 爆炸世界 Y)，并在自身原点处绘制，因此不受 player 缩放/朝向影响。

# 爆炸序列帧贴图为 300×300，scale=1.0 时半径约 150px。爆炸特效是 Sprite2D 直接缩放，
# 这里用 150 × shell_explode_scale 估算可视范围，方便策划对照爆炸大小。
const EXPLODE_BASE_RADIUS := 150.0

# 当前是否能确定爆炸世界坐标（钟馗在已知平台上方）。
var _has_target: bool = false
var _target_pos: Vector2 = Vector2.ZERO

func _ready() -> void:
	z_index = 120  # 高于爆炸特效（z_index=80），确保十字光标在爆炸前层
	top_level = true  # 脱离 player 变换，使用世界坐标自行定位
	process_mode = Node.PROCESS_MODE_ALWAYS
	CharTuning.tuning_changed.connect(queue_redraw)
	add_to_group("shell_explode_marker")
	queue_redraw()

func _process(_delta: float) -> void:
	# 每帧跟随钟馗位置与平台变化重定位 + 重绘
	_update_target()
	if _has_target:
		global_position = _target_pos
	queue_redraw()

func _draw() -> void:
	# 只在 F1 调参面板打开时显示
	var tuning_panel := get_tree().get_first_node_in_group("tuning_panel")
	var panel_visible: bool = tuning_panel != null and tuning_panel.visible
	if not panel_visible:
		return
	# 钟馗不在任何已知平台上方（空中/超界）时无法确定爆炸 Y，不绘制。
	if not _has_target:
		return

	var cross_col := Color(1.0, 0.45, 0.1, 0.95)   # 橙红十字
	var ring_col := Color(1.0, 0.55, 0.2, 0.85)    # 爆炸大小预览圆环
	var r: float = 28.0
	# 十字光标（绘制在自身原点，即爆炸世界位置）
	draw_line(Vector2(-r, 0), Vector2(r, 0), cross_col, 3.0)
	draw_line(Vector2(0, -r), Vector2(0, r), cross_col, 3.0)
	draw_circle(Vector2.ZERO, 6.0, cross_col)
	# 爆炸大小预览圆环：半径随 shell_explode_scale 缩放
	var ring_r: float = EXPLODE_BASE_RADIUS * CharTuning.shell_explode_scale
	draw_arc(Vector2.ZERO, ring_r, 0.0, TAU, 64, ring_col, 2.0)

# 计算炮弹爆炸的世界坐标 (钟馗 X, 平台站立面 Y + 偏移)，写入 _has_target / _target_pos。
func _update_target() -> void:
	_has_target = false
	var player_node := get_tree().get_first_node_in_group("player")
	if player_node == null or not is_instance_valid(player_node) or not (player_node is Node2D):
		return
	var player := player_node as Node2D
	var level := _find_level()
	if level == null:
		return
	var query_pos := _player_foot_world_pos(player)
	var plat: Variant = level.find_platform_for(query_pos)
	if not (plat is Dictionary) or not (plat as Dictionary).has("top_y"):
		return
	var explode_y: float = float((plat as Dictionary)["top_y"]) + CharTuning.shell_explode_offset_y
	_target_pos = Vector2(player.global_position.x, explode_y)
	_has_target = true

# 与 artillery_shell.gd 一致的钟馗脚底世界坐标估算。
func _player_foot_world_pos(player: Node2D) -> Vector2:
	var foot_offset_y: float = CharTuning.body_offset_y + CharTuning.body_height * 0.5
	var col := player.get_node_or_null("Collision") as CollisionShape2D
	if col != null and col.shape is RectangleShape2D:
		foot_offset_y = col.position.y + (col.shape as RectangleShape2D).size.y * 0.5
	return player.global_position + Vector2(0.0, foot_offset_y)

func _find_level() -> Node:
	var lv := get_tree().get_first_node_in_group("level")
	if lv != null and lv.has_method("find_platform_for"):
		return lv
	return null
