# 霓虹竞技场 · NeonArena

2D 射击生存 MVP。Godot 4.7 工程，玩法与手感参数从 HTML 原型
（`D:/workbuddywork/霓虹竞技场-2D射击.html`）1:1 移植。

## 怎么打开

1. 双击 `D:\godot\Godot_v4.7.2-stable_win64.exe`；
2. 导入 → 选本文件夹（`D:\GodotProjects\NeonArena`）→ 打开；
3. 按 **F5** 运行。

## 操作

| 输入 | 效果 |
| --- | --- |
| WASD / 方向键 | 移动（带加速度与摩擦，有惯性） |
| 鼠标 | 瞄准 |
| 按住左键 / 空格 | 连续射击 |
| P | 暂停 |
| R | 阵亡后重开 |

## 玩法

- 一波波敌人从屏幕外生成（有 0.55s 预警圈），清除后进入下一波，怪越来越多越来越快；
- 方块兵（红）· 三角快攻（橙，第 2 波起）· 六边坦克（紫，第 3 波起，7 血带击杀顿帧加重）；
- 击杀概率掉落：**粉圈十字**回血 · **黄圈**速射 8s · **蓝圈三向星**散射 10s，靠近自动吸取；
- 手感全家桶：命中白闪+火花、击杀爆裂粒子+双层冲击波环、顿帧、震屏、枪口火光+后坐力、分数飞字；
- 音效全部运行时 PCM 合成（`scripts/sfx.gd`），零素材；
- 最高纪录存在 `user://best.cfg`。

## 代码结构

```
project.godot          引擎配置（1280x720、gl_compatibility、主场景）
scenes/main.tscn       唯一场景：根 Node2D + main.gd
scripts/main.gd        全部游戏逻辑（状态机/生成/碰撞/粒子/绘制/HUD）
scripts/sfx.gd         运行时合成音效 + 播放器轮播
tests/autotest.gd      自动测试入口（SceneTree 脚本）
tests/autotest_driver.gd   模拟键鼠驾驶员 + 断言
```

> 刻意先单文件驱动 MVP：跑通手感后再拆 Player / Enemy / Spawner 节点。
> 调手感改 `main.gd` 顶部常量（速度/摩擦/射速/顿帧时长等）。

## 自动化自测

无头模式模拟键鼠跑 25 秒完整对局，覆盖：开局 / 移动 / 掉落吸取 / 武器生效 /
确定性击杀 / 暂停恢复 / 阵亡重开 / 资源数量上界，零脚本错误才放行：

```powershell
& "D:\godot\Godot_v4.7.2-stable_win64.exe" --headless --path "D:\GodotProjects\NeonArena" -s res://tests/autotest.gd
# 退出码 0 = PASS；1 = 有断言失败（打印明细）
```

已知无害警告：headless 哑音频驱动下退出可能报 "2 ObjectDB instances leaked"，
空跑不玩也会出现，属引擎退出清理特性，桌面真机不受影响。

## 后续路线

1. **手感迭代**：根据试玩调整顿帧时长、震屏幅度、敌人密度；
2. **内容**：Boss、更多武器（穿透/追踪）、磁吸范围升级；
3. **拆分重构**：把玩家/敌人拆成独立场景与脚本，接入 Godot 内置粒子（GPUParticles2D）；
4. **安卓移植**：本工程可直接导出 APK——需要 JDK 17 + Android SDK（编辑器内有引导），
   代码侧补一套触屏输入（左半屏虚拟摇杆 + 自动瞄准最近的敌人）即可，渲染后端已预设 `gl_compatibility`（安卓兼容）。
