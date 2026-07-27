extends Node

const CONFIG_PATH := "user://char_tuning.cfg"
# Browser builds keep user:// across GitHub Pages deployments. Increment this
# whenever baked enemy calibration must replace previously saved Web values.
const ENEMY_TUNING_VERSION := 4
const FDK_MECHANISM_TUNING_VERSION := 6
const FDK_HUD_TUNING_VERSION := 4
const BOSS_HUD_TUNING_VERSION := 1
# 钟馗本体（char 段）与通用 HUD（ui 段：红心/头像/铜钱/元宝/倒计时/标题）以前未做版本门控，
# 导致 Web 版玩家旧的 user:// 存档会一直覆盖出厂校准。新增版本号后，旧存档会被自动丢弃并
# 用最新 baked 默认值重写。出厂校准变更时必须递增对应版本号。
const CHAR_TUNING_VERSION := 1
const UI_TUNING_VERSION := 1
const BRIBERY_UI_TUNING_VERSION := 1
const FAIL_UI_TUNING_VERSION := 1

signal tuning_changed

# ─────────────────────────────────────────────────────────────────────────
# DEFAULT VALUES (baked from designer's local user://char_tuning.cfg, May 2026)
# 这些默认值是设计师在 F1 调参面板里实际调好的数值，已 baked 进代码作为出厂默认。
# 玩家首次启动（user://char_tuning.cfg 不存在时）用这些值；之后 F1 调参会写回 user://
# 覆盖默认值。Web 版的 user:// 也会跨部署保留；敌人出厂校准变化时必须递增
# ENEMY_TUNING_VERSION，让旧的敌人尺寸和碰撞范围自动迁移。
# 若要重新出厂校准：1) 用 F1 调好  2) 复制 user://char_tuning.cfg 数值过来覆盖这里。
# ─────────────────────────────────────────────────────────────────────────
var sprite_scale: float = 0.46
var sprite_offset_x: float = 0.0
var sprite_offset_y: float = 0.0
var body_width: float = 80.0
var body_height: float = 138.0
var body_offset_y: float = 11.0
var suction_offset_x: float = 224.0
var suction_offset_y: float = -8.0
var suction_width: float = 324.0
var suction_height: float = 116.0
var hold_warning_offset_y: float = -136.0
var inhale_fx_scale: float = 0.71
var inhale_fx_offset_x: float = 70.0
var inhale_fx_offset_y: float = -12.0
var spray_fx_scale: float = 1.0
var spray_fx_offset_x: float = 94.0
var spray_fx_offset_y: float = -12.0
var dust_fx_scale: float = 1.0
var dust_fx_offset_x: float = 0.0
var dust_fx_offset_y: float = 0.0
var mh_sprite_scale: float = 0.46
var mh_sprite_offset_x: float = 17.0
var mh_sprite_offset_y: float = -129.0
var mh_col_offset_x: float = 8.0
var mh_col_offset_y: float = -68.0
var mh_col_width: float = 68.0
var mh_col_height: float = 126.0
var rg_sprite_scale: float = 0.28
var rg_sprite_offset_y: float = -193.0
var rg_col_offset_x: float = -12.0
var rg_col_offset_y: float = -171.0
var rg_col_width: float = 68.0
var rg_col_height: float = 114.0
var rd_sprite_scale: float = 0.44
var rd_sprite_offset_y: float = -119.0
var rd_col_offset_x: float = 25.0
var rd_col_offset_y: float = -84.0
var rd_col_width: float = 126.0
var rd_col_height: float = 178.0
var pz_sprite_scale: float = 0.32
var pz_sprite_offset_y: float = -52.0
var pz_col_offset_x: float = 12.0
var pz_col_offset_y: float = -34.0
var pz_col_width: float = 62.0
var pz_col_height: float = 118.0
var fdk_sprite_scale: float = 0.82
var fdk_sprite_offset_x: float = -17.0
var fdk_sprite_offset_y: float = -58.0
var fdk_col_offset_x: float = 12.0
var fdk_col_offset_y: float = 25.0
var fdk_col_width: float = 252.0
var fdk_col_height: float = 174.0
var fdk_col_scale: float = 1.28
var fdk_mechanism_pos_x: float = 262.0
var fdk_mechanism_pos_y: float = -516.0
var fdk_mechanism_scale: float = 0.49
var fdk_mechanism_pivot_x: float = 400.0
var fdk_mechanism_pivot_y: float = -524.0
var fdk_mechanism_rotation: float = -52.0
# 滚动铁球（FatDemonKing Attack1 放出的会滚动的铁球）的可调参数：
# - fdk_ball_scale       铁球美术资源缩放（视觉大小）
# - fdk_ball_track_offset_y 铁球在三层平台上滚动时的美术 Y 偏移（修正铁球陷进/浮在平台的视觉）
# - fdk_ball_spin_speed  铁球视觉自转速度系数（仅影响贴图旋转快慢，不影响位移）
# - fdk_ball_roll_speed  铁球沿轨道的水平滚动移动速度（像素/秒）
# - fdk_ball_rest_offset_x/y 平行(静止)状态下铁球相对机关平台的初始位置 XY 偏移
var fdk_ball_scale: float = 1.0
var fdk_ball_rest_offset_x: float = 143.0
var fdk_ball_rest_offset_y: float = -87.0
var fdk_ball_track_offset_y: float = -72.0
var fdk_ball_spin_speed: float = 0.5
var fdk_ball_roll_speed: float = 255.0
# 炮弹（FatDemonKing Attack2 落下的炮弹）落在平台上消失/爆炸的高度微调与爆炸大小：
# - shell_firecracker_scale  爆竹本体美术资源缩放
# - shell_explode_offset_y     炮弹在平台站立面 Y 基础上的额外偏移（负值=更高处提前消失爆炸，正值=更靠下）；影响爆炸触发判定高度
# - shell_explode_scale        Explode 爆炸序列帧美术资源的视觉缩放
# - shell_explode_art_offset_y 爆炸美术序列帧相对炮弹爆炸位置的额外 Y 偏移（仅影响美术显示，不改变爆炸触发判定；负值=美术更高，正值=更低）
var shell_firecracker_scale: float = 1.06
var shell_explode_offset_y: float = -44.0
var shell_explode_scale: float = 1.27
var shell_explode_art_offset_y: float = -95.0
# Boss（ChapterBoss 关卡的关底大怪）：当前只接入 sprite 缩放 + 位置偏移，
# 没有碰撞调参（Boss 不参与玩家碰撞/吸入流程，加碰撞之后再补 col_* 字段）。
# 默认 scale 0.4 是个先验估值；策划用 F1 调好后这里 baked 成新默认。
var boss_sprite_scale: float = 1.03
var boss_sprite_offset_x: float = -212.0
var boss_sprite_offset_y: float = -84.0
# Boss 被攻击范围（HurtBox）：玩家释放的捕获物命中此矩形时对 Boss 造成伤害。
# 相对 Boss 节点局部坐标。X/Y 是矩形中心偏移；Width/Height 是矩形尺寸（受 hurt_scale 整体缩放）。
# 调试可视化：F1 面板可见时，Boss 上会画一个紫色半透明矩形显示当前范围。
var boss_hurt_offset_x: float = -217.0
var boss_hurt_offset_y: float = -8.0
var boss_hurt_width: float = 292.0
var boss_hurt_height: float = 474.0
var boss_hurt_scale: float = 1.67
# Boss Attack2 释放 FireSkull 时的"左手法器圆环"偏移（相对 Boss 全局位置，单位像素）。
# Boss 当前默认面朝左侧（朝玩家）；左手在角色身体左侧——画面上仍是 -X 方向。
# 默认值是策划/美术的先验估值，需要在 F1 面板里实际跑动后微调。
var boss_skull_spawn_offset_x: float = 224.0
var boss_skull_spawn_offset_y: float = -169.0
# FireSkull sprite 视觉缩放（飞行 + 喷出 ball 形态共用）。
# PNG 原图较大，0.18 是策划先验估值；F1 面板可实时调整。
var boss_skull_scale: float = 0.57
# Boss Attack3 鬼火：这里的大小与位置是出现缩放动画结束后的 100% 状态。
var boss_ghost_fire_scale: float = 0.43
var boss_ghost_fire_offset_x: float = 0.0
var boss_ghost_fire_offset_y: float = 8.0
# 被发射敌人（团状翻滚 ball）的 sprite scale
var ball_sprite_scale: float = 0.45
# 地图上掉落元宝（被发射敌人撞击 3-5 个捕获物时掉落）的生成偏移、视觉大小和落地贴地高度。
var drop_yuanbao_offset_x: float = 0.0
var drop_yuanbao_offset_y: float = 0.0
var drop_yuanbao_scale: float = 0.40
var drop_yuanbao_fall_half_height: float = 35.0
# 主菜单标题图位置与大小（StartPicture_title.png 在 1920×1080 画布上的中心坐标 + 缩放）
var title_pos_x: float = 364.0
var title_pos_y: float = 494.0
var title_scale: float = 1.16
# 复活买通鬼差界面标题图（Bribery_Text.png）：左上角位置 + 缩放
var bribery_title_pos_x: float = 1380.0
var bribery_title_pos_y: float = 110.0
var bribery_title_scale: float = 1.14
# 复活买通鬼差界面支付说明文字：区域左上角位置 + 字号
var bribery_prompt_pos_x: float = 660.0
var bribery_prompt_pos_y: float = 38.0
var bribery_prompt_font_size: float = 34.0
# 失败界面标题图（Fail_Word.png）：左上角位置 + 缩放
var fail_word_pos_x: float = 522.5
var fail_word_pos_y: float = 190.5
var fail_word_scale: float = 1.0
# 关卡 HUD 钟馗生命值：Hearts 容器在 HeartCounter 内的位置、红心缩放和红心间距
var heart_pos_x: float = 115.0
var heart_pos_y: float = 10.0
var heart_scale: float = 0.94
var heart_spacing: float = -11.0
# 关卡 HUD 钟馗头像：AvatarFrame.png 在 HUD 根节点下的位置和缩放
var avatar_frame_pos_x: float = 26.0
var avatar_frame_pos_y: float = 11.0
var avatar_frame_scale: float = 0.37
# Chapter3 HUD 胖魔王头像与血条。头像位置是左上角，血条位置是矩形左上角。
var fdk_avatar_frame_pos_x: float = 1799.0
var fdk_avatar_frame_pos_y: float = 11.0
var fdk_avatar_frame_scale: float = 0.37
var fdk_health_bar_pos_x: float = 1501.0
var fdk_health_bar_pos_y: float = 48.0
var fdk_health_bar_width: float = 274.0
var fdk_health_bar_height: float = 20.0
# ChapterBoss HUD Boss 头像与血条。头像位置是左上角，血条位置是矩形左上角。
var boss_avatar_frame_pos_x: float = 1792.0
var boss_avatar_frame_pos_y: float = 11.0
var boss_avatar_frame_scale: float = 0.1
var boss_health_bar_pos_x: float = 1349.0
var boss_health_bar_pos_y: float = 48.0
var boss_health_bar_width: float = 419.0
var boss_health_bar_height: float = 28.0
# 关卡 HUD 铜钱/元宝统计：图标与像素数字在各自 Counter 容器内的位置和缩放
var coin_icon_pos_x: float = -363.0
var coin_icon_pos_y: float = 17.0
var coin_icon_scale: float = 0.42
var coin_digits_pos_x: float = -296.0
var coin_digits_pos_y: float = 18.0
var coin_digits_scale: float = 1.0
var yuanbao_icon_pos_x: float = -512.0
var yuanbao_icon_pos_y: float = 21.0
var yuanbao_icon_scale: float = 0.41
var yuanbao_digits_pos_x: float = -420.0
var yuanbao_digits_pos_y: float = 18.0
var yuanbao_digits_scale: float = 1.0
# 关卡 HUD 游戏倒计时背景牌：以屏幕坐标作为中心点，缩放基于 Chapter_Countdown.png 原始尺寸。
var countdown_bg_pos_x: float = 968.0
var countdown_bg_pos_y: float = 53.0
var countdown_bg_scale: float = 1.14
# 关卡 HUD 游戏倒计时数字：TimeLabel 在 CountdownCounter 容器内的位置和整体 Control 缩放。
var countdown_digits_pos_x: float = 298.0
var countdown_digits_pos_y: float = -9.0
var countdown_digits_scale: float = 1.02
# 钟馗"吸入消失点"相对钟馗中心的偏移（朝向跟随钟馗朝向自动镜像 X）
# 敌人被吸时朝这个点飞，到达 capture 触发瞬间敌人正好在此处消失（视觉上=飞进葫芦）
var vanish_point_offset_x: float = 78.0
var vanish_point_offset_y: float = -11.0

# 流星锤怪扔出的锤子调参（仅 MH_ATTACK 状态下生成的飞行锤）
# 锤的 PNG 现在是 1733×200，锁链全长内嵌在贴图里（左端=锤怪手部，右端=锤头）
# 攻击距离由 scale 决定：实际伸出距离 = 1733 × scale - mh_hammer_anchor_padding
# - 当前 scale 0.155 → 实际伸出 ≈ 268px
# - 提高 scale → 锤变大 + 链变长（攻击距离同步扩大）
var mh_hammer_scale: float = 0.24          # 锤 sprite 缩放（PNG 1733×200）
var mh_hammer_offset_x: float = 50.0       # 锤"手部锚点"位置（怪面向方向上距怪中心的 X）
var mh_hammer_offset_y: float = -109.0     # 锤"手部锚点"位置 Y（负值偏上）
# 锤头碰撞盒尺寸（按 scale 自动缩放；指的是 1733×200 贴图中锤头部分的像素尺寸）
var mh_hammer_head_size: float = 98.0      # 锤头近似宽度（贴图中黑色球体直径 ~180px @ 1733 宽）

func _ready() -> void:
	load_config()

func load_config() -> void:
	var cfg := ConfigFile.new()
	var err := cfg.load(CONFIG_PATH)
	if err != OK:
		return
	var enemy_tuning_is_current: bool = (
		cfg.get_value("meta", "enemy_tuning_version", 0) == ENEMY_TUNING_VERSION
	)
	var fdk_mechanism_tuning_is_current: bool = (
		cfg.get_value("meta", "fdk_mechanism_tuning_version", 0) == FDK_MECHANISM_TUNING_VERSION
	)
	var fdk_hud_tuning_is_current: bool = (
		cfg.get_value("meta", "fdk_hud_tuning_version", 0) == FDK_HUD_TUNING_VERSION
	)
	var boss_hud_tuning_is_current: bool = (
		cfg.get_value("meta", "boss_hud_tuning_version", 0) == BOSS_HUD_TUNING_VERSION
	)
	# char 段（钟馗本体）与通用 ui 段（红心/头像/铜钱/元宝/倒计时/标题）的版本门控。
	# 旧 Web 存档没有这两个版本号（默认 0），与当前不符 → 丢弃旧值、用最新 baked 默认重写。
	var char_tuning_is_current: bool = (
		cfg.get_value("meta", "char_tuning_version", 0) == CHAR_TUNING_VERSION
	)
	var ui_tuning_is_current: bool = (
		cfg.get_value("meta", "ui_tuning_version", 0) == UI_TUNING_VERSION
	)
	var bribery_ui_tuning_is_current: bool = (
		cfg.get_value("meta", "bribery_ui_tuning_version", 0) == BRIBERY_UI_TUNING_VERSION
	)
	var fail_ui_tuning_is_current: bool = (
		cfg.get_value("meta", "fail_ui_tuning_version", 0) == FAIL_UI_TUNING_VERSION
	)
	var should_save_config: bool = (
		not enemy_tuning_is_current
		or not fdk_mechanism_tuning_is_current
		or not fdk_hud_tuning_is_current
		or not boss_hud_tuning_is_current
		or not char_tuning_is_current
		or not ui_tuning_is_current
		or not bribery_ui_tuning_is_current
		or not fail_ui_tuning_is_current
	)
	if char_tuning_is_current:
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
		spray_fx_scale       = cfg.get_value("char", "spray_fx_scale", spray_fx_scale)
		spray_fx_offset_x    = cfg.get_value("char", "spray_fx_offset_x", spray_fx_offset_x)
		spray_fx_offset_y    = cfg.get_value("char", "spray_fx_offset_y", spray_fx_offset_y)
		dust_fx_scale        = cfg.get_value("char", "dust_fx_scale", dust_fx_scale)
		dust_fx_offset_x     = cfg.get_value("char", "dust_fx_offset_x", dust_fx_offset_x)
		dust_fx_offset_y     = cfg.get_value("char", "dust_fx_offset_y", dust_fx_offset_y)
		vanish_point_offset_x = cfg.get_value("char", "vanish_point_offset_x", vanish_point_offset_x)
		vanish_point_offset_y = cfg.get_value("char", "vanish_point_offset_y", vanish_point_offset_y)
	ball_sprite_scale    = cfg.get_value("ball", "ball_sprite_scale", ball_sprite_scale)
	drop_yuanbao_offset_x = cfg.get_value("pickup", "drop_yuanbao_offset_x", drop_yuanbao_offset_x)
	drop_yuanbao_offset_y = cfg.get_value("pickup", "drop_yuanbao_offset_y", drop_yuanbao_offset_y)
	drop_yuanbao_scale    = cfg.get_value("pickup", "drop_yuanbao_scale", drop_yuanbao_scale)
	drop_yuanbao_fall_half_height = cfg.get_value("pickup", "drop_yuanbao_fall_half_height", drop_yuanbao_fall_half_height)
	if ui_tuning_is_current:
		title_pos_x          = cfg.get_value("ui", "title_pos_x", title_pos_x)
		title_pos_y          = cfg.get_value("ui", "title_pos_y", title_pos_y)
		title_scale          = cfg.get_value("ui", "title_scale", title_scale)
		if bribery_ui_tuning_is_current:
			bribery_title_pos_x  = cfg.get_value("ui", "bribery_title_pos_x", bribery_title_pos_x)
			bribery_title_pos_y  = cfg.get_value("ui", "bribery_title_pos_y", bribery_title_pos_y)
			bribery_title_scale  = cfg.get_value("ui", "bribery_title_scale", bribery_title_scale)
			bribery_prompt_pos_x = cfg.get_value("ui", "bribery_prompt_pos_x", bribery_prompt_pos_x)
			bribery_prompt_pos_y = cfg.get_value("ui", "bribery_prompt_pos_y", bribery_prompt_pos_y)
			bribery_prompt_font_size = cfg.get_value("ui", "bribery_prompt_font_size", bribery_prompt_font_size)
		if fail_ui_tuning_is_current:
			fail_word_pos_x   = cfg.get_value("ui", "fail_word_pos_x", fail_word_pos_x)
			fail_word_pos_y   = cfg.get_value("ui", "fail_word_pos_y", fail_word_pos_y)
			fail_word_scale   = cfg.get_value("ui", "fail_word_scale", fail_word_scale)
		heart_pos_x          = cfg.get_value("ui", "heart_pos_x", heart_pos_x)
		heart_pos_y          = cfg.get_value("ui", "heart_pos_y", heart_pos_y)
		heart_scale          = cfg.get_value("ui", "heart_scale", heart_scale)
		heart_spacing        = cfg.get_value("ui", "heart_spacing", heart_spacing)
		avatar_frame_pos_x   = cfg.get_value("ui", "avatar_frame_pos_x", avatar_frame_pos_x)
		avatar_frame_pos_y   = cfg.get_value("ui", "avatar_frame_pos_y", avatar_frame_pos_y)
		avatar_frame_scale   = cfg.get_value("ui", "avatar_frame_scale", avatar_frame_scale)
		coin_icon_pos_x      = cfg.get_value("ui", "coin_icon_pos_x", coin_icon_pos_x)
		coin_icon_pos_y      = cfg.get_value("ui", "coin_icon_pos_y", coin_icon_pos_y)
		coin_icon_scale      = cfg.get_value("ui", "coin_icon_scale", coin_icon_scale)
		coin_digits_pos_x    = cfg.get_value("ui", "coin_digits_pos_x", coin_digits_pos_x)
		coin_digits_pos_y    = cfg.get_value("ui", "coin_digits_pos_y", coin_digits_pos_y)
		coin_digits_scale    = cfg.get_value("ui", "coin_digits_scale", coin_digits_scale)
		yuanbao_icon_pos_x   = cfg.get_value("ui", "yuanbao_icon_pos_x", yuanbao_icon_pos_x)
		yuanbao_icon_pos_y   = cfg.get_value("ui", "yuanbao_icon_pos_y", yuanbao_icon_pos_y)
		yuanbao_icon_scale   = cfg.get_value("ui", "yuanbao_icon_scale", yuanbao_icon_scale)
		yuanbao_digits_pos_x = cfg.get_value("ui", "yuanbao_digits_pos_x", yuanbao_digits_pos_x)
		yuanbao_digits_pos_y = cfg.get_value("ui", "yuanbao_digits_pos_y", yuanbao_digits_pos_y)
		yuanbao_digits_scale = cfg.get_value("ui", "yuanbao_digits_scale", yuanbao_digits_scale)
		countdown_bg_pos_x   = cfg.get_value("ui", "countdown_bg_pos_x", countdown_bg_pos_x)
		countdown_bg_pos_y   = cfg.get_value("ui", "countdown_bg_pos_y", countdown_bg_pos_y)
		countdown_bg_scale   = cfg.get_value("ui", "countdown_bg_scale", countdown_bg_scale)
		countdown_digits_pos_x = cfg.get_value("ui", "countdown_digits_pos_x", countdown_digits_pos_x)
		countdown_digits_pos_y = cfg.get_value("ui", "countdown_digits_pos_y", countdown_digits_pos_y)
		countdown_digits_scale = cfg.get_value("ui", "countdown_digits_scale", countdown_digits_scale)
	if fdk_hud_tuning_is_current:
		fdk_avatar_frame_pos_x = cfg.get_value("ui", "fdk_avatar_frame_pos_x", fdk_avatar_frame_pos_x)
		fdk_avatar_frame_pos_y = cfg.get_value("ui", "fdk_avatar_frame_pos_y", fdk_avatar_frame_pos_y)
		fdk_avatar_frame_scale = cfg.get_value("ui", "fdk_avatar_frame_scale", fdk_avatar_frame_scale)
		fdk_health_bar_pos_x   = cfg.get_value("ui", "fdk_health_bar_pos_x", fdk_health_bar_pos_x)
		fdk_health_bar_pos_y   = cfg.get_value("ui", "fdk_health_bar_pos_y", fdk_health_bar_pos_y)
		fdk_health_bar_width   = cfg.get_value("ui", "fdk_health_bar_width", fdk_health_bar_width)
		fdk_health_bar_height  = cfg.get_value("ui", "fdk_health_bar_height", fdk_health_bar_height)
	if boss_hud_tuning_is_current:
		boss_avatar_frame_pos_x = cfg.get_value("ui", "boss_avatar_frame_pos_x", boss_avatar_frame_pos_x)
		boss_avatar_frame_pos_y = cfg.get_value("ui", "boss_avatar_frame_pos_y", boss_avatar_frame_pos_y)
		boss_avatar_frame_scale = cfg.get_value("ui", "boss_avatar_frame_scale", boss_avatar_frame_scale)
		boss_health_bar_pos_x   = cfg.get_value("ui", "boss_health_bar_pos_x", boss_health_bar_pos_x)
		boss_health_bar_pos_y   = cfg.get_value("ui", "boss_health_bar_pos_y", boss_health_bar_pos_y)
		boss_health_bar_width   = cfg.get_value("ui", "boss_health_bar_width", boss_health_bar_width)
		boss_health_bar_height  = cfg.get_value("ui", "boss_health_bar_height", boss_health_bar_height)
	if enemy_tuning_is_current:
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
		fdk_sprite_scale     = cfg.get_value("enemy", "fdk_sprite_scale", fdk_sprite_scale)
		fdk_sprite_offset_x  = cfg.get_value("enemy", "fdk_sprite_offset_x", fdk_sprite_offset_x)
		fdk_sprite_offset_y  = cfg.get_value("enemy", "fdk_sprite_offset_y", fdk_sprite_offset_y)
		fdk_col_offset_x     = cfg.get_value("enemy", "fdk_col_offset_x", fdk_col_offset_x)
		fdk_col_offset_y     = cfg.get_value("enemy", "fdk_col_offset_y", fdk_col_offset_y)
		fdk_col_width        = cfg.get_value("enemy", "fdk_col_width", fdk_col_width)
		fdk_col_height       = cfg.get_value("enemy", "fdk_col_height", fdk_col_height)
		fdk_col_scale        = cfg.get_value("enemy", "fdk_col_scale", fdk_col_scale)
		if fdk_mechanism_tuning_is_current:
			fdk_mechanism_pos_x     = cfg.get_value("enemy", "fdk_mechanism_pos_x", fdk_mechanism_pos_x)
			fdk_mechanism_pos_y     = cfg.get_value("enemy", "fdk_mechanism_pos_y", fdk_mechanism_pos_y)
			fdk_mechanism_scale     = cfg.get_value("enemy", "fdk_mechanism_scale", fdk_mechanism_scale)
			fdk_mechanism_pivot_x   = cfg.get_value("enemy", "fdk_mechanism_pivot_x", fdk_mechanism_pivot_x)
			fdk_mechanism_pivot_y   = cfg.get_value("enemy", "fdk_mechanism_pivot_y", fdk_mechanism_pivot_y)
			fdk_mechanism_rotation  = cfg.get_value("enemy", "fdk_mechanism_rotation", fdk_mechanism_rotation)
			fdk_ball_scale          = cfg.get_value("enemy", "fdk_ball_scale", fdk_ball_scale)
			fdk_ball_rest_offset_x  = cfg.get_value("enemy", "fdk_ball_rest_offset_x", fdk_ball_rest_offset_x)
			fdk_ball_rest_offset_y  = cfg.get_value("enemy", "fdk_ball_rest_offset_y", fdk_ball_rest_offset_y)
			fdk_ball_track_offset_y = cfg.get_value("enemy", "fdk_ball_track_offset_y", fdk_ball_track_offset_y)
			fdk_ball_spin_speed     = cfg.get_value("enemy", "fdk_ball_spin_speed", fdk_ball_spin_speed)
			fdk_ball_roll_speed     = cfg.get_value("enemy", "fdk_ball_roll_speed", fdk_ball_roll_speed)
			shell_firecracker_scale = cfg.get_value("enemy", "shell_firecracker_scale", shell_firecracker_scale)
			shell_explode_offset_y  = cfg.get_value("enemy", "shell_explode_offset_y", shell_explode_offset_y)
			shell_explode_scale     = cfg.get_value("enemy", "shell_explode_scale", shell_explode_scale)
			shell_explode_art_offset_y = cfg.get_value("enemy", "shell_explode_art_offset_y", shell_explode_art_offset_y)
		boss_sprite_scale    = cfg.get_value("enemy", "boss_sprite_scale", boss_sprite_scale)
		boss_sprite_offset_x = cfg.get_value("enemy", "boss_sprite_offset_x", boss_sprite_offset_x)
		boss_sprite_offset_y = cfg.get_value("enemy", "boss_sprite_offset_y", boss_sprite_offset_y)
		boss_hurt_offset_x   = cfg.get_value("enemy", "boss_hurt_offset_x", boss_hurt_offset_x)
		boss_hurt_offset_y   = cfg.get_value("enemy", "boss_hurt_offset_y", boss_hurt_offset_y)
		boss_hurt_width      = cfg.get_value("enemy", "boss_hurt_width", boss_hurt_width)
		boss_hurt_height     = cfg.get_value("enemy", "boss_hurt_height", boss_hurt_height)
		boss_hurt_scale      = cfg.get_value("enemy", "boss_hurt_scale", boss_hurt_scale)
		boss_skull_spawn_offset_x = cfg.get_value("enemy", "boss_skull_spawn_offset_x", boss_skull_spawn_offset_x)
		boss_skull_spawn_offset_y = cfg.get_value("enemy", "boss_skull_spawn_offset_y", boss_skull_spawn_offset_y)
		boss_skull_scale          = cfg.get_value("enemy", "boss_skull_scale", boss_skull_scale)
		boss_ghost_fire_scale     = cfg.get_value("enemy", "boss_ghost_fire_scale", boss_ghost_fire_scale)
		boss_ghost_fire_offset_x  = cfg.get_value("enemy", "boss_ghost_fire_offset_x", boss_ghost_fire_offset_x)
		boss_ghost_fire_offset_y  = cfg.get_value("enemy", "boss_ghost_fire_offset_y", boss_ghost_fire_offset_y)
		mh_hammer_scale     = cfg.get_value("enemy", "mh_hammer_scale", mh_hammer_scale)
		mh_hammer_offset_x  = cfg.get_value("enemy", "mh_hammer_offset_x", mh_hammer_offset_x)
		mh_hammer_offset_y  = cfg.get_value("enemy", "mh_hammer_offset_y", mh_hammer_offset_y)
		mh_hammer_head_size = cfg.get_value("enemy", "mh_hammer_head_size", mh_hammer_head_size)
	else:
		# Keep unrelated personal settings, but rewrite stale enemy calibration
		# so the Web build does not reapply old collision boxes on every launch.
		should_save_config = true
	if should_save_config:
		save_config()

func save_config() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "enemy_tuning_version", ENEMY_TUNING_VERSION)
	cfg.set_value("meta", "fdk_mechanism_tuning_version", FDK_MECHANISM_TUNING_VERSION)
	cfg.set_value("meta", "fdk_hud_tuning_version", FDK_HUD_TUNING_VERSION)
	cfg.set_value("meta", "boss_hud_tuning_version", BOSS_HUD_TUNING_VERSION)
	cfg.set_value("meta", "char_tuning_version", CHAR_TUNING_VERSION)
	cfg.set_value("meta", "ui_tuning_version", UI_TUNING_VERSION)
	cfg.set_value("meta", "bribery_ui_tuning_version", BRIBERY_UI_TUNING_VERSION)
	cfg.set_value("meta", "fail_ui_tuning_version", FAIL_UI_TUNING_VERSION)
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
	cfg.set_value("char", "spray_fx_scale", spray_fx_scale)
	cfg.set_value("char", "spray_fx_offset_x", spray_fx_offset_x)
	cfg.set_value("char", "spray_fx_offset_y", spray_fx_offset_y)
	cfg.set_value("char", "dust_fx_scale", dust_fx_scale)
	cfg.set_value("char", "dust_fx_offset_x", dust_fx_offset_x)
	cfg.set_value("char", "dust_fx_offset_y", dust_fx_offset_y)
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
	cfg.set_value("enemy", "fdk_sprite_scale", fdk_sprite_scale)
	cfg.set_value("enemy", "fdk_sprite_offset_x", fdk_sprite_offset_x)
	cfg.set_value("enemy", "fdk_sprite_offset_y", fdk_sprite_offset_y)
	cfg.set_value("enemy", "fdk_col_offset_x", fdk_col_offset_x)
	cfg.set_value("enemy", "fdk_col_offset_y", fdk_col_offset_y)
	cfg.set_value("enemy", "fdk_col_width", fdk_col_width)
	cfg.set_value("enemy", "fdk_col_height", fdk_col_height)
	cfg.set_value("enemy", "fdk_col_scale", fdk_col_scale)
	cfg.set_value("enemy", "fdk_mechanism_pos_x", fdk_mechanism_pos_x)
	cfg.set_value("enemy", "fdk_mechanism_pos_y", fdk_mechanism_pos_y)
	cfg.set_value("enemy", "fdk_mechanism_scale", fdk_mechanism_scale)
	cfg.set_value("enemy", "fdk_mechanism_pivot_x", fdk_mechanism_pivot_x)
	cfg.set_value("enemy", "fdk_mechanism_pivot_y", fdk_mechanism_pivot_y)
	cfg.set_value("enemy", "fdk_mechanism_rotation", fdk_mechanism_rotation)
	cfg.set_value("enemy", "fdk_ball_scale", fdk_ball_scale)
	cfg.set_value("enemy", "fdk_ball_rest_offset_x", fdk_ball_rest_offset_x)
	cfg.set_value("enemy", "fdk_ball_rest_offset_y", fdk_ball_rest_offset_y)
	cfg.set_value("enemy", "fdk_ball_track_offset_y", fdk_ball_track_offset_y)
	cfg.set_value("enemy", "fdk_ball_spin_speed", fdk_ball_spin_speed)
	cfg.set_value("enemy", "fdk_ball_roll_speed", fdk_ball_roll_speed)
	cfg.set_value("enemy", "shell_firecracker_scale", shell_firecracker_scale)
	cfg.set_value("enemy", "shell_explode_offset_y", shell_explode_offset_y)
	cfg.set_value("enemy", "shell_explode_scale", shell_explode_scale)
	cfg.set_value("enemy", "shell_explode_art_offset_y", shell_explode_art_offset_y)
	cfg.set_value("enemy", "boss_sprite_scale", boss_sprite_scale)
	cfg.set_value("enemy", "boss_sprite_offset_x", boss_sprite_offset_x)
	cfg.set_value("enemy", "boss_sprite_offset_y", boss_sprite_offset_y)
	cfg.set_value("enemy", "boss_hurt_offset_x", boss_hurt_offset_x)
	cfg.set_value("enemy", "boss_hurt_offset_y", boss_hurt_offset_y)
	cfg.set_value("enemy", "boss_hurt_width", boss_hurt_width)
	cfg.set_value("enemy", "boss_hurt_height", boss_hurt_height)
	cfg.set_value("enemy", "boss_hurt_scale", boss_hurt_scale)
	cfg.set_value("enemy", "boss_skull_spawn_offset_x", boss_skull_spawn_offset_x)
	cfg.set_value("enemy", "boss_skull_spawn_offset_y", boss_skull_spawn_offset_y)
	cfg.set_value("enemy", "boss_skull_scale", boss_skull_scale)
	cfg.set_value("enemy", "boss_ghost_fire_scale", boss_ghost_fire_scale)
	cfg.set_value("enemy", "boss_ghost_fire_offset_x", boss_ghost_fire_offset_x)
	cfg.set_value("enemy", "boss_ghost_fire_offset_y", boss_ghost_fire_offset_y)
	cfg.set_value("ball", "ball_sprite_scale", ball_sprite_scale)
	cfg.set_value("pickup", "drop_yuanbao_offset_x", drop_yuanbao_offset_x)
	cfg.set_value("pickup", "drop_yuanbao_offset_y", drop_yuanbao_offset_y)
	cfg.set_value("pickup", "drop_yuanbao_scale", drop_yuanbao_scale)
	cfg.set_value("pickup", "drop_yuanbao_fall_half_height", drop_yuanbao_fall_half_height)
	cfg.set_value("ui", "title_pos_x", title_pos_x)
	cfg.set_value("ui", "title_pos_y", title_pos_y)
	cfg.set_value("ui", "title_scale", title_scale)
	cfg.set_value("ui", "bribery_title_pos_x", bribery_title_pos_x)
	cfg.set_value("ui", "bribery_title_pos_y", bribery_title_pos_y)
	cfg.set_value("ui", "bribery_title_scale", bribery_title_scale)
	cfg.set_value("ui", "bribery_prompt_pos_x", bribery_prompt_pos_x)
	cfg.set_value("ui", "bribery_prompt_pos_y", bribery_prompt_pos_y)
	cfg.set_value("ui", "bribery_prompt_font_size", bribery_prompt_font_size)
	cfg.set_value("ui", "fail_word_pos_x", fail_word_pos_x)
	cfg.set_value("ui", "fail_word_pos_y", fail_word_pos_y)
	cfg.set_value("ui", "fail_word_scale", fail_word_scale)
	cfg.set_value("ui", "heart_pos_x", heart_pos_x)
	cfg.set_value("ui", "heart_pos_y", heart_pos_y)
	cfg.set_value("ui", "heart_scale", heart_scale)
	cfg.set_value("ui", "heart_spacing", heart_spacing)
	cfg.set_value("ui", "avatar_frame_pos_x", avatar_frame_pos_x)
	cfg.set_value("ui", "avatar_frame_pos_y", avatar_frame_pos_y)
	cfg.set_value("ui", "avatar_frame_scale", avatar_frame_scale)
	cfg.set_value("ui", "fdk_avatar_frame_pos_x", fdk_avatar_frame_pos_x)
	cfg.set_value("ui", "fdk_avatar_frame_pos_y", fdk_avatar_frame_pos_y)
	cfg.set_value("ui", "fdk_avatar_frame_scale", fdk_avatar_frame_scale)
	cfg.set_value("ui", "fdk_health_bar_pos_x", fdk_health_bar_pos_x)
	cfg.set_value("ui", "fdk_health_bar_pos_y", fdk_health_bar_pos_y)
	cfg.set_value("ui", "fdk_health_bar_width", fdk_health_bar_width)
	cfg.set_value("ui", "fdk_health_bar_height", fdk_health_bar_height)
	cfg.set_value("ui", "boss_avatar_frame_pos_x", boss_avatar_frame_pos_x)
	cfg.set_value("ui", "boss_avatar_frame_pos_y", boss_avatar_frame_pos_y)
	cfg.set_value("ui", "boss_avatar_frame_scale", boss_avatar_frame_scale)
	cfg.set_value("ui", "boss_health_bar_pos_x", boss_health_bar_pos_x)
	cfg.set_value("ui", "boss_health_bar_pos_y", boss_health_bar_pos_y)
	cfg.set_value("ui", "boss_health_bar_width", boss_health_bar_width)
	cfg.set_value("ui", "boss_health_bar_height", boss_health_bar_height)
	cfg.set_value("ui", "coin_icon_pos_x", coin_icon_pos_x)
	cfg.set_value("ui", "coin_icon_pos_y", coin_icon_pos_y)
	cfg.set_value("ui", "coin_icon_scale", coin_icon_scale)
	cfg.set_value("ui", "coin_digits_pos_x", coin_digits_pos_x)
	cfg.set_value("ui", "coin_digits_pos_y", coin_digits_pos_y)
	cfg.set_value("ui", "coin_digits_scale", coin_digits_scale)
	cfg.set_value("ui", "yuanbao_icon_pos_x", yuanbao_icon_pos_x)
	cfg.set_value("ui", "yuanbao_icon_pos_y", yuanbao_icon_pos_y)
	cfg.set_value("ui", "yuanbao_icon_scale", yuanbao_icon_scale)
	cfg.set_value("ui", "yuanbao_digits_pos_x", yuanbao_digits_pos_x)
	cfg.set_value("ui", "yuanbao_digits_pos_y", yuanbao_digits_pos_y)
	cfg.set_value("ui", "yuanbao_digits_scale", yuanbao_digits_scale)
	cfg.set_value("ui", "countdown_bg_pos_x", countdown_bg_pos_x)
	cfg.set_value("ui", "countdown_bg_pos_y", countdown_bg_pos_y)
	cfg.set_value("ui", "countdown_bg_scale", countdown_bg_scale)
	cfg.set_value("ui", "countdown_digits_pos_x", countdown_digits_pos_x)
	cfg.set_value("ui", "countdown_digits_pos_y", countdown_digits_pos_y)
	cfg.set_value("ui", "countdown_digits_scale", countdown_digits_scale)
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
