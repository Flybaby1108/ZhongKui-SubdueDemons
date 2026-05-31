extends CanvasLayer

const ROW_HEIGHT := 50.0
const LABEL_WIDTH := 360.0
const VALUE_WIDTH := 120.0

var _rows: Array[Dictionary] = []
var _panel: PanelContainer
var _vbox: VBoxContainer

func _ready() -> void:
	layer = 100
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("tuning_panel")
	_build_ui()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F1:
			visible = not visible
			get_tree().paused = visible
			# Refresh debug draw on player
			var player = get_tree().get_first_node_in_group("player")
			if player != null:
				player.queue_redraw()
			# Refresh debug draw on Boss（被攻击范围紫色矩形随面板可见性显隐）
			for boss in get_tree().get_nodes_in_group("boss"):
				boss.queue_redraw()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_F2 and visible:
			_reset_defaults()
			get_viewport().set_input_as_handled()

func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.anchor_top = 0.0
	_panel.anchor_bottom = 0.0
	_panel.offset_left = -680.0
	_panel.offset_top = 100.0
	_panel.offset_right = -20.0
	_panel.offset_bottom = 900.0
	_panel.modulate = Color(1, 1, 1, 0.95)
	add_child(_panel)

	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.05, 0.05, 0.1, 0.92)
	bg.border_color = Color(0.8, 0.6, 0.2, 1)
	bg.border_width_left = 3
	bg.border_width_right = 3
	bg.border_width_top = 3
	bg.border_width_bottom = 3
	bg.corner_radius_top_left = 8
	bg.corner_radius_top_right = 8
	bg.corner_radius_bottom_left = 8
	bg.corner_radius_bottom_right = 8
	bg.content_margin_left = 20
	bg.content_margin_right = 20
	bg.content_margin_top = 20
	bg.content_margin_bottom = 20
	_panel.add_theme_stylebox_override("panel", bg)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel.add_child(scroll)

	_vbox = VBoxContainer.new()
	_vbox.add_theme_constant_override("separation", 12)
	_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_vbox)

	var title := Label.new()
	title.text = "CHARACTER TUNER  (F1 toggle / F2 reset)"
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(1, 0.85, 0.3, 1))
	_vbox.add_child(title)

	var hint := Label.new()
	hint.text = "Live preview - auto saved"
	hint.add_theme_font_size_override("font_size", 18)
	hint.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 1))
	_vbox.add_child(hint)

	_vbox.add_child(HSeparator.new())

	_add_row("Character Scale",  "sprite_scale",        0.05, 3.0,  0.01)
	_add_row("Sprite Offset X",  "sprite_offset_x",     -200, 200,  1.0)
	_add_row("Sprite Offset Y",  "sprite_offset_y",     -200, 200,  1.0)
	_vbox.add_child(HSeparator.new())
	_add_row("Body Width",       "body_width",           20,  400,  2.0)
	_add_row("Body Height",      "body_height",          20,  400,  2.0)
	_add_row("Body Offset Y",    "body_offset_y",       -100, 100,  1.0)
	_vbox.add_child(HSeparator.new())

	var title_col := Label.new()
	title_col.text = "▼ 吸 - 物理碰撞 (青色矩形)"
	title_col.add_theme_font_size_override("font_size", 22)
	title_col.add_theme_color_override("font_color", Color(0, 1, 1, 1))
	_vbox.add_child(title_col)
	_add_row("Collision X",      "suction_offset_x",   -400, 400,  2.0)
	_add_row("Collision Y",      "suction_offset_y",   -200, 200,  2.0)
	_add_row("Collision Width",  "suction_width",        40,  800,  4.0)
	_add_row("Collision Height", "suction_height",       20,  400,  4.0)
	_vbox.add_child(HSeparator.new())

	var title_fx := Label.new()
	title_fx.text = "▼ 吸 - 素材特效 (序列帧)"
	title_fx.add_theme_font_size_override("font_size", 22)
	title_fx.add_theme_color_override("font_color", Color(1, 0.6, 0.2, 1))
	_vbox.add_child(title_fx)
	_add_row("FX Offset X",     "inhale_fx_offset_x", -400, 400,  2.0)
	_add_row("FX Offset Y",     "inhale_fx_offset_y", -200, 200,  2.0)
	_add_row("FX Scale",        "inhale_fx_scale",     0.1,  3.0,  0.01)
	_vbox.add_child(HSeparator.new())

	var title_enemy := Label.new()
	title_enemy.text = "▼ 敌人设置 (MeteorHammer)"
	title_enemy.add_theme_font_size_override("font_size", 22)
	title_enemy.add_theme_color_override("font_color", Color(0.8, 0.2, 0.2, 1))
	_vbox.add_child(title_enemy)
	_add_row("MH Sprite Scale",   "mh_sprite_scale",    0.05, 1.0,  0.01)
	_add_row("MH Sprite Offset Y","mh_sprite_offset_y",-200,  200, 1.0)
	_vbox.add_child(HSeparator.new())
	_add_row("MH Col Width",      "mh_col_width",       10,   400, 2.0)
	_add_row("MH Col Height",     "mh_col_height",      10,   400, 2.0)
	_add_row("MH Col Offset X",   "mh_col_offset_x",   -200,  200, 1.0)
	_add_row("MH Col Offset Y",   "mh_col_offset_y",   -200,  200, 1.0)
	_vbox.add_child(HSeparator.new())

	# 流星锤怪扔出去的锤子：手部锚点位置 + 整体缩放 + 锤头碰撞盒尺寸
	# 锤 PNG 1733×200 内嵌完整锁链。伸出距离 = 1733 × scale，scale 调大 → 锤大 + 链长 + 攻击距离全部同步
	var title_mh_hammer := Label.new()
	title_mh_hammer.text = "▼ 流星锤 (扔出去的锤)"
	title_mh_hammer.add_theme_font_size_override("font_size", 22)
	title_mh_hammer.add_theme_color_override("font_color", Color(1, 0.4, 0.4, 1))
	_vbox.add_child(title_mh_hammer)
	_add_row("Hammer Scale",     "mh_hammer_scale",      0.02, 1.0,  0.005)
	_add_row("Hammer Offset X",  "mh_hammer_offset_x",  -200,  200,  1.0)
	_add_row("Hammer Offset Y",  "mh_hammer_offset_y",  -200,  200,  1.0)
	_add_row("Hammer Head Size", "mh_hammer_head_size",   40,  400,  2.0)
	_vbox.add_child(HSeparator.new())
	
	var title_rg := Label.new()
	title_rg.text = "▼ 敌人设置 (RedGhost)"
	title_rg.add_theme_font_size_override("font_size", 22)
	title_rg.add_theme_color_override("font_color", Color(0.8, 0.2, 0.5, 1))
	_vbox.add_child(title_rg)
	_add_row("RG Sprite Scale",   "rg_sprite_scale",    0.05, 1.0,  0.01)
	_add_row("RG Sprite Offset Y","rg_sprite_offset_y",-200,  200, 1.0)
	_vbox.add_child(HSeparator.new())
	_add_row("RG Col Width",      "rg_col_width",       10,   400, 2.0)
	_add_row("RG Col Height",     "rg_col_height",      10,   400, 2.0)
	_add_row("RG Col Offset X",   "rg_col_offset_x",   -200,  200, 1.0)
	_add_row("RG Col Offset Y",   "rg_col_offset_y",   -200,  200, 1.0)
	_vbox.add_child(HSeparator.new())

	var title_rd := Label.new()
	title_rd.text = "▼ 敌人设置 (RedDevil 红魔王)"
	title_rd.add_theme_font_size_override("font_size", 22)
	title_rd.add_theme_color_override("font_color", Color(0.9, 0.15, 0.15, 1))
	_vbox.add_child(title_rd)
	_add_row("RD Sprite Scale",   "rd_sprite_scale",    0.05, 1.0,  0.01)
	_add_row("RD Sprite Offset Y","rd_sprite_offset_y",-200,  200, 1.0)
	_vbox.add_child(HSeparator.new())
	_add_row("RD Col Width",      "rd_col_width",       10,   400, 2.0)
	_add_row("RD Col Height",     "rd_col_height",      10,   400, 2.0)
	_add_row("RD Col Offset X",   "rd_col_offset_x",   -200,  200, 1.0)
	_add_row("RD Col Offset Y",   "rd_col_offset_y",   -200,  200, 1.0)
	_vbox.add_child(HSeparator.new())

	var title_pz := Label.new()
	title_pz.text = "▼ 敌人设置 (PalaceZombie 宫廷僵尸)"
	title_pz.add_theme_font_size_override("font_size", 22)
	title_pz.add_theme_color_override("font_color", Color(0.5, 0.7, 0.3, 1))
	_vbox.add_child(title_pz)
	_add_row("PZ Sprite Scale",   "pz_sprite_scale",    0.05, 1.0,  0.01)
	_add_row("PZ Sprite Offset Y","pz_sprite_offset_y",-200,  200, 1.0)
	_vbox.add_child(HSeparator.new())
	_add_row("PZ Col Width",      "pz_col_width",       10,   400, 2.0)
	_add_row("PZ Col Height",     "pz_col_height",      10,   400, 2.0)
	_add_row("PZ Col Offset X",   "pz_col_offset_x",   -200,  200, 1.0)
	_add_row("PZ Col Offset Y",   "pz_col_offset_y",   -200,  200, 1.0)
	_vbox.add_child(HSeparator.new())

	# Boss（关底大怪）：当前只调 sprite 缩放 + 位置偏移。Boss 在游戏里钉死在
	# 编辑器画的 BBBBBB 方块顶部中心，用这三个滑块把脚下/姿态校到合适。
	# scale 范围给到 2.0，因为 Boss 通常显著大于普通敌人；offset 范围 ±400
	# 方便从方块顶部一路往下推到地面。
	var title_boss := Label.new()
	title_boss.text = "▼ 敌人设置 (Boss 关底大怪)"
	title_boss.add_theme_font_size_override("font_size", 22)
	title_boss.add_theme_color_override("font_color", Color(0.6, 0.0, 0.0, 1))
	_vbox.add_child(title_boss)
	_add_row("Boss Sprite Scale",    "boss_sprite_scale",    0.05, 2.0,  0.01)
	_add_row("Boss Sprite Offset X", "boss_sprite_offset_x", -400, 400, 1.0)
	_add_row("Boss Sprite Offset Y", "boss_sprite_offset_y", -400, 400, 1.0)
	# Boss 被攻击范围（HurtBox）：玩家释放捕获物命中此紫色矩形 → Boss 掉血。
	# 矩形以 Boss 局部坐标 (Hurt X, Hurt Y) 为中心，宽高为 (Hurt W, Hurt H)，
	# 整体再乘 Hurt Scale。F1 面板可见时 Boss 上会实时画出半透明紫色矩形预览。
	_add_row("Boss Hurt Offset X",   "boss_hurt_offset_x",   -400, 400, 1.0)
	_add_row("Boss Hurt Offset Y",   "boss_hurt_offset_y",   -400, 400, 1.0)
	_add_row("Boss Hurt Width",      "boss_hurt_width",        20, 800, 2.0)
	_add_row("Boss Hurt Height",     "boss_hurt_height",       20, 800, 2.0)
	_add_row("Boss Hurt Scale",      "boss_hurt_scale",       0.1, 3.0, 0.01)
	_add_row("Boss FireSkull Scale",    "boss_skull_scale",      0.02, 1.0,  0.01)
	_add_row("Boss FireSkull Offset X", "boss_skull_spawn_offset_x", -400, 400, 1.0)
	_add_row("Boss FireSkull Offset Y", "boss_skull_spawn_offset_y", -400, 400, 1.0)
	_vbox.add_child(HSeparator.new())

	var title_ball := Label.new()
	title_ball.text = "▼ 团状翻滚 (敌人被发射出去时)"
	title_ball.add_theme_font_size_override("font_size", 22)
	title_ball.add_theme_color_override("font_color", Color(0.9, 0.7, 0.3, 1))
	_vbox.add_child(title_ball)
	_add_row("Ball Sprite Scale", "ball_sprite_scale",  0.05, 1.0,  0.01)
	_vbox.add_child(HSeparator.new())

	var title_main := Label.new()
	title_main.text = "▼ 主菜单标题 (StartPicture_title)"
	title_main.add_theme_font_size_override("font_size", 22)
	title_main.add_theme_color_override("font_color", Color(0.9, 0.85, 0.5, 1))
	_vbox.add_child(title_main)
	_add_row("Title Pos X",       "title_pos_x",     0,   1920, 2.0)
	_add_row("Title Pos Y",       "title_pos_y",     0,   1080, 2.0)
	_add_row("Title Scale",       "title_scale",     0.1, 3.0,  0.02)
	_vbox.add_child(HSeparator.new())

	var title_vanish := Label.new()
	title_vanish.text = "▼ 葫芦吸入消失点 (相对钟馗中心)"
	title_vanish.add_theme_font_size_override("font_size", 22)
	title_vanish.add_theme_color_override("font_color", Color(1, 0.5, 0.9, 1))
	_vbox.add_child(title_vanish)
	_add_row("Vanish Point Offset X", "vanish_point_offset_x", -200, 300, 1.0)
	_add_row("Vanish Point Offset Y", "vanish_point_offset_y", -200, 200, 1.0)
	_vbox.add_child(HSeparator.new())

	_add_row("Timer Label Y",    "hold_warning_offset_y", -400, 0,  2.0)

func _add_row(label_text: String, prop: String, min_v: float, max_v: float, step: float) -> void:
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	_vbox.add_child(hbox)

	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(LABEL_WIDTH, ROW_HEIGHT)
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hbox.add_child(label)

	var slider := HSlider.new()
	slider.custom_minimum_size = Vector2(0, ROW_HEIGHT)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.min_value = min_v
	slider.max_value = max_v
	slider.step = step
	slider.value = CharTuning.get(prop)
	hbox.add_child(slider)

	# 数值显示 + 手动输入：value_holder 同时塞入 Label（默认可见）和 LineEdit（默认隐藏）
	# 点击 Label 区域 -> 切到 LineEdit 抢焦点直接键入；回车/失焦 -> 写回 + 切回 Label
	var value_holder := Control.new()
	value_holder.custom_minimum_size = Vector2(VALUE_WIDTH, ROW_HEIGHT)
	value_holder.mouse_filter = Control.MOUSE_FILTER_STOP
	hbox.add_child(value_holder)

	var value_label := Label.new()
	value_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	value_label.add_theme_font_size_override("font_size", 22)
	value_label.add_theme_color_override("font_color", Color(0.6, 1, 0.8, 1))
	value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	value_label.text = _format_value(slider.value)
	value_holder.add_child(value_label)

	var value_edit := LineEdit.new()
	value_edit.set_anchors_preset(Control.PRESET_FULL_RECT)
	value_edit.add_theme_font_size_override("font_size", 22)
	value_edit.add_theme_color_override("font_color", Color(1, 1, 0.6, 1))
	value_edit.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_edit.visible = false
	value_holder.add_child(value_edit)

	# 把 LineEdit 中的字符串解析成数值并写回 slider/CharTuning（同时触发 slider.value_changed 回调）
	var commit_edit := func() -> void:
		var raw := value_edit.text.strip_edges()
		if raw.is_valid_float():
			var v: float = clamp(raw.to_float(), min_v, max_v)
			slider.value = v   # 触发 value_changed → 写 CharTuning + 更新 value_label
		value_edit.visible = false
		value_label.visible = true
		value_label.text = _format_value(slider.value)

	# 鼠标点击 holder 任意位置 → 进入编辑态（不要求精确点 Label 文字）
	value_holder.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			value_label.visible = false
			value_edit.visible = true
			value_edit.text = _format_value(slider.value)
			value_edit.select_all()
			value_edit.grab_focus()
	)
	value_edit.text_submitted.connect(func(_t: String) -> void: commit_edit.call())
	value_edit.focus_exited.connect(func() -> void:
		if value_edit.visible:
			commit_edit.call()
	)

	slider.value_changed.connect(func(v: float) -> void:
		CharTuning.set(prop, v)
		value_label.text = _format_value(v)
		CharTuning.notify_changed()
	)

	_rows.append({"prop": prop, "slider": slider, "value_label": value_label, "value_edit": value_edit})

func _format_value(v: float) -> String:
	if abs(v) < 10.0:
		return "%.2f" % v
	return "%.0f" % v

func _reset_defaults() -> void:
	CharTuning.sprite_scale = 0.35
	CharTuning.sprite_offset_x = 0.0
	CharTuning.sprite_offset_y = 0.0
	CharTuning.body_width = 70.0
	CharTuning.body_height = 140.0
	CharTuning.body_offset_y = 5.0
	CharTuning.suction_offset_x = 120.0
	CharTuning.suction_offset_y = 0.0
	CharTuning.suction_width = 240.0
	CharTuning.suction_height = 120.0
	CharTuning.hold_warning_offset_y = -180.0
	CharTuning.inhale_fx_scale = 1.0
	CharTuning.inhale_fx_offset_x = 0.0
	CharTuning.inhale_fx_offset_y = 0.0
	for row in _rows:
		var slider: HSlider = row["slider"]
		var value_label: Label = row["value_label"]
		var value_edit: LineEdit = row["value_edit"]
		slider.value = CharTuning.get(row["prop"])
		value_label.text = _format_value(slider.value)
		# 如果该行正处于手动输入态，强制退回 Label 显示，避免输入框留着旧值
		if value_edit.visible:
			value_edit.visible = false
			value_label.visible = true
	CharTuning.notify_changed()
