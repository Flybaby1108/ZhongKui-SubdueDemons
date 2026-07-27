extends CanvasLayer

const ROW_HEIGHT := 50.0
const LABEL_WIDTH := 360.0
const VALUE_WIDTH := 120.0

var _rows: Array[Dictionary] = []
var _panel: PanelContainer
var _vbox: VBoxContainer
var _dragging_panel: bool = false
var _panel_drag_offset: Vector2 = Vector2.ZERO

func _ready() -> void:
	layer = 100
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("tuning_panel")
	_build_ui()

func _exit_tree() -> void:
	_disconnect_rows()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F1:
			visible = not visible
			_dragging_panel = false
			get_tree().paused = visible
			# Refresh debug draw on player
			var player = get_tree().get_first_node_in_group("player")
			if player != null:
				player.queue_redraw()
				if player.has_method("refresh_tuning_previews"):
					player.refresh_tuning_previews()
			for marker in get_tree().get_nodes_in_group("vanish_marker"):
				marker.queue_redraw()
			for marker in get_tree().get_nodes_in_group("shell_explode_marker"):
				marker.queue_redraw()
			# Refresh debug draw on Boss（被攻击范围紫色矩形随面板可见性显隐）
			for boss in get_tree().get_nodes_in_group("boss"):
				boss.queue_redraw()
			for level in get_tree().get_nodes_in_group("level"):
				if level.has_method("refresh_chapter3_mechanism_preview_debug"):
					level.refresh_chapter3_mechanism_preview_debug()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_F2 and visible:
			_reset_defaults()
			get_viewport().set_input_as_handled()
	elif visible and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if _can_start_panel_drag():
				_dragging_panel = true
				_panel_drag_offset = _panel.get_global_mouse_position() - _panel.global_position
				get_viewport().set_input_as_handled()
		elif _dragging_panel:
			_dragging_panel = false
			get_viewport().set_input_as_handled()
	elif visible and event is InputEventMouseMotion and _dragging_panel:
		_move_panel_to(_panel.get_global_mouse_position() - _panel_drag_offset)
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

	var title_spray_fx := Label.new()
	title_spray_fx.text = "▼ 喷出烟雾 (序列帧)"
	title_spray_fx.add_theme_font_size_override("font_size", 22)
	title_spray_fx.add_theme_color_override("font_color", Color(0.85, 0.85, 0.9, 1))
	_vbox.add_child(title_spray_fx)
	_add_row("喷雾大小/缩放", "spray_fx_scale", 0.05, 4.0, 0.01)
	_add_row("喷雾位置 X", "spray_fx_offset_x", -300, 300, 1.0)
	_add_row("喷雾位置 Y", "spray_fx_offset_y", -200, 200, 1.0)
	_vbox.add_child(HSeparator.new())

	var title_dust_fx := Label.new()
	title_dust_fx.text = "▼ 跳跃落地灰尘 (序列帧)"
	title_dust_fx.add_theme_font_size_override("font_size", 22)
	title_dust_fx.add_theme_color_override("font_color", Color(0.65, 0.65, 0.6, 1))
	_vbox.add_child(title_dust_fx)
	_add_row("灰尘大小/缩放", "dust_fx_scale", 0.05, 4.0, 0.01)
	_add_row("灰尘位置 X", "dust_fx_offset_x", -300, 300, 1.0)
	_add_row("灰尘位置 Y", "dust_fx_offset_y", -200, 200, 1.0)
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

	var title_fdk := Label.new()
	title_fdk.text = "▼ 敌人设置 (FatDemonKing 胖魔王)"
	title_fdk.add_theme_font_size_override("font_size", 22)
	title_fdk.add_theme_color_override("font_color", Color(0.7, 0.35, 0.15, 1))
	_vbox.add_child(title_fdk)
	_add_row("FDK Sprite Scale",   "fdk_sprite_scale",    0.05, 1.0,  0.01)
	_add_row("FDK Sprite Offset X","fdk_sprite_offset_x",-300,  300, 1.0)
	_add_row("FDK Sprite Offset Y","fdk_sprite_offset_y",-300,  200, 1.0)
	_vbox.add_child(HSeparator.new())
	_add_row("FDK Col Scale",      "fdk_col_scale",      0.1,   3.0, 0.01)
	_add_row("FDK Col Width",      "fdk_col_width",       10,   500, 2.0)
	_add_row("FDK Col Height",     "fdk_col_height",      10,   500, 2.0)
	_add_row("FDK Col Offset X",   "fdk_col_offset_x",   -250,  250, 1.0)
	_add_row("FDK Col Offset Y",   "fdk_col_offset_y",   -300,  200, 1.0)
	_vbox.add_child(HSeparator.new())
	_add_row("Mechanism Pos X",    "fdk_mechanism_pos_x",   -600,  600, 1.0)
	_add_row("Mechanism Pos Y",    "fdk_mechanism_pos_y",   -600,  600, 1.0)
	_add_row("Mechanism Scale",    "fdk_mechanism_scale",   0.05,  3.0, 0.01)
	_add_row("Mechanism Pivot X",  "fdk_mechanism_pivot_x", -600,  600, 1.0)
	_add_row("Mechanism Pivot Y",  "fdk_mechanism_pivot_y", -600,  600, 1.0)
	_add_row("Mechanism Rotation", "fdk_mechanism_rotation", -180, 180, 1.0)
	_vbox.add_child(HSeparator.new())
	# 滚动铁球：美术大小 / 平台上滚动时的 Y 位置 / 视觉自转速度 / 移动滚动速度
	_add_row("铁球美术大小",       "fdk_ball_scale",          0.05,  2.0,  0.01)
	_add_row("铁球初始位置 X",     "fdk_ball_rest_offset_x",  -400,  400,  1.0)
	_add_row("铁球初始位置 Y",     "fdk_ball_rest_offset_y",  -400,  400,  1.0)
	_add_row("铁球滚动 Y 位置",    "fdk_ball_track_offset_y", -200,  200,  1.0)
	_add_row("铁球转速 (自转)",    "fdk_ball_spin_speed",      0.0,  5.0,  0.05)
	_add_row("铁球滚动速度",       "fdk_ball_roll_speed",       20,  900,  5.0)
	_vbox.add_child(HSeparator.new())
	# 炮弹（Attack2 落下）：落在平台上消失/爆炸的高度微调 + 爆炸大小
	_add_row("炮竹美术大小",        "shell_firecracker_scale", 0.05, 3.0, 0.01)
	# 爆炸高度 Y 偏移：负值=更高处提前消失爆炸，正值=更靠近/穿过平台
	_add_row("炮弹爆炸高度 Y 偏移", "shell_explode_offset_y", -300, 300, 1.0)
	_add_row("Explode 爆炸美术大小", "shell_explode_scale",    0.05, 3.0, 0.01)
	# 爆炸美术高度 Y 偏移：仅移动爆炸序列帧的显示位置，不改变爆炸触发判定（负值=美术更高，正值=更低）
	_add_row("炮弹爆炸美术高度 Y 偏移", "shell_explode_art_offset_y", -300, 300, 1.0)
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
	_add_row("Boss 鬼火大小",          "boss_ghost_fire_scale",    0.02, 2.0,  0.01)
	_add_row("Boss 鬼火位置 X",        "boss_ghost_fire_offset_x", -400, 400, 1.0)
	_add_row("Boss 鬼火位置 Y",        "boss_ghost_fire_offset_y", -400, 400, 1.0)
	_vbox.add_child(HSeparator.new())

	var title_ball := Label.new()
	title_ball.text = "▼ 团状翻滚 (敌人被发射出去时)"
	title_ball.add_theme_font_size_override("font_size", 22)
	title_ball.add_theme_color_override("font_color", Color(0.9, 0.7, 0.3, 1))
	_vbox.add_child(title_ball)
	_add_row("Ball Sprite Scale", "ball_sprite_scale",  0.05, 1.0,  0.01)
	_vbox.add_child(HSeparator.new())

	var title_drop_yuanbao := Label.new()
	title_drop_yuanbao.text = "▼ 地图掉落元宝"
	title_drop_yuanbao.add_theme_font_size_override("font_size", 22)
	title_drop_yuanbao.add_theme_color_override("font_color", Color(1, 0.8, 0.2, 1))
	_vbox.add_child(title_drop_yuanbao)
	_add_row("掉落元宝位置 X", "drop_yuanbao_offset_x", -400, 400, 1.0)
	_add_row("掉落元宝位置 Y", "drop_yuanbao_offset_y", -400, 400, 1.0)
	_add_row("掉落元宝大小", "drop_yuanbao_scale", 0.05, 2.0, 0.01)
	_add_row("掉落元宝贴地高度", "drop_yuanbao_fall_half_height", 0, 120, 1.0)
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

	var title_bribery := Label.new()
	title_bribery.text = "▼ 复活标题 (Bribery_Text)"
	title_bribery.add_theme_font_size_override("font_size", 22)
	title_bribery.add_theme_color_override("font_color", Color(1.0, 0.78, 0.28, 1))
	_vbox.add_child(title_bribery)
	_add_row("复活标题位置 X", "bribery_title_pos_x", -400, 1920, 2.0)
	_add_row("复活标题位置 Y", "bribery_title_pos_y", -400, 1080, 2.0)
	_add_row("复活标题大小", "bribery_title_scale", 0.1, 3.0, 0.02)
	_vbox.add_child(HSeparator.new())

	var title_fail := Label.new()
	title_fail.text = "▼ 失败标题 (Fail_Word)"
	title_fail.add_theme_font_size_override("font_size", 22)
	title_fail.add_theme_color_override("font_color", Color(0.95, 0.25, 0.25, 1))
	_vbox.add_child(title_fail)
	_add_row("失败标题位置 X", "fail_word_pos_x", -400, 1920, 2.0)
	_add_row("失败标题位置 Y", "fail_word_pos_y", -400, 1080, 2.0)
	_add_row("失败标题大小", "fail_word_scale", 0.1, 3.0, 0.02)
	_vbox.add_child(HSeparator.new())

	var title_bribery_prompt := Label.new()
	title_bribery_prompt.text = "▼ 复活支付文字"
	title_bribery_prompt.add_theme_font_size_override("font_size", 22)
	title_bribery_prompt.add_theme_color_override("font_color", Color(1.0, 0.9, 0.58, 1))
	_vbox.add_child(title_bribery_prompt)
	_add_row("复活支付文字位置 X", "bribery_prompt_pos_x", 0, 1920, 2.0)
	_add_row("复活支付文字位置 Y", "bribery_prompt_pos_y", 0, 1080, 2.0)
	_add_row("复活支付文字大小", "bribery_prompt_font_size", 18, 96, 1.0)
	_vbox.add_child(HSeparator.new())

	var title_avatar_hud := Label.new()
	title_avatar_hud.text = "▼ 关卡 HUD 钟馗生命/头像"
	title_avatar_hud.add_theme_font_size_override("font_size", 22)
	title_avatar_hud.add_theme_color_override("font_color", Color(0.45, 0.9, 0.9, 1))
	_vbox.add_child(title_avatar_hud)
	_add_row("红心位置 X", "heart_pos_x", -400, 1920, 1.0)
	_add_row("红心位置 Y", "heart_pos_y", -200, 1080, 1.0)
	_add_row("红心大小", "heart_scale", 0.1, 4.0, 0.01)
	_add_row("生命红心图标间距", "heart_spacing", -80, 120, 1.0)
	_add_row("头像位置 X", "avatar_frame_pos_x", 0, 1920, 1.0)
	_add_row("头像位置 Y", "avatar_frame_pos_y", 0, 1080, 1.0)
	_add_row("头像大小", "avatar_frame_scale", 0.05, 3.0, 0.01)
	_vbox.add_child(HSeparator.new())

	var title_fdk_hud := Label.new()
	title_fdk_hud.text = "▼ Chapter3 HUD 胖魔王头像/血条"
	title_fdk_hud.add_theme_font_size_override("font_size", 22)
	title_fdk_hud.add_theme_color_override("font_color", Color(1.0, 0.45, 0.25, 1))
	_vbox.add_child(title_fdk_hud)
	_add_row("胖魔王头像位置 X", "fdk_avatar_frame_pos_x", 0, 1920, 1.0)
	_add_row("胖魔王头像位置 Y", "fdk_avatar_frame_pos_y", 0, 1080, 1.0)
	_add_row("胖魔王头像大小", "fdk_avatar_frame_scale", 0.05, 3.0, 0.01)
	_add_row("胖魔王血条位置 X", "fdk_health_bar_pos_x", 0, 1920, 1.0)
	_add_row("胖魔王血条位置 Y", "fdk_health_bar_pos_y", 0, 1080, 1.0)
	_add_row("胖魔王血条宽度", "fdk_health_bar_width", 10, 1000, 1.0)
	_add_row("胖魔王血条高度", "fdk_health_bar_height", 4, 200, 1.0)
	_vbox.add_child(HSeparator.new())

	var title_boss_hud := Label.new()
	title_boss_hud.text = "▼ ChapterBoss HUD Boss头像/血条"
	title_boss_hud.add_theme_font_size_override("font_size", 22)
	title_boss_hud.add_theme_color_override("font_color", Color(1.0, 0.35, 0.35, 1))
	_vbox.add_child(title_boss_hud)
	_add_row("Boss头像位置 X", "boss_avatar_frame_pos_x", 0, 1920, 1.0)
	_add_row("Boss头像位置 Y", "boss_avatar_frame_pos_y", 0, 1080, 1.0)
	_add_row("Boss头像大小", "boss_avatar_frame_scale", 0.02, 1.0, 0.005)
	_add_row("Boss血条位置 X", "boss_health_bar_pos_x", 0, 1920, 1.0)
	_add_row("Boss血条位置 Y", "boss_health_bar_pos_y", 0, 1080, 1.0)
	_add_row("Boss血条宽度", "boss_health_bar_width", 10, 1200, 1.0)
	_add_row("Boss血条高度", "boss_health_bar_height", 4, 200, 1.0)
	_vbox.add_child(HSeparator.new())

	var title_coin_hud := Label.new()
	title_coin_hud.text = "▼ 关卡 HUD 铜钱统计"
	title_coin_hud.add_theme_font_size_override("font_size", 22)
	title_coin_hud.add_theme_color_override("font_color", Color(1, 0.75, 0.25, 1))
	_vbox.add_child(title_coin_hud)
	_add_row("铜钱图标位置 X", "coin_icon_pos_x", -1920, 400, 1.0)
	_add_row("铜钱图标位置 Y", "coin_icon_pos_y", -100, 150, 1.0)
	_add_row("铜钱图标大小", "coin_icon_scale", 0.1, 2.0, 0.01)
	_add_row("铜钱数字位置 X", "coin_digits_pos_x", -1920, 500, 1.0)
	_add_row("铜钱数字位置 Y", "coin_digits_pos_y", -100, 150, 1.0)
	_add_row("铜钱数字大小", "coin_digits_scale", 0.1, 2.0, 0.01)
	_vbox.add_child(HSeparator.new())

	var title_yuanbao_hud := Label.new()
	title_yuanbao_hud.text = "▼ 关卡 HUD 元宝统计"
	title_yuanbao_hud.add_theme_font_size_override("font_size", 22)
	title_yuanbao_hud.add_theme_color_override("font_color", Color(1, 0.9, 0.35, 1))
	_vbox.add_child(title_yuanbao_hud)
	_add_row("元宝图标位置 X", "yuanbao_icon_pos_x", -1920, 400, 1.0)
	_add_row("元宝图标位置 Y", "yuanbao_icon_pos_y", -100, 150, 1.0)
	_add_row("元宝图标大小", "yuanbao_icon_scale", 0.1, 2.0, 0.01)
	_add_row("元宝数字位置 X", "yuanbao_digits_pos_x", -1920, 500, 1.0)
	_add_row("元宝数字位置 Y", "yuanbao_digits_pos_y", -100, 150, 1.0)
	_add_row("元宝数字大小", "yuanbao_digits_scale", 0.1, 2.0, 0.01)
	_vbox.add_child(HSeparator.new())

	var title_countdown_hud := Label.new()
	title_countdown_hud.text = "▼ 关卡 HUD 游戏倒计时背景牌"
	title_countdown_hud.add_theme_font_size_override("font_size", 22)
	title_countdown_hud.add_theme_color_override("font_color", Color(0.55, 0.85, 1.0, 1))
	_vbox.add_child(title_countdown_hud)
	_add_row("倒计时背景牌位置 X", "countdown_bg_pos_x", 0, 1920, 2.0)
	_add_row("倒计时背景牌位置 Y", "countdown_bg_pos_y", 0, 300, 1.0)
	_add_row("倒计时背景牌大小", "countdown_bg_scale", 0.1, 4.0, 0.01)
	_add_row("倒计时数字位置 X", "countdown_digits_pos_x", -1000, 1920, 1.0)
	_add_row("倒计时数字位置 Y", "countdown_digits_pos_y", -150, 200, 1.0)
	_add_row("倒计时数字缩放", "countdown_digits_scale", 0.1, 4.0, 0.01)
	_vbox.add_child(HSeparator.new())

	var title_vanish := Label.new()
	title_vanish.text = "▼ 葫芦吸入消失点 (相对钟馗中心)"
	title_vanish.add_theme_font_size_override("font_size", 22)
	title_vanish.add_theme_color_override("font_color", Color(1, 0.5, 0.9, 1))
	_vbox.add_child(title_vanish)
	_add_row("Vanish Point Offset X", "vanish_point_offset_x", -200, 300, 1.0)
	_add_row("Vanish Point Offset Y", "vanish_point_offset_y", -200, 200, 1.0)
	_vbox.add_child(HSeparator.new())

	_add_row("倒计时位置",          "hold_warning_offset_y", -400, 0,  2.0)

func _add_row(label_text: String, prop: String, min_v: float, max_v: float, step: float) -> void:
	var hbox := HBoxContainer.new()
	hbox.set_meta("tuning_parameter_row", true)
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
	slider.scrollable = false
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

	var row_index := _rows.size()
	var holder_gui_input_cb := _on_row_value_holder_gui_input.bind(row_index)
	var text_submitted_cb := _on_row_text_submitted.bind(row_index)
	var focus_exited_cb := _on_row_focus_exited.bind(row_index)
	var value_changed_cb := _on_row_slider_value_changed.bind(row_index)
	var row := {
		"prop": prop,
		"value_holder": value_holder,
		"slider": slider,
		"value_label": value_label,
		"value_edit": value_edit,
		"min_v": min_v,
		"max_v": max_v,
		"holder_gui_input_cb": holder_gui_input_cb,
		"text_submitted_cb": text_submitted_cb,
		"focus_exited_cb": focus_exited_cb,
		"value_changed_cb": value_changed_cb,
	}

	# 鼠标点击 holder 任意位置 → 进入编辑态（不要求精确点 Label 文字）
	value_holder.gui_input.connect(holder_gui_input_cb)
	value_edit.text_submitted.connect(text_submitted_cb)
	value_edit.focus_exited.connect(focus_exited_cb)
	slider.value_changed.connect(value_changed_cb)

	_rows.append(row)

func _format_value(v: float) -> String:
	if abs(v) < 10.0:
		return "%.2f" % v
	return "%.0f" % v

func _on_row_value_holder_gui_input(event: InputEvent, row_index: int) -> void:
	var row := _get_row(row_index)
	if not _is_row_valid(row):
		return
	var value_label: Label = row["value_label"]
	var value_edit: LineEdit = row["value_edit"]
	var slider: HSlider = row["slider"]
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		value_label.visible = false
		value_edit.visible = true
		value_edit.text = _format_value(slider.value)
		value_edit.select_all()
		value_edit.grab_focus()

func _on_row_text_submitted(_text: String, row_index: int) -> void:
	_commit_row_edit(row_index)

func _on_row_focus_exited(row_index: int) -> void:
	var row := _get_row(row_index)
	if _is_row_valid(row) and (row["value_edit"] as LineEdit).visible:
		_commit_row_edit(row_index)

func _on_row_slider_value_changed(v: float, row_index: int) -> void:
	var row := _get_row(row_index)
	if not _is_row_valid(row):
		return
	CharTuning.set(row["prop"], v)
	(row["value_label"] as Label).text = _format_value(v)
	CharTuning.notify_changed()

func _commit_row_edit(row_index: int) -> void:
	var row := _get_row(row_index)
	if not _is_row_valid(row):
		return
	var value_edit: LineEdit = row["value_edit"]
	var value_label: Label = row["value_label"]
	var slider: HSlider = row["slider"]
	var raw := value_edit.text.strip_edges()
	if raw.is_valid_float():
		var v: float = clamp(raw.to_float(), row["min_v"], row["max_v"])
		slider.value = v   # 触发 value_changed → 写 CharTuning + 更新 value_label
	value_edit.visible = false
	value_label.visible = true
	value_label.text = _format_value(slider.value)

func _get_row(row_index: int) -> Dictionary:
	if row_index < 0 or row_index >= _rows.size():
		return {}
	return _rows[row_index]

func _is_row_valid(row: Dictionary) -> bool:
	return not row.is_empty() \
		and is_instance_valid(row.get("value_holder")) \
		and is_instance_valid(row.get("slider")) \
		and is_instance_valid(row.get("value_label")) \
		and is_instance_valid(row.get("value_edit"))

func _disconnect_rows() -> void:
	for row in _rows:
		if row.is_empty():
			continue
		var value_holder := row.get("value_holder") as Control
		var value_edit := row.get("value_edit") as LineEdit
		var slider := row.get("slider") as HSlider
		var holder_gui_input_cb: Callable = row["holder_gui_input_cb"]
		var text_submitted_cb: Callable = row["text_submitted_cb"]
		var focus_exited_cb: Callable = row["focus_exited_cb"]
		var value_changed_cb: Callable = row["value_changed_cb"]
		if is_instance_valid(value_holder) and value_holder.gui_input.is_connected(holder_gui_input_cb):
			value_holder.gui_input.disconnect(holder_gui_input_cb)
		if is_instance_valid(value_edit):
			if value_edit.text_submitted.is_connected(text_submitted_cb):
				value_edit.text_submitted.disconnect(text_submitted_cb)
			if value_edit.focus_exited.is_connected(focus_exited_cb):
				value_edit.focus_exited.disconnect(focus_exited_cb)
		if is_instance_valid(slider) and slider.value_changed.is_connected(value_changed_cb):
			slider.value_changed.disconnect(value_changed_cb)
	_rows.clear()

func _can_start_panel_drag() -> bool:
	if _panel == null:
		return false
	var mouse_pos := _panel.get_global_mouse_position()
	if not Rect2(_panel.global_position, _panel.size).has_point(mouse_pos):
		return false
	var hovered := get_viewport().gui_get_hovered_control()
	if hovered == null:
		return true
	if not _is_descendant_of(hovered, _panel):
		return false
	return not _is_parameter_control(hovered)

func _is_descendant_of(node: Node, ancestor: Node) -> bool:
	var current := node
	while current != null:
		if current == ancestor:
			return true
		current = current.get_parent()
	return false

func _is_parameter_control(control: Control) -> bool:
	var current: Node = control
	while current != null and current != _panel:
		if current.has_meta("tuning_parameter_row"):
			return true
		if current is Range or current is LineEdit:
			return true
		current = current.get_parent()
	return false

func _move_panel_to(pos: Vector2) -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	var panel_size := _panel.size
	var max_pos := Vector2(
		max(0.0, viewport_size.x - panel_size.x),
		max(0.0, viewport_size.y - panel_size.y)
	)
	var clamped_pos := Vector2(
		clamp(pos.x, 0.0, max_pos.x),
		clamp(pos.y, 0.0, max_pos.y)
	)
	_panel.global_position = clamped_pos

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
	CharTuning.spray_fx_scale = 1.0
	CharTuning.spray_fx_offset_x = 94.0
	CharTuning.spray_fx_offset_y = -12.0
	CharTuning.dust_fx_scale = 1.0
	CharTuning.dust_fx_offset_x = 0.0
	CharTuning.dust_fx_offset_y = 0.0
	CharTuning.drop_yuanbao_offset_x = 0.0
	CharTuning.drop_yuanbao_offset_y = 0.0
	CharTuning.drop_yuanbao_scale = 0.40
	CharTuning.drop_yuanbao_fall_half_height = 35.0
	CharTuning.fdk_sprite_scale = 0.82
	CharTuning.fdk_sprite_offset_x = -17.0
	CharTuning.fdk_sprite_offset_y = -58.0
	CharTuning.fdk_col_offset_x = 12.0
	CharTuning.fdk_col_offset_y = 25.0
	CharTuning.fdk_col_width = 252.0
	CharTuning.fdk_col_height = 174.0
	CharTuning.fdk_col_scale = 1.28
	CharTuning.fdk_mechanism_pos_x = 262.0
	CharTuning.fdk_mechanism_pos_y = -516.0
	CharTuning.fdk_mechanism_scale = 0.49
	CharTuning.fdk_mechanism_pivot_x = 400.0
	CharTuning.fdk_mechanism_pivot_y = -524.0
	CharTuning.fdk_mechanism_rotation = -52.0
	CharTuning.fdk_ball_scale = 1.0
	CharTuning.fdk_ball_rest_offset_x = 143.0
	CharTuning.fdk_ball_rest_offset_y = -87.0
	CharTuning.fdk_ball_track_offset_y = -72.0
	CharTuning.fdk_ball_spin_speed = 0.5
	CharTuning.fdk_ball_roll_speed = 255.0
	CharTuning.shell_firecracker_scale = 1.06
	CharTuning.shell_explode_offset_y = -44.0
	CharTuning.shell_explode_scale = 1.27
	CharTuning.shell_explode_art_offset_y = -95.0
	CharTuning.boss_ghost_fire_scale = 0.58
	CharTuning.boss_ghost_fire_offset_x = 0.0
	CharTuning.boss_ghost_fire_offset_y = 24.0
	CharTuning.heart_pos_x = 115.0
	CharTuning.heart_pos_y = 10.0
	CharTuning.heart_scale = 0.94
	CharTuning.heart_spacing = -11.0
	CharTuning.avatar_frame_pos_x = 26.0
	CharTuning.avatar_frame_pos_y = 11.0
	CharTuning.avatar_frame_scale = 0.37
	CharTuning.fdk_avatar_frame_pos_x = 1799.0
	CharTuning.fdk_avatar_frame_pos_y = 11.0
	CharTuning.fdk_avatar_frame_scale = 0.37
	CharTuning.fdk_health_bar_pos_x = 1501.0
	CharTuning.fdk_health_bar_pos_y = 48.0
	CharTuning.fdk_health_bar_width = 274.0
	CharTuning.fdk_health_bar_height = 20.0
	CharTuning.boss_avatar_frame_pos_x = 1792.0
	CharTuning.boss_avatar_frame_pos_y = 11.0
	CharTuning.boss_avatar_frame_scale = 0.1
	CharTuning.boss_health_bar_pos_x = 1349.0
	CharTuning.boss_health_bar_pos_y = 48.0
	CharTuning.boss_health_bar_width = 419.0
	CharTuning.boss_health_bar_height = 28.0
	CharTuning.coin_icon_pos_x = -363.0
	CharTuning.coin_icon_pos_y = 17.0
	CharTuning.coin_icon_scale = 0.42
	CharTuning.coin_digits_pos_x = -296.0
	CharTuning.coin_digits_pos_y = 18.0
	CharTuning.coin_digits_scale = 1.0
	CharTuning.yuanbao_icon_pos_x = -512.0
	CharTuning.yuanbao_icon_pos_y = 21.0
	CharTuning.yuanbao_icon_scale = 0.41
	CharTuning.yuanbao_digits_pos_x = -420.0
	CharTuning.yuanbao_digits_pos_y = 18.0
	CharTuning.yuanbao_digits_scale = 1.0
	CharTuning.countdown_bg_pos_x = 968.0
	CharTuning.countdown_bg_pos_y = 53.0
	CharTuning.countdown_bg_scale = 1.14
	CharTuning.countdown_digits_pos_x = 298.0
	CharTuning.countdown_digits_pos_y = -9.0
	CharTuning.countdown_digits_scale = 1.02
	CharTuning.bribery_title_pos_x = 1380.0
	CharTuning.bribery_title_pos_y = 110.0
	CharTuning.bribery_title_scale = 1.14
	CharTuning.fail_word_pos_x = 522.5
	CharTuning.fail_word_pos_y = 190.5
	CharTuning.fail_word_scale = 1.0
	CharTuning.bribery_prompt_pos_x = 660.0
	CharTuning.bribery_prompt_pos_y = 38.0
	CharTuning.bribery_prompt_font_size = 34.0
	for row in _rows:
		if not _is_row_valid(row):
			continue
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
