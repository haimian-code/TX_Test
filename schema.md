# 数据格式规范

配置文件位于 `data/sample_adventure.json`，采用 JSON。选择 JSON 的原因是：

- 易读，适合策划手写和 AI 生成；
- Godot 原生支持解析；

## 顶层结构

```json
{
  "schema_version": 1,
  "adventure": {},
  "characters": [],
  "skills": [],
  "items": [],
  "affix_pool": [],
  "monsters": [],
  "levels": []
}
```

## character

```json
{
  "id": "waden",
  "name": "书籍清道夫",
  "base_stats": {
    "max_hp": 120,
    "attack": 12,
    "defense": 3,
    "crit_chance": 0.08,
    "crit_damage": 1.8,
    "speed": 10,
    "energy_regen": 6
  },
  "start_energy": 20,
  "attribute_points": 6,
  "skills": ["quick_slash"],
  "items": ["razor_lens"]
}
```

必填字段：

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| id | string | 全局唯一 ID |
| name | string | 显示名 |
| base_stats | object | 基础属性 |
| start_energy | number | 初始能量 |
| attribute_points | int | 开局可分配属性点 |
| skills | string[] | 可用技能 ID |
| items | string[] | 可用道具 ID |

## skill

```json
{
  "id": "rupture_mark",
  "name": "重点标注",
  "cooldown": 3.0,
  "cost": 14,
  "tags": ["direct", "crit"],
  "effect": {
    "type": "damage",
    "power": 1.85,
    "bonus_crit_chance": 0.16
  }
}
```

当前支持的 `effect.type`：

| 类型 | 字段 | 说明 |
| --- | --- | --- |
| damage | power, bonus_crit_chance? | 直接伤害 |
| dot | power, duration, tick_interval, stacks? | 持续伤害 |

## item

```json
{
  "id": "battle_manual",
  "name": "复习手册",
  "modifiers": {
    "cooldown_multiplier": -0.12,
    "energy_regen": 2
  }
}
```

`modifiers` 当前支持：

| 字段 | 说明 |
| --- | --- |
| attack | 直接增加攻击 |
| defense | 直接增加防御 |
| max_hp | 直接增加最大生命 |
| crit_chance | 增加暴击率 |
| crit_damage | 增加暴击伤害倍率 |
| speed | 增加速度 |
| energy_regen | 增加每秒能量恢复 |
| cooldown_multiplier | 技能冷却倍率修正，-0.12 表示冷却缩短 12% |
| dot_multiplier | 持续伤害倍率修正，0.35 表示持续伤害提高 35% |

## item_random_bonus

`affix_pool` 是可选字段，含义是“道具随机加成池”。模拟器会为每局策略启用的每件道具随机抽取一个加成，并把该加成的 `modifiers` 叠加到角色属性上。字段名保留 `affix_pool` 是为了兼容现有导出和测试，界面中统一显示为“道具随机加成”。

```json
{
  "id": "overclocked",
  "name": "冲刺",
  "weight": 2,
  "modifiers": {
    "cooldown_multiplier": -0.06,
    "energy_regen": 1
  }
}
```

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| id | string | 全局唯一 ID |
| name | string | 显示名 |
| weight | number | 随机权重 |
| modifiers | object | 与道具 modifier 相同的属性修正 |

## monster

```json
{
  "id": "paper_thrall",
  "name": "焦虑书页",
  "max_hp": 55,
  "attack": 8,
  "defense": 1,
  "speed": 8,
  "attack_interval": 1.4,
  "count_as": "normal"
}
```

## level

```json
{
  "id": "archive_trial",
  "name": "期末图书馆清理区",
  "waves": [
    {
      "monster": "paper_thrall",
      "count": 3
    }
  ]
}
```

关卡按 `waves` 顺序生成怪物队列。同一时间只激活队列头部怪物，便于观察单体技能和持续伤害的差异。

## 扩展约定

- 新字段默认忽略，保证旧模拟器能加载新配置的基础部分。
- `schema_version` 用于将来做破坏性升级。
- 所有实体通过 `id` 引用，避免嵌套数据过深。
- 配置错误需要返回清晰错误信息，不允许模拟器直接崩溃。
