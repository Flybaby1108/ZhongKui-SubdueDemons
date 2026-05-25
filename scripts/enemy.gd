extends CharacterBody2D
class_name Enemy

enum Type { METEOR_HAMMER, RED_GHOST, RED_DEVIL, PALACE_ZOMBIE }

@export var enemy_type: Type = Type.METEOR_HAMMER

# default_facing_right 表示**美术原图(PNG)**的朝向，**不是**初始运动方向。
# - 如果 PNG 原图角色面朝右（脸/武器/正面在右），设为 true
# - 如果 PNG 原图角色面朝左，设为 false
# 当前所有敌人 PNG 都朝右绘制 → 一律为 true。
# 切勿为了"修正朝向看起来不对"而翻转此字段，那会导致朝向与运动方向相反。
@export var default_facing_right: bool = true

const GRAVITY := 4000.0
const MH_SPEED := 150.0

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
var charging: bool = false
var charge_cooldown: float = 0.0
var initial_y: float = 0.0
var bat_oscillation_t: float = 0.0
var player_ref: Node2D = null

const SCORE_VALUES := {
	Type.METEOR_HAMMER: 200,
	Type.RED_GHOST: 300,
	Type.RED_DEVIL: 400,
	Type.PALACE_ZOMBIE: 500,
}

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
}

var _frames: Array = []
# idle 状态序列帧（与 _frames=walk 区分；从 TEX[type]["idle"] 加载，没配的退化为 _frames）
var _idle_frames: Array = []
# attack 状态序列帧（仅 PALACE_ZOMBIE 配置；为空表示该敌人不会进入 ATTACK 状态）
var _attack_frames: Array = []

# walk / idle / attack / dash / mh_attack 行为状态机：每个敌人在巡逻时随机切换 walk ↔ idle，idle 切回时随机决定是否折返
# ATTACK 状态：仅对 PALACE_ZOMBIE 启用，进入 IDLE 时按 ATTACK_PROB 概率改为 ATTACK（甩法杖射火种）
# DASH 状态：仅对 RED_GHOST 启用，进入 IDLE 时按 DASH_PROB 概率改为 DASH（消失→突进3身位→flutter显现）
# MH_ATTACK 状态：仅对 METEOR_HAMMER 启用，进入 IDLE 时按 MH_ATTACK_PROB 概率改为 MH_ATTACK
#   （预备动作→扔流星锤→收回→回 IDLE）
enum AnimState { WALK, IDLE, ATTACK, DASH, MH_ATTACK }
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
	_frames = []
	for path in TEX[enemy_type]["move"]:
		_frames.append(load(path))
	# 加载 idle 帧（若未配则退化为 walk 帧）
	_idle_frames = []
	if TEX[enemy_type].has("idle"):
		for path in TEX[enemy_type]["idle"]:
			_idle_frames.append(load(path))
	if _idle_frames.is_empty():
		_idle_frames = _frames
	# 加载 attack 帧（仅 PALACE_ZOMBIE 配置；其他敌人 _attack_frames 留空 → 不会进入 ATTACK 状态）
	_attack_frames = []
	if TEX[enemy_type].has("attack"):
		for path in TEX[enemy_type]["attack"]:
			_attack_frames.append(load(path))
	# 加载 dash flutter 帧（仅 RED_GHOST 配置；其他敌人 _dash_frames 留空 → 不会进入 DASH 状态）
	_dash_frames = []
	if TEX[enemy_type].has("dash"):
		for path in TEX[enemy_type]["dash"]:
			_dash_frames.append(load(path))
	# 加载流星锤怪攻击帧 + 锤子帧（仅 METEOR_HAMMER 配置）
	_mh_attack_frames = []
	if TEX[enemy_type].has("mh_attack"):
		for path in TEX[enemy_type]["mh_attack"]:
			_mh_attack_frames.append(load(path))
	_mh_hammer_frames = []
	if TEX[enemy_type].has("mh_hammer"):
		for path in TEX[enemy_type]["mh_hammer"]:
			_mh_hammer_frames.append(load(path))
	sprite.texture = _frames[0]
	anim_timer.timeout.connect(_on_anim_tick)
	anim_timer.start()
	initial_y = global_position.y
	# 初始化 walk 状态计时（每个敌人各自随机起跑，避免整张图同步切换）
	state_duration = randf_range(WALK_DURATION_MIN, WALK_DURATION_MAX)
	state_timer = randf_range(0.0, state_duration * 0.5)  # 随机初始 phase
	# 不在此处获取 player_ref：敌人可能在 player 之前被实例化 (level grid 顺序)
	# 改为在 _apply_capture_texture 中按需懒加载

	CharTuning.tuning_changed.connect(_apply_tuning)
	_apply_tuning()

func _apply_tuning() -> void:
	# shrink 阶段不要覆盖 sprite.scale / sprite.position —— shrink 公式接管
	# 只写入 collision（与 sprite 视觉解耦）
	var skip_sprite: bool = is_being_shrunk
	if enemy_type == Type.METEOR_HAMMER:
		if not skip_sprite:
			sprite.scale = Vector2(CharTuning.mh_sprite_scale, CharTuning.mh_sprite_scale)
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
# 持续被钟馗"真正吸引"的累计时间（秒）；中断（脱离吸气区/玩家松开）→ 归零
# 累计 ≥ SUCTION_CAPTURE_TIME 时算捕获成功，进入 in-flight 飞向葫芦阶段
var suction_hold_timer: float = 0.0
const SUCTION_CAPTURE_TIME := 1.0
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

func _physics_process(delta: float) -> void:
	if dying or is_captured:
		return
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
	# 维护"持续被吸"计时：吸气全程通过 is_frozen 标记，敌人**完全冻结在原地**。
	# 1 秒计满 → player 调 begin_capture_flight()，敌人进入 in-flight 阶段自我推进。
	# 设计：is_being_sucked 已废弃（保留字段以兼容 ball.gd 等可能的引用，但不再用作位置驱动）。
	if is_frozen:
		suction_hold_timer += delta
	else:
		suction_hold_timer = 0.0
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
		# 缩放 + sprite.position 收敛到 vanish（与原 shrink 公式一致）
		var factor: float = 1.0 - progress
		var base: float = _get_base_sprite_scale()
		var mul: float = _get_capture_scale_mul()
		sprite.scale = Vector2(base * mul * factor, base * mul * factor)
		var vanish_local: Vector2 = flight_vanish_world - global_position
		sprite.position = _orig_sprite_position.lerp(vanish_local, progress)
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
			
	is_being_sucked = false

func _process_walking_enemy(delta: float) -> void:
	velocity.y += GRAVITY * delta
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
		
	move_and_slide()
	if is_on_wall():
		direction = -direction
	if is_on_floor() and not _has_ground_ahead():
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
				sprite.texture = _idle_frames[0]
	elif anim_state == AnimState.IDLE:
		# IDLE → WALK
		anim_state = AnimState.WALK
		state_duration = randf_range(WALK_DURATION_MIN, WALK_DURATION_MAX)
		# 随机折返
		if randf() < REVERSE_ON_RESUME_PROB:
			direction = -direction
		anim_frame = 0
		if not _frames.is_empty():
			sprite.texture = _frames[0]
	# ATTACK / DASH 状态由各自的 tick 函数自行处理 → WALK 的过渡，不在此分支处理

# 进入 ATTACK 状态：初始化攻击动画累加器，显示 attack 首帧
# 之后由 _tick_attack_anim 推进序列帧、生成火种、完成后回 WALK
func _enter_attack_state() -> void:
	anim_state = AnimState.ATTACK
	_attack_anim_accum = 0.0
	_attack_frame_idx = 0
	_attack_spawned = false
	if not _attack_frames.is_empty():
		sprite.texture = _attack_frames[0]
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
		sprite.texture = _attack_frames[_attack_frame_idx]
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
		sprite.texture = _frames[0]

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
	global_position.x = target_x

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
		_:                  return 60.0

func _exit_dash_to_walk() -> void:
	# 万一异常中途没显示，确保 sprite 可见
	sprite.show()
	anim_state = AnimState.WALK
	state_duration = randf_range(WALK_DURATION_MIN, WALK_DURATION_MAX)
	state_timer = 0.0
	anim_frame = 0
	if not _frames.is_empty():
		sprite.texture = _frames[0]

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
		sprite.texture = _mh_attack_frames[0]
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
			sprite.texture = _mh_attack_frames[_mh_char_frame_idx]
			# 播到第 21 帧（index 20）→ 切到 THROW_OUT 子阶段 + 生成锤
			if _mh_char_frame_idx == MH_THROW_TRIGGER_FRAME and _mh_hammer_node == null:
				_enter_mh_throw_out()
	else:
		# THROW_OUT / RETRIEVE：角色循环 20~27（_21~_28）
		_mh_char_frame_idx += 1
		if _mh_char_frame_idx > MH_LOOP_FRAME_END:
			_mh_char_frame_idx = MH_LOOP_FRAME_START
		sprite.texture = _mh_attack_frames[_mh_char_frame_idx]

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
	if not (body is Player):
		return
	if body.invincible or body.is_vacuuming:
		return
	body.invincible = true
	body.invincible_timer = body.HURT_INVINCIBLE_TIME
	body.take_damage()
	# 锤击中后继续飞行（不消失）—— 与单发火种不同，锤是周期攻击的"主武器"

# 收尾：销毁锤节点，回到 WALK 状态
func _exit_mh_attack_to_walk() -> void:
	if _mh_hammer_node != null and is_instance_valid(_mh_hammer_node):
		_mh_hammer_node.queue_free()
	_mh_hammer_node = null
	_mh_hammer_area = null
	anim_state = AnimState.WALK
	state_duration = randf_range(WALK_DURATION_MIN, WALK_DURATION_MAX)
	state_timer = 0.0
	anim_frame = 0
	if not _frames.is_empty():
		sprite.texture = _frames[0]

# ───────── 火种生成（PalaceZombie ATTACK 状态用） ─────────

# 生成两枚火种，朝僵尸面向方向滑行（一前一后）
func _spawn_fire_seeds() -> void:
	# 已被捕获/死亡 → 不再生成火种（防止 ATTACK 中途被吸进葫芦后还产生火种）
	if is_captured or dying or is_in_flight:
		return
	var scene := load(FIRE_SEED_SCENE)
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
	# 射线起点：贴在 collision 底部边缘外侧
	ground_check.position.x = col_ox + (col_w / 2.0 + 4.0) * direction
	ground_check.position.y = col_oy + col_h / 2.0 - 4.0
	# 射线终点：从起点向下 30 像素（覆盖典型 tile 高度 10 + 缓冲）
	ground_check.target_position = Vector2(0, 30.0)
	ground_check.force_raycast_update()
	return ground_check.is_colliding()

func freeze_for_suction() -> void:
	if is_captured or dying:
		return
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
	var base: float = _get_base_sprite_scale()
	sprite.scale = Vector2(base, base)
	# 复位 sprite.position（被吸过程可能朝消失点偏移了）
	sprite.position = _orig_sprite_position
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
	# 还原 sprite 的 base scale（capture 期间可能被乘了 capture_mul 补偿）
	var base: float = _get_base_sprite_scale()
	sprite.scale = Vector2(base, base)
	# 按当前 walk/idle 状态恢复对应帧
	var frames: Array = _idle_frames if anim_state == AnimState.IDLE else _frames
	if frames.is_empty():
		return
	sprite.texture = frames[anim_frame % frames.size()]

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
				_capture_frames.append(load(path))
		else:
			_capture_frames.append(load(tex_value))
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

# 当前 capture 状态对应的 sprite 缩放补偿；非 capture 状态返回 1.0
func _get_capture_scale_mul() -> float:
	if _capture_key == "":
		return 1.0
	if not CAPTURE_SCALE_MUL.has(enemy_type):
		return 1.0
	var per_enemy: Dictionary = CAPTURE_SCALE_MUL[enemy_type]
	return per_enemy.get(_capture_key, 1.0)

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
		_:
			return 1.0

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

# 钟馗持续吸 1 秒 → 调此进入"飞向葫芦"阶段。从此 enemy 自我推进飞行动画，
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
	# 保存"原始 sprite.position"以便 shrink 公式正确 lerp
	# 每次起飞都重新记录（覆盖旧值），因为现在 1 秒冻结期间不再调 apply_suction_shrink
	_orig_sprite_position = sprite.position

func become_captured() -> void:
	is_captured = true
	set_collision_layer_value(3, false)
	set_collision_mask_value(1, false)
	anim_timer.stop()
	# 被吸入葫芦后整个敌人节点隐藏（不再显示在钟馗旁边）
	hide()

func die() -> void:
	if dying:
		return
	dying = true
	is_captured = true
	# 保险：DASH VANISH 阶段中死亡 → 强制显示 sprite，避免死亡动画隐形播放
	sprite.show()
	# 保险：MH_ATTACK 中死亡 → 清理掉飞行的锤子（避免孤儿节点）
	if _mh_hammer_node != null and is_instance_valid(_mh_hammer_node):
		_mh_hammer_node.queue_free()
		_mh_hammer_node = null
		_mh_hammer_area = null
	GameState.add_score(SCORE_VALUES[enemy_type])
	set_collision_layer_value(3, false)
	anim_timer.stop()
	var die_tex = TEX[enemy_type]["die"]
	for i in range(die_tex.size()):
		sprite.texture = load(die_tex[i])
		await get_tree().create_timer(0.1).timeout
	queue_free()

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
	# ATTACK / DASH / MH_ATTACK 状态：序列帧由各自的 tick 函数推进，跳过 AnimTimer 默认推进
	if anim_state == AnimState.ATTACK or anim_state == AnimState.DASH or anim_state == AnimState.MH_ATTACK:
		return
	# IDLE 状态：推进 idle 帧（独立于 walk 帧序列）
	if anim_state == AnimState.IDLE:
		if _idle_frames.is_empty():
			return
		anim_frame = (anim_frame + 1) % _idle_frames.size()
		sprite.texture = _idle_frames[anim_frame]
		return
	if _frames.is_empty():
		return
	# 配置了 WALK_INTERMITTENT 的敌人由 _tick_walk_intermittent_anim 推进 walk 帧，跳过默认推进
	if WALK_INTERMITTENT.has(enemy_type):
		return
	anim_frame = (anim_frame + 1) % _frames.size()
	sprite.texture = _frames[anim_frame]

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
			sprite.texture = _frames[0]
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
			sprite.texture = _frames[0]
			_walk_intermittent_playing = false
			_walk_intermittent_timer = 0.0
			return true   # 立刻进入立定
		sprite.texture = _frames[anim_frame]
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
