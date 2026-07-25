extends CharacterBody2D
class_name Enemy

enum Type { METEOR_HAMMER, RED_GHOST, RED_DEVIL, PALACE_ZOMBIE, FAT_DEMON_KING }

@export var enemy_type: Type = Type.METEOR_HAMMER

# default_facing_right 表示**美术原图(PNG)**的朝向，**不是**初始运动方向。
# - 如果 PNG 原图角色面朝右（脸/武器/正面在右），设为 true
# - 如果 PNG 原图角色面朝左，设为 false
# 当前所有敌人 PNG 都朝右绘制 → 一律为 true。
# 切勿为了"修正朝向看起来不对"而翻转此字段，那会导致朝向与运动方向相反。
@export var default_facing_right: bool = true

const GRAVITY := 4000.0
const MH_SPEED := 150.0

# ───────── 跨平台跳跃（HOP）：仅红衣女鬼 / 宫廷僵尸 ─────────
# 设计：每只敌人独立计时，每隔 PLATFORM_HOP_CHECK_INTERVAL_MIN~MAX 秒
# 以 PLATFORM_HOP_TRIGGER_PROB 概率触发一次"换平台"。
# 目标平台从场景中所有平台里**随机**选取（不再依据"自己拥挤"或"目标空旷"），
# X 同步移动到目标平台中心，Y 由物理 + 跳跃速度推动。
# 敌人类型限制：仅 Type.RED_GHOST 与 Type.PALACE_ZOMBIE 参与；
# 流星锤怪（METEOR_HAMMER）与红魔王（RED_DEVIL）不会跨平台跳跃。
# 总开关；运行时关闭可彻底禁用此机制（调试用）。
const PLATFORM_HOP_ENABLED := true
# 每只敌人独立的"是否需要换平台"检查间隔（秒）
const PLATFORM_HOP_CHECK_INTERVAL_MIN := 1.0
const PLATFORM_HOP_CHECK_INTERVAL_MAX := 2.5
# 即使平台已超员，也以一定概率触发（避免所有同时拥挤的敌人一起跳，破坏画面）
const PLATFORM_HOP_TRIGGER_PROB := 0.98
# 起跳初速度（Y 负值=向上）。GRAVITY=4000 → 这个速度可达约 (1300^2)/(2*4000) ≈ 211 像素高
# 一个 tile 行高 10 像素，可越过 ≈ 21 行；足以从下层平台跳到任意上层。
const PLATFORM_HOP_JUMP_VELOCITY := -1300.0
# 上跳/下落过程中 X 轴匀速对齐到目标平台中心的速率（像素/秒）
const PLATFORM_HOP_X_SPEED := 120.0
# HOP 安全超时：如果某只敌人卡在跳跃中超过此秒数还没落到任何平台，强制结束（防卡死）
const PLATFORM_HOP_TIMEOUT := 4.0
# HOP 滞回阈值：避免目标 Y 与当前 Y 几乎相同时被错判为 DOWN（同层换位）
const PLATFORM_HOP_DOWN_HYSTERESIS := 8.0
# HOP 类型：UP=直接施加跳跃速度；DOWN=穿透单向平台往下落
enum HopMode { UP, DOWN }
var is_hopping: bool = false
var _hop_mode: int = HopMode.UP
var _hop_target_x: float = 0.0   # 目标平台中心 X
var _hop_target_y: float = 0.0   # 目标平台站立面 Y（用于落地判定容差）
var _hop_target_left: float = 0.0
var _hop_target_right: float = 0.0
var _hop_timer: float = 0.0      # 已进入 HOP 的累计时长（超过 TIMEOUT 强制结束）
var _hop_check_timer: float = 0.0
var _hop_check_interval: float = 0.0
# 缓存 Level 节点引用（懒加载；找不到则放弃 hop 机制，不阻塞其他逻辑）
var _level_ref: Node = null
var _level_lookup_done: bool = false

@onready var sprite: Sprite2D = $Sprite
@onready var anim_timer: Timer = $AnimTimer
@onready var ground_check: RayCast2D = $GroundCheck
@onready var wall_check: RayCast2D = $WallCheck
@onready var collision: CollisionShape2D = $Collision

var direction: int = -1
var is_captured: bool = false
var captured_lock_velocity: Vector2 = Vector2.ZERO
var anim_frame: int = 0
var dying: bool = false
var health: int = 1
var charging: bool = false
var charge_cooldown: float = 0.0
var initial_y: float = 0.0

# Boss 召唤的小怪 spawn 后短暂"豁免期"：避免被场上残留的 ball
# （player.gd 投掷出来翻滚 2s 的攻击物）在 spawn 那一帧立刻 die() 抹掉。
# Boss_Attack1 召唤 4 只敌人时，正好玩家可能刚发射 ball 攻击 Boss，
# ball 沿水平方向飞 1500px/s 经过多个平台，会在 spawn 后下一物理帧
# 同时秒杀 1~4 只刚出现的敌人 → 玩家看到"敌人完全没出现"。
# 默认 0（普通敌人不需要）；level.spawn_summoned_enemy() 会显式置为 SUMMON_INVULN_TIME。
const SUMMON_INVULN_TIME := 0.4
var summon_invuln_t: float = 0.0
# Boss 召唤的小怪 spawn 后短暂"无伤期"：出现后头 1 秒内不会对钟馗造成接触伤害。
# 让玩家有反应/躲避空间，避免敌人凭空出现就贴脸扣血。
# 默认 0（普通敌人立即可造成伤害）；level.spawn_summoned_enemy() 会显式置为 SUMMON_CONTACT_DAMAGE_DELAY。
const SUMMON_CONTACT_DAMAGE_DELAY := 1.0
var contact_damage_delay_t: float = 0.0
var bat_oscillation_t: float = 0.0
var player_ref: Node2D = null

const SCORE_VALUES := {
	Type.METEOR_HAMMER: 200,
	Type.RED_GHOST: 300,
	Type.RED_DEVIL: 400,
	Type.PALACE_ZOMBIE: 500,
	Type.FAT_DEMON_KING: 600,
}
const FAT_DEMON_KING_MAX_HEALTH := 10

const TEX := {
	Type.METEOR_HAMMER: {
		"move":           [
			"res://assets/sprites/Enemy/MeteorHammer/MeteorHammer_idle/MeteorHammer_idle_01.png",
			"res://assets/sprites/Enemy/MeteorHammer/MeteorHammer_idle/MeteorHammer_idle_02.png",
			"res://assets/sprites/Enemy/MeteorHammer/MeteorHammer_idle/MeteorHammer_idle_03.png",
			"res://assets/sprites/Enemy/MeteorHammer/MeteorHammer_idle/MeteorHammer_idle_04.png",
			"res://assets/sprites/Enemy/MeteorHammer/MeteorHammer_idle/MeteorHammer_idle_05.png",
			"res://assets/sprites/Enemy/MeteorHammer/MeteorHammer_idle/MeteorHammer_idle_06.png",
			"res://assets/sprites/Enemy/MeteorHammer/MeteorHammer_idle/MeteorHammer_idle_07.png",
			"res://assets/sprites/Enemy/MeteorHammer/MeteorHammer_idle/MeteorHammer_idle_08.png",
			"res://assets/sprites/Enemy/MeteorHammer/MeteorHammer_idle/MeteorHammer_idle_09.png",
			"res://assets/sprites/Enemy/MeteorHammer/MeteorHammer_idle/MeteorHammer_idle_10.png",
			"res://assets/sprites/Enemy/MeteorHammer/MeteorHammer_idle/MeteorHammer_idle_11.png",
		],
		"captured":       "res://assets/sprites/Enemy/MeteorHammer/MeteorHammer_idle/MeteorHammer_idle_01.png",
		"capture_front":  [
			"res://assets/sprites/Enemy/MeteorHammer/MeteorHammer_capture/MeteorHammer_capture_f_01.png",
			"res://assets/sprites/Enemy/MeteorHammer/MeteorHammer_capture/MeteorHammer_capture_f_02.png",
			"res://assets/sprites/Enemy/MeteorHammer/MeteorHammer_capture/MeteorHammer_capture_f_03.png",
			"res://assets/sprites/Enemy/MeteorHammer/MeteorHammer_capture/MeteorHammer_capture_f_04.png",
			"res://assets/sprites/Enemy/MeteorHammer/MeteorHammer_capture/MeteorHammer_capture_f_05.png",
		],
		"capture_back":   [
			"res://assets/sprites/Enemy/MeteorHammer/MeteorHammer_capture/MeteorHammer_capture_b_01.png",
			"res://assets/sprites/Enemy/MeteorHammer/MeteorHammer_capture/MeteorHammer_capture_b_02.png",
			"res://assets/sprites/Enemy/MeteorHammer/MeteorHammer_capture/MeteorHammer_capture_b_03.png",
			"res://assets/sprites/Enemy/MeteorHammer/MeteorHammer_capture/MeteorHammer_capture_b_04.png",
			"res://assets/sprites/Enemy/MeteorHammer/MeteorHammer_capture/MeteorHammer_capture_b_05.png",
		],
		# idle 状态帧（MH 暂无独立 walk 美术，idle 与 walk 共用同一套帧；视觉上仅靠"停下来"区分）
		"idle":           [
			"res://assets/sprites/Enemy/MeteorHammer/MeteorHammer_idle/MeteorHammer_idle_01.png",
			"res://assets/sprites/Enemy/MeteorHammer/MeteorHammer_idle/MeteorHammer_idle_02.png",
			"res://assets/sprites/Enemy/MeteorHammer/MeteorHammer_idle/MeteorHammer_idle_03.png",
			"res://assets/sprites/Enemy/MeteorHammer/MeteorHammer_idle/MeteorHammer_idle_04.png",
			"res://assets/sprites/Enemy/MeteorHammer/MeteorHammer_idle/MeteorHammer_idle_05.png",
			"res://assets/sprites/Enemy/MeteorHammer/MeteorHammer_idle/MeteorHammer_idle_06.png",
			"res://assets/sprites/Enemy/MeteorHammer/MeteorHammer_idle/MeteorHammer_idle_07.png",
			"res://assets/sprites/Enemy/MeteorHammer/MeteorHammer_idle/MeteorHammer_idle_08.png",
			"res://assets/sprites/Enemy/MeteorHammer/MeteorHammer_idle/MeteorHammer_idle_09.png",
			"res://assets/sprites/Enemy/MeteorHammer/MeteorHammer_idle/MeteorHammer_idle_10.png",
			"res://assets/sprites/Enemy/MeteorHammer/MeteorHammer_idle/MeteorHammer_idle_11.png",
		],
		# 流星锤攻击：角色动作序列（28 帧）
		# 0~27 是预备→蓄势→甩锤（一次性播放）；21~27 是"挥锤过程中"的循环段（扔锤+收锤期间反复播）
		"mh_attack":      [
			"res://assets/sprites/Enemy/MeteorHammer/MeteorHammer_Attack/MeteorHammer_Attack_01.png",
			"res://assets/sprites/Enemy/MeteorHammer/MeteorHammer_Attack/MeteorHammer_Attack_02.png",
			"res://assets/sprites/Enemy/MeteorHammer/MeteorHammer_Attack/MeteorHammer_Attack_03.png",
			"res://assets/sprites/Enemy/MeteorHammer/MeteorHammer_Attack/MeteorHammer_Attack_04.png",
			"res://assets/sprites/Enemy/MeteorHammer/MeteorHammer_Attack/MeteorHammer_Attack_05.png",
			"res://assets/sprites/Enemy/MeteorHammer/MeteorHammer_Attack/MeteorHammer_Attack_06.png",
			"res://assets/sprites/Enemy/MeteorHammer/MeteorHammer_Attack/MeteorHammer_Attack_07.png",
			"res://assets/sprites/Enemy/MeteorHammer/MeteorHammer_Attack/MeteorHammer_Attack_08.png",
			"res://assets/sprites/Enemy/MeteorHammer/MeteorHammer_Attack/MeteorHammer_Attack_09.png",
			"res://assets/sprites/Enemy/MeteorHammer/MeteorHammer_Attack/MeteorHammer_Attack_10.png",
			"res://assets/sprites/Enemy/MeteorHammer/MeteorHammer_Attack/MeteorHammer_Attack_11.png",
			"res://assets/sprites/Enemy/MeteorHammer/MeteorHammer_Attack/MeteorHammer_Attack_12.png",
			"res://assets/sprites/Enemy/MeteorHammer/MeteorHammer_Attack/MeteorHammer_Attack_13.png",
			"res://assets/sprites/Enemy/MeteorHammer/MeteorHammer_Attack/MeteorHammer_Attack_14.png",
			"res://assets/sprites/Enemy/MeteorHammer/MeteorHammer_Attack/MeteorHammer_Attack_15.png",
			"res://assets/sprites/Enemy/MeteorHammer/MeteorHammer_Attack/MeteorHammer_Attack_16.png",
			"res://assets/sprites/Enemy/MeteorHammer/MeteorHammer_Attack/MeteorHammer_Attack_17.png",
			"res://assets/sprites/Enemy/MeteorHammer/MeteorHammer_Attack/MeteorHammer_Attack_18.png",
			"res://assets/sprites/Enemy/MeteorHammer/MeteorHammer_Attack/MeteorHammer_Attack_19.png",
			"res://assets/sprites/Enemy/MeteorHammer/MeteorHammer_Attack/MeteorHammer_Attack_20.png",
			"res://assets/sprites/Enemy/MeteorHammer/MeteorHammer_Attack/MeteorHammer_Attack_21.png",
			"res://assets/sprites/Enemy/MeteorHammer/MeteorHammer_Attack/MeteorHammer_Attack_22.png",
			"res://assets/sprites/Enemy/MeteorHammer/MeteorHammer_Attack/MeteorHammer_Attack_23.png",
			"res://assets/sprites/Enemy/MeteorHammer/MeteorHammer_Attack/MeteorHammer_Attack_24.png",
			"res://assets/sprites/Enemy/MeteorHammer/MeteorHammer_Attack/MeteorHammer_Attack_25.png",
			"res://assets/sprites/Enemy/MeteorHammer/MeteorHammer_Attack/MeteorHammer_Attack_26.png",
			"res://assets/sprites/Enemy/MeteorHammer/MeteorHammer_Attack/MeteorHammer_Attack_27.png",
			"res://assets/sprites/Enemy/MeteorHammer/MeteorHammer_Attack/MeteorHammer_Attack_28.png",
		],
		# 流星锤：扔出去的锤子序列帧（5 帧）。扔出 = 1→5 正向播放；收回 = 5→1 反向播放
		"mh_hammer":      [
			"res://assets/sprites/Enemy/MeteorHammer/MeteorHammer_Hammer/MeteorHammer_Hammer_01.png",
			"res://assets/sprites/Enemy/MeteorHammer/MeteorHammer_Hammer/MeteorHammer_Hammer_02.png",
			"res://assets/sprites/Enemy/MeteorHammer/MeteorHammer_Hammer/MeteorHammer_Hammer_03.png",
			"res://assets/sprites/Enemy/MeteorHammer/MeteorHammer_Hammer/MeteorHammer_Hammer_04.png",
			"res://assets/sprites/Enemy/MeteorHammer/MeteorHammer_Hammer/MeteorHammer_Hammer_05.png",
		],
		"die":            ["res://assets/sprites/Enemy/MeteorHammer/MeteorHammer_idle/MeteorHammer_idle_01.png"],
	},
	Type.RED_GHOST: {
		"move":           [
			"res://assets/sprites/Enemy/RedGhost/RedGhost_idle/RedGhost_idle_01.png",
			"res://assets/sprites/Enemy/RedGhost/RedGhost_idle/RedGhost_idle_02.png",
			"res://assets/sprites/Enemy/RedGhost/RedGhost_idle/RedGhost_idle_03.png",
			"res://assets/sprites/Enemy/RedGhost/RedGhost_idle/RedGhost_idle_04.png",
			"res://assets/sprites/Enemy/RedGhost/RedGhost_idle/RedGhost_idle_05.png",
			"res://assets/sprites/Enemy/RedGhost/RedGhost_idle/RedGhost_idle_06.png",
			"res://assets/sprites/Enemy/RedGhost/RedGhost_idle/RedGhost_idle_07.png",
		],
		"captured":       "res://assets/sprites/Enemy/RedGhost/RedGhost_idle/RedGhost_idle_01.png",
		# capture_front 支持 String 或 Array：String=单帧，Array=序列帧（与 AnimTimer 同步）
		"capture_front":  [
			"res://assets/sprites/Enemy/RedGhost/RedGhost_capture/RedGhost_capture_f_01.png",
			"res://assets/sprites/Enemy/RedGhost/RedGhost_capture/RedGhost_capture_f_02.png",
			"res://assets/sprites/Enemy/RedGhost/RedGhost_capture/RedGhost_capture_f_03.png",
			"res://assets/sprites/Enemy/RedGhost/RedGhost_capture/RedGhost_capture_f_04.png",
		],
		"capture_back":   [
			"res://assets/sprites/Enemy/RedGhost/RedGhost_capture/RedGhost_capture_b_01.png",
			"res://assets/sprites/Enemy/RedGhost/RedGhost_capture/RedGhost_capture_b_02.png",
			"res://assets/sprites/Enemy/RedGhost/RedGhost_capture/RedGhost_capture_b_03.png",
			"res://assets/sprites/Enemy/RedGhost/RedGhost_capture/RedGhost_capture_b_04.png",
			"res://assets/sprites/Enemy/RedGhost/RedGhost_capture/RedGhost_capture_b_05.png",
		],
		# idle 状态帧（RG 暂无独立 walk 美术，idle 与 walk 共用同一套帧）
		"idle":           [
			"res://assets/sprites/Enemy/RedGhost/RedGhost_idle/RedGhost_idle_01.png",
			"res://assets/sprites/Enemy/RedGhost/RedGhost_idle/RedGhost_idle_02.png",
			"res://assets/sprites/Enemy/RedGhost/RedGhost_idle/RedGhost_idle_03.png",
			"res://assets/sprites/Enemy/RedGhost/RedGhost_idle/RedGhost_idle_04.png",
			"res://assets/sprites/Enemy/RedGhost/RedGhost_idle/RedGhost_idle_05.png",
			"res://assets/sprites/Enemy/RedGhost/RedGhost_idle/RedGhost_idle_06.png",
			"res://assets/sprites/Enemy/RedGhost/RedGhost_idle/RedGhost_idle_07.png",
		],
		# DASH 突进显现动画：红衣女鬼突进 3 身位后显示，播放 5 帧 flutter 序列
		"dash":           [
			"res://assets/sprites/Enemy/RedGhost/RedGhost_flutter/RedGhost_flutter_01.png",
			"res://assets/sprites/Enemy/RedGhost/RedGhost_flutter/RedGhost_flutter_02.png",
			"res://assets/sprites/Enemy/RedGhost/RedGhost_flutter/RedGhost_flutter_03.png",
			"res://assets/sprites/Enemy/RedGhost/RedGhost_flutter/RedGhost_flutter_04.png",
			"res://assets/sprites/Enemy/RedGhost/RedGhost_flutter/RedGhost_flutter_05.png",
		],
		"die":            ["res://assets/sprites/Enemy/RedGhost/RedGhost_idle/RedGhost_idle_01.png"],
	},
	Type.RED_DEVIL: {
		# "move" 是常态显示帧（包括行进）。红魔王一直在巡逻（除 frozen/capture/die），
		# 所以这里直接用 walk 序列。idle_01~09 暂未使用，留作未来"静止状态"区分时启用。
		"move":           [
			"res://assets/sprites/Enemy/RedDevil/RedDevil_walk/RedDevil_walk_01.png",
			"res://assets/sprites/Enemy/RedDevil/RedDevil_walk/RedDevil_walk_02.png",
			"res://assets/sprites/Enemy/RedDevil/RedDevil_walk/RedDevil_walk_03.png",
			"res://assets/sprites/Enemy/RedDevil/RedDevil_walk/RedDevil_walk_04.png",
			"res://assets/sprites/Enemy/RedDevil/RedDevil_walk/RedDevil_walk_05.png",
		],
		"captured":       "res://assets/sprites/Enemy/RedDevil/RedDevil_idle/RedDevil_idle_01.png",
		"capture_front":  [
			"res://assets/sprites/Enemy/RedDevil/RedDevil_capture/RedDevil_capture_f_01.png",
			"res://assets/sprites/Enemy/RedDevil/RedDevil_capture/RedDevil_capture_f_02.png",
			"res://assets/sprites/Enemy/RedDevil/RedDevil_capture/RedDevil_capture_f_03.png",
			"res://assets/sprites/Enemy/RedDevil/RedDevil_capture/RedDevil_capture_f_04.png",
			"res://assets/sprites/Enemy/RedDevil/RedDevil_capture/RedDevil_capture_f_05.png",
		],
		"capture_back":   [
			"res://assets/sprites/Enemy/RedDevil/RedDevil_capture/RedDevil_capture_b_01.png",
			"res://assets/sprites/Enemy/RedDevil/RedDevil_capture/RedDevil_capture_b_02.png",
			"res://assets/sprites/Enemy/RedDevil/RedDevil_capture/RedDevil_capture_b_03.png",
			"res://assets/sprites/Enemy/RedDevil/RedDevil_capture/RedDevil_capture_b_04.png",
			"res://assets/sprites/Enemy/RedDevil/RedDevil_capture/RedDevil_capture_b_05.png",
		],
		# idle 状态帧（RD 有独立 idle_01~09 美术，与 walk 美术不同）
		"idle":           [
			"res://assets/sprites/Enemy/RedDevil/RedDevil_idle/RedDevil_idle_01.png",
			"res://assets/sprites/Enemy/RedDevil/RedDevil_idle/RedDevil_idle_02.png",
			"res://assets/sprites/Enemy/RedDevil/RedDevil_idle/RedDevil_idle_03.png",
			"res://assets/sprites/Enemy/RedDevil/RedDevil_idle/RedDevil_idle_04.png",
			"res://assets/sprites/Enemy/RedDevil/RedDevil_idle/RedDevil_idle_05.png",
			"res://assets/sprites/Enemy/RedDevil/RedDevil_idle/RedDevil_idle_06.png",
			"res://assets/sprites/Enemy/RedDevil/RedDevil_idle/RedDevil_idle_07.png",
			"res://assets/sprites/Enemy/RedDevil/RedDevil_idle/RedDevil_idle_08.png",
			"res://assets/sprites/Enemy/RedDevil/RedDevil_idle/RedDevil_idle_09.png",
		],
		# 攻击序列：红魔王"举狼牙棒挥向前方"动画，5 帧
		# 与 PalaceZombie 共用 ATTACK 状态机（_attack_frames + _tick_attack_anim）
		# 红魔王 ATTACK 是纯近战挥击，不生成投射物（火种生成在 _tick_attack_anim 中按 enemy_type 门控）
		"attack":         [
			"res://assets/sprites/Enemy/RedDevil/RedDevil_Attack/RedDevil_Attack_01.png",
			"res://assets/sprites/Enemy/RedDevil/RedDevil_Attack/RedDevil_Attack_02.png",
			"res://assets/sprites/Enemy/RedDevil/RedDevil_Attack/RedDevil_Attack_03.png",
			"res://assets/sprites/Enemy/RedDevil/RedDevil_Attack/RedDevil_Attack_04.png",
			"res://assets/sprites/Enemy/RedDevil/RedDevil_Attack/RedDevil_Attack_05.png",
		],
		"die":            ["res://assets/sprites/Enemy/RedDevil/RedDevil_idle/RedDevil_idle_01.png"],
	},
	Type.PALACE_ZOMBIE: {
		# "move" 是常态显示帧。宫廷僵尸是"跳着走"：跳一下 → 立定停留 → 再跳一下。
		# 5 帧 walk 序列代表一次完整跳跃，由 WALK_INTERMITTENT 机制间歇式播放。
		# idle_01~07 暂未使用，留作未来"静止状态"区分时启用。
		"move":           [
			"res://assets/sprites/Enemy/PalaceZombie/PalaceZombie_walk/PalaceZombie_walk_01.png",
			"res://assets/sprites/Enemy/PalaceZombie/PalaceZombie_walk/PalaceZombie_walk_02.png",
			"res://assets/sprites/Enemy/PalaceZombie/PalaceZombie_walk/PalaceZombie_walk_03.png",
			"res://assets/sprites/Enemy/PalaceZombie/PalaceZombie_walk/PalaceZombie_walk_04.png",
			"res://assets/sprites/Enemy/PalaceZombie/PalaceZombie_walk/PalaceZombie_walk_05.png",
		],
		"captured":       "res://assets/sprites/Enemy/PalaceZombie/PalaceZombie_idle/PalaceZombie_idle_01.png",
		"capture_front":  [
			"res://assets/sprites/Enemy/PalaceZombie/PalaceZombie_capture/PalaceZombie_capture_f_01.png",
			"res://assets/sprites/Enemy/PalaceZombie/PalaceZombie_capture/PalaceZombie_capture_f_02.png",
			"res://assets/sprites/Enemy/PalaceZombie/PalaceZombie_capture/PalaceZombie_capture_f_03.png",
			"res://assets/sprites/Enemy/PalaceZombie/PalaceZombie_capture/PalaceZombie_capture_f_04.png",
			"res://assets/sprites/Enemy/PalaceZombie/PalaceZombie_capture/PalaceZombie_capture_f_05.png",
		],
		"capture_back":   [
			"res://assets/sprites/Enemy/PalaceZombie/PalaceZombie_capture/PalaceZombie_capture_b_01.png",
			"res://assets/sprites/Enemy/PalaceZombie/PalaceZombie_capture/PalaceZombie_capture_b_02.png",
			"res://assets/sprites/Enemy/PalaceZombie/PalaceZombie_capture/PalaceZombie_capture_b_03.png",
			"res://assets/sprites/Enemy/PalaceZombie/PalaceZombie_capture/PalaceZombie_capture_b_04.png",
			"res://assets/sprites/Enemy/PalaceZombie/PalaceZombie_capture/PalaceZombie_capture_b_05.png",
		],
		# idle 状态帧（PZ 有独立 idle_01~07 美术，与跳走的 walk 美术不同）
		"idle":           [
			"res://assets/sprites/Enemy/PalaceZombie/PalaceZombie_idle/PalaceZombie_idle_01.png",
			"res://assets/sprites/Enemy/PalaceZombie/PalaceZombie_idle/PalaceZombie_idle_02.png",
			"res://assets/sprites/Enemy/PalaceZombie/PalaceZombie_idle/PalaceZombie_idle_03.png",
			"res://assets/sprites/Enemy/PalaceZombie/PalaceZombie_idle/PalaceZombie_idle_04.png",
			"res://assets/sprites/Enemy/PalaceZombie/PalaceZombie_idle/PalaceZombie_idle_05.png",
			"res://assets/sprites/Enemy/PalaceZombie/PalaceZombie_idle/PalaceZombie_idle_06.png",
			"res://assets/sprites/Enemy/PalaceZombie/PalaceZombie_idle/PalaceZombie_idle_07.png",
		],
		# 攻击序列：宫廷僵尸"甩法杖射火种"动画，5 帧
		"attack":         [
			"res://assets/sprites/Enemy/PalaceZombie/PalaceZombie_attack/PalaceZombie_attack_1.png",
			"res://assets/sprites/Enemy/PalaceZombie/PalaceZombie_attack/PalaceZombie_attack_2.png",
			"res://assets/sprites/Enemy/PalaceZombie/PalaceZombie_attack/PalaceZombie_attack_3.png",
			"res://assets/sprites/Enemy/PalaceZombie/PalaceZombie_attack/PalaceZombie_attack_4.png",
			"res://assets/sprites/Enemy/PalaceZombie/PalaceZombie_attack/PalaceZombie_attack_5.png",
		],
		"die":            ["res://assets/sprites/Enemy/PalaceZombie/PalaceZombie_idle/PalaceZombie_idle_01.png"],
	},
	Type.FAT_DEMON_KING: {
		"move":           [
			"res://assets/sprites/Enemy/FatDemonKing/FatDemonKing_idle/FatDemonKing_idle_01.png",
			"res://assets/sprites/Enemy/FatDemonKing/FatDemonKing_idle/FatDemonKing_idle_02.png",
			"res://assets/sprites/Enemy/FatDemonKing/FatDemonKing_idle/FatDemonKing_idle_03.png",
			"res://assets/sprites/Enemy/FatDemonKing/FatDemonKing_idle/FatDemonKing_idle_04.png",
			"res://assets/sprites/Enemy/FatDemonKing/FatDemonKing_idle/FatDemonKing_idle_05.png",
			"res://assets/sprites/Enemy/FatDemonKing/FatDemonKing_idle/FatDemonKing_idle_06.png",
			"res://assets/sprites/Enemy/FatDemonKing/FatDemonKing_idle/FatDemonKing_idle_07.png",
			"res://assets/sprites/Enemy/FatDemonKing/FatDemonKing_idle/FatDemonKing_idle_08.png",
			"res://assets/sprites/Enemy/FatDemonKing/FatDemonKing_idle/FatDemonKing_idle_09.png",
			"res://assets/sprites/Enemy/FatDemonKing/FatDemonKing_idle/FatDemonKing_idle_10.png",
			"res://assets/sprites/Enemy/FatDemonKing/FatDemonKing_idle/FatDemonKing_idle_11.png",
			"res://assets/sprites/Enemy/FatDemonKing/FatDemonKing_idle/FatDemonKing_idle_12.png",
			"res://assets/sprites/Enemy/FatDemonKing/FatDemonKing_idle/FatDemonKing_idle_13.png",
			"res://assets/sprites/Enemy/FatDemonKing/FatDemonKing_idle/FatDemonKing_idle_14.png",
			"res://assets/sprites/Enemy/FatDemonKing/FatDemonKing_idle/FatDemonKing_idle_15.png",
			"res://assets/sprites/Enemy/FatDemonKing/FatDemonKing_idle/FatDemonKing_idle_16.png",
		],
		"captured":       "res://assets/sprites/Enemy/FatDemonKing/FatDemonKing_idle/FatDemonKing_idle_01.png",
		"capture_front":  "res://assets/sprites/Enemy/FatDemonKing/FatDemonKing_idle/FatDemonKing_idle_01.png",
		"capture_back":   "res://assets/sprites/Enemy/FatDemonKing/FatDemonKing_idle/FatDemonKing_idle_01.png",
		"idle":           [
			"res://assets/sprites/Enemy/FatDemonKing/FatDemonKing_idle/FatDemonKing_idle_01.png",
			"res://assets/sprites/Enemy/FatDemonKing/FatDemonKing_idle/FatDemonKing_idle_02.png",
			"res://assets/sprites/Enemy/FatDemonKing/FatDemonKing_idle/FatDemonKing_idle_03.png",
			"res://assets/sprites/Enemy/FatDemonKing/FatDemonKing_idle/FatDemonKing_idle_04.png",
			"res://assets/sprites/Enemy/FatDemonKing/FatDemonKing_idle/FatDemonKing_idle_05.png",
			"res://assets/sprites/Enemy/FatDemonKing/FatDemonKing_idle/FatDemonKing_idle_06.png",
			"res://assets/sprites/Enemy/FatDemonKing/FatDemonKing_idle/FatDemonKing_idle_07.png",
			"res://assets/sprites/Enemy/FatDemonKing/FatDemonKing_idle/FatDemonKing_idle_08.png",
			"res://assets/sprites/Enemy/FatDemonKing/FatDemonKing_idle/FatDemonKing_idle_09.png",
			"res://assets/sprites/Enemy/FatDemonKing/FatDemonKing_idle/FatDemonKing_idle_10.png",
			"res://assets/sprites/Enemy/FatDemonKing/FatDemonKing_idle/FatDemonKing_idle_11.png",
			"res://assets/sprites/Enemy/FatDemonKing/FatDemonKing_idle/FatDemonKing_idle_12.png",
			"res://assets/sprites/Enemy/FatDemonKing/FatDemonKing_idle/FatDemonKing_idle_13.png",
			"res://assets/sprites/Enemy/FatDemonKing/FatDemonKing_idle/FatDemonKing_idle_14.png",
			"res://assets/sprites/Enemy/FatDemonKing/FatDemonKing_idle/FatDemonKing_idle_15.png",
			"res://assets/sprites/Enemy/FatDemonKing/FatDemonKing_idle/FatDemonKing_idle_16.png",
		],
		"fdk_attack":     [
			"res://assets/sprites/Enemy/FatDemonKing/FatDemonKing_Attack1/FatDemonKing_Attack1_01.png",
			"res://assets/sprites/Enemy/FatDemonKing/FatDemonKing_Attack1/FatDemonKing_Attack1_02.png",
			"res://assets/sprites/Enemy/FatDemonKing/FatDemonKing_Attack1/FatDemonKing_Attack1_03.png",
			"res://assets/sprites/Enemy/FatDemonKing/FatDemonKing_Attack1/FatDemonKing_Attack1_04.png",
			"res://assets/sprites/Enemy/FatDemonKing/FatDemonKing_Attack1/FatDemonKing_Attack1_05.png",
			"res://assets/sprites/Enemy/FatDemonKing/FatDemonKing_Attack1/FatDemonKing_Attack1_06.png",
			"res://assets/sprites/Enemy/FatDemonKing/FatDemonKing_Attack1/FatDemonKing_Attack1_07.png",
			"res://assets/sprites/Enemy/FatDemonKing/FatDemonKing_Attack1/FatDemonKing_Attack1_08.png",
			"res://assets/sprites/Enemy/FatDemonKing/FatDemonKing_Attack1/FatDemonKing_Attack1_09.png",
			"res://assets/sprites/Enemy/FatDemonKing/FatDemonKing_Attack1/FatDemonKing_Attack1_10.png",
			"res://assets/sprites/Enemy/FatDemonKing/FatDemonKing_Attack1/FatDemonKing_Attack1_11.png",
			"res://assets/sprites/Enemy/FatDemonKing/FatDemonKing_Attack1/FatDemonKing_Attack1_12.png",
			"res://assets/sprites/Enemy/FatDemonKing/FatDemonKing_Attack1/FatDemonKing_Attack1_13.png",
			"res://assets/sprites/Enemy/FatDemonKing/FatDemonKing_Attack1/FatDemonKing_Attack1_14.png",
			"res://assets/sprites/Enemy/FatDemonKing/FatDemonKing_Attack1/FatDemonKing_Attack1_15.png",
			"res://assets/sprites/Enemy/FatDemonKing/FatDemonKing_Attack1/FatDemonKing_Attack1_16.png",
		],
		"fdk_attack2":    [
			"res://assets/sprites/Enemy/FatDemonKing/FatDemonKing_Attack2/FatDemonKing_Attack2_01.png",
			"res://assets/sprites/Enemy/FatDemonKing/FatDemonKing_Attack2/FatDemonKing_Attack2_02.png",
			"res://assets/sprites/Enemy/FatDemonKing/FatDemonKing_Attack2/FatDemonKing_Attack2_03.png",
			"res://assets/sprites/Enemy/FatDemonKing/FatDemonKing_Attack2/FatDemonKing_Attack2_04.png",
			"res://assets/sprites/Enemy/FatDemonKing/FatDemonKing_Attack2/FatDemonKing_Attack2_05.png",
			"res://assets/sprites/Enemy/FatDemonKing/FatDemonKing_Attack2/FatDemonKing_Attack2_06.png",
			"res://assets/sprites/Enemy/FatDemonKing/FatDemonKing_Attack2/FatDemonKing_Attack2_07.png",
			"res://assets/sprites/Enemy/FatDemonKing/FatDemonKing_Attack2/FatDemonKing_Attack2_08.png",
			"res://assets/sprites/Enemy/FatDemonKing/FatDemonKing_Attack2/FatDemonKing_Attack2_09.png",
			"res://assets/sprites/Enemy/FatDemonKing/FatDemonKing_Attack2/FatDemonKing_Attack2_10.png",
			"res://assets/sprites/Enemy/FatDemonKing/FatDemonKing_Attack2/FatDemonKing_Attack2_11.png",
			"res://assets/sprites/Enemy/FatDemonKing/FatDemonKing_Attack2/FatDemonKing_Attack2_12.png",
			"res://assets/sprites/Enemy/FatDemonKing/FatDemonKing_Attack2/FatDemonKing_Attack2_13.png",
			"res://assets/sprites/Enemy/FatDemonKing/FatDemonKing_Attack2/FatDemonKing_Attack2_14.png",
			"res://assets/sprites/Enemy/FatDemonKing/FatDemonKing_Attack2/FatDemonKing_Attack2_15.png",
			"res://assets/sprites/Enemy/FatDemonKing/FatDemonKing_Attack2/FatDemonKing_Attack2_16.png",
			"res://assets/sprites/Enemy/FatDemonKing/FatDemonKing_Attack2/FatDemonKing_Attack2_17.png",
			"res://assets/sprites/Enemy/FatDemonKing/FatDemonKing_Attack2/FatDemonKing_Attack2_18.png",
			"res://assets/sprites/Enemy/FatDemonKing/FatDemonKing_Attack2/FatDemonKing_Attack2_19.png",
			"res://assets/sprites/Enemy/FatDemonKing/FatDemonKing_Attack2/FatDemonKing_Attack2_20.png",
			"res://assets/sprites/Enemy/FatDemonKing/FatDemonKing_Attack2/FatDemonKing_Attack2_21.png",
			"res://assets/sprites/Enemy/FatDemonKing/FatDemonKing_Attack2/FatDemonKing_Attack2_22.png",
		],
		"fdk_attack3":    [
			"res://assets/sprites/Enemy/FatDemonKing/FatDemonKing_Attack3/FatDemonKing_Attack3_01.png",
			"res://assets/sprites/Enemy/FatDemonKing/FatDemonKing_Attack3/FatDemonKing_Attack3_02.png",
			"res://assets/sprites/Enemy/FatDemonKing/FatDemonKing_Attack3/FatDemonKing_Attack3_03.png",
			"res://assets/sprites/Enemy/FatDemonKing/FatDemonKing_Attack3/FatDemonKing_Attack3_04.png",
			"res://assets/sprites/Enemy/FatDemonKing/FatDemonKing_Attack3/FatDemonKing_Attack3_05.png",
			"res://assets/sprites/Enemy/FatDemonKing/FatDemonKing_Attack3/FatDemonKing_Attack3_06.png",
			"res://assets/sprites/Enemy/FatDemonKing/FatDemonKing_Attack3/FatDemonKing_Attack3_07.png",
			"res://assets/sprites/Enemy/FatDemonKing/FatDemonKing_Attack3/FatDemonKing_Attack3_08.png",
			"res://assets/sprites/Enemy/FatDemonKing/FatDemonKing_Attack3/FatDemonKing_Attack3_09.png",
			"res://assets/sprites/Enemy/FatDemonKing/FatDemonKing_Attack3/FatDemonKing_Attack3_10.png",
			"res://assets/sprites/Enemy/FatDemonKing/FatDemonKing_Attack3/FatDemonKing_Attack3_11.png",
			"res://assets/sprites/Enemy/FatDemonKing/FatDemonKing_Attack3/FatDemonKing_Attack3_12.png",
			"res://assets/sprites/Enemy/FatDemonKing/FatDemonKing_Attack3/FatDemonKing_Attack3_13.png",
			"res://assets/sprites/Enemy/FatDemonKing/FatDemonKing_Attack3/FatDemonKing_Attack3_14.png",
			"res://assets/sprites/Enemy/FatDemonKing/FatDemonKing_Attack3/FatDemonKing_Attack3_15.png",
			"res://assets/sprites/Enemy/FatDemonKing/FatDemonKing_Attack3/FatDemonKing_Attack3_16.png",
			"res://assets/sprites/Enemy/FatDemonKing/FatDemonKing_Attack3/FatDemonKing_Attack3_17.png",
			"res://assets/sprites/Enemy/FatDemonKing/FatDemonKing_Attack3/FatDemonKing_Attack3_18.png",
			"res://assets/sprites/Enemy/FatDemonKing/FatDemonKing_Attack3/FatDemonKing_Attack3_19.png",
			"res://assets/sprites/Enemy/FatDemonKing/FatDemonKing_Attack3/FatDemonKing_Attack3_20.png",
			"res://assets/sprites/Enemy/FatDemonKing/FatDemonKing_Attack3/FatDemonKing_Attack3_21.png",
		],
		"die":            ["res://assets/sprites/Enemy/FatDemonKing/FatDemonKing_idle/FatDemonKing_idle_01.png"],
	},
}

var _frames: Array = []
# idle 状态序列帧（与 _frames=walk 区分；从 TEX[type]["idle"] 加载，没配的退化为 _frames）
var _idle_frames: Array = []
# attack 状态序列帧（仅 PALACE_ZOMBIE 配置；为空表示该敌人不会进入 ATTACK 状态）
var _attack_frames: Array = []
var _fdk_attack_frames: Array = []
# Attack2 序列帧（仅 FAT_DEMON_KING；与 Attack1 交替施展，目前只播放动画无机关效果）
var _fdk_attack2_frames: Array = []
# Attack3 序列帧（仅 FAT_DEMON_KING；胖魔王拍手，从画面上方降落 6 个随机敌人）
var _fdk_attack3_frames: Array = []

# walk / idle / attack / dash / mh_attack / fdk_attack 行为状态机：每个敌人在巡逻时随机切换 walk ↔ idle，idle 切回时随机决定是否折返
# ATTACK 状态：仅对 PALACE_ZOMBIE 启用，进入 IDLE 时按 ATTACK_PROB 概率改为 ATTACK（甩法杖射火种）
# DASH 状态：仅对 RED_GHOST 启用，进入 IDLE 时按 DASH_PROB 概率改为 DASH（消失→突进3身位→flutter显现）
# MH_ATTACK 状态：仅对 METEOR_HAMMER 启用，进入 IDLE 时按 MH_ATTACK_PROB 概率改为 MH_ATTACK
#   （预备动作→扔流星锤→收回→回 IDLE）
enum AnimState { WALK, IDLE, ATTACK, DASH, MH_ATTACK, FDK_ATTACK, FDK_ATTACK2, FDK_ATTACK3 }
var anim_state: int = AnimState.WALK
var state_timer: float = 0.0
var state_duration: float = 0.0  # 当前状态结束的总时长（随机）

# 状态时长随机范围（秒）
const WALK_DURATION_MIN := 2.0
const WALK_DURATION_MAX := 5.0
const IDLE_DURATION_MIN := 1.0
const IDLE_DURATION_MAX := 2.0
# idle → walk 切换时折返概率
const REVERSE_ON_RESUME_PROB := 0.5
# 让敌人离平台边缘和前方墙体稍微远一点，避免 chapter2 左侧这种窄平台把 AI 夹住。
const PLATFORM_EDGE_LOOKAHEAD := 12.0
const WALL_REBOUND_NUDGE := 6.0

# 宫廷僵尸 ATTACK 状态参数
# 进入 IDLE 时按此概率改为 ATTACK（甩法杖射火种）
const ATTACK_PROB := 0.6
# 攻击动画：5 帧 × ATTACK_FRAME_INTERVAL = 总时长
const ATTACK_FRAME_INTERVAL := 0.15
# 攻击序列在第 N 帧（0-indexed）触发火种生成（"法杖甩到前方"的那一瞬间）
const ATTACK_SPAWN_FRAME := 3
# 火种场景路径（懒加载在 _spawn_fire_seeds 中）
const FIRE_SEED_SCENE := "res://scenes/fire_seed.tscn"
# 两枚火种相对僵尸位置的 X 偏移（朝面向方向，第一枚在更前方，第二枚紧跟其后）
const FIRE_SEED_OFFSETS_X := [50.0, 10.0]
# 火种生成时相对僵尸的 Y 偏移（负值=偏上，从僵尸手中/法杖高度生成，下落贴地）
const FIRE_SEED_OFFSET_Y := -10.0

# 攻击动画专用累加器和状态
var _attack_anim_accum: float = 0.0
var _attack_frame_idx: int = 0
var _attack_spawned: bool = false  # 本轮攻击是否已生成火种（防止多帧重复触发）

# 红衣女鬼 DASH 状态参数
# 进入 IDLE 时按此概率改为 DASH（消失 → 突进 → flutter 显现）
const DASH_PROB := 0.5
# "消失"阶段时长（敌人 hide() 在原地，让玩家感受到"突然不见了"的瞬间）
const DASH_VANISH_DURATION := 0.18
# 突进距离（以 collision width 为身位单位，3 身位）
const DASH_BODY_LENGTHS := 3.0
# flutter 显现动画每帧间隔（5 帧 × 0.10s = 0.5s 一轮）
const DASH_FLUTTER_FRAME_INTERVAL := 0.10
# DASH 状态推进累加器 + 阶段
# 子阶段：VANISH（隐身）→ FLUTTER（显现 + 播放序列）→ 回 WALK
enum DashPhase { VANISH, FLUTTER }
var _dash_phase: int = DashPhase.VANISH
var _dash_phase_timer: float = 0.0
var _dash_frame_idx: int = 0
var _dash_anim_accum: float = 0.0
# flutter 序列帧（仅 RED_GHOST 配置；为空则不会进入 DASH 状态）
var _dash_frames: Array = []

# 流星锤怪 MH_ATTACK 状态参数
# 进入 IDLE 时按此概率改为 MH_ATTACK（扔锤 → 收锤 → 回 IDLE）
const MH_ATTACK_PROB := 0.55
# 角色动作每帧间隔（28 帧预备 + 之后的 21~27 循环都用此节奏）
const MH_ATTACK_FRAME_INTERVAL := 0.05  # 28 × 0.05 = 1.4s 预备
# 角色动作中"扔锤触发帧"的索引（0-indexed；用户说"播放到 Attack_21 时"→ index 20）
const MH_THROW_TRIGGER_FRAME := 20
# 角色循环段的起止 index（21~28 → index 20~27）
const MH_LOOP_FRAME_START := 20
const MH_LOOP_FRAME_END := 27   # inclusive
# 流星锤动画参数
# 锤每帧间隔（5 帧序列：1→5 表示链从短到全长伸出；5→1 收回）
# 锤 PNG 1733×200 已把整条链画进贴图，sprite 锚定在怪手部不移动，
# 由序列帧的差异表现"伸出"和"收回"动作。
const MH_HAMMER_FRAME_INTERVAL := 0.08
# 流星锤是否对玩家造成伤害（任意伸出阶段锤头碰到都扣 1 心）
const MH_HAMMER_DAMAGE := true
# 注：锤的 scale / offset X / offset Y / 锤头碰撞盒尺寸 现已搬到 CharTuning 由 F1 调参面板控制
# 字段：mh_hammer_scale / mh_hammer_offset_x / mh_hammer_offset_y / mh_hammer_head_size
# 攻击距离由 scale 决定：reach ≈ 1733 × scale

# MH_ATTACK 子阶段
# WINDUP: 播放 _01~_28 一次，到 frame 20（_21.png）时切到 THROW_OUT 并生成锤
# THROW_OUT: 角色循环 _21~_28，锤朝外飞 + 锤序列 1→5 正向播放
# RETRIEVE: 角色仍循环 _21~_28，锤朝怪飞回 + 锤序列 5→1 反向播放
# EXIT: 锤回到怪 → 销毁锤节点，回 WALK
enum MhAttackPhase { WINDUP, THROW_OUT, RETRIEVE }
var _mh_phase: int = MhAttackPhase.WINDUP
var _mh_char_frame_idx: int = 0           # 当前角色帧 index（0~27）
var _mh_char_anim_accum: float = 0.0
var _mh_hammer_frame_idx: int = 0         # 当前锤子帧 index（0~4）
var _mh_hammer_anim_accum: float = 0.0
var _mh_hammer_node: Sprite2D = null      # 飞出去的锤子精灵（攻击期间存活，结束销毁）
var _mh_hammer_area: Area2D = null        # 锤子的伤害检测 Area2D 子节点
var _mh_hammer_frames: Array = []         # 5 张锤子纹理（预加载）
var _mh_attack_frames: Array = []         # 28 张角色攻击纹理（预加载）

# 胖魔王机关攻击（重做）：
#   Mechanism 是一个常驻平台，右侧停着一颗铁球。平时机关平行（Rotation = 0）。
#   FatDemonKing_Attack1 时，机关按固定时序动作：旋转倾斜(0.5秒) → 停留(2秒) → 复位(1秒)。
#   机关旋转到 F1 编辑器设置的 fdk_mechanism_rotation 角度，铁球顺着倾斜角度滚落到上层
#   平台，并沿“上层左滚→中层右滚→下层左滚出画面”的三层路径匀速滚动（与机关时序相互独立）。
#   机关复位回 0 度后等待下一次 Attack1，循环往复。
#   铁球只伤害钟馗（扣 1 血），不影响敌人。
const FDK_INITIAL_ATTACK_DELAY := 3.0
const FDK_ATTACK_INTERVAL := 5.0
const FDK_ATTACK_FRAME_INTERVAL := 0.08
# Attack3：胖魔王拍手后，从画面上方降落这么多个随机种类的敌人。
const FDK_ATTACK3_SUMMON_COUNT := 6
# 降落敌人的起始 Y（屏幕顶在 y=0，取负值让敌人从画面外落入），落地由重力接管。
const FDK_ATTACK3_SPAWN_Y := -160.0
# 拍手动画播到这一帧（0-indexed）时触发敌人降落（"拍手到位"的那一瞬间）。
const FDK_ATTACK3_SUMMON_FRAME := 10
# 三层平台降落点的 X 取值范围（仅作为拿不到关卡几何时的地面兜底横向区间）。
const FDK_ATTACK3_SPAWN_X_MIN := 260.0
const FDK_ATTACK3_SPAWN_X_MAX := 1650.0
# 在目标平台横向范围内取 X 时，左右各留这么多像素边距。
# 这个值需要覆盖召唤池里最大碰撞盒的侧向外扩，避免敌人脚点虽然在平台上、
# 但身体出生或巡逻时插进 chapter3 中层平台左侧墙角。
const FDK_ATTACK3_LANDING_EDGE_MARGIN := 96.0
# 召唤落点避开钟馗，防止敌人刚落下就和玩家碰撞扣血。
const FDK_ATTACK3_PLAYER_SAFE_X := 180.0
const FDK_ATTACK3_PLAYER_SAFE_Y := 180.0
const FDK_ATTACK3_SPAWN_PICK_ATTEMPTS := 10
# 敌人从目标平台表面上方这么高处落下。取值需小于相邻两层表面间距（Stage3 约 260px），
# 确保中层/地面的起点已落在上一层平台之下，不会被上一层平台拦截或卡进其底面。
const FDK_ATTACK3_DROP_HEIGHT := 120.0
# 归类三层落点时，判定两块平台是否属于"同一层"的表面高度容差（像素）。
const FDK_ATTACK3_TIER_Y_TOLERANCE := 40.0
const PLATFORM_BODY_SIDE_CLEARANCE := 2.0
# 可供 Attack3 降落召唤的随机敌人场景（与 Boss 召唤一致的四种杂兵）。
const FDK_SUMMON_SCENE_PATHS := [
	"res://scenes/enemy_meteor_hammer.tscn",
	"res://scenes/enemy_red_ghost.tscn",
	"res://scenes/enemy_red_devil.tscn",
	"res://scenes/enemy_palace_zombie.tscn",
]
var _fdk_summon_scenes: Array = []
# 本轮 Attack3 是否已触发降落（防止动画多帧重复召唤）。
var _fdk_attack3_summoned: bool = false
# Attack3 落点带轮换起点：每次施放 +1 取模 3，让三层平台/地面的降落分布更均衡。
var _fdk_attack3_band_offset: int = 0
# Attack2：收招（动画播完）后延迟这么久，炮弹从屏幕上方落下砸向钟馗（秒）。
const FDK_ATTACK2_SHELL_DELAY := 1.0
# 炮弹场景（从屏幕上方落下，命中钟馗扣 1 血）。
const FDK_ARTILLERY_SHELL_SCENE := "res://scenes/artillery_shell.tscn"
# 炮弹生成时的屏幕上方起始 Y（屏幕顶在 y=0，取负值让炮弹从画面外落入）。
const FDK_ARTILLERY_SHELL_SPAWN_Y := -120.0
const FDK_IRON_BALL_SCENE := "res://scenes/iron_ball.tscn"
const FDK_IRON_BALL_TEXTURE := "res://assets/sprites/Chapter3/IronBall.png"
const FDK_IRON_BALL_REST_SCALE := 0.55
const FDK_MECHANISM_TEXTURE := "res://assets/sprites/Chapter3/Mechanism.png"
# 机关倾斜 / 复位的过渡时间（秒）：倾斜耗时 0.5 秒，复位耗时 1 秒。
const FDK_MECHANISM_TILT_TIME := 0.5
const FDK_MECHANISM_RESET_TIME := 1.0
# 机关倾斜到位后停留这么久，再开始复位（秒）。
const FDK_MECHANISM_TILT_HOLD_TIME := 2.0
# 倾斜完成后铁球开始滚落的延迟（秒）
const FDK_BALL_RELEASE_DELAY := 0.18
# 胖魔王执行攻击动画后，延迟这么久机关才开始旋转倾斜、铁球落下（秒）。
const FDK_ATTACK_TILT_DELAY := 1.0
# 机关相对胖魔王本体的默认摆放偏移（屏幕像素）。FDK 默认朝左，机关在身体前方。
# 这些是先验估值，可由 F1 的 Mechanism Pos X/Y + Pivot X/Y 进一步微调。
const FDK_MECHANISM_OFFSET := Vector2(-120.0, 30.0)
# 三层平台 / 地面的滚动表面高度 Y（取自 level_data Stage3：tile=10px，表面顶= row*10）。
# 上层平台 row35 → 表面 y≈350；中层平台 row61 → y≈610；下层地面 row85 → y≈850。
const FDK_TRACK_UPPER_Y := 350.0
const FDK_TRACK_MIDDLE_Y := 610.0
const FDK_TRACK_GROUND_Y := 850.0
# 各层的左右边界 X（终点掉落点）。
# 上层平台 x 225~1885（左端为终点）；中层平台 x 25~1685（右端为终点）；地面全宽。
const FDK_TRACK_UPPER_LEFT_X := 225.0
const FDK_TRACK_MIDDLE_LEFT_X := 25.0
const FDK_TRACK_MIDDLE_RIGHT_X := 1685.0
const FDK_TRACK_GROUND_EXIT_X := -220.0
# 铁球从机关左侧斜面滑下后，在上层平台上的着陆 X（位于机关下方偏左、上层平台范围内）。
# 相对 spawn 向左偏移这么多像素，使铁球先沿斜面向左下滑落，再开始三层平台滚动。
const FDK_TRACK_UPPER_LANDING_DX := -180.0
# 着陆 X 的左右兜底范围（钳制在上层平台有效区间内，避免极端调参把落点推出平台）。
const FDK_TRACK_UPPER_LANDING_MIN_X := 260.0
const FDK_TRACK_UPPER_LANDING_MAX_X := 1700.0
var _fdk_attack_cooldown: float = 0.0
var _fdk_attack_accum: float = 0.0
var _fdk_attack_frame_idx: int = 0
# 下一次普通攻击的招式索引（0=Attack1, 1=Attack2, 2=Attack3），每次出招后 +1 取模，
# 实现 Attack3 → Attack1 → Attack2 → Attack3 三招轮流，每 5 秒发动一次。首发为 Attack3。
var _fdk_next_attack: int = 2
var _fdk_mechanisms: Array[Node] = []
static var _fdk_mechanism_texture_cache: Texture2D = null
static var _resource_cache: Dictionary = {}
static var _frame_cache: Dictionary = {}
# 常驻机关平台（含静止铁球展示）与其当前活动的滚动铁球
var _fdk_mechanism: Node2D = null
var _fdk_active_ball: Node = null
# 机关是否处于倾斜状态（倾斜→停留→复位时序进行中）。
var _fdk_mechanism_tilted: bool = false
# 当前 capture 状态的序列帧缓存（朝向变化或退出 capture 时重建/清空）
var _capture_frames: Array = []
var _capture_frame_idx: int = 0
# 当前 capture key（"capture_front" / "capture_back"），用于检测朝向切换需要重建帧列表
var _capture_key: String = ""
# 给特定敌人 capture 动画用的独立累加器（覆盖 AnimTimer 0.25s 节奏）
var _capture_anim_accum: float = 0.0

# 间歇式 walk 动画配置（"跳一下 → 立定停留 → 再跳"节奏）
# key = enemy_type, value = { idle_interval: 立定停留秒数, frame_interval: 跳跃期间每帧秒数 }
# 跳跃阶段播放 _frames 全部 5 帧；立定阶段停留在第 1 帧（PNG 应为"落地立定"姿态）
# 未列出的敌人沿用默认连续播放（红魔王、流星锤、红衣女鬼）
const WALK_INTERMITTENT := {
	Type.PALACE_ZOMBIE: {
		"idle_interval":  0.4,    # 立定停留 0.4s
		"frame_interval": 0.1,    # 跳跃 5 帧 × 0.1s = 0.5s 一跳
	},
}
# 间歇式 walk 状态
var _walk_intermittent_playing: bool = false   # false=立定停留；true=正在跳跃
var _walk_intermittent_timer: float = 0.0

# 某些敌人的 capture 动画希望比默认 AnimTimer (4fps) 更快
# key = enemy_type，value = 每帧间隔（秒）；未列出的敌人沿用 AnimTimer 节奏
# 流星锤被吸时挣扎剧烈，5 帧用 0.125s/帧 (8fps) → 0.625s 一轮，比默认 1.25s/轮 急促一倍
const CAPTURE_FRAME_INTERVAL := {
	Type.METEOR_HAMMER: 0.125,
}

# 各敌人在 idle/move/die/attack 等普通状态下的额外 scale 乘子
# 默认（未列出的敌人）所有状态 mul=1.0，即 sprite.scale = base_scale
# 注意：MeteorHammer 历史上曾对 idle/move/die 乘 0.90 来缩小，导致 idle 视觉比 attack 小一截；
# 现已统一为 1.0，所有状态使用同一基准 scale，体积保持一致。
const NORMAL_SCALE_MUL := {}

# capture 状态下 sprite 的额外缩放补偿（当 capture 美术画布与 idle 不同尺寸时用）
# 当前 RedGhost idle/capture_f/capture_b 都统一为 500×500 → 无需补偿，全部 1.0
# （未来若有敌人的 capture 画布与 idle 不同，按需在此字典里加 mul）
const CAPTURE_SCALE_MUL := {
	Type.RED_GHOST: {
		"capture_front": 1.00,
		"capture_back":  1.00,
	},
	# PalaceZombie idle / capture_f / capture_b 全部 500×500，无需补偿
	Type.PALACE_ZOMBIE: {
		"capture_front": 1.00,
		"capture_back":  1.00,
	},
	# RedDevil idle / capture_f / capture_b 全部 600×600，无需补偿
	Type.RED_DEVIL: {
		"capture_front": 1.00,
		"capture_back":  1.00,
	},
}

func _ready() -> void:
	add_to_group("enemy")
	health = FAT_DEMON_KING_MAX_HEALTH if enemy_type == Type.FAT_DEMON_KING else 1
	_frames = _get_cached_frame_list(TEX[enemy_type]["move"])
	# 加载 idle 帧（若未配则退化为 walk 帧）
	_idle_frames = _frames
	if TEX[enemy_type].has("idle"):
		_idle_frames = _get_cached_frame_list(TEX[enemy_type]["idle"])
	if _idle_frames.is_empty():
		_idle_frames = _frames
	# 加载 attack 帧（有 attack 配置的敌人会进入 ATTACK 状态）
	if TEX[enemy_type].has("attack"):
		_attack_frames = _get_cached_frame_list(TEX[enemy_type]["attack"])
	# 加载 dash flutter 帧（仅 RED_GHOST 配置；其他敌人 _dash_frames 留空 → 不会进入 DASH 状态）
	if TEX[enemy_type].has("dash"):
		_dash_frames = _get_cached_frame_list(TEX[enemy_type]["dash"])
	# 加载流星锤怪攻击帧 + 锤子帧（仅 METEOR_HAMMER 配置）
	if TEX[enemy_type].has("mh_attack"):
		_mh_attack_frames = _get_cached_frame_list(TEX[enemy_type]["mh_attack"])
	if TEX[enemy_type].has("mh_hammer"):
		_mh_hammer_frames = _get_cached_frame_list(TEX[enemy_type]["mh_hammer"])
	if TEX[enemy_type].has("fdk_attack"):
		_fdk_attack_frames = _get_cached_frame_list(TEX[enemy_type]["fdk_attack"])
	if TEX[enemy_type].has("fdk_attack2"):
		_fdk_attack2_frames = _get_cached_frame_list(TEX[enemy_type]["fdk_attack2"])
	if TEX[enemy_type].has("fdk_attack3"):
		_fdk_attack3_frames = _get_cached_frame_list(TEX[enemy_type]["fdk_attack3"])
	_apply_normal_texture(_frames[0], "move")
	anim_timer.timeout.connect(_on_anim_tick)
	anim_timer.start()
	initial_y = global_position.y
	# 初始化 walk 状态计时（每个敌人各自随机起跑，避免整张图同步切换）
	state_duration = randf_range(WALK_DURATION_MIN, WALK_DURATION_MAX)
	state_timer = randf_range(0.0, state_duration * 0.5)  # 随机初始 phase
	# 初始化 hop 检查计时（每只敌人随机错开第一次检查，避免整波同步换平台）
	_hop_check_interval = randf_range(PLATFORM_HOP_CHECK_INTERVAL_MIN, PLATFORM_HOP_CHECK_INTERVAL_MAX)
	_hop_check_timer = randf_range(0.0, _hop_check_interval)
	wall_check.collision_mask = 1
	# 不在此处获取 player_ref：敌人可能在 player 之前被实例化 (level grid 顺序)
	# 改为在 _apply_capture_texture 中按需懒加载

	CharTuning.tuning_changed.connect(_apply_tuning)
	_apply_tuning()
	if enemy_type == Type.FAT_DEMON_KING:
		_fdk_attack_cooldown = FDK_INITIAL_ATTACK_DELAY
		call_deferred("_notify_fat_demon_king_hud_show")

func _exit_tree() -> void:
	if CharTuning.tuning_changed.is_connected(_apply_tuning):
		CharTuning.tuning_changed.disconnect(_apply_tuning)

func _apply_tuning() -> void:
	# shrink 阶段不要覆盖 sprite.scale / sprite.position —— shrink 公式接管
	# 只写入 collision（与 sprite 视觉解耦）
	var skip_sprite: bool = is_being_shrunk
	if enemy_type == Type.METEOR_HAMMER:
		if not skip_sprite:
			_apply_current_normal_scale()
			sprite.position = Vector2(CharTuning.mh_sprite_offset_x, CharTuning.mh_sprite_offset_y)
		if collision and collision.shape is RectangleShape2D:
			collision.position = Vector2(CharTuning.mh_col_offset_x, CharTuning.mh_col_offset_y)
			(collision.shape as RectangleShape2D).size = Vector2(CharTuning.mh_col_width, CharTuning.mh_col_height)
	elif enemy_type == Type.RED_GHOST:
		if not skip_sprite:
			sprite.scale = Vector2(CharTuning.rg_sprite_scale, CharTuning.rg_sprite_scale)
			sprite.position = Vector2(0, CharTuning.rg_sprite_offset_y)
		if collision and collision.shape is RectangleShape2D:
			collision.position = Vector2(CharTuning.rg_col_offset_x, CharTuning.rg_col_offset_y)
			(collision.shape as RectangleShape2D).size = Vector2(CharTuning.rg_col_width, CharTuning.rg_col_height)
	elif enemy_type == Type.RED_DEVIL:
		if not skip_sprite:
			sprite.scale = Vector2(CharTuning.rd_sprite_scale, CharTuning.rd_sprite_scale)
			sprite.position = Vector2(0, CharTuning.rd_sprite_offset_y)
		if collision and collision.shape is RectangleShape2D:
			collision.position = Vector2(CharTuning.rd_col_offset_x, CharTuning.rd_col_offset_y)
			(collision.shape as RectangleShape2D).size = Vector2(CharTuning.rd_col_width, CharTuning.rd_col_height)
	elif enemy_type == Type.PALACE_ZOMBIE:
		if not skip_sprite:
			sprite.scale = Vector2(CharTuning.pz_sprite_scale, CharTuning.pz_sprite_scale)
			sprite.position = Vector2(0, CharTuning.pz_sprite_offset_y)
		if collision and collision.shape is RectangleShape2D:
			collision.position = Vector2(CharTuning.pz_col_offset_x, CharTuning.pz_col_offset_y)
			(collision.shape as RectangleShape2D).size = Vector2(CharTuning.pz_col_width, CharTuning.pz_col_height)
	elif enemy_type == Type.FAT_DEMON_KING:
		if not skip_sprite:
			sprite.scale = Vector2(CharTuning.fdk_sprite_scale, CharTuning.fdk_sprite_scale)
			sprite.position = _get_base_sprite_offset()
		if collision and collision.shape is RectangleShape2D:
			collision.position = Vector2(CharTuning.fdk_col_offset_x, CharTuning.fdk_col_offset_y)
			(collision.shape as RectangleShape2D).size = Vector2(
				CharTuning.fdk_col_width * CharTuning.fdk_col_scale,
				CharTuning.fdk_col_height * CharTuning.fdk_col_scale
			)
		for mechanism in _fdk_mechanisms:
			if is_instance_valid(mechanism):
				_apply_fdk_mechanism_tuning(mechanism)
	# 如果当前处于 capture 状态，重新应用补偿（F1 调参后避免补偿丢失）
	# 注意：shrink 阶段不在这里处理，shrink 公式已包含 mul
	if _capture_key != "" and not is_being_shrunk:
		var base: float = _get_base_sprite_scale()
		var mul: float = _get_capture_scale_mul()
		sprite.scale = Vector2(base * mul, base * mul)
	queue_redraw()

func _draw() -> void:
	var tuning_panel = get_tree().get_first_node_in_group("tuning_panel")
	var panel_visible = tuning_panel != null and tuning_panel.visible
	if not panel_visible:
		return
	
	var cx: float = 0.0
	var cy: float = 0.0
	var w: float = 0.0
	var h: float = 0.0
	
	if enemy_type == Type.METEOR_HAMMER:
		cx = CharTuning.mh_col_offset_x
		cy = CharTuning.mh_col_offset_y
		w = CharTuning.mh_col_width
		h = CharTuning.mh_col_height
	elif enemy_type == Type.RED_GHOST:
		cx = CharTuning.rg_col_offset_x
		cy = CharTuning.rg_col_offset_y
		w = CharTuning.rg_col_width
		h = CharTuning.rg_col_height
	elif enemy_type == Type.RED_DEVIL:
		cx = CharTuning.rd_col_offset_x
		cy = CharTuning.rd_col_offset_y
		w = CharTuning.rd_col_width
		h = CharTuning.rd_col_height
	elif enemy_type == Type.PALACE_ZOMBIE:
		cx = CharTuning.pz_col_offset_x
		cy = CharTuning.pz_col_offset_y
		w = CharTuning.pz_col_width
		h = CharTuning.pz_col_height
	elif enemy_type == Type.FAT_DEMON_KING:
		cx = CharTuning.fdk_col_offset_x
		cy = CharTuning.fdk_col_offset_y
		w = CharTuning.fdk_col_width * CharTuning.fdk_col_scale
		h = CharTuning.fdk_col_height * CharTuning.fdk_col_scale
		
	var rect := Rect2(cx - w / 2.0, cy - h / 2.0, w, h)
	draw_rect(rect, Color(0, 1, 1, 0.35), true)
	draw_rect(rect, Color(0, 1, 1, 0.9), false, 2.0)
	# 流星锤怪：额外画出锤的预览（手部锚点 + 链伸出方向 + 最远端锤头 + 视觉 bbox）
	# 让用户可视化调整 hammer_offset_x/y / scale / head_size，无需等敌人真的攻击
	if enemy_type == Type.METEOR_HAMMER:
		var dir_x: float = 1.0 if direction >= 0 else -1.0
		var hand_local := Vector2(
			CharTuning.mh_hammer_offset_x * dir_x,
			CharTuning.mh_hammer_offset_y
		)
		# 锤贴图 1733×200，按 scale 缩放后整体 reach = 1733 × scale
		var hs: float = CharTuning.mh_hammer_scale
		var tex_w: float = 1733.0
		var reach: float = tex_w * hs
		var far_local := Vector2(hand_local.x + reach * dir_x, hand_local.y)
		# 链方向预览线（手部 → 最远端锤头）
		draw_line(hand_local, far_local, Color(1, 0.5, 0.2, 0.85), 2.0)
		# 手部锚点（红色 X 标记）
		var x_size := 12.0
		draw_line(hand_local + Vector2(-x_size, -x_size), hand_local + Vector2(x_size, x_size), Color(1, 0.2, 0.2, 1), 3.0)
		draw_line(hand_local + Vector2(-x_size, x_size), hand_local + Vector2(x_size, -x_size), Color(1, 0.2, 0.2, 1), 3.0)
		# 最远端锤头（橙色圆点）
		draw_circle(far_local, 8.0, Color(1, 0.6, 0.2, 0.9))
		# 锤头碰撞盒尺寸预览（位于最远端，按 head_size × scale 渲染）
		var head_w: float = CharTuning.mh_hammer_head_size * hs
		var head_h: float = head_w * 0.9
		var head_rect := Rect2(
			far_local.x - head_w * 0.5,
			far_local.y - head_h * 0.5,
			head_w,
			head_h
		)
		draw_rect(head_rect, Color(1, 0.3, 0.3, 0.25), true)
		draw_rect(head_rect, Color(1, 0.4, 0.4, 0.8), false, 1.5)
		# 整体 sprite 视觉范围（1733×200 × scale）
		var visual_h: float = 200.0 * hs
		var visual_rect := Rect2(
			hand_local.x if dir_x > 0 else hand_local.x - reach,
			hand_local.y - visual_h * 0.5,
			reach,
			visual_h
		)
		draw_rect(visual_rect, Color(0.6, 0.4, 1.0, 0.10), true)
		draw_rect(visual_rect, Color(0.6, 0.4, 1.0, 0.5), false, 1.0)

var is_being_sucked: bool = false
var is_frozen: bool = false
var is_being_shrunk: bool = false
var _was_being_shrunk: bool = false
var _was_frozen: bool = false
# 被钟馗"真正吸引"的累计时间（秒）；中断（脱离吸气区/玩家松开）也保留进度
# 累计 ≥ SUCTION_CAPTURE_TIME 时算捕获成功，进入 in-flight 飞向葫芦阶段
var suction_hold_timer: float = 0.0
const SUCTION_CAPTURE_TIME := 1.0  # 默认/兜底值
# 按敌人类型区分的捕获时长：流星锤怪 2s、红魔 3s，其余维持 1s
const SUCTION_CAPTURE_TIME_BY_TYPE := {
	Type.METEOR_HAMMER: 2.0,
	Type.RED_DEVIL:     3.0,
	Type.RED_GHOST:     1.0,
	Type.PALACE_ZOMBIE: 1.0,
	Type.FAT_DEMON_KING: 3.0,
}

func get_suction_capture_time() -> float:
	return SUCTION_CAPTURE_TIME_BY_TYPE.get(enemy_type, SUCTION_CAPTURE_TIME)
# 捕获成功后的"飞向葫芦"阶段：敌人朝 vanish_world 飞 + 缩小，与玩家是否仍按吸键无关
# 完成后 is_captured = true + hide()，玩家可以发射
var is_in_flight: bool = false
var flight_t: float = 0.0
var flight_start_pos: Vector2 = Vector2.ZERO
var flight_vanish_world: Vector2 = Vector2.ZERO
const FLIGHT_DURATION := 0.4
# 进入"被吸缩小"流程前的 sprite.position 备份（用于 vanish 偏移 lerp 和 reset 复位）
var _orig_sprite_position: Vector2 = Vector2.ZERO
# 被吸阶段的"起点位置"（用于 global_position 朝 vanish_world 线性插值）
# 进入被吸状态时记录一次，中断或 capture 时清空
var _suction_start_pos: Vector2 = Vector2.ZERO
var _has_suction_start: bool = false
# 由 player 每帧传入的"消失点世界坐标"，用于运动学插值
var _suction_vanish_world: Vector2 = Vector2.ZERO
var _has_suction_vanish: bool = false
var _has_suction_visual_origin: bool = false
var _pending_ball_reward_armed: bool = false
var _pending_ball_reward_type: int = -1
var _pending_ball_reward_pos: Vector2 = Vector2.ZERO
var _pending_ball_reward_parent: Node = null
var _pending_ball_reward_surface_y: float = NAN

const SUCTION_FLIGHT_STRETCH_MAX := 0.70
const SUCTION_FLIGHT_SQUASH_MAX := 0.30

func _physics_process(delta: float) -> void:
	if dying or is_captured:
		return
	# 召唤豁免期倒数：让 spawn 后头几帧不被 ball.die() 抹掉
	if summon_invuln_t > 0.0:
		summon_invuln_t = max(0.0, summon_invuln_t - delta)
	# 召唤无伤期倒数：spawn 后头 1 秒内不对钟馗造成接触伤害
	if contact_damage_delay_t > 0.0:
		contact_damage_delay_t = max(0.0, contact_damage_delay_t - delta)
	# 上一帧被吸缩小过，本帧却没继续被吸 → 恢复正常尺寸
	if _was_being_shrunk and not is_being_shrunk:
		reset_suction_shrink()
	# 上一帧冻结但本帧没冻结、也没进入正式吸引 → 恢复 idle 纹理
	if _was_frozen and not is_frozen and not is_being_shrunk:
		_restore_idle_texture()
	_was_being_shrunk = is_being_shrunk
	_was_frozen = is_frozen
	# capture 状态下用自定义累加器推进序列帧（仅对配置了 CAPTURE_FRAME_INTERVAL 的敌人生效）
	# 必须在 is_being_shrunk = false 之前，否则状态判断会失准
	_tick_capture_custom_anim(delta)
	is_being_shrunk = false
	# 维护"累计被吸"计时：吸气全程通过 is_frozen 标记，敌人**完全冻结在原地**。
	# 累计计满 → player 调 begin_capture_flight()，敌人进入 in-flight 阶段自我推进。
	# 设计：is_being_sucked 已废弃（保留字段以兼容 ball.gd 等可能的引用，但不再用作位置驱动）。
	if is_frozen:
		suction_hold_timer += delta
	else:
		_has_suction_start = false
		_has_suction_vanish = false
	if global_position.y > 1100.0:
		die()
		return
	# in-flight 阶段：自我推进飞向葫芦，期间不响应任何外部物理 / 吸气状态
	# 完成 → become_captured()（hide + 标记 is_captured）
	# **关键**：玩家是否仍按吸键、是否还在范围内，均不影响此阶段。敌人必然飞完入葫芦。
	if is_in_flight:
		flight_t = min(FLIGHT_DURATION, flight_t + delta)
		var progress: float = flight_t / FLIGHT_DURATION
		global_position = flight_start_pos.lerp(flight_vanish_world, progress)
		_apply_suction_flight_stretch(progress)
		velocity = Vector2.ZERO
		if flight_t >= FLIGHT_DURATION:
			is_in_flight = false
			become_captured()
		return
	if is_frozen:
		# 被吸期间（蓄力 + 完成期通用）：**完全冻结**，velocity 清零，不响应重力 / walking。
		# 敌人物理位置完全不变——避免之前 kinematic lerp 路径会穿过 one-way 平台的 bug。
		velocity = Vector2.ZERO
		# 不调用 move_and_slide，确保敌人**精确**停留在原地（move_and_slide 在某些边界条件下
		# 仍会因 collision 解算微调位置，那不是我们想要的）。
		is_frozen = false
		is_being_sucked = false
		return
	match enemy_type:
		Type.METEOR_HAMMER:
			_process_walking_enemy(delta)
		Type.RED_GHOST:
			_process_walking_enemy(delta)
		Type.RED_DEVIL:
			_process_walking_enemy(delta)
		Type.PALACE_ZOMBIE:
			_process_walking_enemy(delta)
		Type.FAT_DEMON_KING:
			_process_fat_demon_king(delta)
			
	is_being_sucked = false

func _process_stationary_enemy() -> void:
	velocity = Vector2.ZERO
	if not is_being_shrunk:
		sprite.flip_h = false

func _process_fat_demon_king(delta: float) -> void:
	_process_stationary_enemy()
	# 常驻机关：首次进入时生成一个平台（右侧停着静止铁球），平行状态（Rotation = 0）。
	_ensure_fdk_mechanism()
	# 冷却持续递减，不因攻击动画或铁球仍在滚动而暂停——
	# 攻击过程（动画 / 铁球滚动）不计入“每 5 秒一次”的累积，固定每 5 秒发动一次新攻击。
	_fdk_attack_cooldown -= delta
	if _fdk_attack_cooldown <= 0.0:
		# Attack3 首发，之后 Attack1 → Attack2 → Attack3 轮流施展。攻击开始时立即重置冷却，
		# 使下一次攻击在“本次开始后 5 秒”触发（攻击动画时长不计入间隔）。
		_fdk_attack_cooldown = FDK_ATTACK_INTERVAL
		match _fdk_next_attack:
			1:
				if not _fdk_attack2_frames.is_empty():
					_enter_fdk_attack2_state()
				else:
					_enter_fdk_attack_state()
			2:
				if not _fdk_attack3_frames.is_empty():
					_enter_fdk_attack3_state()
				else:
					_enter_fdk_attack_state()
			_:
				_enter_fdk_attack_state()
	if anim_state == AnimState.FDK_ATTACK:
		_tick_fdk_attack(delta)
	elif anim_state == AnimState.FDK_ATTACK2:
		_tick_fdk_attack2(delta)
	elif anim_state == AnimState.FDK_ATTACK3:
		_tick_fdk_attack3(delta)

func _process_walking_enemy(delta: float) -> void:
	velocity.y += GRAVITY * delta
	# ── HOP：跨平台跳跃 ──
	# 已在跳跃中：由 _tick_platform_hop 接管移动，不进入巡逻状态机/技能分支。
	if is_hopping:
		_tick_platform_hop(delta)
		return
	# 不在跳跃中：每隔一段时间随机检查一次"是否该换平台"。
	# 仅在 WALK / IDLE 状态触发（避免打断 ATTACK / DASH / MH_ATTACK 这些技能动画）。
	# 类型限制：仅红衣女鬼 / 宫廷僵尸 参与跨平台跳跃。
	if PLATFORM_HOP_ENABLED \
			and (enemy_type == Type.RED_GHOST or enemy_type == Type.PALACE_ZOMBIE) \
			and (anim_state == AnimState.WALK or anim_state == AnimState.IDLE) \
			and is_on_floor():
		_hop_check_timer += delta
		if _hop_check_timer >= _hop_check_interval:
			_hop_check_timer = 0.0
			_hop_check_interval = randf_range(
				PLATFORM_HOP_CHECK_INTERVAL_MIN, PLATFORM_HOP_CHECK_INTERVAL_MAX)
			_try_platform_hop()
			if is_hopping:
				_tick_platform_hop(delta)
				return
	if not is_being_sucked:
		# walk/idle/attack 行为状态机：随机切换 → 控制是否移动
		_tick_walk_idle_state_machine(delta)
		if anim_state == AnimState.ATTACK:
			# 攻击中：原地不动，由 _tick_attack_anim 推进动画并在指定帧生成火种
			velocity.x = 0.0
			_tick_attack_anim(delta)
		elif anim_state == AnimState.DASH:
			# 突进中：原地不动（瞬移由 _tick_dash 在阶段切换时执行）
			velocity.x = 0.0
			_tick_dash(delta)
		elif anim_state == AnimState.MH_ATTACK:
			# 流星锤攻击：原地不动，由 _tick_mh_attack 推进角色帧 + 锤子飞行
			velocity.x = 0.0
			_tick_mh_attack(delta)
		elif anim_state == AnimState.IDLE:
			velocity.x = 0.0
		elif WALK_INTERMITTENT.has(enemy_type):
			# 宫廷僵尸"跳一下停一下"的子节奏（在 WALK 状态内）
			var jumping_idle: bool = _tick_walk_intermittent_anim(delta)
			velocity.x = 0.0 if jumping_idle else MH_SPEED * direction
		else:
			# 常规连续移动
			velocity.x = MH_SPEED * direction
	else:
		# When being sucked, we apply some friction to the Y axis to simulate air resistance
		pass

	var wall_direction := direction
	var turned_early := false
	if is_on_floor() and abs(velocity.x) > 0.0 and _has_wall_ahead():
		direction = -direction
		if velocity.x != 0.0:
			velocity.x = abs(velocity.x) * direction
		turned_early = true

	move_and_slide()
	if is_on_wall():
		# 先轻微推出碰撞面，再反向；否则在窄平台边缘会来回抖动卡住。
		global_position.x -= wall_direction * WALL_REBOUND_NUDGE
		if not turned_early:
			direction = -direction
	var clamped_to_platform := false
	if is_on_floor():
		clamped_to_platform = _clamp_to_walkable_platform()
		if not clamped_to_platform and not _has_ground_ahead():
			direction = -direction
	# 被吸状态下 flip_h 与纹理由 _apply_capture_texture 接管，不在此覆盖
	if not is_being_shrunk:
		sprite.flip_h = (direction < 0) if default_facing_right else (direction > 0)

# walk ↔ idle ↔ attack 随机状态机
# - WALK 状态：累积 state_timer，到 state_duration 时切到 IDLE（或 ATTACK，按概率）
# - IDLE 状态：累积 state_timer，到 state_duration 时切回 WALK，并按概率折返
# - ATTACK 状态：由 _tick_attack_anim 推进动画 + 火种生成；动画完成后切回 WALK
func _tick_walk_idle_state_machine(delta: float) -> void:
	state_timer += delta
	if state_timer < state_duration:
		return
	# 切换状态
	state_timer = 0.0
	if anim_state == AnimState.WALK:
		# WALK → IDLE / ATTACK / DASH / MH_ATTACK（按敌人配置的概率分支）
		# PalaceZombie 有 attack 帧 → ATTACK_PROB 概率进入 ATTACK
		# RedGhost 有 dash 帧 → DASH_PROB 概率进入 DASH
		# MeteorHammer 有 mh_attack 帧 → MH_ATTACK_PROB 概率进入 MH_ATTACK
		if not _attack_frames.is_empty() and randf() < ATTACK_PROB:
			_enter_attack_state()
		elif not _dash_frames.is_empty() and randf() < DASH_PROB:
			_enter_dash_state()
		elif not _mh_attack_frames.is_empty() and randf() < MH_ATTACK_PROB:
			_enter_mh_attack_state()
		else:
			anim_state = AnimState.IDLE
			state_duration = randf_range(IDLE_DURATION_MIN, IDLE_DURATION_MAX)
			# idle 进入瞬间立刻显示 idle 帧首帧（不等 _on_anim_tick）
			anim_frame = 0
			if not _idle_frames.is_empty():
				_apply_normal_texture(_idle_frames[0], "idle")
	elif anim_state == AnimState.IDLE:
		# IDLE → WALK
		anim_state = AnimState.WALK
		state_duration = randf_range(WALK_DURATION_MIN, WALK_DURATION_MAX)
		# 随机折返
		if randf() < REVERSE_ON_RESUME_PROB:
			direction = -direction
		anim_frame = 0
		if not _frames.is_empty():
			_apply_normal_texture(_frames[0], "move")
	# ATTACK / DASH 状态由各自的 tick 函数自行处理 → WALK 的过渡，不在此分支处理

# 进入 ATTACK 状态：初始化攻击动画累加器，显示 attack 首帧
# 之后由 _tick_attack_anim 推进序列帧、生成火种、完成后回 WALK
func _enter_attack_state() -> void:
	anim_state = AnimState.ATTACK
	_attack_anim_accum = 0.0
	_attack_frame_idx = 0
	_attack_spawned = false
	if not _attack_frames.is_empty():
		_apply_normal_texture(_attack_frames[0], "attack")
	# state_duration 在此不再有意义（ATTACK 自己管动画完成）；设个上限避免卡死
	state_duration = ATTACK_FRAME_INTERVAL * _attack_frames.size() + 0.5
	state_timer = 0.0

# 推进 ATTACK 序列帧 + 在 ATTACK_SPAWN_FRAME 触发火种生成 + 完成后回 WALK
# 返回 true 表示 ATTACK 状态仍在进行（外部应保持 velocity.x = 0）
func _tick_attack_anim(delta: float) -> bool:
	if _attack_frames.is_empty():
		# 异常保护：没有 attack 帧却进了 ATTACK 状态 → 立即回 WALK
		_exit_attack_to_walk()
		return false
	_attack_anim_accum += delta
	while _attack_anim_accum >= ATTACK_FRAME_INTERVAL:
		_attack_anim_accum -= ATTACK_FRAME_INTERVAL
		_attack_frame_idx += 1
		if _attack_frame_idx >= _attack_frames.size():
			# 动画播完 → 切回 WALK
			_exit_attack_to_walk()
			return false
		_apply_normal_texture(_attack_frames[_attack_frame_idx], "attack")
		# 在指定帧触发火种生成（只触发一次，防止跳帧重复）
		# 仅 PalaceZombie 的 ATTACK 会射火种；红魔王 ATTACK 是近战挥击狼牙棒，无投射物
		if not _attack_spawned and _attack_frame_idx >= ATTACK_SPAWN_FRAME:
			_attack_spawned = true
			if enemy_type == Type.PALACE_ZOMBIE:
				_spawn_fire_seeds()
	return true

func _exit_attack_to_walk() -> void:
	anim_state = AnimState.WALK
	state_duration = randf_range(WALK_DURATION_MIN, WALK_DURATION_MAX)
	state_timer = 0.0
	anim_frame = 0
	if not _frames.is_empty():
		_apply_normal_texture(_frames[0], "move")

# ───────── 红衣女鬼 DASH 技能（消失 → 突进 3 身位 → flutter 显现 → 回 WALK） ─────────

# 进入 DASH 状态：第一阶段 VANISH（hide + 原地停留 DASH_VANISH_DURATION 秒），
# 时间到由 _tick_dash 完成"瞬移 3 身位 + 切到 FLUTTER 阶段"
func _enter_dash_state() -> void:
	anim_state = AnimState.DASH
	_dash_phase = DashPhase.VANISH
	_dash_phase_timer = 0.0
	_dash_frame_idx = 0
	_dash_anim_accum = 0.0
	# 立刻"消失"：sprite hide。collision 仍保留，避免突进期间被玩家穿过
	# （注意 hide 是 sprite 层面，不影响 CharacterBody2D 自身碰撞）
	sprite.hide()
	# state_duration 给个上限，避免极端情况下卡死（VANISH + FLUTTER 总时长）
	state_duration = DASH_VANISH_DURATION + DASH_FLUTTER_FRAME_INTERVAL * _dash_frames.size() + 0.5
	state_timer = 0.0
	velocity = Vector2.ZERO

# 推进 DASH 状态：阶段切换 + 突进瞬移 + flutter 序列帧推进
# 返回 true 表示 DASH 仍在进行（外部应保持 velocity.x = 0）
func _tick_dash(delta: float) -> bool:
	_dash_phase_timer += delta
	if _dash_phase == DashPhase.VANISH:
		# 隐身停留期满 → 瞬移 3 身位到面向方向，切到 FLUTTER 阶段
		if _dash_phase_timer >= DASH_VANISH_DURATION:
			_perform_dash_teleport()
			_dash_phase = DashPhase.FLUTTER
			_dash_phase_timer = 0.0
			_dash_frame_idx = 0
			_dash_anim_accum = 0.0
			# 显现 + 显示 flutter 首帧
			sprite.show()
			if not _dash_frames.is_empty():
				sprite.texture = _dash_frames[0]
				# 朝向同步（突进后仍按 direction 决定 flip_h）
				sprite.flip_h = (direction < 0) if default_facing_right else (direction > 0)
		return true
	# FLUTTER 阶段：按 DASH_FLUTTER_FRAME_INTERVAL 推进 5 帧序列；播完 → 回 WALK
	if _dash_frames.is_empty():
		_exit_dash_to_walk()
		return false
	_dash_anim_accum += delta
	while _dash_anim_accum >= DASH_FLUTTER_FRAME_INTERVAL:
		_dash_anim_accum -= DASH_FLUTTER_FRAME_INTERVAL
		_dash_frame_idx += 1
		if _dash_frame_idx >= _dash_frames.size():
			_exit_dash_to_walk()
			return false
		sprite.texture = _dash_frames[_dash_frame_idx]
	return true

# 执行突进瞬移：朝 direction 方向移动 3 个身位，clamp 在屏幕内
# 用射线检查目的地脚下是否有平台；若无平台 → 缩短距离落在最近的可站立位置（防止突进到悬空）
func _perform_dash_teleport() -> void:
	var body_w: float = _get_body_width()
	var full_dist: float = body_w * DASH_BODY_LENGTHS * direction
	# 尝试目标点；如果落空（脚下没平台），逐步缩短到最远的可站立位置
	var attempts: int = 6  # 6 步分段尝试 → 最少 3/6=0.5 身位
	var target_x: float = global_position.x
	for i in range(attempts, 0, -1):
		var try_dist: float = full_dist * float(i) / float(attempts)
		var try_x: float = global_position.x + try_dist
		# clamp 在屏幕内（与 player WORLD_LEFT/RIGHT 同步：0~1920）
		try_x = clamp(try_x, 40.0, 1880.0)
		if _is_ground_under(try_x, global_position.y):
			target_x = try_x
			break
	global_position.x = _clamp_x_to_walkable_platform(target_x, global_position.y)

# 测试给定世界坐标下方是否有 tile 平台（避免突进到空中）
func _is_ground_under(world_x: float, world_y: float) -> bool:
	var space := get_world_2d().direct_space_state
	var from := Vector2(world_x, world_y)
	var to := Vector2(world_x, world_y + 120.0)
	var ray := PhysicsRayQueryParameters2D.create(from, to)
	ray.collision_mask = 1  # tile 平台层
	return not space.intersect_ray(ray).is_empty()

func _get_body_width() -> float:
	match enemy_type:
		Type.METEOR_HAMMER: return CharTuning.mh_col_width
		Type.RED_GHOST:     return CharTuning.rg_col_width
		Type.RED_DEVIL:     return CharTuning.rd_col_width
		Type.PALACE_ZOMBIE: return CharTuning.pz_col_width
		Type.FAT_DEMON_KING: return CharTuning.fdk_col_width * CharTuning.fdk_col_scale
		_:                  return 60.0

func _exit_dash_to_walk() -> void:
	# 万一异常中途没显示，确保 sprite 可见
	sprite.show()
	anim_state = AnimState.WALK
	state_duration = randf_range(WALK_DURATION_MIN, WALK_DURATION_MAX)
	state_timer = 0.0
	anim_frame = 0
	if not _frames.is_empty():
		_apply_normal_texture(_frames[0], "move")

# ───────── 流星锤怪 MH_ATTACK 技能（预备 → 扔锤 → 收锤 → 回 WALK） ─────────

# 进入 MH_ATTACK 状态：初始化为 WINDUP 阶段，从第 0 帧开始播角色动作
func _enter_mh_attack_state() -> void:
	anim_state = AnimState.MH_ATTACK
	_mh_phase = MhAttackPhase.WINDUP
	_mh_char_frame_idx = 0
	_mh_char_anim_accum = 0.0
	_mh_hammer_frame_idx = 0
	_mh_hammer_anim_accum = 0.0
	if not _mh_attack_frames.is_empty():
		_apply_normal_texture(_mh_attack_frames[0], "mh_attack")
	velocity = Vector2.ZERO
	# state_duration 给个大上限（防止异常情况卡死）；正常由 _tick_mh_attack 自行退出
	state_duration = 10.0
	state_timer = 0.0

# 推进 MH_ATTACK 状态（角色帧 + 锤子飞行 + 阶段切换）
func _tick_mh_attack(delta: float) -> void:
	if _mh_attack_frames.is_empty():
		_exit_mh_attack_to_walk()
		return
	# 推进角色动作帧
	_mh_char_anim_accum += delta
	while _mh_char_anim_accum >= MH_ATTACK_FRAME_INTERVAL:
		_mh_char_anim_accum -= MH_ATTACK_FRAME_INTERVAL
		_advance_mh_char_frame()
	# 推进锤子飞行 + 锤子帧动画（仅 THROW_OUT / RETRIEVE 阶段）
	if _mh_phase == MhAttackPhase.THROW_OUT or _mh_phase == MhAttackPhase.RETRIEVE:
		_tick_mh_hammer_flight(delta)

# 角色帧推进 + 阶段切换
func _advance_mh_char_frame() -> void:
	if _mh_phase == MhAttackPhase.WINDUP:
		# WINDUP：0~27 一次性播放；播到 trigger 帧时切到 THROW_OUT + 生成锤
		_mh_char_frame_idx += 1
		if _mh_char_frame_idx >= _mh_attack_frames.size():
			# 播完 28 帧仍没触发？保护：异常情况直接进入 RETRIEVE 或退出
			_mh_char_frame_idx = MH_LOOP_FRAME_START
			# 触发也保险：到 28 帧时若锤还没生成（理论不会发生），强制生成
			if _mh_hammer_node == null:
				_enter_mh_throw_out()
		else:
			_apply_normal_texture(_mh_attack_frames[_mh_char_frame_idx], "mh_attack")
			# 播到第 21 帧（index 20）→ 切到 THROW_OUT 子阶段 + 生成锤
			if _mh_char_frame_idx == MH_THROW_TRIGGER_FRAME and _mh_hammer_node == null:
				_enter_mh_throw_out()
	else:
		# THROW_OUT / RETRIEVE：角色循环 20~27（_21~_28）
		_mh_char_frame_idx += 1
		if _mh_char_frame_idx > MH_LOOP_FRAME_END:
			_mh_char_frame_idx = MH_LOOP_FRAME_START
		_apply_normal_texture(_mh_attack_frames[_mh_char_frame_idx], "mh_attack")

# 切到 THROW_OUT 阶段：生成锤子节点，初始位置在怪手部
func _enter_mh_throw_out() -> void:
	_mh_phase = MhAttackPhase.THROW_OUT
	_mh_hammer_frame_idx = 0
	_mh_hammer_anim_accum = 0.0
	_spawn_mh_hammer()

# 锤子动画推进 + 锤头碰撞盒同步
# 锤 PNG 1733×200 把整条链 + 锤头都画进了贴图：左端=锚点（怪手部），右端=锤头。
# 因此锤 Sprite 不会"飞行"——固定锚定在怪手部，由序列帧的差异表现"伸出"和"收回"。
# THROW_OUT: 序列帧正向 1→5（链从短到长）；播到最后一帧切到 RETRIEVE
# RETRIEVE: 序列帧反向 5→1（链从长到短）；播到第一帧 → 退出 MH_ATTACK
func _tick_mh_hammer_flight(delta: float) -> void:
	if _mh_hammer_node == null or not is_instance_valid(_mh_hammer_node):
		# 锤丢失（异常）→ 直接退出
		_exit_mh_attack_to_walk()
		return
	# 每帧根据当前调参重算手部位置 + 同步锤 sprite scale + 朝向（F1 实时调参生效）
	var hand_world: Vector2 = global_position + Vector2(
		CharTuning.mh_hammer_offset_x * direction,
		CharTuning.mh_hammer_offset_y
	)
	# Signed scale：朝左时 scale.x = -|S| 让贴图水平镜像（同时子 Area2D 也跟着镜像，无需手动算 direction）
	var hs: float = CharTuning.mh_hammer_scale
	_mh_hammer_node.scale = Vector2(hs * direction, hs)
	# 锤 sprite 保持锚定在怪手部世界坐标
	_mh_hammer_node.global_position = hand_world
	# 推进序列帧
	_mh_hammer_anim_accum += delta
	if _mh_phase == MhAttackPhase.THROW_OUT:
		# 正向推进 0→4（伸出），到达最后一帧 → 切 RETRIEVE
		while _mh_hammer_anim_accum >= MH_HAMMER_FRAME_INTERVAL:
			_mh_hammer_anim_accum -= MH_HAMMER_FRAME_INTERVAL
			if _mh_hammer_frame_idx < _mh_hammer_frames.size() - 1:
				_mh_hammer_frame_idx += 1
				_mh_hammer_node.texture = _mh_hammer_frames[_mh_hammer_frame_idx]
			else:
				# 已到最后一帧（最大伸出）→ 切到 RETRIEVE
				_mh_phase = MhAttackPhase.RETRIEVE
				_mh_hammer_anim_accum = 0.0
				break
	else:  # RETRIEVE
		# 反向推进 4→0（收回），到达第一帧 → 退出 MH_ATTACK
		while _mh_hammer_anim_accum >= MH_HAMMER_FRAME_INTERVAL:
			_mh_hammer_anim_accum -= MH_HAMMER_FRAME_INTERVAL
			if _mh_hammer_frame_idx > 0:
				_mh_hammer_frame_idx -= 1
				_mh_hammer_node.texture = _mh_hammer_frames[_mh_hammer_frame_idx]
			else:
				# 已收回到起始帧 → 销毁锤 + 回 WALK
				_exit_mh_attack_to_walk()
				return
	# 同步锤头伤害盒位置（跟随当前帧"锤头大致位置"）
	_update_mh_hammer_head_area()

# 锤头伤害盒：跟随锤当前帧的锤头视觉位置移动
# 锤头 X 估计：第 i 帧（i=0~4）锤头位于贴图 X = t × texture_width，t 从 0.1（贴手部）到 0.95（最远）
# 锤 sprite 用 signed scale（scale.x 在朝左时为 -|S|）→ 子节点 Area2D 自动跟随镜像
# 因此 Area2D 的 local x 永远用正向 t * tex_w，由父 sprite 的 signed scale 自动镜像到正确世界位置
func _update_mh_hammer_head_area() -> void:
	if _mh_hammer_area == null or not is_instance_valid(_mh_hammer_area):
		return
	if _mh_hammer_frames.is_empty():
		return
	var tex_w: float = _mh_hammer_frames[0].get_width()  # 1733
	var n: int = _mh_hammer_frames.size()
	# 锤头位置 fraction：帧 0 在 ~10%；帧 N-1 在 ~95%。线性插值。
	var t: float = 0.1 + 0.85 * (float(_mh_hammer_frame_idx) / float(n - 1))
	_mh_hammer_area.position = Vector2(t * tex_w, 0.0)

# 在怪手部位置生成锤子精灵 + 伤害检测 Area2D
# 锤子是怪的子节点的同级节点（挂在 parent 上）→ 锚定在怪手部世界坐标
# Sprite 用 offset.x = +W/2 让贴图的左端（锚点 = 锁链尾）对齐到 sprite.position
func _spawn_mh_hammer() -> void:
	if is_captured or dying or is_in_flight:
		return
	if _mh_hammer_frames.is_empty():
		return
	var parent_node := get_parent()
	if parent_node == null:
		return
	# 创建锤子精灵（scale / offset 由 CharTuning 控制，F1 调参面板可调）
	_mh_hammer_node = Sprite2D.new()
	_mh_hammer_node.texture = _mh_hammer_frames[0]
	# Sprite offset：把贴图的左端对齐到 sprite.position（手部锚点）
	# offset 单位 = 贴图像素；offset.x = +W/2 → 贴图左列在 position；offset.y = 0 保持垂直居中
	var tex_w: float = _mh_hammer_frames[0].get_width()
	_mh_hammer_node.offset = Vector2(tex_w * 0.5, 0.0)
	# Signed scale：朝左时 scale.x = -|S| 把整个 sprite + 子节点都水平镜像
	# 比 flip_h 干净——flip_h 只影响渲染不影响子节点 transform，会导致 Area2D 错位
	var hs: float = CharTuning.mh_hammer_scale
	_mh_hammer_node.scale = Vector2(hs * direction, hs)
	_mh_hammer_node.z_index = 5  # 在怪 sprite 上层，避免被遮挡
	# 锤 sprite 世界坐标 = 怪手部（每帧由 _tick_mh_hammer_flight 同步刷新）
	_mh_hammer_node.global_position = global_position + Vector2(
		CharTuning.mh_hammer_offset_x * direction,
		CharTuning.mh_hammer_offset_y
	)
	parent_node.add_child(_mh_hammer_node)
	# 伤害检测 Area2D：作为 sprite 的子节点，每帧定位到锤头视觉位置
	if MH_HAMMER_DAMAGE:
		_mh_hammer_area = Area2D.new()
		_mh_hammer_area.collision_layer = 0
		_mh_hammer_area.collision_mask = 2  # 玩家身体层
		var col := CollisionShape2D.new()
		var shape := RectangleShape2D.new()
		# 锤头碰撞盒大小（贴图像素，sprite scale 会自动作用）
		var head_px: float = CharTuning.mh_hammer_head_size
		shape.size = Vector2(head_px, head_px * 0.9)
		col.shape = shape
		_mh_hammer_area.add_child(col)
		_mh_hammer_node.add_child(_mh_hammer_area)
		_mh_hammer_area.body_entered.connect(_on_mh_hammer_hit_player)
		# 立即定位到第 0 帧的锤头位置
		_update_mh_hammer_head_area()

# 锤碰到玩家 → 扣血（仅在玩家非无敌且非吸气中时生效，与 fire_seed 同语义）
func _on_mh_hammer_hit_player(body: Node) -> void:
	if body is Boss and not body.dying:
		body.take_damage(1)
		return
	if not (body is Player):
		return
	if body.invincible or body.is_vacuuming:
		return
	# 召唤出现后头 1 秒内不造成接触伤害
	if contact_damage_delay_t > 0.0:
		return
	body.invincible = true
	body.invincible_timer = body.HURT_INVINCIBLE_TIME
	body.take_damage()
	# 锤击中后继续飞行（不消失）—— 与单发火种不同，锤是周期攻击的"主武器"

# 收尾：销毁锤节点，回到 WALK 状态
func _exit_mh_attack_to_walk() -> void:
	if _mh_hammer_node != null and is_instance_valid(_mh_hammer_node):
		_mh_hammer_node.call_deferred("queue_free")
	_mh_hammer_node = null
	_mh_hammer_area = null
	anim_state = AnimState.WALK
	state_duration = randf_range(WALK_DURATION_MIN, WALK_DURATION_MAX)
	state_timer = 0.0
	anim_frame = 0
	if not _frames.is_empty():
		_apply_normal_texture(_frames[0], "move")

# ───────── 胖魔王机关攻击（Mechanism 平台 + 铁球） ─────────

func _enter_fdk_attack_state() -> void:
	anim_state = AnimState.FDK_ATTACK
	_fdk_attack_accum = 0.0
	_fdk_attack_frame_idx = 0
	velocity = Vector2.ZERO
	# 下一次出招改用 Attack2（Attack1 → Attack2 → Attack3 轮流）。
	_fdk_next_attack = 1
	if not _fdk_attack_frames.is_empty():
		_apply_normal_texture(_fdk_attack_frames[0], "fdk_attack")
	# Attack1：攻击动画开始 1 秒后，机关才从平行(0°)旋转到 F1 设置的角度，
	# 随后铁球顺着倾斜角度滚落。
	GameState.wait(self, FDK_ATTACK_TILT_DELAY).connect(_trigger_fdk_mechanism_tilt)

# Attack2：与 Attack1 交替施展。当前仅播放 22 帧攻击动画，暂无机关/铁球等实际攻击效果，
# 后续可在此处补充 Attack2 施展后引发的实际攻击逻辑。
func _enter_fdk_attack2_state() -> void:
	anim_state = AnimState.FDK_ATTACK2
	_fdk_attack_accum = 0.0
	_fdk_attack_frame_idx = 0
	velocity = Vector2.ZERO
	# 下一次出招改用 Attack3（Attack1 → Attack2 → Attack3 轮流）。
	_fdk_next_attack = 2
	if not _fdk_attack2_frames.is_empty():
		_apply_normal_texture(_fdk_attack2_frames[0], "fdk_attack2")

func _tick_fdk_attack2(delta: float) -> void:
	if _fdk_attack2_frames.is_empty():
		_exit_fdk_attack_to_idle()
		return
	_fdk_attack_accum += delta
	while _fdk_attack_accum >= FDK_ATTACK_FRAME_INTERVAL:
		_fdk_attack_accum -= FDK_ATTACK_FRAME_INTERVAL
		_fdk_attack_frame_idx += 1
		if _fdk_attack_frame_idx >= _fdk_attack2_frames.size():
			# Attack2 动画播完（收招）：延迟 1 秒后从屏幕上方落下炮弹砸向钟馗。
			_schedule_fdk_artillery_shell()
			_exit_fdk_attack_to_idle()
			return
		_apply_normal_texture(_fdk_attack2_frames[_fdk_attack_frame_idx], "fdk_attack2")

# Attack2 收招后：延迟 FDK_ATTACK2_SHELL_DELAY 秒，再生成下落炮弹。
func _schedule_fdk_artillery_shell() -> void:
	if is_captured or dying or is_in_flight:
		return
	GameState.wait(self, FDK_ATTACK2_SHELL_DELAY).connect(_spawn_fdk_artillery_shell)

# 在钟馗当前水平位置的正上方（屏幕外）生成炮弹，直线落下砸向钟馗，命中扣 1 血。
func _spawn_fdk_artillery_shell() -> void:
	if not is_inside_tree():
		return
	var parent_node := get_parent()
	if parent_node == null:
		return
	var scene := _cached_load(FDK_ARTILLERY_SHELL_SCENE) as PackedScene
	if scene == null:
		return
	# 锁定钟馗当前 X：炮弹从其正上方落下。找不到玩家则以屏幕中心兜底。
	var target_x: float = get_viewport().get_visible_rect().size.x * 0.5
	var player := get_tree().get_first_node_in_group("player")
	if player != null and is_instance_valid(player) and player is Node2D:
		target_x = (player as Node2D).global_position.x
	var shell = scene.instantiate()
	parent_node.add_child(shell)
	if shell is Node2D:
		(shell as Node2D).global_position = Vector2(target_x, FDK_ARTILLERY_SHELL_SPAWN_Y)

# Attack3：胖魔王拍手——播放拍手动画，拍手到位时从画面上方降落 6 个随机种类的敌人，
# 随机分布到上层平台 / 中层平台 / 地面三层。降落敌人不计入通关数（走 spawn_summoned_enemy 旁路）。
func _enter_fdk_attack3_state() -> void:
	anim_state = AnimState.FDK_ATTACK3
	_fdk_attack_accum = 0.0
	_fdk_attack_frame_idx = 0
	_fdk_attack3_summoned = false
	velocity = Vector2.ZERO
	# 下一次出招改回 Attack1（Attack1 → Attack2 → Attack3 轮流）。
	_fdk_next_attack = 0
	if not _fdk_attack3_frames.is_empty():
		_apply_normal_texture(_fdk_attack3_frames[0], "fdk_attack3")

func _tick_fdk_attack3(delta: float) -> void:
	if _fdk_attack3_frames.is_empty():
		_exit_fdk_attack_to_idle()
		return
	_fdk_attack_accum += delta
	while _fdk_attack_accum >= FDK_ATTACK_FRAME_INTERVAL:
		_fdk_attack_accum -= FDK_ATTACK_FRAME_INTERVAL
		_fdk_attack_frame_idx += 1
		if _fdk_attack_frame_idx >= _fdk_attack3_frames.size():
			_exit_fdk_attack_to_idle()
			return
		# 拍手到位的那一帧触发敌人降落（仅触发一次）。
		if not _fdk_attack3_summoned and _fdk_attack_frame_idx >= FDK_ATTACK3_SUMMON_FRAME:
			_fdk_attack3_summoned = true
			_summon_fdk_falling_enemies()
		_apply_normal_texture(_fdk_attack3_frames[_fdk_attack_frame_idx], "fdk_attack3")

# 从画面上方降落 FDK_ATTACK3_SUMMON_COUNT 个随机敌人，均衡分布到 上层 / 中层 / 地面 三层。
#
# 之前的实现把所有敌人都从同一个固定 X 区间（260~1650）、固定 Y=-160 自由落下，
# 由重力决定落点。但 Stage3 上层平台横向覆盖了该 X 区间的全部范围（约 220~1890），
# 任何从上方落下的敌人都会先撞到上层平台，所以全部堆在上层，永远到不了中层/地面。
#
# 现在改为：从关卡实际几何 level.get_platforms() 取出所有平台（与敌人同一世界坐标系），
# 按表面高度 top_y 归类成 上层 / 中层 / 地面 三个落点组，
# 每个敌人轮换选一个落点组、组内随机选一块平台，并在该平台横向范围内随机取 X，
# 然后从“该平台表面正上方一小段”落下 —— 由于起点已在上层平台之下，重力直接把它带到目标层。
func _summon_fdk_falling_enemies() -> void:
	if is_captured or dying or is_in_flight:
		return
	var level := _find_level()
	if level == null or not level.has_method("spawn_summoned_enemy"):
		return
	if _fdk_summon_scenes.is_empty():
		for path in FDK_SUMMON_SCENE_PATHS:
			var s := _cached_load(path) as PackedScene
			if s != null:
				_fdk_summon_scenes.append(s)
	if _fdk_summon_scenes.is_empty():
		return
	# tiers[0]=上层 tiers[1]=中层 tiers[2]=地面，每个元素是该层若干平台记录 {top_y,left_x,right_x}。
	var tiers := _build_fdk_attack3_tiers(level)
	for i in range(FDK_ATTACK3_SUMMON_COUNT):
		var scene: PackedScene = _fdk_summon_scenes[randi() % _fdk_summon_scenes.size()]
		# 轮换 + 随机起点：保证三层都能分到敌人，又不至于每次都固定顺序。
		var tier_index := (i + _fdk_attack3_band_offset) % tiers.size()
		var tier: Array = tiers[tier_index]
		if tier.is_empty():
			continue
		var plat: Dictionary = tier[randi() % tier.size()]
		var lo: float = float(plat["left_x"]) + FDK_ATTACK3_LANDING_EDGE_MARGIN
		var hi: float = float(plat["right_x"]) - FDK_ATTACK3_LANDING_EDGE_MARGIN
		if hi < lo:
			# 平台太窄，退回用中心。
			lo = float(plat["center_x"]) if plat.has("center_x") else (float(plat["left_x"]) + float(plat["right_x"])) * 0.5
			hi = lo
		# 从目标平台表面上方一小段落下：起点已位于上层平台之下，避免被上层平台拦截。
		var spawn_y := float(plat["top_y"]) - FDK_ATTACK3_DROP_HEIGHT
		var spawn_x := _pick_fdk_attack3_spawn_x(lo, hi, spawn_y)
		var enemy_node: Node = level.spawn_summoned_enemy(scene, Vector2(spawn_x, spawn_y))
		if enemy_node is Enemy:
			var enemy := enemy_node as Enemy
			var center_x := float(plat.get("center_x", spawn_x))
			# 第二层平台左侧更容易和墙角/边缘挤住，所以这层优先往右走；
			# 其他层则按出生点位于平台中心线的哪一侧，先朝更宽松的一边移动。
			if tier_index == 1:
				enemy.direction = 1
			else:
				enemy.direction = 1 if spawn_x < center_x else -1
	_fdk_attack3_band_offset = (_fdk_attack3_band_offset + 1) % 3

func _pick_fdk_attack3_spawn_x(lo: float, hi: float, spawn_y: float) -> float:
	var player := get_tree().get_first_node_in_group("player")
	if player == null or not is_instance_valid(player) or not (player is Node2D):
		return randf_range(lo, hi)
	var player_pos: Vector2 = (player as Node2D).global_position
	if abs(spawn_y - player_pos.y) > FDK_ATTACK3_PLAYER_SAFE_Y:
		return randf_range(lo, hi)

	var best_x: float = randf_range(lo, hi)
	var best_dist: float = abs(best_x - player_pos.x)
	for _attempt in range(FDK_ATTACK3_SPAWN_PICK_ATTEMPTS):
		var candidate_x: float = randf_range(lo, hi)
		var dist: float = abs(candidate_x - player_pos.x)
		if dist >= FDK_ATTACK3_PLAYER_SAFE_X:
			return candidate_x
		if dist > best_dist:
			best_x = candidate_x
			best_dist = dist
	return best_x

# 把关卡所有平台/地面按表面高度 top_y 归类成 上层 / 中层 / 地面 三层。
# 数据来自 level.get_platforms()（真实关卡几何，与敌人同一世界坐标系）：
# 收集所有不同的 top_y 值并排序，最小的一档为上层、最大的一档为地面、其余归中层。
# 返回 [上层平台数组, 中层平台数组, 地面平台数组]，每块平台为含 top_y/left_x/right_x/center_x 的字典。
func _build_fdk_attack3_tiers(level: Node) -> Array:
	var plats: Array = []
	if level.has_method("get_platforms"):
		for p in level.get_platforms():
			if p is Dictionary and p.has("top_y") and p.has("left_x") and p.has("right_x"):
				if float(p["right_x"]) - float(p["left_x"]) >= 1.0:
					plats.append(p)
	if plats.is_empty():
		# 没拿到关卡几何时的兜底：用 Attack1 铁球轨道常量构造三层（同一世界坐标系）。
		return [
			[{"top_y": FDK_TRACK_UPPER_Y, "left_x": FDK_TRACK_UPPER_LANDING_MIN_X, "right_x": FDK_TRACK_UPPER_LANDING_MAX_X}],
			[{"top_y": FDK_TRACK_MIDDLE_Y, "left_x": FDK_TRACK_MIDDLE_LEFT_X, "right_x": FDK_TRACK_MIDDLE_RIGHT_X}],
			[{"top_y": FDK_TRACK_GROUND_Y, "left_x": FDK_ATTACK3_SPAWN_X_MIN, "right_x": FDK_ATTACK3_SPAWN_X_MAX}],
		]
	# 收集所有不同的表面高度并排序（由高到低：上层 top_y 最小，地面最大）。
	var ys: Array = []
	for p in plats:
		var y: float = float(p["top_y"])
		var found := false
		for ey in ys:
			if abs(ey - y) <= FDK_ATTACK3_TIER_Y_TOLERANCE:
				found = true
				break
		if not found:
			ys.append(y)
	ys.sort()
	var upper_y: float = ys[0]
	var ground_y: float = ys[ys.size() - 1]
	var upper: Array = []
	var middle: Array = []
	var ground: Array = []
	for p in plats:
		var y: float = float(p["top_y"])
		if abs(y - upper_y) <= FDK_ATTACK3_TIER_Y_TOLERANCE:
			upper.append(p)
		elif abs(y - ground_y) <= FDK_ATTACK3_TIER_Y_TOLERANCE:
			ground.append(p)
		else:
			middle.append(p)
	# 若中层为空（只识别出两档），把地面的一部分让给中层不合适；保持空即由轮换跳过。
	return [upper, middle, ground]

# 向上查找所在的 Level 节点（用于调用 spawn_summoned_enemy）。
func _find_level() -> Node:
	var n: Node = get_parent()
	while n != null:
		if n is Level:
			return n
		n = n.get_parent()
	return null

func _tick_fdk_attack(delta: float) -> void:
	if _fdk_attack_frames.is_empty():
		_exit_fdk_attack_to_idle()
		return
	_fdk_attack_accum += delta
	while _fdk_attack_accum >= FDK_ATTACK_FRAME_INTERVAL:
		_fdk_attack_accum -= FDK_ATTACK_FRAME_INTERVAL
		_fdk_attack_frame_idx += 1
		if _fdk_attack_frame_idx >= _fdk_attack_frames.size():
			_exit_fdk_attack_to_idle()
			return
		_apply_normal_texture(_fdk_attack_frames[_fdk_attack_frame_idx], "fdk_attack")

func _exit_fdk_attack_to_idle() -> void:
	anim_state = AnimState.IDLE
	# 冷却已在攻击开始时重置；此处不再重置，确保攻击动画时长不计入下一次攻击的 5 秒间隔。
	state_timer = 0.0
	state_duration = IDLE_DURATION_MIN
	anim_frame = 0
	if not _idle_frames.is_empty():
		_apply_normal_texture(_idle_frames[0], "idle")

# 确保常驻机关平台存在（首次进入 FDK 处理时创建），平行状态，右侧停一颗静止铁球。
func _ensure_fdk_mechanism() -> void:
	if _fdk_mechanism != null and is_instance_valid(_fdk_mechanism):
		return
	if is_captured or dying or is_in_flight:
		return
	var parent_node := get_parent()
	if parent_node == null:
		return
	var platform := Node2D.new()
	platform.name = "FatDemonKingMechanism"
	platform.z_index = 50
	var pivot_node := Node2D.new()
	pivot_node.name = "MechanismPivot"
	var sprite_node := Sprite2D.new()
	sprite_node.name = "MechanismSprite"
	sprite_node.texture = _load_fdk_mechanism_texture()
	pivot_node.add_child(sprite_node)
	# 静止展示用铁球：停在机关（平台）右侧，随机关一起旋转。
	var rest_ball := Sprite2D.new()
	rest_ball.name = "RestIronBall"
	rest_ball.texture = _load_fdk_iron_ball_texture()
	rest_ball.scale = Vector2(FDK_IRON_BALL_REST_SCALE, FDK_IRON_BALL_REST_SCALE)
	rest_ball.z_index = 1
	pivot_node.add_child(rest_ball)
	platform.add_child(pivot_node)
	parent_node.add_child(platform)
	_fdk_mechanism = platform
	_fdk_mechanisms.append(platform)
	_apply_fdk_mechanism_tuning(platform)

# Attack 时触发：机关旋转到 F1 角度 → 释放滚动铁球 → 机关复位平行。
func _trigger_fdk_mechanism_tilt() -> void:
	# 0.5 秒延迟期间若被捕获 / 死亡 / 飞行中，则取消本次倾斜。
	if is_captured or dying or is_in_flight:
		return
	_ensure_fdk_mechanism()
	if _fdk_mechanism == null or not is_instance_valid(_fdk_mechanism):
		return
	var pivot_node := _fdk_mechanism.get_node_or_null("MechanismPivot") as Node2D
	if pivot_node == null:
		return
	# 上一次的倾斜→停留→复位时序尚未结束 → 跳过，避免叠加 tween 造成角度冲突。
	if _fdk_mechanism_tilted:
		return
	var base_rot := _fdk_mechanism_base_rotation()
	var tilt_rot := base_rot + CharTuning.fdk_mechanism_rotation
	# 标记为倾斜状态。复位时机由下面的 tween 链固定控制（倾斜0.5秒→停留2秒→复位1秒）。
	_fdk_mechanism_tilted = true
	# 倾斜到位后再放球（独立定时器触发，不占用主时序 tween 链）。
	GameState.wait(self, FDK_MECHANISM_TILT_TIME + FDK_BALL_RELEASE_DELAY).connect(_release_fdk_iron_ball)
	# 一条 tween 串起完整时序：倾斜(0.5s) → 停留(2s) → 复位(1s) → 恢复静止铁球。
	var tween := _fdk_mechanism.create_tween()
	# 1) 旋转到倾斜角度，耗时 0.5 秒
	tween.tween_property(pivot_node, "rotation_degrees", tilt_rot, FDK_MECHANISM_TILT_TIME)
	# 2) 倾斜到位后停留 2 秒
	tween.tween_interval(FDK_MECHANISM_TILT_HOLD_TIME)
	# 3) 旋转回平行(0°)，耗时 1 秒
	tween.tween_property(pivot_node, "rotation_degrees", base_rot, FDK_MECHANISM_RESET_TIME)
	# 4) 复位完成：恢复静止展示铁球，并清除倾斜标记
	tween.tween_callback(_on_fdk_tilt_sequence_finished)

# 机关在平行状态下 pivot 的基础旋转角度（仅由 F1 摆放，不含 Attack 倾斜量）。
func _fdk_mechanism_base_rotation() -> float:
	return 0.0

# 倾斜→停留→复位的完整 tween 链结束：清除倾斜标记并恢复静止展示铁球。
func _on_fdk_tilt_sequence_finished() -> void:
	_fdk_mechanism_tilted = false
	_restore_fdk_rest_ball()

# 释放一颗真正会滚动的铁球，按三层平台路径匀速滚动；同时隐藏静止展示球。
func _release_fdk_iron_ball() -> void:
	if _fdk_mechanism == null or not is_instance_valid(_fdk_mechanism):
		return
	var parent_node := get_parent()
	if parent_node == null:
		return
	var pivot_node := _fdk_mechanism.get_node_or_null("MechanismPivot") as Node2D
	var rest_ball: Sprite2D = null
	var spawn_pos := _fdk_mechanism.global_position
	if pivot_node != null:
		rest_ball = pivot_node.get_node_or_null("RestIronBall") as Sprite2D
		if rest_ball != null:
			spawn_pos = rest_ball.global_position
			rest_ball.visible = false
	var scene := _cached_load(FDK_IRON_BALL_SCENE) as PackedScene
	if scene == null:
		return
	var ball = scene.instantiate()
	# 铁球场景默认 z_index = -10 会被关卡背景遮挡 → 强制提到机关之上，确保滚动可见。
	if ball is CanvasItem:
		(ball as CanvasItem).z_index = 51
	parent_node.add_child(ball)
	_fdk_active_ball = ball
	if ball.has_method("launch_path"):
		ball.launch_path(_build_fdk_track(spawn_pos), 0.0)
	# 机关复位时机由倾斜 tween 链固定控制（倾斜0.5s→停留2s→复位1s），与铁球滚动相互独立。
	# 铁球滚出画面后自行 queue_free，不再参与机关复位。

# 构建三层滚动路径：机关左侧斜面滑下 → 上层平台(向左滚至左端终点) → 中层平台(向右滚至右端终点)
# → 下层地面(向左滚出画面)。所有坐标取自 Stage3 关卡几何，铁球匀速滚动。
func _build_fdk_track(spawn_pos: Vector2) -> Array:
	var radius := IronBall.COLLISION_SIZE * IronBall.BALL_SCALE * 0.5
	var upper_y := FDK_TRACK_UPPER_Y - radius
	var middle_y := FDK_TRACK_MIDDLE_Y - radius
	var ground_y := FDK_TRACK_GROUND_Y - radius
	# 着陆点位于机关左下方：从 spawn X 向左偏移，并钳制在上层平台有效区间内。
	var landing_x: float = clampf(
		spawn_pos.x + FDK_TRACK_UPPER_LANDING_DX,
		FDK_TRACK_UPPER_LANDING_MIN_X,
		FDK_TRACK_UPPER_LANDING_MAX_X
	)
	var points: Array = []
	points.append(spawn_pos)                                          # 机关左侧起点（铁球停靠处）
	points.append(Vector2(landing_x, upper_y))                        # 沿左侧斜面向左下滑落到上层平台
	points.append(Vector2(FDK_TRACK_UPPER_LEFT_X, upper_y))           # 上层平台向左滚到左端终点
	points.append(Vector2(FDK_TRACK_UPPER_LEFT_X, middle_y))          # 从上层终点掉到中层平台
	points.append(Vector2(FDK_TRACK_MIDDLE_RIGHT_X, middle_y))        # 中层平台向右滚到右端终点
	points.append(Vector2(FDK_TRACK_MIDDLE_RIGHT_X, ground_y))        # 从中层终点掉到下层地面
	points.append(Vector2(FDK_TRACK_GROUND_EXIT_X, ground_y))         # 下层地面向左滚出画面
	return points

func _restore_fdk_rest_ball() -> void:
	if _fdk_mechanism == null or not is_instance_valid(_fdk_mechanism):
		return
	var pivot_node := _fdk_mechanism.get_node_or_null("MechanismPivot") as Node2D
	if pivot_node == null:
		return
	var rest_ball := pivot_node.get_node_or_null("RestIronBall") as Sprite2D
	if rest_ball != null:
		rest_ball.visible = true

static func _load_fdk_mechanism_texture() -> Texture2D:
	if _fdk_mechanism_texture_cache != null:
		return _fdk_mechanism_texture_cache
	_fdk_mechanism_texture_cache = _cached_load(FDK_MECHANISM_TEXTURE) as Texture2D
	if _fdk_mechanism_texture_cache == null:
		push_warning("Failed to load FDK mechanism PNG: %s" % FDK_MECHANISM_TEXTURE)
		return null
	return _fdk_mechanism_texture_cache

static func _load_fdk_iron_ball_texture() -> Texture2D:
	return _cached_load(FDK_IRON_BALL_TEXTURE) as Texture2D

static func _cached_load(path: String) -> Resource:
	if _resource_cache.has(path):
		return _resource_cache[path]
	var res := load(path)
	_resource_cache[path] = res
	return res

static func _get_cached_frame_list(paths: Array) -> Array:
	var key := _frame_cache_key(paths)
	if _frame_cache.has(key):
		return _frame_cache[key]
	var frames: Array = []
	for path in paths:
		var tex := _cached_load(str(path)) as Texture2D
		if tex != null:
			frames.append(tex)
	_frame_cache[key] = frames
	return frames

static func _frame_cache_key(paths: Array) -> String:
	var key := ""
	for path in paths:
		key += str(path)
		key += "|"
	return key

# 机关平台的摆放与旋转支点（平行状态）。Mechanism Pivot X/Y 是旋转支点，
# Mechanism Pos X/Y 是平台贴图相对支点的位置，Mechanism Rotation 是 Attack1 倾斜角。
func _apply_fdk_mechanism_tuning(platform: Node) -> void:
	if not platform is Node2D:
		return
	var platform_2d := platform as Node2D
	platform_2d.rotation_degrees = 0.0
	# 机关整体锚定在“屏幕中心”的世界坐标，与 F1 调参预览(CanvasLayer 居中)保持同一坐标系，
	# 这样 F1 调好的 Pivot / Pos / Rotation 值在运行时落点与预览完全一致（否则会偏出屏幕）。
	# 本游戏无 Camera2D，世界坐标 == 屏幕坐标，屏幕中心即视口尺寸的一半。
	platform_2d.global_position = get_viewport().get_visible_rect().size * 0.5
	var pivot_node := platform_2d.get_node_or_null("MechanismPivot") as Node2D
	if pivot_node == null:
		return
	pivot_node.position = Vector2(CharTuning.fdk_mechanism_pivot_x, CharTuning.fdk_mechanism_pivot_y)
	# 仅在机关处于平行(未倾斜)时由调参直接写入旋转；倾斜过程由 tween 接管。
	if anim_state != AnimState.FDK_ATTACK and (_fdk_active_ball == null or not is_instance_valid(_fdk_active_ball)):
		pivot_node.rotation_degrees = _fdk_mechanism_base_rotation()
	var sprite_node := pivot_node.get_node_or_null("MechanismSprite") as Sprite2D
	if sprite_node == null:
		return
	sprite_node.position = Vector2(CharTuning.fdk_mechanism_pos_x, CharTuning.fdk_mechanism_pos_y) - pivot_node.position
	var s: float = max(0.01, CharTuning.fdk_mechanism_scale)
	sprite_node.scale = Vector2(s, s)
	sprite_node.offset = Vector2.ZERO
	# 静止铁球停在机关平台左侧（贴图左端附近、表面之上）。机关倾斜时铁球从左侧斜面滑下。
	# 铁球美术大小跟随 F1 的“铁球美术大小”实时调整。
	var rest_ball := pivot_node.get_node_or_null("RestIronBall") as Sprite2D
	if rest_ball != null and sprite_node.texture != null:
		var ball_scale: float = max(0.01, CharTuning.fdk_ball_scale)
		rest_ball.scale = Vector2(ball_scale, ball_scale)
		var half_w := sprite_node.texture.get_width() * 0.5 * s
		var ball_r := IronBall.COLLISION_SIZE * 0.5 * ball_scale
		var rest_offset := Vector2(CharTuning.fdk_ball_rest_offset_x, CharTuning.fdk_ball_rest_offset_y)
		rest_ball.position = sprite_node.position + Vector2(-half_w * 0.7, -ball_r) + rest_offset

func _get_viewport_center_global() -> Vector2:
	var camera := get_viewport().get_camera_2d()
	if camera != null:
		return camera.get_screen_center_position()
	var screen_center := get_viewport().get_visible_rect().size * 0.5
	return get_viewport().get_canvas_transform().affine_inverse() * screen_center

# ───────── 火种生成（PalaceZombie ATTACK 状态用） ─────────

# 生成两枚火种，朝僵尸面向方向滑行（一前一后）
func _spawn_fire_seeds() -> void:
	# 已被捕获/死亡 → 不再生成火种（防止 ATTACK 中途被吸进葫芦后还产生火种）
	if is_captured or dying or is_in_flight:
		return
	var scene := _cached_load(FIRE_SEED_SCENE)
	if scene == null:
		return
	# 把火种挂在父节点（与 ball.gd 同级），让它独立于僵尸生命周期
	var parent_node := get_parent()
	if parent_node == null:
		return
	for ox in FIRE_SEED_OFFSETS_X:
		var fire = scene.instantiate()
		parent_node.add_child(fire)
		fire.global_position = global_position + Vector2(ox * direction, FIRE_SEED_OFFSET_Y)
		if fire.has_method("launch"):
			fire.launch(direction)

func _has_ground_ahead() -> bool:
	# 动态跟随 collision shape：射线起点紧贴 collision 底部边缘外侧，向下探测一小段
	# 解决 collision 被调参面板调整后，写死的 ground_check 坐标失配导致原地抖动的 bug
	var col_w := 60.0
	var col_h := 70.0
	var col_ox := 0.0
	var col_oy := 5.0
	match enemy_type:
		Type.METEOR_HAMMER:
			col_w = CharTuning.mh_col_width
			col_h = CharTuning.mh_col_height
			col_ox = CharTuning.mh_col_offset_x
			col_oy = CharTuning.mh_col_offset_y
		Type.RED_GHOST:
			col_w = CharTuning.rg_col_width
			col_h = CharTuning.rg_col_height
			col_ox = CharTuning.rg_col_offset_x
			col_oy = CharTuning.rg_col_offset_y
		Type.RED_DEVIL:
			col_w = CharTuning.rd_col_width
			col_h = CharTuning.rd_col_height
			col_ox = CharTuning.rd_col_offset_x
			col_oy = CharTuning.rd_col_offset_y
		Type.PALACE_ZOMBIE:
			col_w = CharTuning.pz_col_width
			col_h = CharTuning.pz_col_height
			col_ox = CharTuning.pz_col_offset_x
			col_oy = CharTuning.pz_col_offset_y
		Type.FAT_DEMON_KING:
			col_w = CharTuning.fdk_col_width * CharTuning.fdk_col_scale
			col_h = CharTuning.fdk_col_height * CharTuning.fdk_col_scale
			col_ox = CharTuning.fdk_col_offset_x
			col_oy = CharTuning.fdk_col_offset_y
	# 射线起点：贴在 collision 底部边缘外侧
	ground_check.position.x = col_ox + (col_w / 2.0 + PLATFORM_EDGE_LOOKAHEAD) * direction
	ground_check.position.y = col_oy + col_h / 2.0 - 4.0
	# 射线终点：从起点向下 30 像素（覆盖典型 tile 高度 10 + 缓冲）
	ground_check.target_position = Vector2(0, 30.0)
	ground_check.force_raycast_update()
	return ground_check.is_colliding()

func _has_wall_ahead() -> bool:
	# 提前探测前方障碍，避免敌人把身体推进窄平台夹缝里再回不来。
	var col_w := 60.0
	var col_h := 70.0
	var col_ox := 0.0
	var col_oy := 5.0
	match enemy_type:
		Type.METEOR_HAMMER:
			col_w = CharTuning.mh_col_width
			col_h = CharTuning.mh_col_height
			col_ox = CharTuning.mh_col_offset_x
			col_oy = CharTuning.mh_col_offset_y
		Type.RED_GHOST:
			col_w = CharTuning.rg_col_width
			col_h = CharTuning.rg_col_height
			col_ox = CharTuning.rg_col_offset_x
			col_oy = CharTuning.rg_col_offset_y
		Type.RED_DEVIL:
			col_w = CharTuning.rd_col_width
			col_h = CharTuning.rd_col_height
			col_ox = CharTuning.rd_col_offset_x
			col_oy = CharTuning.rd_col_offset_y
		Type.PALACE_ZOMBIE:
			col_w = CharTuning.pz_col_width
			col_h = CharTuning.pz_col_height
			col_ox = CharTuning.pz_col_offset_x
			col_oy = CharTuning.pz_col_offset_y
		Type.FAT_DEMON_KING:
			col_w = CharTuning.fdk_col_width * CharTuning.fdk_col_scale
			col_h = CharTuning.fdk_col_height * CharTuning.fdk_col_scale
			col_ox = CharTuning.fdk_col_offset_x
			col_oy = CharTuning.fdk_col_offset_y
	wall_check.position.x = col_ox + (col_w / 2.0 + 4.0) * direction
	wall_check.position.y = col_oy
	wall_check.target_position = Vector2(PLATFORM_EDGE_LOOKAHEAD * direction, 0.0)
	wall_check.force_raycast_update()
	return wall_check.is_colliding()

func _get_collision_local_rect() -> Rect2:
	if collision != null and collision.shape is RectangleShape2D:
		var rect_shape := collision.shape as RectangleShape2D
		return Rect2(collision.position - rect_shape.size * 0.5, rect_shape.size)
	return Rect2(Vector2(-30.0, -70.0), Vector2(60.0, 70.0))

func _clamp_x_to_walkable_platform(world_x: float, world_y: float) -> float:
	var level := _get_level()
	if level == null or not level.has_method("find_platform_for"):
		return world_x
	var body_rect := _get_collision_local_rect()
	var platform = _find_platform_for_body_clamp(level, world_x, world_y, body_rect)
	if platform == null:
		return world_x
	var platform_left_edge: float = float(platform["left_x"]) - 5.0 + PLATFORM_BODY_SIDE_CLEARANCE
	var platform_right_edge: float = float(platform["right_x"]) + 5.0 - PLATFORM_BODY_SIDE_CLEARANCE
	var min_x := platform_left_edge - body_rect.position.x
	var max_x := platform_right_edge - body_rect.end.x
	if min_x > max_x:
		return (min_x + max_x) * 0.5
	return clampf(world_x, min_x, max_x)

func _find_platform_for_body_clamp(level: Node, world_x: float, world_y: float,
		body_rect: Rect2) -> Variant:
	var platform = level.find_platform_for(Vector2(world_x, world_y))
	if platform != null:
		return platform
	if not level.has_method("get_platforms"):
		return null
	var body_reach: float = max(abs(body_rect.position.x), abs(body_rect.end.x)) + 20.0
	var best: Variant = null
	var best_dist := INF
	for p in level.get_platforms():
		if not (p is Dictionary) or not p.has("top_y") or not p.has("left_x") or not p.has("right_x"):
			continue
		if abs(world_y - float(p["top_y"])) > 18.0:
			continue
		var left_edge: float = float(p["left_x"]) - 5.0 - body_reach
		var right_edge: float = float(p["right_x"]) + 5.0 + body_reach
		if world_x < left_edge or world_x > right_edge:
			continue
		var dist: float = 0.0
		if world_x < float(p["left_x"]):
			dist = float(p["left_x"]) - world_x
		elif world_x > float(p["right_x"]):
			dist = world_x - float(p["right_x"])
		if dist < best_dist:
			best_dist = dist
			best = p
	return best

func _clamp_to_walkable_platform() -> bool:
	var before_x := global_position.x
	var clamped_x := _clamp_x_to_walkable_platform(before_x, global_position.y)
	if abs(clamped_x - before_x) <= 0.01:
		return false
	global_position.x = clamped_x
	velocity.x = 0.0
	direction = 1 if clamped_x > before_x else -1
	return true

# ───────── 跨平台跳跃（HOP） ─────────
# 懒加载：向上查找含 get_platforms 方法的祖先节点（即 Level）
func _get_level() -> Node:
	if _level_lookup_done:
		return _level_ref
	_level_lookup_done = true
	var n := get_parent()
	while n != null:
		if n.has_method("get_platforms"):
			_level_ref = n
			break
		n = n.get_parent()
	return _level_ref

# 检查是否需要换平台。条件：
#   1. 当前敌人类型在允许列表（仅 RED_GHOST / PALACE_ZOMBIE）
#   2. 通过随机概率 PLATFORM_HOP_TRIGGER_PROB
#   3. 能定位到当前所在平台
#   4. 场景中存在至少一个其他平台
# 满足 → 随机选一个其他平台进入 is_hopping 状态。
# 注意：流星锤怪 / 红魔王不参与跨平台跳跃；不再使用"自己平台拥挤"或
# "目标平台空旷"的判定，目标完全随机。
func _try_platform_hop() -> void:
	# 仅限红衣女鬼 与 宫廷僵尸
	if enemy_type != Type.RED_GHOST and enemy_type != Type.PALACE_ZOMBIE:
		return
	if randf() >= PLATFORM_HOP_TRIGGER_PROB:
		return  # 概率没中
	var level := _get_level()
	if level == null:
		return
	var here = level.find_platform_for(global_position)
	if here == null:
		return
	var target = level.pick_random_other_platform(here["id"])
	if target == null:
		return  # 场景里只有一个平台
	_begin_hop(target)

# 进入 HOP 状态：根据目标平台 Y 决定向上还是向下穿越。
func _begin_hop(target: Dictionary) -> void:
	is_hopping = true
	_hop_timer = 0.0
	_hop_target_x = target["center_x"]
	_hop_target_y = target["top_y"]
	_hop_target_left = target["left_x"]
	_hop_target_right = target["right_x"]
	# 中断当前所有"原地动作"型状态，回到 WALK，避免技能子计时器残留
	if anim_state != AnimState.WALK:
		anim_state = AnimState.WALK
		state_timer = 0.0
		state_duration = randf_range(WALK_DURATION_MIN, WALK_DURATION_MAX)
	# 朝目标方向调整朝向（视觉合理，不影响 hop 自身物理）
	if _hop_target_x > global_position.x:
		direction = 1
	else:
		direction = -1
	# 目标平台站立面 Y 比当前低（数值更大）→ 向下；否则向上
	if _hop_target_y > global_position.y + PLATFORM_HOP_DOWN_HYSTERESIS:
		_hop_mode = HopMode.DOWN
		# 下穿单向平台：把碰撞盒推到平台之下，并给一个朝下的初速度（参考 player.gd:563）
		# 注意：实心 tile（GrassSrc/DirtSrc）不能下穿，敌人此时若站在实心 tile 上会被卡住，
		# 但下层若是 PlatformSrc(one-way) 就能穿过。这里做最朴素的处理；卡住会在 TIMEOUT 强制退出。
		global_position.y += 10.0
		velocity.y = 400.0
	else:
		_hop_mode = HopMode.UP
		velocity.y = PLATFORM_HOP_JUMP_VELOCITY

# HOP 中每帧推进：X 朝目标对齐，Y 任由重力 / 跳跃速度推动；
# 落到目标平台（脚部 Y 接近 top_y 且 X 在范围内 且 is_on_floor）→ 结束 HOP。
func _tick_platform_hop(delta: float) -> void:
	_hop_timer += delta
	# X 轴：朝目标 center_x 匀速移动，到达后停下
	var dx := _hop_target_x - global_position.x
	if abs(dx) > 1.0:
		velocity.x = sign(dx) * PLATFORM_HOP_X_SPEED
	else:
		velocity.x = 0.0
	# 视觉朝向跟运动方向走
	sprite.flip_h = (sign(dx) < 0) if default_facing_right else (sign(dx) > 0)
	move_and_slide()
	# 结束条件 1：超时强制结束（防极端地形卡住）
	if _hop_timer >= PLATFORM_HOP_TIMEOUT:
		_end_hop()
		return
	# 结束条件 2：在地面上、X 已在目标平台站立面范围内、Y 站立面接近目标
	if is_on_floor() and velocity.y >= 0.0:
		var on_target_x: bool = global_position.x >= _hop_target_left - 5.0 \
				and global_position.x <= _hop_target_right + 5.0
		var on_target_y: bool = abs(global_position.y - _hop_target_y) <= 14.0
		if on_target_x and on_target_y:
			_end_hop()
			return
		# 兜底：UP 模式下若已落到任意平台（不一定是目标），也接受 —— 避免反复尝试卡死
		if _hop_mode == HopMode.UP and _hop_timer > 0.6:
			_end_hop()

func _end_hop() -> void:
	is_hopping = false
	_hop_timer = 0.0
	velocity.x = 0.0
	# 重置巡逻状态时长，让敌人在新平台上稳定走一段时间再考虑技能
	state_timer = 0.0
	state_duration = randf_range(WALK_DURATION_MIN, WALK_DURATION_MAX)
	# hop 后给一个较长的换平台冷却，避免立刻再次起跳
	_hop_check_timer = 0.0
	_hop_check_interval = randf_range(
		PLATFORM_HOP_CHECK_INTERVAL_MIN, PLATFORM_HOP_CHECK_INTERVAL_MAX)

# ───────── 以上：跨平台跳跃 ─────────

func freeze_for_suction(_vanish_world: Vector2 = Vector2.INF) -> void:
	if is_captured or dying:
		return
	# 被吸住的流星锤攻击元素可反打 Boss：吸到锤子时按一次命中处理。
	if anim_state == AnimState.MH_ATTACK \
			and _mh_hammer_area != null \
			and is_instance_valid(_mh_hammer_area) \
			and _mh_hammer_area.monitoring:
		for body in _mh_hammer_area.get_overlapping_bodies():
			if body is Boss and not body.dying:
				body.take_damage(1)
				break
	# 若敌人正在 DASH（红衣女鬼突进）→ 立即中断技能，恢复显示，让玩家能看到被吸的敌人
	# 否则 sprite 在 VANISH 阶段 hidden，被吸时玩家看不到敌人
	if anim_state == AnimState.DASH:
		sprite.show()
		_exit_dash_to_walk()
	# 若流星锤怪正在 MH_ATTACK（扔锤/收锤中）→ 中断技能并销毁锤子，避免飞行的孤儿锤
	if anim_state == AnimState.MH_ATTACK:
		_exit_mh_attack_to_walk()
	# 进入蓄力（冻结）状态时，立刻切换为 capture 纹理（与正式吸引共用同一外观）
	if not is_frozen and not is_being_shrunk:
		_apply_capture_texture()
		_orig_sprite_position = sprite.position
		_has_suction_visual_origin = true
	is_frozen = true

# 被吸过程中按 progress (0~1) 缩小 sprite；1.0 = 完全消失
# 注意：只缩小 scale，不动 sprite.visible，避免与 capture 流程冲突
# 缩小敌人 sprite。progress 0→1 期间：
# - sprite.scale 从原大 → 0
# - 若提供 vanish_world，sprite 的渲染中心同步收敛到 vanish_world（解决"碰撞中心 ≠ 视觉中心"
#   导致敌人视觉停在葫芦上方的问题）
func apply_suction_shrink(progress: float, vanish_world: Vector2 = Vector2.INF) -> void:
	if is_captured or dying:
		return
	# 首次进入被吸状态时切换为正面/背面被吸纹理（蓄力期已切换则跳过）
	if not is_being_shrunk and not is_frozen:
		_apply_capture_texture()
		# 记录"原始 sprite.position"，缩小过程中 lerp 到目标偏移
		_orig_sprite_position = sprite.position
	is_being_shrunk = true
	var clamped: float = clamp(progress, 0.0, 1.0)
	var factor: float = 1.0 - clamped
	var base: float = _get_base_sprite_scale()
	# 缩小过程中保留 capture 补偿，避免缩小起点视觉跳变
	var mul: float = _get_capture_scale_mul()
	sprite.scale = Vector2(base * mul * factor, base * mul * factor)
	# 若提供消失点世界坐标，sprite.position 朝"敌人 → 消失点"方向线性偏移，
	# 让 sprite 视觉中心收敛到消失点。同时缓存给 _physics_process 用作位置插值目标。
	if vanish_world.x != INF and vanish_world.y != INF:
		_suction_vanish_world = vanish_world
		_has_suction_vanish = true
		var vanish_local: Vector2 = vanish_world - global_position
		sprite.position = _orig_sprite_position.lerp(vanish_local, clamped)

# 取消缩放效果，恢复原状（被 capture 或松开吸键后调用）
func reset_suction_shrink() -> void:
	sprite.visible = true
	is_being_shrunk = false
	_was_being_shrunk = false
	_has_suction_visual_origin = false
	var base: float = _get_base_sprite_scale()
	sprite.scale = Vector2(base, base)
	# 复位 sprite.position（被吸过程可能朝消失点偏移了）
	sprite.position = _get_base_sprite_offset()
	_restore_idle_texture()

# 把 sprite 切回 idle 动画帧（用于退出被吸/冻结状态）
func _restore_idle_texture() -> void:
	# 退出 capture 状态 → 清空 capture 帧缓存，下次进入时按当前朝向重建
	_capture_frames = []
	_capture_frame_idx = 0
	_capture_key = ""
	# 退出 capture 时重置 walk 间歇式状态，避免残留 timer 让下次跳跃节奏不规则
	if WALK_INTERMITTENT.has(enemy_type):
		_walk_intermittent_playing = false
		_walk_intermittent_timer = 0.0
		anim_frame = 0
	if is_captured or dying:
		return
	# 按当前 walk/idle 状态恢复对应帧
	var frames: Array = _idle_frames if anim_state == AnimState.IDLE else _frames
	if frames.is_empty():
		return
	var key: String = "idle" if anim_state == AnimState.IDLE else "move"
	_apply_normal_texture(frames[anim_frame % frames.size()], key)

# 根据"敌人是否面对钟馗"切换 capture_front / capture_back 纹理
# 假设 capture_*.png 原图朝向钟馗的方向是"右"；按 direction 决定 flip_h
# TEX 中 capture_front/back 可以是 String (单帧) 或 Array (序列帧)。
# 序列帧由 _on_anim_tick 推进 _capture_frame_idx 实现动画。
func _apply_capture_texture() -> void:
	# 懒加载 player_ref：敌人可能在 player 之前被实例化（level grid 顺序），
	# _ready 时刻 player 尚不存在，此处再次尝试。
	if player_ref == null or not is_instance_valid(player_ref):
		player_ref = get_tree().get_first_node_in_group("player")
		if player_ref == null:
			return
	var dx_to_player: int = 1 if player_ref.global_position.x > global_position.x else -1
	var facing_player: bool = (direction == dx_to_player)
	var key: String = "capture_front" if facing_player else "capture_back"
	# 朝向切换或首次进入 capture：重建帧缓存
	if key != _capture_key or _capture_frames.is_empty():
		_capture_key = key
		_capture_frames = []
		var tex_value = TEX[enemy_type][key]
		if tex_value is Array:
			for path in tex_value:
				_capture_frames.append(_cached_load(path))
		else:
			_capture_frames.append(_cached_load(tex_value))
		_capture_frame_idx = 0
	if not _capture_frames.is_empty():
		sprite.texture = _capture_frames[_capture_frame_idx]
	# 让敌人显示朝向 = direction（原图朝右，direction<0 时翻转）
	sprite.flip_h = direction < 0
	# 应用 capture 状态的缩放补偿（不同 capture 美术画布尺寸不一致时校正视觉大小）
	# 只在非 shrink 阶段直接应用；shrink 阶段由 apply_suction_shrink 公式接管
	if not is_being_shrunk:
		var base: float = _get_base_sprite_scale()
		var mul: float = _get_capture_scale_mul()
		sprite.scale = Vector2(base * mul, base * mul)

func _apply_suction_flight_stretch(progress: float) -> void:
	var clamped: float = clamp(progress, 0.0, 1.0)
	var factor: float = 1.0 - clamped
	var peak: float = sin(clamped * PI)
	var base: float = _get_base_sprite_scale()
	var mul: float = _get_capture_scale_mul()
	var stretch: float = 1.0 + SUCTION_FLIGHT_STRETCH_MAX * peak
	var squash: float = 1.0 - SUCTION_FLIGHT_SQUASH_MAX * peak
	sprite.scale = Vector2(base * mul * factor * stretch, base * mul * factor * squash)
	var vanish_local: Vector2 = flight_vanish_world - global_position
	sprite.position = _orig_sprite_position.lerp(vanish_local, clamped)

# 当前 capture 状态对应的 sprite 缩放补偿；非 capture 状态返回 1.0
func _get_capture_scale_mul() -> float:
	if _capture_key == "":
		return 1.0
	if not CAPTURE_SCALE_MUL.has(enemy_type):
		return 1.0
	var per_enemy: Dictionary = CAPTURE_SCALE_MUL[enemy_type]
	return per_enemy.get(_capture_key, 1.0)

func _get_normal_scale_mul(key: String) -> float:
	if not NORMAL_SCALE_MUL.has(enemy_type):
		return 1.0
	var per_enemy: Dictionary = NORMAL_SCALE_MUL[enemy_type]
	return per_enemy.get(key, 1.0)

func _apply_normal_scale(key: String) -> void:
	var base: float = _get_base_sprite_scale()
	var mul: float = _get_normal_scale_mul(key)
	sprite.scale = Vector2(base * mul, base * mul)

func _apply_current_normal_scale() -> void:
	if is_being_shrunk or is_frozen or _was_being_shrunk or _was_frozen:
		return
	if anim_state == AnimState.MH_ATTACK:
		_apply_normal_scale("mh_attack")
	elif anim_state == AnimState.IDLE:
		_apply_normal_scale("idle")
	else:
		_apply_normal_scale("move")

func _apply_normal_texture(texture: Texture2D, key: String) -> void:
	sprite.texture = texture
	_apply_normal_scale(key)

func _get_base_sprite_scale() -> float:
	match enemy_type:
		Type.METEOR_HAMMER:
			return CharTuning.mh_sprite_scale
		Type.RED_GHOST:
			return CharTuning.rg_sprite_scale
		Type.RED_DEVIL:
			return CharTuning.rd_sprite_scale
		Type.PALACE_ZOMBIE:
			return CharTuning.pz_sprite_scale
		Type.FAT_DEMON_KING:
			return CharTuning.fdk_sprite_scale
		_:
			return 1.0

func _get_base_sprite_offset() -> Vector2:
	match enemy_type:
		Type.METEOR_HAMMER:
			return Vector2(CharTuning.mh_sprite_offset_x, CharTuning.mh_sprite_offset_y)
		Type.RED_GHOST:
			return Vector2(0.0, CharTuning.rg_sprite_offset_y)
		Type.RED_DEVIL:
			return Vector2(0.0, CharTuning.rd_sprite_offset_y)
		Type.PALACE_ZOMBIE:
			return Vector2(0.0, CharTuning.pz_sprite_offset_y)
		Type.FAT_DEMON_KING:
			return Vector2(CharTuning.fdk_sprite_offset_x, CharTuning.fdk_sprite_offset_y)
		_:
			return Vector2.ZERO

func apply_suction(dir: Vector2, force: float) -> void:
	# dir / force 保留为参数兼容，但实际飞行路径用纯运动学位置插值（apply_suction_shrink 传入 vanish_world）
	# 这样彻底避开"重力 vs 吸力"拉扯（之前会上下弹）以及"被推到一边穿 one-way 平台"（之前会掉平台下）
	if is_captured or dying:
		return
	is_being_sucked = true
	# 首次进入被吸状态时记录起点位置，作为 lerp 起点
	if not _has_suction_start:
		_suction_start_pos = global_position
		_has_suction_start = true

# 钟馗累计吸满阈值 → 调此进入"飞向葫芦"阶段。从此 enemy 自我推进飞行动画，
# 与玩家是否继续按吸键无关；动画完成后自动变成 is_captured + hide()。
func begin_capture_flight(vanish_world: Vector2) -> void:
	if is_captured or dying or is_in_flight:
		return
	is_in_flight = true
	flight_t = 0.0
	flight_start_pos = global_position
	flight_vanish_world = vanish_world
	# 进入飞行阶段就脱离碰撞 / 不再被任何吸气逻辑干扰
	set_collision_layer_value(3, false)
	set_collision_mask_value(1, false)
	# capture 状态 flag 重置：飞行中不算被吸 / 不算 frozen
	is_being_sucked = false
	is_frozen = false
	is_being_shrunk = true   # 维持 capture 纹理和缩放公式
	_orig_sprite_position = sprite.position
	_has_suction_visual_origin = true

func become_captured() -> void:
	is_captured = true
	set_collision_layer_value(3, false)
	set_collision_mask_value(1, false)
	anim_timer.stop()
	# 被吸入葫芦后整个敌人节点隐藏（不再显示在钟馗旁边）
	hide()

func take_damage(amount: int = 1) -> void:
	if dying:
		return
	health = max(0, health - amount)
	if enemy_type == Type.FAT_DEMON_KING:
		_notify_fat_demon_king_hud_update()
	sprite.modulate = Color(1.0, 0.35, 0.35, 1.0)
	var tween := create_tween()
	tween.tween_property(sprite, "modulate", Color.WHITE, 0.12)
	if health <= 0:
		die()

func arm_ball_reward(hit_position: Vector2, pickup_type: int, drop_parent: Node) -> void:
	_pending_ball_reward_armed = true
	_pending_ball_reward_type = pickup_type
	_pending_ball_reward_pos = hit_position
	_pending_ball_reward_parent = drop_parent
	_pending_ball_reward_surface_y = _find_reward_surface_y(hit_position, drop_parent)

func _drop_pending_ball_reward() -> void:
	if not _pending_ball_reward_armed:
		return
	_pending_ball_reward_armed = false
	var parent: Node = _pending_ball_reward_parent if (_pending_ball_reward_parent != null and is_instance_valid(_pending_ball_reward_parent) and _pending_ball_reward_parent.is_inside_tree()) else null
	if parent == null:
		var loop := Engine.get_main_loop()
		if loop is SceneTree:
			parent = (loop as SceneTree).current_scene
	if parent == null:
		return
	var pickup_scene := load("res://scenes/pickup.tscn") as PackedScene
	if pickup_scene == null:
		push_error("Failed to load pickup scene for enemy reward drop.")
		return
	var reward = pickup_scene.instantiate()
	reward.pickup_type = _pending_ball_reward_type
	parent.add_child(reward)
	if _pending_ball_reward_type == Pickup.Type.STAR:
		reward.global_position = _pending_ball_reward_pos + Vector2(CharTuning.drop_yuanbao_offset_x, CharTuning.drop_yuanbao_offset_y)
	else:
		reward.global_position = _pending_ball_reward_pos
	if not is_nan(_pending_ball_reward_surface_y) and reward.has_method("lock_fall_to_surface"):
		reward.lock_fall_to_surface(_pending_ball_reward_surface_y)

func _find_reward_surface_y(hit_position: Vector2, drop_parent: Node) -> float:
	var level := _find_level_from_node(drop_parent)
	if level == null:
		level = _get_level()
	if level != null and level.has_method("find_platform_for"):
		var platform = level.find_platform_for(hit_position)
		if platform != null and platform.has("top_y"):
			return float(platform["top_y"])
	return _find_nearby_floor_y(hit_position)

func _find_level_from_node(node: Node) -> Node:
	var n := node
	while n != null:
		if n.has_method("find_platform_for"):
			return n
		n = n.get_parent()
	return null

func _find_nearby_floor_y(hit_position: Vector2) -> float:
	var space := get_world_2d().direct_space_state
	var best_y := NAN
	var best_dist := INF
	for offset_x in [0.0, -24.0, 24.0, -48.0, 48.0]:
		var from := hit_position + Vector2(offset_x, -8.0)
		var to := hit_position + Vector2(offset_x, 96.0)
		var ray := PhysicsRayQueryParameters2D.create(from, to)
		ray.collision_mask = 1
		ray.exclude = [get_rid()]
		var hit := space.intersect_ray(ray)
		if hit.is_empty():
			continue
		var dist: float = abs(float(hit.position.y) - hit_position.y)
		if dist < best_dist:
			best_dist = dist
			best_y = float(hit.position.y)
	return best_y

func die() -> void:
	if dying:
		return
	dying = true
	is_captured = true
	_drop_pending_ball_reward()
	if enemy_type == Type.FAT_DEMON_KING:
		_notify_fat_demon_king_hud_hide()
	# 保险：DASH VANISH 阶段中死亡 → 强制显示 sprite，避免死亡动画隐形播放
	sprite.show()
	# 保险：MH_ATTACK 中死亡 → 清理掉飞行的锤子（避免孤儿节点）
	if _mh_hammer_node != null and is_instance_valid(_mh_hammer_node):
		_mh_hammer_node.call_deferred("queue_free")
		_mh_hammer_node = null
		_mh_hammer_area = null
	for mechanism in _fdk_mechanisms:
		if is_instance_valid(mechanism):
			mechanism.call_deferred("queue_free")
	_fdk_mechanisms.clear()
	_fdk_mechanism = null
	# 死亡时不主动清滚动铁球（让其滚完/滚出画面自然消失，避免半路凭空消失）
	_fdk_active_ball = null
	# 机关已销毁 → 清掉倾斜标记。
	_fdk_mechanism_tilted = false
	GameState.add_score(SCORE_VALUES[enemy_type])
	set_collision_layer_value(3, false)
	anim_timer.stop()
	var die_tex = TEX[enemy_type]["die"]
	for i in range(die_tex.size()):
		# 节点已离开场景树（切场景 / 退出）：立即停止播放死亡帧，避免协程在
		# GameState.wait 上重新挂起，导致其 GDScript 函数状态（RefCounted）在退出时残留。
		if not is_inside_tree():
			return
		_apply_normal_texture(_cached_load(die_tex[i]), "die")
		await GameState.wait(self, 0.1)
	call_deferred("queue_free")

func _on_anim_tick() -> void:
	# 处于 capture 状态（蓄力冻结 / 真正吸引）→ 推进 capture 序列帧（如果有多帧），
	# 不切到 idle 帧。
	# is_frozen / is_being_shrunk 是"瞬态"flag——每物理帧末会被重置为 false，
	# 跨物理帧检查会误判；改用 _was_frozen / _was_being_shrunk 保留上一物理帧状态。
	var in_capture: bool = is_being_shrunk or is_frozen or _was_being_shrunk or _was_frozen
	if in_capture:
		# 该敌人配置了 CAPTURE_FRAME_INTERVAL → capture 帧由 _tick_capture_custom_anim 推进，跳过此处
		if CAPTURE_FRAME_INTERVAL.has(enemy_type):
			return
		if _capture_frames.size() > 1:
			_capture_frame_idx = (_capture_frame_idx + 1) % _capture_frames.size()
			sprite.texture = _capture_frames[_capture_frame_idx]
		return
	# ATTACK / DASH / MH_ATTACK / FDK_ATTACK / FDK_ATTACK2 / FDK_ATTACK3 状态：序列帧由各自的 tick 函数推进，跳过 AnimTimer 默认推进
	if anim_state == AnimState.ATTACK or anim_state == AnimState.DASH or anim_state == AnimState.MH_ATTACK or anim_state == AnimState.FDK_ATTACK or anim_state == AnimState.FDK_ATTACK2 or anim_state == AnimState.FDK_ATTACK3:
		return
	# IDLE 状态：推进 idle 帧（独立于 walk 帧序列）
	if anim_state == AnimState.IDLE:
		if _idle_frames.is_empty():
			return
		anim_frame = (anim_frame + 1) % _idle_frames.size()
		_apply_normal_texture(_idle_frames[anim_frame], "idle")
		return
	if _frames.is_empty():
		return
	# 配置了 WALK_INTERMITTENT 的敌人由 _tick_walk_intermittent_anim 推进 walk 帧，跳过默认推进
	if WALK_INTERMITTENT.has(enemy_type):
		return
	anim_frame = (anim_frame + 1) % _frames.size()
	_apply_normal_texture(_frames[anim_frame], "move")

# 间歇式 walk 动画推进（"跳一下→立定→再跳"节奏）+ 同步 velocity.x（立定时不动）
# 返回 true 表示当前处于立定停留期（外部物理应让 velocity.x = 0）
func _tick_walk_intermittent_anim(delta: float) -> bool:
	if not WALK_INTERMITTENT.has(enemy_type) or _frames.is_empty():
		return false
	var cfg: Dictionary = WALK_INTERMITTENT[enemy_type]
	var idle_interval: float = cfg["idle_interval"]
	var frame_interval: float = cfg["frame_interval"]
	_walk_intermittent_timer += delta
	if not _walk_intermittent_playing:
		# 立定停留：维持第 1 帧，直到 idle_interval 满
		if anim_frame != 0:
			anim_frame = 0
			_apply_normal_texture(_frames[0], "move")
		if _walk_intermittent_timer >= idle_interval:
			_walk_intermittent_timer -= idle_interval
			_walk_intermittent_playing = true
			anim_frame = 0  # 跳跃从第 1 帧开始
		return true   # 仍在立定阶段（但下一物理帧已经进入跳跃，调用方下一帧会再问）
	# 跳跃阶段：按 frame_interval 推进
	while _walk_intermittent_timer >= frame_interval:
		_walk_intermittent_timer -= frame_interval
		anim_frame += 1
		if anim_frame >= _frames.size():
			# 一轮跳跃完成：回到第 1 帧，进入立定停留
			anim_frame = 0
			_apply_normal_texture(_frames[0], "move")
			_walk_intermittent_playing = false
			_walk_intermittent_timer = 0.0
			return true   # 立刻进入立定
		_apply_normal_texture(_frames[anim_frame], "move")
	return false   # 仍在跳跃阶段，外部物理正常移动

# 自定义 capture 序列帧推进（覆盖默认 AnimTimer 节奏，对配置了 CAPTURE_FRAME_INTERVAL 的敌人生效）
func _tick_capture_custom_anim(delta: float) -> void:
	if not CAPTURE_FRAME_INTERVAL.has(enemy_type):
		return
	# 非 capture 状态：重置累加器，避免下次进入 capture 时第一帧立刻跳
	var in_capture: bool = is_being_shrunk or is_frozen or _was_being_shrunk or _was_frozen
	if not in_capture or _capture_frames.size() <= 1:
		_capture_anim_accum = 0.0
		return
	var interval: float = CAPTURE_FRAME_INTERVAL[enemy_type]
	_capture_anim_accum += delta
	while _capture_anim_accum >= interval:
		_capture_anim_accum -= interval
		_capture_frame_idx = (_capture_frame_idx + 1) % _capture_frames.size()
		sprite.texture = _capture_frames[_capture_frame_idx]

func _get_hud() -> Node:
	var level := _find_level()
	if level == null:
		return null
	if "ui" in level:
		return level.ui
	return null

func _notify_fat_demon_king_hud_show() -> void:
	var hud := _get_hud()
	if hud != null and hud.has_method("show_fat_demon_king_bar"):
		hud.show_fat_demon_king_bar(FAT_DEMON_KING_MAX_HEALTH)

func _notify_fat_demon_king_hud_update() -> void:
	var hud := _get_hud()
	if hud != null and hud.has_method("update_fat_demon_king_health"):
		hud.update_fat_demon_king_health(health)

func _notify_fat_demon_king_hud_hide() -> void:
	var hud := _get_hud()
	if hud != null and hud.has_method("hide_fat_demon_king_bar"):
		hud.hide_fat_demon_king_bar()
