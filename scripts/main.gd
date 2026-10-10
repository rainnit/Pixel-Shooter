extends Node2D
## ============================================================
## 霓虹竞技场 · 2D 射击生存 MVP（Godot 4 版）
## 手感参数与玩法逻辑从 HTML 原型 1:1 移植：
## 移动带加速度/摩擦、命中白闪+火花、击杀爆炸粒子+冲击波环、
## 顿帧、震屏、枪口火光+后坐力、掉落吸取、波次递进。
## 单文件驱动（场景/粒子/HUD 全部代码生成），后续再拆分。
## ============================================================

const SfxLib := preload("res://scripts/sfx.gd")

# ---------------- 手感参数（与 HTML 原型一致） ----------------
const PLAYER_SPEED := 340.0   # 走路速度上限（像素/秒）
const PLAYER_R := 13.0        # 玩家半径
const ACCEL := 15.0           # 加速度倍率（调高 = 起步/变向更跟手）
const FRICTION := 0.00008     # 指数摩擦（调低 = 停得更快、变向更利落）
const BULLET_SPEED := 780.0
const FIRE_CD := 0.095        # 基础射速间隔（加 快：0.13 → 0.095）
const FIRE_CD_RAPID := 0.055  # 速射间隔
const MAX_HP := 5
const FREEZE_TIME := 0.06     # 击杀顿帧（加长，反馈更强）
const FREEZE_TIME_BIG := 0.10
const HIT_FREEZE := 0.014     # 命中微顿帧
const COMBO_WINDOW := 1.6     # 连击窗口（秒）
const AIM_ASSIST_RAD := 0.14  # 瞄准吸附角（约 8°，调小 = 鼠标跟手）

# ---------------- 敌人类型 ----------------
var TYPES := {
	"grunt": {"r": 15.0, "hp": 2, "speed": 120.0, "color": Color("#ff5c5c"), "score": 10, "kind": "square"},
	"swift": {"r": 11.0, "hp": 1, "speed": 215.0, "color": Color("#ffb020"), "score": 15, "kind": "tri"},
	"brute": {"r": 27.0, "hp": 7, "speed": 68.0, "color": Color("#b06cff"), "score": 40, "kind": "hex"},
}

# ---------------- 状态 ----------------
enum Phase { MENU, PLAY, PAUSE, OVER }

var phase: int = Phase.MENU
var time := 0.0
var score := 0
var wave := 1
var hp := MAX_HP
var invuln := 0.0
var freeze := 0.0
var shake := 0.0
var flash := 0.0
var fire_cd := 0.0
var rapid_t := 0.0        # 速射剩余时间（秒），0 = 未激活
var spread_t := 0.0       # 散射剩余时间（秒），可与速射同时生效
var spawn_left := 0
var spawn_t := 0.0
var inter_t := 0.0
var best := 0
var banner_t := 0.0
var prev_mouse_down := false
var combo_n := 0
var combo_t := 0.0
var max_combo := 0
var zoom_punch := 0.0     # 击杀镜头缩放拳
var flash_col := Color(1.0, 0.3, 0.25)  # 全屏闪色（受伤红 / 击杀白）

var player := {"x": 0.0, "y": 0.0, "vx": 0.0, "vy": 0.0, "recoil": 0.0, "aim": 0.0}
var bullets: Array = []
var enemies: Array = []
var parts: Array = []
var rings: Array = []
var texts: Array = []
var pickups: Array = []
var marks: Array = []
var decals: Array = []    # 击杀尸痕（地面淡出色块）
var hitmarks: Array = []  # 命中十字标记

var cam: Camera2D
var sfx                  # SFX.Bus
var lbl_hp: Label
var lbl_wp: Label
var lbl_score: Label
var lbl_best: Label
var lbl_combo: Label
var lbl_wave: Label
var lbl_banner: Label
var lbl_menu: Label
var flash_rect: ColorRect


func _ready() -> void:
	randomize()
	cam = Camera2D.new()
	add_child(cam)
	cam.make_current()
	sfx = SfxLib.new()
	add_child(sfx)
	_build_hud()
	_load_best()
	_reset()
	phase = Phase.MENU
	_show_menu()


# ---------------- HUD（CanvasLayer + Label，代码生成） ----------------
func _mk_label(size: int, color: Color, h_align: int) -> Label:
	var l := Label.new()
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.horizontal_alignment = h_align
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	flash_rect = ColorRect.new()
	flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash_rect.color = Color(1, 0.3, 0.25, 0.0)
	flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(flash_rect)

	lbl_hp = _mk_label(20, Color("#ff8a8a"), HORIZONTAL_ALIGNMENT_LEFT)
	lbl_hp.offset_left = 18
	lbl_hp.offset_top = 14
	layer.add_child(lbl_hp)

	lbl_wp = _mk_label(14, Color("#7fe0ff"), HORIZONTAL_ALIGNMENT_LEFT)
	lbl_wp.offset_left = 18
	lbl_wp.offset_top = 46
	layer.add_child(lbl_wp)

	lbl_score = _mk_label(28, Color("#ffe08a"), HORIZONTAL_ALIGNMENT_CENTER)
	lbl_score.offset_top = 12
	layer.add_child(lbl_score)

	lbl_best = _mk_label(13, Color("#5d7290"), HORIZONTAL_ALIGNMENT_CENTER)
	lbl_best.offset_top = 50
	layer.add_child(lbl_best)

	lbl_combo = _mk_label(20, Color("#ffb020"), HORIZONTAL_ALIGNMENT_CENTER)
	lbl_combo.offset_top = 84
	layer.add_child(lbl_combo)

	lbl_wave = _mk_label(17, Color("#8fa8c8"), HORIZONTAL_ALIGNMENT_RIGHT)
	lbl_wave.offset_right = -20
	lbl_wave.offset_top = 16
	layer.add_child(lbl_wave)

	lbl_banner = _mk_label(42, Color("#7fe0ff"), HORIZONTAL_ALIGNMENT_CENTER)
	lbl_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl_banner.modulate.a = 0.0
	layer.add_child(lbl_banner)

	lbl_menu = _mk_label(24, Color("#cfe3ff"), HORIZONTAL_ALIGNMENT_CENTER)
	lbl_menu.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	layer.add_child(lbl_menu)

func _show_menu() -> void:
	lbl_menu.text = "霓 虹 竞 技 场\n\nWASD 移动 · 鼠标瞄准 · 自动开火（不用按键！）\n1.6 秒内连杀有连击加成，最高 x5\n击杀掉落：粉圈回血 · 黄圈速射 · 蓝圈散射\n\n按 空格 或 点击 开始 · P 暂停 · R 重开"
	lbl_menu.visible = true

func banner(text: String) -> void:
	lbl_banner.text = text
	lbl_banner.modulate.a = 1.0
	banner_t = 1.4


# ---------------- 流程 ----------------
func _load_best() -> void:
	var cf := ConfigFile.new()
	if cf.load("user://best.cfg") == OK:
		best = int(cf.get_value("s", "best", 0))

func _save_best() -> void:
	var cf := ConfigFile.new()
	cf.set_value("s", "best", best)
	cf.save("user://best.cfg")

func _reset() -> void:
	bullets.clear(); enemies.clear(); parts.clear()
	rings.clear(); texts.clear(); pickups.clear(); marks.clear()
	decals.clear(); hitmarks.clear()
	combo_n = 0; combo_t = 0.0; max_combo = 0; zoom_punch = 0.0
	time = 0.0; score = 0; wave = 1; hp = MAX_HP
	invuln = 0.0; freeze = 0.0; shake = 0.0; flash = 0.0
	fire_cd = 0.0; rapid_t = 0.0; spread_t = 0.0
	spawn_left = 0; spawn_t = 0.0; inter_t = 0.0
	player.x = get_viewport_rect().size.x * 0.5
	player.y = get_viewport_rect().size.y * 0.5
	player.vx = 0.0; player.vy = 0.0; player.recoil = 0.0
	_update_hud()
	start_wave(1)

func _start() -> void:
	lbl_menu.visible = false
	_reset()
	phase = Phase.PLAY

func _pause() -> void:
	phase = Phase.PAUSE
	banner("已暂停 · 按 P 继续")
	banner_t = 9999.0

func _resume() -> void:
	phase = Phase.PLAY
	lbl_banner.modulate.a = 0.0
	banner_t = 0.0

func game_over() -> void:
	phase = Phase.OVER
	_burst(player.x, player.y, Color("#35c4ff"), 40, 500.0, 0.9, 5.0)
	_ring(player.x, player.y, Color("#35c4ff"), 260.0, 0.7, 5.0)
	shake = 16.0
	if score > best:
		best = score
		_save_best()
	lbl_menu.text = "阵 亡\n\n得分 %d · 波次 %d · 存活 %.0f 秒 · 最高连杀 x%d\n最高纪录 %d\n\n按 R 再来一局" % [score, wave, time, max_combo, best]
	lbl_menu.visible = true
	sfx.over()

func start_wave(n: int) -> void:
	wave = n
	spawn_left = 4 + n * 2 + (n - 4 if n >= 5 else 0)
	spawn_t = 0.0
	banner("第 %d 波" % n)
	sfx.wave()


# ---------------- 输入 ----------------
func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match phase:
			Phase.MENU:
				if event.keycode in [KEY_SPACE, KEY_ENTER]:
					_start()
			Phase.PLAY:
				if event.keycode == KEY_P:
					_pause()
			Phase.PAUSE:
				if event.keycode == KEY_P:
					_resume()
			Phase.OVER:
				if event.keycode == KEY_R:
					_start()


# ---------------- 主循环 ----------------
func _process(delta: float) -> void:
	if banner_t > 0.0:
		banner_t -= delta
		if banner_t <= 0.0 and phase != Phase.PAUSE:
			lbl_banner.modulate.a = 0.0

	match phase:
		Phase.MENU:
			var down := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
			if down and not prev_mouse_down:
				_start()
			prev_mouse_down = down
		Phase.PLAY:
			var dt := delta
			if freeze > 0.0:
				dt *= 0.12   # 击杀顿帧：世界瞬间变慢
			freeze = maxf(0.0, freeze - delta)
			_update(dt)
		Phase.OVER:
			_decay_particles(delta)

	shake = maxf(0.0, shake - delta * 30.0)
	flash = maxf(0.0, flash - delta)
	# 世界坐标 = 屏幕坐标（原点在左上角），相机永远对准视口中心
	cam.position = get_viewport_rect().size * 0.5
	if shake > 0.1:
		cam.offset = Vector2(randf_range(-shake, shake), randf_range(-shake, shake))
	else:
		cam.offset = Vector2.ZERO
	# 击杀镜头缩放拳：瞬间放大再弹回
	zoom_punch *= pow(0.002, delta)
	cam.zoom = Vector2.ONE * (1.0 + zoom_punch)
	flash_rect.color = Color(flash_col.r, flash_col.g, flash_col.b, flash * 0.35)
	# 残血警示：呼吸红光
	if phase == Phase.PLAY and hp <= 2:
		flash_rect.color.a = maxf(flash_rect.color.a, 0.05 + 0.04 * sin(time * 6.0))
	queue_redraw()


# ---------------- 更新 ----------------
func _update(dt: float) -> void:
	time += dt
	var vs := get_viewport_rect().size

	# ---- 玩家移动：加速度 + 指数摩擦 ----
	var iv := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT): iv.x += 1
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT): iv.x -= 1
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN): iv.y += 1
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP): iv.y -= 1
	if iv.length_squared() > 1.0:
		iv = iv.normalized()
	player.vx += iv.x * PLAYER_SPEED * ACCEL * dt
	player.vy += iv.y * PLAYER_SPEED * ACCEL * dt
	var fr := pow(FRICTION, dt)
	player.vx *= fr; player.vy *= fr
	var sp := Vector2(player.vx, player.vy).length()
	if sp > PLAYER_SPEED:
		var k := PLAYER_SPEED / sp
		player.vx *= k; player.vy *= k
	player.x = clampf(player.x + player.vx * dt, PLAYER_R, vs.x - PLAYER_R)
	player.y = clampf(player.y + player.vy * dt, PLAYER_R, vs.y - PLAYER_R)
	player.recoil = maxf(0.0, player.recoil - dt * 40.0)
	# ---- 瞄准：鼠标方向 + 轻微吸附（附近有敌人时帮你纠偏） ----
	var mouse_aim: float = (get_global_mouse_position() - Vector2(player.x, player.y)).angle()
	var best_ang := mouse_aim
	var best_diff := AIM_ASSIST_RAD
	for e in enemies:
		if e.dead:
			continue
		var to_e := Vector2(e.x - player.x, e.y - player.y)
		if to_e.length() > 620.0:
			continue
		var diff: float = absf(wrapf(to_e.angle() - mouse_aim, -PI, PI))
		if diff < best_diff:
			best_diff = diff
			best_ang = to_e.angle()
	player.aim = best_ang
	invuln = maxf(0.0, invuln - dt)

	# ---- 连击窗口倒数 ----
	if combo_n > 0:
		combo_t -= dt
		if combo_t <= 0.0:
			combo_n = 0
			_update_hud()

	# 移动尘埃
	if sp > 120.0 and randf() < dt * 22.0:
		parts.append({
			"x": player.x - player.vx * 0.02, "y": player.y - player.vy * 0.02,
			"vx": randf_range(-30, 30), "vy": randf_range(-30, 30),
			"life": 0.3, "max": 0.3, "size": 2.0, "color": Color("#2c4a6e"), "drag": 3.0,
		})

	# ---- 自动开火：手指彻底退休，鼠标只管瞄准 ----
	fire_cd -= dt
	if fire_cd <= 0.0:
		_shoot()
	rapid_t = maxf(0.0, rapid_t - dt)
	spread_t = maxf(0.0, spread_t - dt)
	_update_hud()

	# ---- 波次推进 ----
	if spawn_left > 0:
		spawn_t -= dt
		if spawn_t <= 0.0:
			_spawn_enemy(_pick_type())
			spawn_left -= 1
			spawn_t = maxf(0.12, 0.85 - wave * 0.05) * randf_range(0.6, 1.4)
	elif marks.is_empty() and enemies.is_empty():
		inter_t += dt
		if inter_t > 2.2:
			inter_t = 0.0
			start_wave(wave + 1)
	for i in range(marks.size() - 1, -1, -1):
		var mk: Dictionary = marks[i]
		mk.t -= dt
		if mk.t <= 0.0:
			_realize(mk)
			marks.remove_at(i)

	# ---- 子弹 ----
	for i in range(bullets.size() - 1, -1, -1):
		var b: Dictionary = bullets[i]
		b.px = b.x; b.py = b.y
		b.x += b.vx * dt; b.y += b.vy * dt
		b.life -= dt
		if b.life <= 0.0 or b.x < -20.0 or b.x > vs.x + 20.0 or b.y < -20.0 or b.y > vs.y + 20.0:
			bullets.remove_at(i)
			continue
		for e in enemies:
			if e.dead:
				continue
			if (b.x - e.x) * (b.x - e.x) + (b.y - e.y) * (b.y - e.y) < (e.r + 4.0) * (e.r + 4.0):
				_hit_enemy(e, b.x, b.y)
				bullets.remove_at(i)
				break

	# ---- 敌人：追玩家 + 蛇皮走位 ----
	for e in enemies:
		if e.dead:
			continue
		e.flash = maxf(0.0, e.flash - dt)
		var dx: float = player.x - e.x
		var dy: float = player.y - e.y
		var d := Vector2(dx, dy).length()
		e.wobble += dt * 3.0
		var ang: float = atan2(dy, dx) + sin(e.wobble) * 0.2
		e.vx += (cos(ang) * e.speed - e.vx) * dt * 4.0
		e.vy += (sin(ang) * e.speed - e.vy) * dt * 4.0
		e.x += e.vx * dt; e.y += e.vy * dt
		if d < e.r + PLAYER_R:
			_hurt_player(e.x, e.y)

	# ---- 敌人两两排斥，防止叠成一坨 ----
	for i in range(enemies.size()):
		var a: Dictionary = enemies[i]
		if a.dead: continue
		for j in range(i + 1, enemies.size()):
			var b2: Dictionary = enemies[j]
			if b2.dead: continue
			var dx2: float = b2.x - a.x
			var dy2: float = b2.y - a.y
			var min_d: float = a.r + b2.r
			var d2 := dx2 * dx2 + dy2 * dy2
			if d2 > 0.01 and d2 < min_d * min_d:
				var dd := sqrt(d2)
				var push := (min_d - dd) / dd * 0.5
				a.x -= dx2 * push; a.y -= dy2 * push
				b2.x += dx2 * push; b2.y += dy2 * push
	enemies = enemies.filter(func(e): return not e.dead)

	# ---- 掉落物：靠近自动吸取 ----
	for i in range(pickups.size() - 1, -1, -1):
		var p: Dictionary = pickups[i]
		p.t += dt
		var pdx: float = player.x - p.x
		var pdy: float = player.y - p.y
		var pd := Vector2(pdx, pdy).length()
		if pd < 90.0 and pd > 0.01:
			p.x += pdx / pd * 260.0 * dt
			p.y += pdy / pd * 260.0 * dt
		if pd < PLAYER_R + 12.0:
			if p.kind == "heal":
				hp = mini(MAX_HP, hp + 1)
				_float_text(p.x, p.y, "+1 HP", Color("#ff8a8a"))
			elif p.kind == "rapid":
				rapid_t = minf(30.0, rapid_t + 14.0)
				_float_text(p.x, p.y, "速射 %.0fs!" % rapid_t, Color("#7fe0ff"))
			else:
				spread_t = minf(30.0, spread_t + 16.0)
				_float_text(p.x, p.y, "散射 %.0fs!" % spread_t, Color("#7fe0ff"))
			_burst(p.x, p.y, Color.WHITE, 8, 200.0, 0.3, 3.0)
			sfx.pick()
			pickups.remove_at(i)
		elif p.t > 12.0:
			pickups.remove_at(i)

	_update_fx(dt)


func _decay_particles(dt: float) -> void:
	# 阵亡后只剩粒子飘完，_update_fx 一手包办
	_update_fx(dt)

func _update_fx(dt: float) -> void:
	for i in range(parts.size() - 1, -1, -1):
		var p: Dictionary = parts[i]
		p.life -= dt
		if p.life <= 0.0:
			parts.remove_at(i); continue
		var dr := pow(0.02, dt * p.drag)
		p.vx *= dr; p.vy *= dr
		p.x += p.vx * dt; p.y += p.vy * dt
	for i in range(rings.size() - 1, -1, -1):
		var r: Dictionary = rings[i]
		r.life -= dt
		if r.life <= 0.0:
			rings.remove_at(i); continue
		var t: float = 1.0 - r.life / r.max_life
		r.r = 6.0 + (r.max_r - 6.0) * (1.0 - pow(1.0 - t, 3.0))
	for i in range(decals.size() - 1, -1, -1):
		var dcl: Dictionary = decals[i]
		dcl.life -= dt
		if dcl.life <= 0.0:
			decals.remove_at(i)
	for i in range(hitmarks.size() - 1, -1, -1):
		var hm: Dictionary = hitmarks[i]
		hm.life -= dt
		if hm.life <= 0.0:
			hitmarks.remove_at(i)
	for i in range(texts.size() - 1, -1, -1):
		var tx: Dictionary = texts[i]
		tx.life -= dt
		tx.y -= 46.0 * dt
		if tx.life <= 0.0:
			texts.remove_at(i)


# ---------------- 射击 / 伤害 ----------------
func _shoot() -> void:
	var spread := spread_t > 0.0
	var count := 5 if spread else 1
	fire_cd = FIRE_CD_RAPID if rapid_t > 0.0 else FIRE_CD
	for i in count:
		var off := 0.0
		if spread:
			off = (i - (count - 1) / 2.0) * 0.14
		else:
			off = randf_range(-0.02, 0.02)
		var a: float = player.aim + off
		var mx: float = player.x + cos(player.aim) * (PLAYER_R + 10.0)
		var my: float = player.y + sin(player.aim) * (PLAYER_R + 10.0)
		bullets.append({
			"x": mx, "y": my, "px": mx, "py": my,
			"vx": cos(a) * BULLET_SPEED, "vy": sin(a) * BULLET_SPEED, "life": 1.0,
		})
	# 枪口火光 + 后坐力
	var gx: float = player.x + cos(player.aim) * (PLAYER_R + 12.0)
	var gy: float = player.y + sin(player.aim) * (PLAYER_R + 12.0)
	_burst(gx, gy, Color("#ffe9a0"), 3, 180.0, 0.12, 3.0)
	player.recoil = 4.5
	player.vx -= cos(player.aim) * 26.0
	player.vy -= sin(player.aim) * 26.0
	shake = maxf(shake, 0.8)  # 自动开火后连射震屏要轻，不然晕
	sfx.shoot()

func _hit_enemy(e: Dictionary, bx: float, by: float) -> void:
	e.hp -= 1
	e.flash = 0.12
	_burst(bx, by, e.color, 9, 300.0, 0.35, 4.0)
	_burst(bx, by, Color.WHITE, 4, 340.0, 0.16, 2.2)
	freeze = maxf(freeze, HIT_FREEZE)
	shake = maxf(shake, 2.4)
	hitmarks.append({"x": bx, "y": by, "life": 0.12, "max": 0.12})
	var kb := 60.0 if e.etype == "brute" else 150.0
	var d := Vector2(e.x - bx, e.y - by).length()
	if d > 0.01:
		e.vx += (e.x - bx) / d * kb
		e.vy += (e.y - by) / d * kb
	if e.hp <= 0:
		_kill_enemy(e)
	else:
		sfx.hit()

func _kill_enemy(e: Dictionary) -> void:
	e.dead = true
	var big: bool = e.etype == "brute"
	_burst(e.x, e.y, e.color, 22 + int(e.r), 420.0, 0.6, 5.0)
	_burst(e.x, e.y, Color.WHITE, 8, 320.0, 0.3, 3.0)
	_ring(e.x, e.y, e.color, e.r * 5.0, 0.4, 4.0)
	_ring(e.x, e.y, Color.WHITE, e.r * 2.6, 0.25, 2.5)
	decals.append({"x": e.x, "y": e.y, "r": e.r * 1.4, "color": e.color, "life": 0.5, "max": 0.5})
	shake = maxf(shake, 13.0 if big else 7.0)
	freeze = maxf(freeze, FREEZE_TIME_BIG if big else FREEZE_TIME)
	zoom_punch = maxf(zoom_punch, 0.09 if big else 0.05)
	flash = maxf(flash, 0.10)
	flash_col = Color(1, 1, 1)
	# 连击：窗口内连杀，加成最高 5 倍
	combo_n += 1
	combo_t = COMBO_WINDOW
	max_combo = maxi(max_combo, combo_n)
	var mult := minf(1.0 + combo_n * 0.25, 5.0)
	var gain: int = int(e.score * (1 + wave / 3) * mult)
	score += gain
	_float_text(e.x, e.y - e.r, "+%d" % gain, Color("#ffe08a"))
	if combo_n >= 2:
		var cc := Color("#ffe08a") if combo_n < 4 else (Color("#ffb020") if combo_n < 7 else Color("#ff5c5c"))
		texts.append({"x": e.x, "y": e.y - e.r - 22.0, "str": "x%d 连杀" % combo_n,
			"color": cc, "life": 0.9, "max": 0.9, "big": true})
	sfx.boom(combo_n)
	var roll := randf()
	if roll < 0.10:
		pickups.append({"x": e.x, "y": e.y, "kind": "heal", "t": 0.0})
	elif roll < 0.20:
		# 掉落哪种武器道具：优先掉当前没激活的那种（双开时随机）
		var kind := "rapid"
		if rapid_t > 0.0 and spread_t <= 0.0:
			kind = "spread"
		elif spread_t > 0.0 and rapid_t <= 0.0:
			kind = "rapid"
		elif rapid_t > 0.0 and spread_t > 0.0:
			kind = "spread" if randf() < 0.5 else "rapid"
		pickups.append({"x": e.x, "y": e.y, "kind": kind, "t": 0.0})

func _hurt_player(fx: float, fy: float) -> void:
	if invuln > 0.0:
		return
	hp -= 1
	invuln = 1.0
	shake = maxf(shake, 14.0)
	flash = 0.4
	flash_col = Color(1.0, 0.3, 0.25)
	combo_n = 0   # 挨打断连击，风险换收益
	_burst(player.x, player.y, Color("#ff5c5c"), 14, 320.0, 0.5, 4.0)
	var d := Vector2(player.x - fx, player.y - fy).length()
	if d > 0.01:
		player.vx += (player.x - fx) / d * 380.0
		player.vy += (player.y - fy) / d * 380.0
	_update_hud()
	sfx.hurt()
	if hp <= 0:
		game_over()


# ---------------- 波次生成 ----------------
func _pick_type() -> String:
	var r := randf()
	if wave >= 3 and r < 0.12 + wave * 0.015:
		return "brute"
	if wave >= 2 and r < 0.45:
		return "swift"
	return "grunt"

func _spawn_enemy(type: String) -> void:
	# 屏幕外四边随机，先给 0.55s 预警圈再出现 —— 公平且有张力
	var side := randi_range(0, 3)
	var vs := get_viewport_rect().size
	var m := 40.0
	var x := 0.0
	var y := 0.0
	if side == 0:
		x = randf_range(0, vs.x); y = -m
	elif side == 1:
		x = vs.x + m; y = randf_range(0, vs.y)
	elif side == 2:
		x = randf_range(0, vs.x); y = vs.y + m
	else:
		x = -m; y = randf_range(0, vs.y)
	marks.append({"x": x, "y": y, "t": 0.55, "etype": type})

func _realize(mk: Dictionary) -> void:
	var t: Dictionary = TYPES[mk.etype]
	var hpv: int = t.hp + (wave / 3 if mk.etype == "brute" else 0)
	enemies.append({
		"etype": mk.etype, "shape": t.kind, "x": mk.x, "y": mk.y,
		"r": t.r, "hp": hpv, "max_hp": t.hp,
		"speed": t.speed * (1.0 + wave * 0.04),
		"color": t.color, "score": t.score,
		"vx": 0.0, "vy": 0.0, "flash": 0.0, "wobble": randf_range(0.0, TAU),
		"dead": false,
	})


# ---------------- 粒子工具 ----------------
func _burst(x: float, y: float, color: Color, n: int, speed: float, life: float, size: float) -> void:
	for i in n:
		var a := randf_range(0.0, TAU)
		var s := randf_range(speed * 0.3, speed)
		parts.append({
			"x": x, "y": y,
			"vx": cos(a) * s, "vy": sin(a) * s,
			"life": randf_range(life * 0.5, life), "max": life,
			"size": randf_range(size * 0.5, size), "color": color,
			"drag": randf_range(2.5, 5.0),
		})

func _ring(x: float, y: float, color: Color, max_r: float, life: float, width: float) -> void:
	rings.append({
		"x": x, "y": y, "r": 6.0, "max_r": max_r,
		"life": life, "max_life": life, "color": color, "width": width,
	})

func _float_text(x: float, y: float, str_val: String, color: Color) -> void:
	texts.append({"x": x, "y": y, "str": str_val, "color": color, "life": 0.8, "max": 0.8})


# ---------------- HUD 刷新 ----------------
func _update_hud() -> void:
	lbl_hp.text = "HP " + "●".repeat(maxi(0, hp)) + "○".repeat(maxi(0, MAX_HP - hp))
	var wp_bits: PackedStringArray = []
	if rapid_t > 0.0:
		wp_bits.append("速射 %.1fs" % rapid_t)
	if spread_t > 0.0:
		wp_bits.append("散射 %.1fs" % spread_t)
	lbl_wp.text = "  ·  ".join(wp_bits)
	lbl_score.text = str(score)
	lbl_best.text = "最高 %d" % best
	lbl_wave.text = "WAVE %d" % wave
	lbl_combo.text = ("x%d 连杀" % combo_n) if combo_n >= 2 else ""


# ---------------- 渲染 ----------------
func _draw() -> void:
	var vs := get_viewport_rect().size

	# 背景与网格
	draw_rect(Rect2(-40, -40, vs.x + 80, vs.y + 80), Color("#07090f"))
	var grid_c := Color(0.24, 0.35, 0.55, 0.10)
	var step := 56.0
	var gx := 0.0
	while gx < vs.x:
		draw_line(Vector2(gx, 0), Vector2(gx, vs.y), grid_c, 1.0)
		gx += step
	var gy := 0.0
	while gy < vs.y:
		draw_line(Vector2(0, gy), Vector2(vs.x, gy), grid_c, 1.0)
		gy += step

	# 尸痕（击杀地面淡出色块）
	for dcl in decals:
		var da: float = clampf(dcl.life / dcl.max, 0.0, 1.0)
		var dc: Color = dcl.color
		dc.a = da * 0.22
		draw_circle(Vector2(dcl.x, dcl.y), dcl.r, dc)

	# 生成预警圈（闪烁收缩）
	for mk in marks:
		var t: Dictionary = TYPES[mk.etype]
		var mx: float = clampf(mk.x, 20.0, vs.x - 20.0)
		var my: float = clampf(mk.y, 20.0, vs.y - 20.0)
		var a := 0.4 + 0.4 * sin(mk.t * 25.0)
		draw_arc(Vector2(mx, my), 10.0 + mk.t * 22.0, 0, TAU, 32,
			Color(t.color.r, t.color.g, t.color.b, a), 2.0)

	# 掉落物（几何图形 + 色环）
	for p in pickups:
		var pulse := 1.0 + sin(p.t * 6.0) * 0.15
		var pc := Color("#ff6b8a") if p.kind == "heal" else (Color("#ffd257") if p.kind == "rapid" else Color("#7fe0ff"))
		draw_arc(Vector2(p.x, p.y), 11.0 * pulse, 0, TAU, 24, pc, 2.0)
		if p.kind == "heal":   # 十字
			draw_rect(Rect2(p.x - 6, p.y - 2, 12, 4), pc)
			draw_rect(Rect2(p.x - 2, p.y - 6, 4, 12), pc)
		elif p.kind == "rapid":  # 闪电三角
			draw_colored_polygon(PackedVector2Array([
				Vector2(p.x, p.y - 7), Vector2(p.x + 5, p.y + 5), Vector2(p.x - 5, p.y + 5)]), pc)
		else:                  # 三向星
			for k in 3:
				var a2: float = k * TAU / 3.0 + p.t * 2.0
				draw_line(Vector2(p.x, p.y),
					Vector2(p.x + cos(a2) * 7.0, p.y + sin(a2) * 7.0), pc, 2.5)

	# 粒子（发光小方块，透明度随寿命衰减）
	for p in parts:
		var a3: float = clampf(p.life / p.max, 0.0, 1.0)
		var s: float = p.size * (0.5 + a3 * 0.5)
		var c: Color = p.color
		c.a = a3
		# 外圈半透明放大一版，冒充辉光
		c2_glow(c, s, p.x, p.y)
		draw_rect(Rect2(p.x - s / 2, p.y - s / 2, s, s), c)

	# 冲击波环
	for r in rings:
		var a4: float = clampf(r.life / r.max_life, 0.0, 1.0)
		var rc: Color = r.color
		rc.a = a4 * 0.9
		draw_arc(Vector2(r.x, r.y), r.r, 0, TAU, 40, rc, maxf(0.5, r.width * a4))

	# 敌人
	for e in enemies:
		var pos := Vector2(e.x, e.y)
		var body_c: Color = Color.WHITE if e.flash > 0.0 else e.color
		# 底光
		draw_circle(pos, e.r * 1.5, Color(e.color.r, e.color.g, e.color.b, 0.12))
		# 血条
		if e.hp < e.max_hp:
			draw_rect(Rect2(e.x - e.r, e.y - e.r - 10, e.r * 2, 4), Color(0, 0, 0, 0.5))
			draw_rect(Rect2(e.x - e.r, e.y - e.r - 10, e.r * 2 * float(e.hp) / float(e.max_hp), 4), Color("#ff6b5c"))
		match e.shape:
			"square":
				var wob := sin(e.wobble * 2.0) * 0.12
				draw_set_transform(pos, wob, Vector2.ONE)
				draw_rect(Rect2(-e.r, -e.r, e.r * 2, e.r * 2), body_c)
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			"tri":
				var ta := atan2(player.y - e.y, player.x - e.x)
				draw_set_transform(pos, ta, Vector2.ONE)
				draw_colored_polygon(PackedVector2Array([
					Vector2(e.r * 1.3, 0), Vector2(-e.r, e.r * 0.8), Vector2(-e.r, -e.r * 0.8)]), body_c)
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			_:
				var pts := PackedVector2Array()
				for k in 6:
					var ha: float = k * TAU / 6.0
					pts.append(Vector2(cos(ha) * e.r, sin(ha) * e.r))
				draw_colored_polygon(pts, body_c)

	# 子弹（拖尾）
	for b in bullets:
		draw_line(Vector2(b.px, b.py), Vector2(b.x, b.y),
			Color(1.0, 0.88, 0.5, 0.35), 8.0)
		draw_line(Vector2(b.px, b.py), Vector2(b.x, b.y),
			Color("#ffe9a0"), 5.0)

	# 命中十字标记
	for hm in hitmarks:
		var hma: float = clampf(hm.life / hm.max, 0.0, 1.0)
		var hmc := Color(1, 1, 1, hma)
		for k2 in 4:
			var ang2: float = k2 * TAU / 4.0 + 0.785
			var dirv := Vector2(cos(ang2), sin(ang2))
			draw_line(Vector2(hm.x, hm.y) + dirv * 5.0,
				Vector2(hm.x, hm.y) + dirv * 10.0, hmc, 2.0)

	# 玩家（无敌闪烁）
	if not (invuln > 0.0 and fmod(time * 16.0, 2.0) < 1.0):
		var ppos := Vector2(player.x, player.y)
		draw_circle(ppos, PLAYER_R * 1.7, Color(0.21, 0.77, 1.0, 0.12))
		# 枪管
		draw_set_transform(ppos, player.aim, Vector2.ONE)
		draw_rect(Rect2(PLAYER_R - 2.0 - player.recoil, -2.5, 14.0, 5.0), Color("#9fd8ff"))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		# 身体
		draw_circle(ppos, PLAYER_R, Color("#35c4ff"))
		draw_arc(ppos, PLAYER_R, 0, TAU, 32, Color(1, 1, 1, 0.85), 2.0)
		# 朝向点
		draw_circle(ppos + Vector2(cos(player.aim), sin(player.aim)) * (PLAYER_R + 4.0), 2.0, Color.WHITE)

	# 飞字
	var font := ThemeDB.fallback_font
	for tx in texts:
		var a5: float = clampf(tx.life / tx.max, 0.0, 1.0)
		var tc: Color = tx.color
		tc.a = a5
		var fs: int = 22 if tx.get("big", false) else 15
		draw_string(font, Vector2(tx.x - 80, tx.y), tx.str,
			HORIZONTAL_ALIGNMENT_CENTER, 160, fs, tc)

func c2_glow(c: Color, s: float, x: float, y: float) -> void:
	var g := c
	g.a = c.a * 0.25
	draw_rect(Rect2(x - s, y - s, s * 2, s * 2), g)
