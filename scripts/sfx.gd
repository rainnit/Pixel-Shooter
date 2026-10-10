extends Node
## 零素材音效：运行时 PCM 合成（移植自 HTML 原型的 WebAudio 方案）。
## 用法：const SfxLib := preload("res://scripts/sfx.gd") 然后 SfxLib.new() 加入场景树。

const RATE := 22050

## 把 float 采样写成 16-bit WAV 流
static func _wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.stereo = false
	s.data = data
	return s

## 扫频音。kind: "sine" | "square" | "saw" | "tri"
static func synth_tone(f0: float, f1: float, dur: float, kind: String, vol: float) -> AudioStreamWAV:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / float(n)
		var f: float = lerpf(f0, f1, t)
		phase += TAU * f / RATE
		var s := 0.0
		match kind:
			"square":
				s = signf(sin(phase)) * 0.55
			"saw":
				s = fposmod(phase / TAU, 1.0) * 2.0 - 1.0
			"tri":
				s = absf(fposmod(phase / TAU, 1.0) - 0.5) * 4.0 - 1.0
			_:
				s = sin(phase)
		# 指数衰减包络，结尾自然归零
		var env := pow(0.0002, t)
		out[i] = s * env * vol
	return _wav(out)

## 白噪声（爆炸用）
static func synth_noise(dur: float, vol: float) -> AudioStreamWAV:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / float(n)
		out[i] = randf_range(-1.0, 1.0) * pow(0.004, t) * vol
	return _wav(out)

# ---------------- 播放器轮播 ----------------
var _players: Array = []
var _idx := 0
var _cache := {}

func _ready() -> void:
	for i in 10:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_players.append(p)

func _exit_tree() -> void:
	stop_all()

## 停止所有播放（不销毁池子，之后还能继续用）
func stop_all() -> void:
	for p in _players:
		p.stop()

func _play(key: String, stream: AudioStreamWAV, volume_db := 0.0) -> void:
	if not _cache.has(key):
		_cache[key] = stream
	var p: AudioStreamPlayer = _players[_idx]
	_idx = (_idx + 1) % _players.size()
	p.stream = _cache[key]
	p.volume_db = volume_db
	p.play()

func _tone(key: String, f0: float, f1: float, dur: float, kind: String, vol: float) -> void:
	_play(key, synth_tone(f0, f1, dur, kind, vol))

# ---- 具名音效（与 HTML 原型一一对应） ----
func shoot() -> void:
	# 三档随机音高，连射不单调
	match randi_range(0, 2):
		0: _tone("shoot0", 720, 210, 0.07, "square", 0.05)
		1: _tone("shoot1", 780, 230, 0.07, "square", 0.05)
		2: _tone("shoot2", 840, 250, 0.07, "square", 0.05)

func hit() -> void:
	_tone("hit", 320, 180, 0.05, "square", 0.07)

func boom(combo_n := 0) -> void:
	_play("boom_n", synth_noise(0.28, 0.22))
	# 连击越高爆炸音调越高，越杀越上头
	var lv := mini(combo_n, 8)
	var pitch := 1.0 + lv * 0.06
	_tone("boom_t%d" % lv, 150.0 * pitch, 38.0 * pitch, 0.30, "saw", 0.20)

func hurt() -> void:
	_tone("hurt", 200, 70, 0.25, "saw", 0.20)

func pick() -> void:
	_tone("pick", 520, 1040, 0.12, "tri", 0.12)

func wave() -> void:
	_tone("wave1", 330, 660, 0.18, "tri", 0.12)
	_tone("wave2", 660, 990, 0.18, "tri", 0.10)

func over() -> void:
	_tone("over", 330, 60, 0.9, "saw", 0.20)
