extends Node2D

# Boss 的 FireSkull 出生位置预览标记（橙色粗十字 + 中心圆环）。
#
# 为什么单独抽一个节点：
#   原先这套十字画在 boss.gd 的 _draw() 里——也就是 Boss 节点（CharacterBody2D）
#   自身的 CanvasItem 上。Godot 的渲染顺序是"父节点先画、子节点后画"，所以 Boss 的
#   Sprite 子节点会盖在 Boss._draw() 输出之上，导致这个预览十字被 Boss 角色挡住。
#
#   解决方案：把这部分绘制移到一个**位于 Sprite 之后**的子节点 (Node2D) 上。同层级
#   下兄弟节点按 add_child 顺序自下而上叠放，所以这个 marker 会自然画在 Sprite 上层，
#   不再被 Boss 美术挡住。
#
# 显示规则：
#   仅在 F1 调参面板（group "tuning_panel" 的节点）可见时绘制；其余情况完全不画，
#   保证正常游戏画面不会出现这条调试用十字。
#
# 坐标系：
#   marker 节点 position 始终为 Vector2.ZERO（在 boss.gd 中 add_child 后保持），
#   所以 (CharTuning.boss_skull_spawn_offset_x, _y) 直接就是 Boss 局部坐标系下的
#   投射物出生位置——与 boss.gd::_spawn_fire_skull 中
#       global_position + Vector2(offset_x, offset_y)
#   的语义 1:1 对应。

func _ready() -> void:
	# 调参信号一变就重绘（offset_x/y 拖动要立即看到十字位置变化）
	CharTuning.tuning_changed.connect(queue_redraw)

# 跟踪面板上一次的可见状态。F1 切换面板显隐时，tuning_panel.gd 只会主动通知
# Boss 自身 queue_redraw（见 tuning_panel.gd::_input 里的 boss 遍历），不会
# 递归到 Boss 的子节点。这里自己每帧轻量地比一下面板可见状态，
# 一旦发生切换就触发本节点 redraw —— 比侵入 tuning_panel.gd 干净。
var _last_panel_visible: bool = false

func _process(_delta: float) -> void:
	var tuning_panel := get_tree().get_first_node_in_group("tuning_panel")
	var now_visible: bool = tuning_panel != null and tuning_panel.visible
	if now_visible != _last_panel_visible:
		_last_panel_visible = now_visible
		queue_redraw()

func _draw() -> void:
	var tuning_panel := get_tree().get_first_node_in_group("tuning_panel")
	var panel_visible: bool = tuning_panel != null and tuning_panel.visible
	if not panel_visible:
		return

	var sx: float = CharTuning.boss_skull_spawn_offset_x
	var sy: float = CharTuning.boss_skull_spawn_offset_y
	var skull_arm: float = 24.0          # 十字臂长（px）
	var skull_thick: float = 5.0         # 粗度（"粗十字"，比 hurt 的 2.0 明显粗）
	var skull_col := Color(1.0, 0.55, 0.1, 0.95)   # 鲜橙，与紫色 hurt 区分
	var skull_outline := Color(0.0, 0.0, 0.0, 0.6)  # 黑色描边，提升在花哨背景上的辨识度

	# 先画黑描边（更粗），再画橙色主线
	draw_line(Vector2(sx - skull_arm, sy), Vector2(sx + skull_arm, sy), skull_outline, skull_thick + 2.0)
	draw_line(Vector2(sx, sy - skull_arm), Vector2(sx, sy + skull_arm), skull_outline, skull_thick + 2.0)
	draw_line(Vector2(sx - skull_arm, sy), Vector2(sx + skull_arm, sy), skull_col, skull_thick)
	draw_line(Vector2(sx, sy - skull_arm), Vector2(sx, sy + skull_arm), skull_col, skull_thick)
	# 中心小圆环加强可见性
	draw_circle(Vector2(sx, sy), 4.0, skull_col)
	draw_arc(Vector2(sx, sy), 8.0, 0.0, TAU, 24, skull_outline, 1.5)
