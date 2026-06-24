# 流派策略 API 规范

当前实现采用 GDScript 策略类。选择这种形式是因为它满足题目最低要求，Godot 内部可直接替换脚本，调试成本低；同时接口输入输出都使用 Dictionary，后续可以平滑迁移到 JSON-RPC、HTTP 或外部进程。

## 策略基类

所有策略继承：

```gdscript
res://scripts/strategies/strategy_base.gd
```

策略需要实现三个方法：

```gdscript
func get_strategy_id() -> String
func allocate_attributes(context: Dictionary) -> Dictionary
func choose_items(context: Dictionary) -> Array[String]
func decide_action(context: Dictionary) -> Dictionary
```

## allocate_attributes（属性分配 API）

调用时机：战斗开始前。

输入示例：

```json
{
  "points": 6,
  "character": {},
  "level": {}
}
```

返回示例：

```json
{
  "attack": 3,
  "crit": 2,
  "speed": 1
}
```

模拟器会校验总点数不超过 `points`，并忽略未知字段。

当前属性点字段采用内部英文 key，方便代码和 JSON 稳定引用；界面和策划文档使用中文展示：

| 中文属性 | 内部字段 |
| --- | --- |
| 攻击 | attack |
| 防御 | defense |
| 暴击 | crit |
| 速度 | speed |
| 最大生命 | max_hp |

## choose_items

调用时机：属性分配之后、战斗开始之前。

输入示例：

```json
{
  "available_items": ["razor_lens", "toxin_vial", "battle_manual"],
  "character": {},
  "level": {}
}
```

返回示例：

```json
["razor_lens", "battle_manual"]
```

当前示例允许策略从角色拥有的道具中选择启用道具。为了体现流派差异，策略通常选择 2 件核心道具。

## decide_action

调用时机：

- 回合制：玩家行动回合开始时；
- Tick 制：每个 tick，如果有技能可释放则询问策略。

输入示例：

```json
{
  "mode": "tick",
  "time": 4.2,
  "turn": 12,
  "player": {
    "hp": 94,
    "max_hp": 120,
    "energy": 25,
    "stats": {}
  },
  "enemy": {
    "id": "ink_guardian",
    "hp": 91,
    "max_hp": 145
  },
  "skills": [
    {
      "id": "quick_slash",
      "cooldown_left": 0,
      "cost": 8
    }
  ],
  "active_effects": []
}
```

返回示例：

```json
{
  "type": "cast_skill",
  "skill": "rupture_mark"
}
```

当前支持的动作：

| type | 字段 | 说明 |
| --- | --- | --- |
| cast_skill | skill | 释放指定技能 |
| wait | 无 | 不释放技能，保留能量或等待时机 |

如果策略返回的技能不存在、CD 未好或能量不足，模拟器会记录失败原因并执行等待，不会崩溃。

## 样例策略

### CritBurstStrategy

路径：

```text
res://scripts/strategies/crit_burst_strategy.gd
```

行为：

- 加点偏向攻击 / 暴击 / 速度；
- 启用专注透镜和复习手册；
- 优先释放重点标注，其次快速翻检，最后情绪净化。

### CorrosionStrategy

路径：

```text
res://scripts/strategies/corrosion_strategy.gd
```

行为：

- 加点偏向攻击 / 防御 / 最大生命；
- 启用情绪中和剂和复习手册；
- 优先保持情绪净化，再用快速翻检填充。

## 外部策略扩展方向

因为当前 `context` 和 `action` 都是 Dictionary/JSON 友好结构，后续可以新增 `HttpStrategyAdapter`：

1. Godot 将 `context` 序列化为 JSON；
2. 通过 HTTP POST 发送给外部 Python/LLM 服务；
3. 服务返回 action JSON；
4. Godot 复用同一套动作校验和战斗结算逻辑。

这样不会影响 `BattleSimulator` 的核心代码。
