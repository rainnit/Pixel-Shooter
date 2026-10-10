extends SceneTree
## 自动测试入口：
## godot --headless -s res://tests/autotest.gd
## 加载主场景并挂上驾驶员，模拟键鼠跑 25 秒完整对局。

func _initialize() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	var driver: Node = load("res://tests/autotest_driver.gd").new()
	driver.main = scene
	root.add_child(driver)
	print("[autotest] scene + driver loaded")
