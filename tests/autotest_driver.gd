extends Node
## 自动测试驾驶员：确定性注入 + 有机冒烟，校验游戏关键路径。
## 由 tests/autotest.gd（SceneTree 脚本）挂载，仅用于自测，不进游戏。

var main: Node
var frame := 0
var errors: Array = []
var held_keys: Array = []
var kill_score_before := 0
var kill_target: Dictionary = {}
var pause_score := -1
var max_bullets := 0
var max_enemies := 0

const DIRS := [
	[KEY_W, 0], [KEY_D, 0], [KEY_S, 0], [KEY_A, 0],
	[KEY_W, KEY_D], [KEY_S, KEY_D], [KEY_S, KEY_A], [KEY_W, KEY_A],
]

func check(cond: bool, msg: String) -> void:
	if not cond:
		errors.append(msg)
		print("[autotest] FAIL: " + msg)

func _key(code: int, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = code as Key
	ev.keycode = code as Key
	ev.pressed = pressed
	Input.parse_input_event(ev)

func _move_mouse(pos: Vector2) -> void:
	var mm := InputEventMouseMotion.new()
	mm.position = pos
	mm.global_position = pos
	Input.parse_input_event(mm)

func _release_all() -> void:
	for k in held_keys:
		_key(k, false)
	held_keys.clear()

func _aim_nearest() -> void:
	# 瞄最近的敌人（带人类误差），没敌人就画圈甩
	var t := float(frame) * 0.05
	var target := Vector2(main.player.x, main.player.y) \
		+ Vector2(cos(t), sin(t)) * 260.0
	var nd := 1e12
	var nearest: Dictionary = {}
	for e in main.enemies:
		if e.dead:
			continue
		var d: float = Vector2(e.x - main.player.x, e.y - main.player.y).length()
		if d < nd:
			nd = d
			nearest = e
	if not nearest.is_empty():
		target = Vector2(nearest.x, nearest.y) \
			+ Vector2(randf_range(-15, 15), randf_range(-15, 15))
	_move_mouse(target)

func _process(_dt: float) -> void:
	frame += 1
	var vs: Vector2 = main.get_viewport_rect().size

	if frame == 5:
		main._start()
		check(main.phase == 1, "开局后应进入 PLAY 阶段")  # Phase.PLAY == 1

	# 有机游玩：每 45 帧换方向，鼠标瞄最近敌人
	if frame % 45 == 0 and frame < 1400:
		_release_all()
		var dir: Array = DIRS[(frame / 45) % DIRS.size()]
		for k in dir:
			_key(k, true)
			held_keys.append(k)
	_aim_nearest()

	if frame == 300:
		check(main.player.x != vs.x * 0.5 or main.player.y != vs.y * 0.5,
			"移动 5 秒后玩家应已离开出生点")

	# ---- 确定性测试 1：掉落吸取 + 武器生效 ----
	if frame == 640:
		main.pickups.append({"x": main.player.x, "y": main.player.y, "kind": "rapid", "t": 0.0})
	if frame == 700:
		check(main.rapid_t > 0.0, "掉落物应被吸取且速射生效")

	# ---- 确定性测试 1b：散射与速射可同时叠加 ----
	if frame == 710:
		main.pickups.append({"x": main.player.x, "y": main.player.y, "kind": "spread", "t": 0.0})
	if frame == 715:
		check(main.rapid_t > 0.0 and main.spread_t > 0.0,
			"速射与散射应可同时激活")

	# ---- 确定性测试 2：静止敌人被击杀 ----
	if frame == 720:
		kill_score_before = main.score
		main.enemies.append({
			"etype": "grunt", "shape": "square",
			"x": main.player.x + 130.0, "y": main.player.y,
			"r": 15.0, "hp": 1, "max_hp": 2, "speed": 0.0,
			"color": Color("#ff5c5c"), "score": 10,
			"vx": 0.0, "vy": 0.0, "flash": 0.0, "wobble": 0.0, "dead": false,
		})
		kill_target = main.enemies[main.enemies.size() - 1]
	if frame == 850:
		check(kill_target.dead, "瞄准静止敌人 2 秒内应被击杀")
		check(main.score > kill_score_before, "击杀后分数应增加")

	# ---- 确定性测试 3：暂停/恢复 ----
	if frame == 900:
		main._pause()
		check(main.phase == 2, "P 后应进入 PAUSE")  # Phase.PAUSE == 2
	if frame == 920:
		if main.phase == 2:
			pause_score = main.score
			main._resume()
			check(main.phase == 1, "P 后应恢复 PLAY")

	# ---- 确定性测试 4：阵亡与重开 ----
	if frame == 980:
		main.invuln = 0.0
		main.hp = 1
		main._hurt_player(main.player.x + 1.0, main.player.y + 1.0)
		check(main.phase == 3, "血量归零应进入 OVER")  # Phase.OVER == 3
	if frame == 1020:
		main._start()
		check(main.phase == 1, "重开后应回到 PLAY")
		check(main.score == 0, "重开后分数应清零")
		check(main.hp == main.MAX_HP, "重开后血量应回满")
		check(main.enemies.is_empty(), "重开后敌人应清空")

	# 资源规模护栏（防泄漏/失控）
	max_bullets = maxi(max_bullets, main.bullets.size())
	max_enemies = maxi(max_enemies, main.enemies.size())

	# 周期采样
	if frame % 300 == 0:
		print("[autotest] t=%ds phase=%d score=%d wave=%d enemies=%d hp=%d" %
			[frame / 60, main.phase, main.score, main.wave,
			main.enemies.size(), main.hp])

	# 收尾
	if frame >= 1500:
		check(main.phase == 1, "测试结束时游戏应处于可玩状态（而不是卡死）")
		check(max_bullets < 500, "子弹数量应有上界（实测 %d）" % max_bullets)
		check(max_enemies < 200, "敌人数量应有上界（实测 %d）" % max_enemies)
		_release_all()
		print("[autotest] 峰值: bullets=%d enemies=%d" % [max_bullets, max_enemies])
		# 停掉所有声音，等音频服务器混几帧再退，避免退出瞬间泄漏 playback
		main.sfx.stop_all()
		main.set_process(false)
		set_process(false)
		await get_tree().process_frame
		await get_tree().process_frame
		await get_tree().process_frame
		await get_tree().process_frame
		await get_tree().process_frame
		if errors.is_empty():
			print("[autotest] PASS · 全部断言通过")
			get_tree().quit(0)
		else:
			print("[autotest] FAIL · %d 项断言失败" % errors.size())
			for e in errors:
				print("  - " + e)
			get_tree().quit(1)
