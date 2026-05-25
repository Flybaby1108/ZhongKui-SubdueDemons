extends Node2D
# 消失点可视化标记（紫色十字 + 圆点）
# 作为 player 最后一个子节点，确保渲染在 Sprite / SuctionVisual 之上
# 仅在 F1 调参面板打开时可见

func _ready() -> void:
	z_index = 100  # 双保险：高 z_index 确保渲染在所有子节点之上

func _process(_delta: float) -> void:
	# 跟随父节点朝向 + 调参变化，每帧重绘
	queue_redraw()

func _draw() -> void:
	# 只在 F1 调参面板打开时显示
	var tuning_panel = get_tree().get_first_node_in_group("tuning_panel")
	var panel_visible = tuning_panel != null and tuning_panel.visible
	if not panel_visible:
		return
	var player := get_parent()
	if player == null:
		return
	# 朝向跟随 player.facing_right
	var dir_x: float = 1.0
	if "facing_right" in player:
		dir_x = 1.0 if player.facing_right else -1.0
	var vx: float = CharTuning.vanish_point_offset_x * dir_x
	var vy: float = CharTuning.vanish_point_offset_y
	var r: float = 16.0
	draw_line(Vector2(vx - r, vy), Vector2(vx + r, vy), Color(1, 0.3, 1, 0.95), 3.0)
	draw_line(Vector2(vx, vy - r), Vector2(vx, vy + r), Color(1, 0.3, 1, 0.95), 3.0)
	draw_circle(Vector2(vx, vy), 6.0, Color(1, 0.3, 1, 0.85))
