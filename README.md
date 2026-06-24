# 肉鸽流派模拟验证器

Godot 4.x 编写的轻量肉鸽流派强弱模拟验证器。当前设定是期末周图书馆，玩家作为书籍清道夫清理被负面情绪污染的书籍怪物。项目用于加载一份策划配置，替换不同策略 API 实现，批量运行同一关卡，并输出胜率、耗时、伤害曲线和 JSON/CSV 结果。

## 环境

- Godot 4.7 stable
- 语言：GDScript
- 推荐使用 Godot 4.7 stable 打开项目；Godot 安装路径不固定，按自己电脑实际位置选择即可

## 拉取项目后如何本地运行

### 方式一：用 Godot 编辑器运行

1. 安装 Godot 4.7 stable。
2. 从 GitHub 拉取或下载本项目。

   ```powershell
   git clone https://github.com/haimian-code/TX_Test.git
   ```

   如果是下载 ZIP，先完整解压，再进入解压后的项目目录。

3. 打开 Godot，点击 `Import / 导入`。
4. 选择项目根目录下的 `project.godot` 文件。
5. 导入后打开项目。
6. 如果 Godot 没有自动运行主场景，就手动打开：

   ```text
   scenes/main.tscn
   ```

7. 点击 Godot 右上角运行按钮，或按 `F5` 运行。
8. 在界面中选择策略、模式和批量次数。
9. 点击：
   - `运行单局`：运行单局模拟
   - `批量模拟`：连续运行 N 局并统计结果
   - `对比流派`：对比暴击爆发流和情绪净化流
   - `导出结果`：导出最近一次结果

### 方式二：用命令行运行主界面

如果已经知道 Godot 程序位置，也可以直接用命令行打开项目。下面路径只是示例，需要替换成自己电脑上的实际路径。

```powershell
& 'D:\Godot\Godot_v4.7-stable_win64.exe' --path 'D:\TX_Test'
```

其中：

```text
D:\Godot\Godot_v4.7-stable_win64.exe  是 Godot 程序路径
D:\TX_Test                            是项目目录，里面应该能看到 project.godot
```

不要直接双击 `.gd`、`.tscn`、`.json` 文件，也不要用浏览器打开项目源码。这个仓库是 Godot 项目源码，需要用 Godot 打开 `project.godot` 运行。

### 常见打不开原因

- Godot 版本不对：建议使用 Godot 4.7 stable。
- 打开的目录不对：要选择包含 `project.godot` 的项目根目录。
- ZIP 没有解压：GitHub 下载的 ZIP 必须先完整解压，不能在压缩包预览里运行。
- 只打开了 `scenes/main.tscn`：应先通过 `project.godot` 导入整个项目。
- 路径写死了：README 中的 `D:\TX_Test` 只是示例，实际路径以自己电脑为准。
- 项目文件缺失：项目根目录至少应包含 `project.godot`、`scenes/`、`scripts/`、`data/`。

## 命令行测试

也可以用命令行验证脚本是否能加载。下面路径仍然只是示例，需要替换为自己电脑上的 Godot 路径和项目路径：

```powershell
& 'D:\Godot\Godot_v4.7-stable_win64_console.exe' --headless --path 'D:\TX_Test' --quit-after 1
```

运行自动 smoke test：

```powershell
& 'D:\Godot\Godot_v4.7-stable_win64_console.exe' --headless --path 'D:\TX_Test' --script 'res://scripts/cli_smoke_test.gd'
```

成功时会输出 `SMOKE_OK`，并在 `exports/` 下生成 `smoke_last.json` 和 `smoke_last.csv`。

运行自动测试用例：

```powershell
& 'D:\Godot\Godot_v4.7-stable_win64_console.exe' --headless --path 'D:\TX_Test' --script 'res://scripts/cli_tests.gd'
```

该脚本覆盖配置加载、坏配置报错、策略输出、固定种子确定性、tick/turn 战斗结果、情绪净化流持续伤害覆盖、道具随机加成记录、回合制攻击间隔和 JSON/CSV 导出。

运行数据审计：

```powershell
& 'D:\Godot\Godot_v4.7-stable_win64_console.exe' --headless --path 'D:\TX_Test' --script 'res://scripts/cli_balance_audit.gd'
```

该脚本会用固定种子测试 `crit_tick`、`corrosion_tick`、`crit_turn`、`corrosion_turn` 四组组合，方便发现不同模式之间的数值或规则异常。

## 项目结构

```text
data/
  sample_adventure.json       示例策划配置
scenes/
  main.tscn                   主界面
scripts/
  main.gd                     UI 和入口
  core/
    battle_simulator.gd       战斗模拟核心
    config_loader.gd          配置加载与校验
    result_exporter.gd        JSON/CSV 导出
  strategies/
    strategy_base.gd          策略 API 基类
    crit_burst_strategy.gd    暴击爆发流
    corrosion_strategy.gd     情绪净化流
design.md                     策划案
schema.md                     数据格式规范
api.md                        策略 API 规范
```

## 已实现范围

- JSON 配置加载和基础校验
- 角色、技能、道具、怪物、关卡数据驱动
- GDScript 策略 API
- 暴击爆发流与情绪净化流两套策略
- 回合制模式
- Tick 实时模式
- 单局模拟
- 批量模拟
- 胜率、平均耗时、平均剩余 HP 统计
- 技能释放次数、总伤害、承受伤害统计
- 文本伤害曲线
- JSON / CSV 导出
- 简单 Godot UI 显示 HP、日志和结果
- 自动测试脚本和数据审计脚本
- 简单可视化对比面板：点击“对比流派”后用数字表对比胜率、平均耗时、平均生命、平均伤害
- 道具随机加成：每局按随机种子给已选道具抽取额外属性，并在单局/批量结果中记录具体效果

## 本地验证结果

已在 Godot 4.7 stable 下通过。示例输出如下，批量模拟的平均值会因随机种子略有波动：

```text
SMOKE_OK
crit_once won=true elapsed=13.1 hp=38.4 damage=571.9
corrosion_once won=true elapsed=27.0 hp=11.3 damage=588.3
crit_batch win_rate=1.00 avg_elapsed=13.8
corrosion_batch win_rate=0.50 avg_elapsed=22.3
```

这说明：

- 配置可以加载；
- 两套策略可以替换运行；
- tick / turn 两种模式都能跑；
- 批量模拟能统计胜率和平均耗时；
- JSON / CSV 导出可用。

最近一次数据审计结果：

```text
crit_tick       wins=95/100 avg_elapsed=13.39 avg_hp=23.56
corrosion_tick  wins=49/100 avg_elapsed=22.03 avg_hp=3.42
crit_turn       wins=96/100 avg_elapsed=19.78 avg_hp=27.48
corrosion_turn  wins=69/100 avg_elapsed=28.42 avg_hp=11.85
```

审计中发现并修复过一个规则问题：早期回合制模式里怪物每回合都会攻击，没有尊重配置中的 `attack_interval`，导致 turn 模式下情绪净化流被系统性压低到 0% 胜率。现在回合制会按时间步进结算冷却、能量、持续伤害和怪物攻击间隔。后续又调高了唯一关卡中怪物的生命和攻击，让胜率不再全部饱和为 100%，从而更适合验证流派强弱。

最近一次自动测试结果为 `CLI_TESTS_OK`，共覆盖 38 个断言。

## 设计自评

本项目刻意避免复杂寻路、动画和美术，把工程重点放在“数据 -> 策略 -> 模拟 -> 结果”的闭环上。战斗规则简化为玩家和队列头部怪物交战，怪物只会普攻。

初始预期是：

- 暴击爆发流平均耗时更短；
- 情绪净化流胜率更稳定，尤其在精英怪长战中容错更高。

但是结果发现，暴击爆发流确实平均耗时更短，但是情绪净化流的胜率却更低，我认为这是因为当前关卡环境不适合它，它的输出启动慢，导致战斗时间变长，怪物攻击次数增加，最后承伤压过了它的生存优势。
