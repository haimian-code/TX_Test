class_name BattleSimulator
extends RefCounted


const ConfigLoaderScript = preload("res://scripts/core/config_loader.gd")

# 战斗模式 ID。UI、测试和结果导出都使用这两个字符串保持一致。
const MODE_TICK := "tick"
const MODE_TURN := "turn"

# Tick 模式每 0.1 秒推进一次；上限用于防止异常策略导致无限循环。
const TICK_SECONDS := 0.1
const MAX_TICKS := 2400
const MAX_TURNS := 500

# 配置加载后会被拆成多个索引表，战斗过程中按 id 查找会更直接。
var config: Dictionary
var skills_by_id: Dictionary
var items_by_id: Dictionary
var monsters_by_id: Dictionary
var affix_pool: Array = []

# rng 只属于模拟器实例；固定 seed 时可以复现实验结果。
var rng := RandomNumberGenerator.new()

# 单场战斗的过程数据。run_once 开始时会清空，最终放进 result。
var logs: Array[String] = []
var damage_curve: Array[Dictionary] = []


func _init(source_config: Dictionary) -> void:
	config = source_config
	var loader = ConfigLoaderScript.new()
	# 这里复用 ConfigLoader 的 index_by_id 工具，不重复写索引构建逻辑。
	skills_by_id = loader.index_by_id(config.get("skills", []))
	items_by_id = loader.index_by_id(config.get("items", []))
	monsters_by_id = loader.index_by_id(config.get("monsters", []))
	affix_pool = config.get("affix_pool", [])


# 运行一场战斗。strategy 只负责做决策，具体结算仍由模拟器统一执行。
func run_once(strategy: RefCounted, mode: String, seed_value: int = 0) -> Dictionary:
	logs = []
	damage_curve = []
	if seed_value == 0:
		# 没传 seed 时使用随机种子，适合 UI 中的普通模拟。
		rng.randomize()
		seed_value = rng.randi()
	else:
		# 传入 seed 时保证同一策略、同一模式、同一配置下结果可复现。
		rng.seed = seed_value

	# 当前版本只使用配置中的第一个角色和第一个关卡，满足“一个关卡”的实现目标。
	var character: Dictionary = config.get("characters", [])[0]
	var level: Dictionary = config.get("levels", [])[0]
	var player := _build_player(character, level, strategy)
	var enemy_queue := _build_enemy_queue(level)
	var enemy_total := enemy_queue.size()
	# state 是单场战斗的可变上下文；所有结算函数都围绕它读写。
	var state := {
		"mode": mode,
		"seed": seed_value,
		"time": 0.0,
		"turn": 0,
		"tick": 0,
		"player": player,
		"enemy_queue": enemy_queue,
		"current_enemy": enemy_queue.pop_front() if not enemy_queue.is_empty() else {},
		"enemy_total": enemy_total,
		"enemy_index": 1 if enemy_total > 0 else 0,
		"enemies_defeated": 0,
		"total_damage": 0.0,
		"damage_taken": 0.0,
		"skill_casts": {},
		"active_effects": []
	}

	_log(state, "battle_start", "%s 开始挑战 %s（%s）。" % [_display_strategy(strategy.get_strategy_id()), level.get("name", ""), _display_mode(mode)])

	if state["current_enemy"].is_empty():
		return _build_result(state, strategy, true, "Level has no enemies.")

	# 双模式共享同一套角色、敌人、技能和结果结构，只是时间推进方式不同。
	if mode == MODE_TURN:
		_run_turn_mode(state, strategy)
	else:
		_run_tick_mode(state, strategy)

	var won: bool = float(state["player"].get("hp", 0.0)) > 0.0 and state["current_enemy"].is_empty() and state["enemy_queue"].is_empty()
	var reason: String = "victory" if won else "defeat"
	if not won and float(state["player"].get("hp", 0.0)) > 0.0:
		reason = "time_limit"
	return _build_result(state, strategy, won, reason)


# 批量模拟会保留每一场完整结果，同时汇总胜率、平均耗时、平均生命等指标。
func run_batch(strategy: RefCounted, mode: String, runs: int) -> Dictionary:
	var results: Array[Dictionary] = []
	var wins := 0
	var total_time := 0.0
	var total_hp := 0.0
	var total_damage := 0.0
	var affix_counts := {}
	var safe_runs = max(1, runs)

	for i in safe_runs:
		# 每场使用不同 seed，让批量结果能体现随机词缀和暴击带来的波动。
		var result := run_once(strategy, mode, int(Time.get_unix_time_from_system()) + i * 7919 + rng.randi_range(1, 999999))
		results.append(result)
		if bool(result.get("won", false)):
			wins += 1
		total_time += float(result.get("elapsed", 0.0))
		total_hp += float(result.get("player_hp", 0.0))
		total_damage += float(result.get("total_damage", 0.0))
		for affix in result.get("affixes", []):
			var affix_id := str(affix.get("id", ""))
			affix_counts[affix_id] = int(affix_counts.get(affix_id, 0)) + 1

	return {
		"strategy": strategy.get_strategy_id(),
		"mode": mode,
		"runs": safe_runs,
		"wins": wins,
		"win_rate": float(wins) / float(safe_runs),
		"average_elapsed": total_time / float(safe_runs),
		"average_player_hp": total_hp / float(safe_runs),
		"average_total_damage": total_damage / float(safe_runs),
		"affix_counts": affix_counts,
		"results": results
	}


func _run_tick_mode(state: Dictionary, strategy: RefCounted) -> void:
	var player: Dictionary = state["player"]
	var player_attack_timer := 0.0
	var enemy_attack_timer := 0.0

	# Tick 模式是连续时间：能量、冷却、攻击间隔、持续伤害都按 delta 递减/累加。
	while int(state["tick"]) < MAX_TICKS and _battle_continues(state):
		state["tick"] = int(state["tick"]) + 1
		state["time"] = float(state["time"]) + TICK_SECONDS

		_regen_energy(player, TICK_SECONDS)
		_reduce_cooldowns(player, TICK_SECONDS)
		_apply_effects(state, TICK_SECONDS)

		player_attack_timer -= TICK_SECONDS
		enemy_attack_timer -= TICK_SECONDS

		if player_attack_timer <= 0.0 and _battle_continues(state):
			_player_basic_attack(state)
			# 速度越高，普通攻击间隔越短；下限避免速度过高导致过密攻击。
			player_attack_timer = max(0.4, 1.7 - float(player["stats"].get("speed", 0.0)) * 0.045)

		if _advance_enemy_if_needed(state):
			continue

		if _battle_continues(state):
			# 策略 API 调用点：模拟器提供上下文，策略返回动作请求。
			var action: Dictionary = strategy.decide_action(_build_context(state))
			_apply_player_action(state, action)

		if _advance_enemy_if_needed(state):
			continue

		if enemy_attack_timer <= 0.0 and _battle_continues(state):
			_enemy_basic_attack(state)
			enemy_attack_timer = float(state["current_enemy"].get("attack_interval", 1.5))


func _run_turn_mode(state: Dictionary, strategy: RefCounted) -> void:
	var enemy_attack_timer := 0.0
	# 回合制模式按整回合推进：每回合处理一次冷却、能量、持续伤害和双方行动。
	while int(state["turn"]) < MAX_TURNS and _battle_continues(state):
		state["turn"] = int(state["turn"]) + 1
		state["time"] = float(state["turn"])
		enemy_attack_timer = max(0.0, enemy_attack_timer - 1.0)

		_reduce_cooldowns(state["player"], 1.0)
		_regen_energy(state["player"], 1.0)
		_apply_effects(state, 1.0)
		if _advance_enemy_if_needed(state):
			enemy_attack_timer = 0.0
			continue

		var player_speed := float(state["player"]["stats"].get("speed", 0.0))
		var enemy_speed := float(state["current_enemy"].get("speed", 0.0))
		# 回合制通过速度决定先后手；速度相同默认玩家先手，减少平局歧义。
		var player_first := player_speed >= enemy_speed

		if player_first:
			_player_turn(state, strategy)
			if _advance_enemy_if_needed(state):
				enemy_attack_timer = 0.0
				continue
			if enemy_attack_timer <= 0.0 and _battle_continues(state):
				_enemy_turn(state)
				enemy_attack_timer = float(state["current_enemy"].get("attack_interval", 1.5))
		else:
			if enemy_attack_timer <= 0.0:
				_enemy_turn(state)
				enemy_attack_timer = float(state["current_enemy"].get("attack_interval", 1.5))
			if _battle_continues(state):
				_player_turn(state, strategy)
				if _advance_enemy_if_needed(state):
					enemy_attack_timer = 0.0


func _player_turn(state: Dictionary, strategy: RefCounted) -> void:
	# 回合制中如果策略没有可执行技能，就退回普通攻击，避免角色空过一整回合。
	var action: Dictionary = strategy.decide_action(_build_context(state))
	var acted: bool = _apply_player_action(state, action)
	if not acted and _battle_continues(state):
		_player_basic_attack(state)


func _enemy_turn(state: Dictionary) -> void:
	_enemy_basic_attack(state)


func _build_player(character: Dictionary, level: Dictionary, strategy: RefCounted) -> Dictionary:
	var stats: Dictionary = character.get("base_stats", {}).duplicate(true)
	var points := int(character.get("attribute_points", 0))
	# 策略 API：把角色、关卡和点数交给流派，获得该流派的开局加点方案。
	var allocation: Dictionary = strategy.allocate_attributes({
		"points": points,
		"character": character,
		"level": level
	})
	_apply_attribute_points(stats, allocation, points)

	var available_items: Array = character.get("items", [])
	# 策略 API：流派从角色可用道具中挑选自己的核心装备。
	var chosen_items: Array = strategy.choose_items({
		"available_items": available_items,
		"character": character,
		"level": level
	})
	chosen_items = _sanitize_items(chosen_items, available_items)
	_apply_items(stats, chosen_items)
	# 每件已选装备随机获得一个词缀，制造同一流派在批量模拟中的结果波动。
	var rolled_affixes := _roll_affixes(chosen_items)
	_apply_affixes(stats, rolled_affixes)

	var max_hp := float(stats.get("max_hp", 1.0))
	var cooldowns := {}
	for skill_id in character.get("skills", []):
		cooldowns[str(skill_id)] = 0.0

	return {
		"id": character.get("id", ""),
		"name": character.get("name", ""),
		"stats": stats,
		"hp": max_hp,
		"max_hp": max_hp,
		"energy": float(character.get("start_energy", 0.0)),
		"skills": character.get("skills", []).duplicate(),
		"items": chosen_items,
		"affixes": rolled_affixes,
		"cooldowns": cooldowns,
		"allocation": allocation
	}


func _apply_attribute_points(stats: Dictionary, allocation: Dictionary, max_points: int) -> void:
	var spent := 0
	for key in allocation.keys():
		spent += max(0, int(allocation[key]))
	if spent > max_points:
		# 策略如果返回了超额点数，模拟器按比例压缩，保证策略不能越权。
		var scale := float(max_points) / float(spent)
		for key in allocation.keys():
			allocation[key] = int(floor(float(allocation[key]) * scale))

	# 点数到属性的换算集中在这里，策略只关心“投几类点”，不关心数值公式。
	stats["attack"] = float(stats.get("attack", 0.0)) + float(allocation.get("attack", 0)) * 2.0
	stats["defense"] = float(stats.get("defense", 0.0)) + float(allocation.get("defense", 0)) * 1.0
	stats["crit_chance"] = float(stats.get("crit_chance", 0.0)) + float(allocation.get("crit", 0)) * 0.04
	stats["speed"] = float(stats.get("speed", 0.0)) + float(allocation.get("speed", 0)) * 1.0
	stats["max_hp"] = float(stats.get("max_hp", 0.0)) + float(allocation.get("max_hp", 0)) * 12.0


func _sanitize_items(chosen_items: Array, available_items: Array) -> Array:
	var result: Array = []
	for item_id in chosen_items:
		var id := str(item_id)
		# 过滤不存在或重复的道具，防止策略脚本返回非法 ID 影响后续结算。
		if available_items.has(id) and not result.has(id):
			result.append(id)
	return result


func _apply_items(stats: Dictionary, chosen_items: Array) -> void:
	for item_id in chosen_items:
		var item: Dictionary = items_by_id.get(str(item_id), {})
		var modifiers: Dictionary = item.get("modifiers", {})
		# 道具 modifier 是通用加法模型，便于配置新增 attack、crit_chance 等字段。
		for key in modifiers.keys():
			stats[key] = float(stats.get(key, 0.0)) + float(modifiers[key])


func _roll_affixes(chosen_items: Array) -> Array:
	var result: Array = []
	if affix_pool.is_empty():
		return result
	for item_id in chosen_items:
		# 当前规则：每件装备 roll 一个词缀；词缀效果稍后统一叠加到 stats。
		var affix := _weighted_random_affix()
		if affix.is_empty():
			continue
		result.append({
			"item": str(item_id),
			"id": str(affix.get("id", "")),
			"name": str(affix.get("name", "")),
			"modifiers": affix.get("modifiers", {}).duplicate(true)
		})
	return result


func _weighted_random_affix() -> Dictionary:
	var total_weight := 0.0
	for affix in affix_pool:
		total_weight += max(0.0, float(affix.get("weight", 1.0)))
	if total_weight <= 0.0:
		return {}
	# 权重随机：权重越大，被抽中的概率越高。
	var roll := rng.randf_range(0.0, total_weight)
	var cursor := 0.0
	for affix in affix_pool:
		cursor += max(0.0, float(affix.get("weight", 1.0)))
		if roll <= cursor:
			return affix
	return affix_pool[-1]


func _apply_affixes(stats: Dictionary, rolled_affixes: Array) -> void:
	for affix in rolled_affixes:
		var modifiers: Dictionary = affix.get("modifiers", {})
		# 词缀和道具使用同一套 modifier 叠加规则，便于扩展新属性。
		for key in modifiers.keys():
			stats[key] = float(stats.get(key, 0.0)) + float(modifiers[key])


func _build_enemy_queue(level: Dictionary) -> Array:
	var queue: Array = []
	for wave in level.get("waves", []):
		var monster_id := str(wave.get("monster", ""))
		var count := int(wave.get("count", 0))
		for i in count:
			# 按关卡 wave 顺序展开怪物队列，战斗中始终取队首作为当前敌人。
			var monster: Dictionary = monsters_by_id.get(monster_id, {}).duplicate(true)
			monster["queue_index"] = queue.size() + 1
			monster["instance_id"] = "%s_%d_%d" % [monster_id, queue.size(), i]
			monster["hp"] = float(monster.get("max_hp", 1.0))
			monster["max_hp"] = float(monster.get("max_hp", 1.0))
			queue.append(monster)
	return queue


func _build_context(state: Dictionary) -> Dictionary:
	var player: Dictionary = state["player"]
	var enemy: Dictionary = state["current_enemy"]
	var skill_states: Array = []
	for skill_id in player.get("skills", []):
		var skill: Dictionary = skills_by_id.get(str(skill_id), {})
		var cost := float(skill.get("cost", 0.0))
		var cooldown_left := float(player["cooldowns"].get(str(skill_id), 0.0))
		skill_states.append({
			"id": str(skill_id),
			"name": skill.get("name", skill_id),
			"cooldown_left": cooldown_left,
			"cost": cost,
			"enough_energy": float(player.get("energy", 0.0)) >= cost
		})

	# 这是给策略看的“只读上下文”：暴露决策需要的信息，不暴露完整 state 让策略随意改。
	return {
		"mode": state["mode"],
		"time": state["time"],
		"turn": state["turn"],
		"tick": state["tick"],
		"player": {
			"hp": player.get("hp", 0.0),
			"max_hp": player.get("max_hp", 0.0),
			"energy": player.get("energy", 0.0),
			"stats": player.get("stats", {})
		},
		"enemy": {
			"id": enemy.get("id", ""),
			"name": enemy.get("name", ""),
			"hp": enemy.get("hp", 0.0),
			"max_hp": enemy.get("max_hp", 0.0)
		},
		"skills": skill_states,
		"active_effects": state.get("active_effects", [])
	}


func _apply_player_action(state: Dictionary, action: Dictionary) -> bool:
	# 当前动作协议只支持 cast_skill；其他动作视为 wait，由调用方决定是否普攻兜底。
	if action.get("type", "wait") != "cast_skill":
		return false
	var skill_id := str(action.get("skill", ""))
	return _cast_skill(state, skill_id)


func _cast_skill(state: Dictionary, skill_id: String) -> bool:
	var player: Dictionary = state["player"]
	# 策略返回的技能 ID 必须属于角色，不能凭空请求配置外技能。
	if not player.get("skills", []).has(skill_id):
		_log(state, "invalid_action", "策略请求了未知技能：%s。" % skill_id)
		return false
	if not skills_by_id.has(skill_id):
		_log(state, "invalid_action", "缺少技能配置：%s。" % skill_id)
		return false

	var skill: Dictionary = skills_by_id[skill_id]
	var cooldown_left := float(player["cooldowns"].get(skill_id, 0.0))
	var cost := float(skill.get("cost", 0.0))
	# 冷却未好或能量不足时，施法失败；策略下次仍可重新决策。
	if cooldown_left > 0.0 or float(player.get("energy", 0.0)) < cost:
		return false

	player["energy"] = float(player.get("energy", 0.0)) - cost
	player["cooldowns"][skill_id] = _effective_cooldown(player, skill)
	state["skill_casts"][skill_id] = int(state["skill_casts"].get(skill_id, 0)) + 1
	_log(state, "cast_skill", "玩家释放 %s。" % skill.get("name", skill_id))

	var effect: Dictionary = skill.get("effect", {})
	match str(effect.get("type", "")):
		"damage":
			# 直接伤害技能立即结算一次伤害。
			var damage: float = _roll_damage(player, effect)
			_deal_damage_to_enemy(state, damage, "%s 命中" % skill.get("name", skill_id))
		"dot":
			# 持续伤害记录在 active_effects，由 _apply_effects 按时间/回合触发。
			state["active_effects"].append({
				"source_skill": skill_id,
				"name": skill.get("name", skill_id),
				"remaining": float(effect.get("duration", 0.0)),
				"tick_interval": float(effect.get("tick_interval", 1.0)),
				"tick_timer": 0.0,
				"power": float(effect.get("power", 0.0)),
				"target_instance": state["current_enemy"].get("instance_id", "")
			})
		_:
			_log(state, "invalid_skill", "技能 %s 使用了不支持的效果。" % skill_id)
	return true


func _effective_cooldown(player: Dictionary, skill: Dictionary) -> float:
	var base: float = float(skill.get("cooldown", 0.0))
	var modifier: float = float(player["stats"].get("cooldown_multiplier", 0.0))
	# cooldown_multiplier 为负表示缩短冷却；保留 0.1 下限避免出现 0 冷却。
	return max(0.1, base * (1.0 + modifier))


func _roll_damage(player: Dictionary, effect: Dictionary) -> float:
	var stats: Dictionary = player["stats"]
	var base: float = float(stats.get("attack", 0.0)) * float(effect.get("power", 1.0))
	var crit_chance: float = clamp(float(stats.get("crit_chance", 0.0)) + float(effect.get("bonus_crit_chance", 0.0)), 0.0, 0.95)
	var crit_damage: float = max(1.0, float(stats.get("crit_damage", 1.5)))
	# 暴击率限制到 95%，保留少量失败概率，让批量模拟不会完全变成确定结果。
	if rng.randf() < crit_chance:
		base *= crit_damage
	return base


func _player_basic_attack(state: Dictionary) -> void:
	var player: Dictionary = state["player"]
	var damage: float = _roll_damage(player, {"power": 0.72})
	_deal_damage_to_enemy(state, damage, "普通攻击")


func _enemy_basic_attack(state: Dictionary) -> void:
	var enemy: Dictionary = state["current_enemy"]
	var player: Dictionary = state["player"]
	var raw_damage: float = float(enemy.get("attack", 0.0))
	# 玩家防御降低受到的伤害，但至少保留 1 点，避免高防御完全无伤。
	var damage: float = max(1.0, raw_damage - float(player["stats"].get("defense", 0.0)) * 0.65)
	player["hp"] = max(0.0, float(player.get("hp", 0.0)) - damage)
	state["damage_taken"] = float(state["damage_taken"]) + damage
	_log(state, "enemy_attack", "%s 攻击玩家，造成 %.1f 点伤害。" % [enemy.get("name", "敌人"), damage])
	_record_curve(state, "enemy_attack")


func _deal_damage_to_enemy(state: Dictionary, raw_damage: float, event_name: String) -> void:
	var enemy: Dictionary = state["current_enemy"]
	if enemy.is_empty():
		return
	# 敌人防御降低玩家造成的伤害，同样保留最低 1 点伤害。
	var damage: float = max(1.0, raw_damage - float(enemy.get("defense", 0.0)) * 0.45)
	enemy["hp"] = max(0.0, float(enemy.get("hp", 0.0)) - damage)
	state["total_damage"] = float(state["total_damage"]) + damage
	_log(state, "damage", "%s 对 %s 造成 %.1f 点伤害。" % [event_name, enemy.get("name", "敌人"), damage])
	_record_curve(state, event_name)


func _apply_effects(state: Dictionary, delta: float) -> void:
	var player: Dictionary = state["player"]
	var remaining_effects: Array = []
	for effect in state.get("active_effects", []):
		# 持续伤害绑定具体敌人实例；换怪后旧 DOT 不会错误打到新敌人。
		if effect.get("target_instance", "") != state["current_enemy"].get("instance_id", ""):
			continue
		effect["remaining"] = float(effect.get("remaining", 0.0)) - delta
		effect["tick_timer"] = float(effect.get("tick_timer", 0.0)) - delta
		while float(effect.get("tick_timer", 0.0)) <= 0.0 and float(effect.get("remaining", 0.0)) > 0.0:
			effect["tick_timer"] = float(effect.get("tick_timer", 0.0)) + float(effect.get("tick_interval", 1.0))
			var dot_multiplier: float = 1.0 + float(player["stats"].get("dot_multiplier", 0.0))
			# DOT 伤害不走暴击，主要受 attack、技能 power 和 dot_multiplier 影响。
			var damage: float = float(player["stats"].get("attack", 0.0)) * float(effect.get("power", 0.0)) * dot_multiplier
			_deal_damage_to_enemy(state, damage, "%s 持续伤害" % effect.get("name", "持续伤害"))
			if not _battle_continues(state):
				break
		if float(effect.get("remaining", 0.0)) > 0.0 and _battle_continues(state):
			remaining_effects.append(effect)
	state["active_effects"] = remaining_effects


func _regen_energy(player: Dictionary, delta: float) -> void:
	# 能量上限固定 100，Tick 模式传 0.1，回合制传 1.0。
	player["energy"] = min(100.0, float(player.get("energy", 0.0)) + float(player["stats"].get("energy_regen", 0.0)) * delta)


func _reduce_cooldowns(player: Dictionary, delta: float) -> void:
	# 冷却不会降到负数，策略只需要判断是否等于 0。
	for skill_id in player["cooldowns"].keys():
		player["cooldowns"][skill_id] = max(0.0, float(player["cooldowns"][skill_id]) - delta)


func _advance_enemy_if_needed(state: Dictionary) -> bool:
	if state["current_enemy"].is_empty():
		return false
	if float(state["current_enemy"].get("hp", 0.0)) > 0.0:
		return false

	# 当前敌人死亡后，立刻推进到队列中的下一只；这体现“按关卡定义排队战斗”。
	_log(state, "enemy_defeated", "%s 被击败。" % state["current_enemy"].get("name", "敌人"))
	state["enemies_defeated"] = int(state.get("enemies_defeated", 0)) + 1
	# DOT 只作用于当前敌人，换怪后清空避免跨目标污染。
	state["active_effects"] = []
	if state["enemy_queue"].is_empty():
		state["current_enemy"] = {}
		_record_curve(state, "战斗结束")
		return true
	state["current_enemy"] = state["enemy_queue"].pop_front()
	state["enemy_index"] = int(state["current_enemy"].get("queue_index", int(state.get("enemy_index", 0)) + 1))
	_log(state, "enemy_spawn", "%s 进入战斗。" % state["current_enemy"].get("name", "敌人"))
	_record_curve(state, "enemy_spawn")
	return true


func _battle_continues(state: Dictionary) -> bool:
	# 战斗继续的条件：玩家还活着，并且还有当前敌人。
	return float(state["player"].get("hp", 0.0)) > 0.0 and not state["current_enemy"].is_empty()


func _build_result(state: Dictionary, strategy: RefCounted, won: bool, reason: String) -> Dictionary:
	# result 是 UI、导出和测试共同依赖的数据契约，字段尽量保持稳定。
	return {
		"strategy": strategy.get_strategy_id(),
		"mode": state.get("mode", ""),
		"seed": state.get("seed", 0),
		"won": won,
		"reason": reason,
		"elapsed": state.get("time", 0.0),
		"turns": state.get("turn", 0),
		"ticks": state.get("tick", 0),
		"player_hp": state["player"].get("hp", 0.0),
		"player_max_hp": state["player"].get("max_hp", 0.0),
		"allocation": state["player"].get("allocation", {}),
		"items": state["player"].get("items", []),
		"affixes": state["player"].get("affixes", []),
		"enemy_total": state.get("enemy_total", 0),
		"enemies_defeated": state.get("enemies_defeated", 0),
		"enemy_progress": "%d/%d" % [int(state.get("enemies_defeated", 0)), int(state.get("enemy_total", 0))],
		"skill_casts": state.get("skill_casts", {}),
		"total_damage": state.get("total_damage", 0.0),
		"damage_taken": state.get("damage_taken", 0.0),
		"damage_curve": damage_curve,
		"logs": logs
	}


func _log(state: Dictionary, event_type: String, message: String) -> void:
	# event_type 目前主要用于代码可读性，日志文本给 UI 展示；限制长度防止批量结果过大。
	logs.append("%s %s" % [_format_log_prefix(state), message])
	if logs.size() > 300:
		logs.pop_front()


func _record_curve(state: Dictionary, event_name: String) -> void:
	# damage_curve 是实时血量、敌人进度和 CSV 导出的数据来源。
	var enemy_hp := 0.0
	var enemy_max_hp := 1.0
	var enemy_name := ""
	var enemy_index := int(state.get("enemy_index", 0))
	if not state["current_enemy"].is_empty():
		enemy_hp = float(state["current_enemy"].get("hp", 0.0))
		enemy_max_hp = max(1.0, float(state["current_enemy"].get("max_hp", 1.0)))
		enemy_name = str(state["current_enemy"].get("name", ""))
		enemy_index = int(state["current_enemy"].get("queue_index", enemy_index))
	damage_curve.append({
		"mode": str(state.get("mode", "")),
		"time": float(state.get("time", 0.0)),
		"tick": int(state.get("tick", 0)),
		"turn": int(state.get("turn", 0)),
		"total_damage": float(state.get("total_damage", 0.0)),
		"player_hp": float(state["player"].get("hp", 0.0)),
		"player_max_hp": float(state["player"].get("max_hp", 1.0)),
		"enemy_name": enemy_name,
		"enemy_index": enemy_index,
		"enemy_total": int(state.get("enemy_total", 0)),
		"enemies_defeated": int(state.get("enemies_defeated", 0)),
		"enemy_hp": enemy_hp,
		"enemy_max_hp": enemy_max_hp,
		"event": event_name
	})
	# 保留最近 1000 个点，避免长战斗导出超大文件。
	if damage_curve.size() > 1000:
		damage_curve.pop_front()


func _format_log_prefix(state: Dictionary) -> String:
	if str(state.get("mode", "")) == MODE_TURN:
		return "[第 %d 回合]" % int(state.get("turn", 0))
	return "[%.1f 秒 / Tick %d]" % [float(state.get("time", 0.0)), int(state.get("tick", 0))]


func _display_strategy(strategy_id: String) -> String:
	match strategy_id:
		"crit_burst":
			return "暴击爆发流"
		"corrosion":
			return "腐蚀持续流"
		_:
			return strategy_id


func _display_mode(mode_id: String) -> String:
	match mode_id:
		MODE_TICK:
			return "实时 Tick"
		MODE_TURN:
			return "回合制"
		_:
			return mode_id
