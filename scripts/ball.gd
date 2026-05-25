extends CharacterBody2D
class_name Ball

const ROLL_TIME := 2.0
const GRAVITY := 4000.0
const ROLL_SPEED := 1500.0
# 团状翻滚每秒旋转弧度（基础值；最终方向由飞行方向决定符号）
const ROLL_SPIN_SPEED := TAU * 2.0  # 2 圈/秒
# 团状形态视觉缩放：由 CharTuning.ball_sprite_scale 控制（F1 调参面板可实时调节）

# 按 Enemy.Type enum 映射团状翻滚贴图
# 0=METEOR_HAMMER, 1=RED_GHOST, 2=RED_DEVIL, 3=PALACE_ZOMBIE
const LAUNCHED_TEX := {
	0: "res://assets/sprites/Enemy/MeteorHammer/MeteorHammer_launched/MeteorHammer_launched.png",
	1: "res://assets/sprites/Enemy/RedGhost/RedGhost_launched/RedGhost_launched.png",
	2: "res://assets/sprites/Enemy/RedDevil/RedDevil_launched/RedDevil_launched.png",
	3: "res://assets/sprites/Enemy/PalaceZombie/PalaceZombie_launched/PalaceZombie_launched.png",
}

const PICKUP_SCENE = preload("res://scenes/pickup.tscn")

var roll_timer: float = ROLL_TIME
var enemy_type: int = 0
var direction: int = 1
var capture_count: int = 1
var already_hit: Array = []

@onready var sprite: Sprite2D = $Sprite
@onready var hit_area: Area2D = $HitArea

func _ready() -> void:
	hit_area.body_entered.connect(_on_hit_body)
	# 监听调参变化，实时同步 sprite scale
	CharTuning.tuning_changed.connect(_apply_tuning)

func _apply_tuning() -> void:
	var s: float = CharTuning.ball_sprite_scale
	sprite.scale = Vector2(s, s)

func launch(initial_velocity: Vector2, captured_type: int, captures: int = 1) -> void:
	velocity = initial_velocity
	enemy_type = captured_type
	direction = 1 if initial_velocity.x >= 0.0 else -1
	capture_count = clampi(captures, 1, 3)
	if LAUNCHED_TEX.has(captured_type):
		sprite.texture = load(LAUNCHED_TEX[captured_type])
	_apply_tuning()
	# 初始旋转角度随机（0 ~ 2π）
	sprite.rotation = randf() * TAU

func _physics_process(delta: float) -> void:
	roll_timer -= delta
	if roll_timer <= 0.0:
		queue_free()
		return
	velocity.y += GRAVITY * delta
	velocity.x = ROLL_SPEED * direction
	move_and_slide()
	if is_on_wall():
		direction = -direction
	# 团状翻滚：sprite 持续旋转，方向跟随飞行方向（右飞顺时针，左飞逆时针）
	sprite.rotation += ROLL_SPIN_SPEED * direction * delta

func _on_hit_body(body: Node) -> void:
	if body is Enemy and not body.dying and not body.is_captured and not already_hit.has(body):
		already_hit.append(body)
		# 每个被滚动 ball 撞死的敌人只爆 1 枚铜钱
		_drop_coin(body.global_position)
		body.die()

func _drop_coin(at: Vector2) -> void:
	var parent = get_parent()
	if parent == null:
		return
	var coin = PICKUP_SCENE.instantiate()
	coin.pickup_type = Pickup.Type.COIN
	parent.add_child(coin)
	# 在敌人位置生成铜钱；铜钱自身有重力 + 地面探测，会自动落到正下方最近的平台/地面上
	# （即使敌人当时在空中、悬崖边、平台上方多层结构等情况都能正确处理）
	coin.global_position = at
