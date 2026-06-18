extends Sprite2D

# 炮弹爆炸序列帧播放器：逐帧切换 Explode_01~10，播完自动移除。
# 独立于炮弹存在，因此炮弹消失后爆炸仍能完整播放。

var _frames: Array = []
var _frame_time: float = 0.05
var _accum: float = 0.0
var _idx: int = 0

func start(frames: Array, frame_time: float) -> void:
	_frames = frames
	_frame_time = maxf(0.001, frame_time)
	_idx = 0
	if _frames.is_empty():
		queue_free()
		return
	texture = _frames[0]
	set_process(true)

func _process(delta: float) -> void:
	if _frames.is_empty():
		queue_free()
		return
	_accum += delta
	while _accum >= _frame_time:
		_accum -= _frame_time
		_idx += 1
		if _idx >= _frames.size():
			queue_free()
			return
		texture = _frames[_idx]
