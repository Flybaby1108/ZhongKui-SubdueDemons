extends Node

const CONFIG_PATH := "user://char_tuning.cfg"

signal tuning_changed

# ─────────────────────────────────────────────────────────────────────────
# DEFAULT VALUES (baked from designer's local user://char_tuning.cfg, May 2026)
# 这些默认值是设计师在 F1 调参面板里实际调好的数值，已 baked 进代码作为出厂默认。
# 玩家首次启动（user://char_tuning.cfg 不存在时）用这些值；之后 F1 调参会写回 user://
# 覆盖默认值。CI/Web 版没有用户 cfg，因此只看这里的值——必须与设计师本地保持一致。
# 若要重新出厂校准：1) 用 F1 调好  2) 复制 user://char_tuning.cfg 数值过来覆盖这里。
# ─────────────────────────────────────────────────────────────────────────
var sprite_scale: float = 0.35
var sprite_offset_x: float = 0.0
var sprite_offset_y: float = 0.0
var body_width: float = 70.0
var body_height: float = 140.0
var body_offset_y: float = 5.0
var suction_offset_x: float = 208.0
var suction_offset_y: float = -24.0
var suction_width: float = 292.0
var suction_height: float = 176.0
var hold_warning_offset_y: float = -196.0
var inhale_fx_scale: float = 0.71
var inhale_fx_offset_x: float = 70.0
var inhale_fx_offset_y: float = -16.0
var mh_sprite_scale: float = 0.31
var mh_sprite_offset_x: float = 17.0
var mh_sprite_offset_y: float = -64.0
var mh_col_offset_x: float = 12.0
var mh_col_offset_y: float = -70.0
var mh_col_width: float = 70.0
var mh_col_height: float = 126.0
var rg_sprite_scale: float = 0.29
var rg_sprite_offset_y: float = -170.0
var rg_col_offset_x: float = -9.0
var rg_col_offset_y: float = -170.0
var rg_col_width: float = 68.0
var rg_col_height: float = 114.0
var rd_sprite_scale: float = 0.45
var rd_sprite_offset_y: float = -132.0
var rd_col_offset_x: float = 25.0
var rd_col_offset_y: float = -86.0
var rd_col_width: float = 130.0
var rd_col_height: float = 176.0
var pz_sprite_scale: float = 0.32
var pz_sprite_offset_y: float = -52.0
var pz_col_offset_x: float = 12.0
var pz_col_offset_y: float = -34.0
var pz_col_width: float = 62.0
var pz_col_height: float = 118.0
# 被发射敌人（团状翻滚 ball）的 sprite scale
var ball_sprite_scale: float = 0.45
# 主菜单标题图位置与大小（StartPicture_title.png 在 1920×1080 画布上的中心坐标 + 缩放）
var title_pos_x: float = 340.0
var title_pos_y: float = 502.0
var title_scale: float = 1.14
# 钟馗"吸入消失点"相对钟馗中心的偏移（朝向跟随钟馗朝向自动镜像 X）
# 敌人被吸时朝这个点飞，到达 capture 触发瞬间敌人正好在此处消失（视觉上=飞进葫芦）
var vanish_point_offset_x: float = 78.0
var vanish_point_offset_y: float = -11.0

# 流星锤怪扔出的锤子调参（仅 MH_ATTACK 状态下生成的飞行锤）
# 锤的 PNG 现在是 1733×200，锁链全长内嵌在贴图里（左端=锤怪手部，右端=锤头）
# 攻击距离由 scale 决定：实际伸出距离 = 1733 × scale - mh_hammer_anchor_padding
# - 当前 scale 0.155 → 实际伸出 ≈ 268px
# - 提高 scale → 锤变大 + 链变长（攻击距离同步扩大）
var mh_hammer_scale: float = 0.155         # 锤 sprite 缩放（PNG 1733×200）
var mh_hammer_offset_x: float = 32.0       # 锤"手部锚点"位置（怪面向方向上距怪中心的 X）
var mh_hammer_offset_y: float = -52.0      # 锤"手部锚点"位置 Y（负值偏上）
# 锤头碰撞盒尺寸（按 scale 自动缩放；指的是 1733×200 贴图中锤头部分的像素尺寸）
var mh_hammer_head_size: float = 180.0     # 锤头近似宽度（贴图中黑色球体直径 ~180px @ 1733 宽）

func _ready() -> void:
	load_config()

func load_config() -> void:
	var cfg := ConfigFile.new()
	var err := cfg.load(CONFIG_PATH)
	if err != OK:
		return
	sprite_scale         = cfg.get_value("char", "sprite_scale", sprite_scale)
	sprite_offset_x      = cfg.get_value("char", "sprite_offset_x", sprite_offset_x)
	sprite_offset_y      = cfg.get_value("char", "sprite_offset_y", sprite_offset_y)
	body_width           = cfg.get_value("char", "body_width", body_width)
	body_height          = cfg.get_value("char", "body_height", body_height)
	body_offset_y        = cfg.get_value("char", "body_offset_y", body_offset_y)
	suction_offset_x     = cfg.get_value("char", "suction_offset_x", suction_offset_x)
	suction_offset_y     = cfg.get_value("char", "suction_offset_y", suction_offset_y)
	suction_width        = cfg.get_value("char", "suction_width", suction_width)
	suction_height       = cfg.get_value("char", "suction_height", suction_height)
	hold_warning_offset_y = cfg.get_value("char", "hold_warning_offset_y", hold_warning_offset_y)
	inhale_fx_scale      = cfg.get_value("char", "inhale_fx_scale", inhale_fx_scale)
	inhale_fx_offset_x   = cfg.get_value("char", "inhale_fx_offset_x", inhale_fx_offset_x)
	inhale_fx_offset_y   = cfg.get_value("char", "inhale_fx_offset_y", inhale_fx_offset_y)
	mh_sprite_scale      = cfg.get_value("enemy", "mh_sprite_scale", mh_sprite_scale)
	mh_sprite_offset_x   = cfg.get_value("enemy", "mh_sprite_offset_x", mh_sprite_offset_x)
	mh_sprite_offset_y   = cfg.get_value("enemy", "mh_sprite_offset_y", mh_sprite_offset_y)
	mh_col_offset_x      = cfg.get_value("enemy", "mh_col_offset_x", mh_col_offset_x)
	mh_col_offset_y      = cfg.get_value("enemy", "mh_col_offset_y", mh_col_offset_y)
	mh_col_width         = cfg.get_value("enemy", "mh_col_width", mh_col_width)
	mh_col_height        = cfg.get_value("enemy", "mh_col_height", mh_col_height)
	rg_sprite_scale      = cfg.get_value("enemy", "rg_sprite_scale", rg_sprite_scale)
	rg_sprite_offset_y   = cfg.get_value("enemy", "rg_sprite_offset_y", rg_sprite_offset_y)
	rg_col_offset_x      = cfg.get_value("enemy", "rg_col_offset_x", rg_col_offset_x)
	rg_col_offset_y      = cfg.get_value("enemy", "rg_col_offset_y", rg_col_offset_y)
	rg_col_width         = cfg.get_value("enemy", "rg_col_width", rg_col_width)
	rg_col_height        = cfg.get_value("enemy", "rg_col_height", rg_col_height)
	rd_sprite_scale      = cfg.get_value("enemy", "rd_sprite_scale", rd_sprite_scale)
	rd_sprite_offset_y   = cfg.get_value("enemy", "rd_sprite_offset_y", rd_sprite_offset_y)
	rd_col_offset_x      = cfg.get_value("enemy", "rd_col_offset_x", rd_col_offset_x)
	rd_col_offset_y      = cfg.get_value("enemy", "rd_col_offset_y", rd_col_offset_y)
	rd_col_width         = cfg.get_value("enemy", "rd_col_width", rd_col_width)
	rd_col_height        = cfg.get_value("enemy", "rd_col_height", rd_col_height)
	pz_sprite_scale      = cfg.get_value("enemy", "pz_sprite_scale", pz_sprite_scale)
	pz_sprite_offset_y   = cfg.get_value("enemy", "pz_sprite_offset_y", pz_sprite_offset_y)
	pz_col_offset_x      = cfg.get_value("enemy", "pz_col_offset_x", pz_col_offset_x)
	pz_col_offset_y      = cfg.get_value("enemy", "pz_col_offset_y", pz_col_offset_y)
	pz_col_width         = cfg.get_value("enemy", "pz_col_width", pz_col_width)
	pz_col_height        = cfg.get_value("enemy", "pz_col_height", pz_col_height)
	ball_sprite_scale    = cfg.get_value("ball", "ball_sprite_scale", ball_sprite_scale)
	title_pos_x          = cfg.get_value("ui", "title_pos_x", title_pos_x)
	title_pos_y          = cfg.get_value("ui", "title_pos_y", title_pos_y)
	title_scale          = cfg.get_value("ui", "title_scale", title_scale)
	vanish_point_offset_x = cfg.get_value("char", "vanish_point_offset_x", vanish_point_offset_x)
	vanish_point_offset_y = cfg.get_value("char", "vanish_point_offset_y", vanish_point_offset_y)
	mh_hammer_scale     = cfg.get_value("enemy", "mh_hammer_scale", mh_hammer_scale)
	mh_hammer_offset_x  = cfg.get_value("enemy", "mh_hammer_offset_x", mh_hammer_offset_x)
	mh_hammer_offset_y  = cfg.get_value("enemy", "mh_hammer_offset_y", mh_hammer_offset_y)
	mh_hammer_head_size = cfg.get_value("enemy", "mh_hammer_head_size", mh_hammer_head_size)

func save_config() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("char", "sprite_scale", sprite_scale)
	cfg.set_value("char", "sprite_offset_x", sprite_offset_x)
	cfg.set_value("char", "sprite_offset_y", sprite_offset_y)
	cfg.set_value("char", "body_width", body_width)
	cfg.set_value("char", "body_height", body_height)
	cfg.set_value("char", "body_offset_y", body_offset_y)
	cfg.set_value("char", "suction_offset_x", suction_offset_x)
	cfg.set_value("char", "suction_offset_y", suction_offset_y)
	cfg.set_value("char", "suction_width", suction_width)
	cfg.set_value("char", "suction_height", suction_height)
	cfg.set_value("char", "hold_warning_offset_y", hold_warning_offset_y)
	cfg.set_value("char", "inhale_fx_scale", inhale_fx_scale)
	cfg.set_value("char", "inhale_fx_offset_x", inhale_fx_offset_x)
	cfg.set_value("char", "inhale_fx_offset_y", inhale_fx_offset_y)
	cfg.set_value("enemy", "mh_sprite_scale", mh_sprite_scale)
	cfg.set_value("enemy", "mh_sprite_offset_x", mh_sprite_offset_x)
	cfg.set_value("enemy", "mh_sprite_offset_y", mh_sprite_offset_y)
	cfg.set_value("enemy", "mh_col_offset_x", mh_col_offset_x)
	cfg.set_value("enemy", "mh_col_offset_y", mh_col_offset_y)
	cfg.set_value("enemy", "mh_col_width", mh_col_width)
	cfg.set_value("enemy", "mh_col_height", mh_col_height)
	cfg.set_value("enemy", "rg_sprite_scale", rg_sprite_scale)
	cfg.set_value("enemy", "rg_sprite_offset_y", rg_sprite_offset_y)
	cfg.set_value("enemy", "rg_col_offset_x", rg_col_offset_x)
	cfg.set_value("enemy", "rg_col_offset_y", rg_col_offset_y)
	cfg.set_value("enemy", "rg_col_width", rg_col_width)
	cfg.set_value("enemy", "rg_col_height", rg_col_height)
	cfg.set_value("enemy", "rd_sprite_scale", rd_sprite_scale)
	cfg.set_value("enemy", "rd_sprite_offset_y", rd_sprite_offset_y)
	cfg.set_value("enemy", "rd_col_offset_x", rd_col_offset_x)
	cfg.set_value("enemy", "rd_col_offset_y", rd_col_offset_y)
	cfg.set_value("enemy", "rd_col_width", rd_col_width)
	cfg.set_value("enemy", "rd_col_height", rd_col_height)
	cfg.set_value("enemy", "pz_sprite_scale", pz_sprite_scale)
	cfg.set_value("enemy", "pz_sprite_offset_y", pz_sprite_offset_y)
	cfg.set_value("enemy", "pz_col_offset_x", pz_col_offset_x)
	cfg.set_value("enemy", "pz_col_offset_y", pz_col_offset_y)
	cfg.set_value("enemy", "pz_col_width", pz_col_width)
	cfg.set_value("enemy", "pz_col_height", pz_col_height)
	cfg.set_value("ball", "ball_sprite_scale", ball_sprite_scale)
	cfg.set_value("ui", "title_pos_x", title_pos_x)
	cfg.set_value("ui", "title_pos_y", title_pos_y)
	cfg.set_value("ui", "title_scale", title_scale)
	cfg.set_value("char", "vanish_point_offset_x", vanish_point_offset_x)
	cfg.set_value("char", "vanish_point_offset_y", vanish_point_offset_y)
	cfg.set_value("enemy", "mh_hammer_scale", mh_hammer_scale)
	cfg.set_value("enemy", "mh_hammer_offset_x", mh_hammer_offset_x)
	cfg.set_value("enemy", "mh_hammer_offset_y", mh_hammer_offset_y)
	cfg.set_value("enemy", "mh_hammer_head_size", mh_hammer_head_size)
	cfg.save(CONFIG_PATH)

func notify_changed() -> void:
	tuning_changed.emit()
	save_config()
