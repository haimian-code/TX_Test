extends SceneTree


# 平衡性审计脚本。
# 固定跑 100 个 seed，用于观察两个流派在 Tick/回合制下的胜率、耗时、剩余生命和技能释放分布。
const ConfigLoaderScript = preload("res://scripts/core/config_loader.gd")
const BattleSimulatorScript = preload("res://scripts/core/battle_simulator.gd")
const CritBurstStrategyScript = preload("res://scripts/strategies/crit_burst_strategy.gd")
const CorrosionStrategyScript = preload("res://scripts/strategies/corrosion_strategy.gd")


func _initialize() -> void:
	# 这是诊断脚本，不直接断言成败，重点是打印稳定的统计数据供调参比较。
	var loader = ConfigLoaderScript.new()
	var config: Dictionary = loader.load_config("res://data/sample_adventure.json")
	if config.is_empty():
		printerr("CONFIG_ERROR: %s" % loader.error_message)
		quit(1)
		return

	var simulator = BattleSimulatorScript.new(config)
	# 四组组合：两个流派 × 两种模式。
	var test_cases: Array[Dictionary] = [
		{"name": "crit_tick", "strategy": CritBurstStrategyScript.new(), "mode": "tick"},
		{"name": "corrosion_tick", "strategy": CorrosionStrategyScript.new(), "mode": "tick"},
		{"name": "crit_turn", "strategy": CritBurstStrategyScript.new(), "mode": "turn"},
		{"name": "corrosion_turn", "strategy": CorrosionStrategyScript.new(), "mode": "turn"}
	]

	print("BALANCE_AUDIT runs=100 seeds=20000..20099")
	for test_case in test_cases:
		var summary := _run_case(simulator, test_case)
		_print_summary(summary)
		print("")
	quit(0)


func _run_case(simulator: RefCounted, test_case: Dictionary) -> Dictionary:
	# 汇总一组 100 场结果，返回平均值、极值、失败原因和少量样本。
	var results: Array[Dictionary] = []
	var wins := 0
	var total_elapsed := 0.0
	var total_hp := 0.0
	var total_damage := 0.0
	var total_taken := 0.0
	var min_elapsed := INF
	var max_elapsed := 0.0
	var min_hp := INF
	var max_hp := 0.0
	var skill_totals := {}
	var reasons := {}
	var samples: Array[Dictionary] = []

	for i in 100:
		# 使用固定 seed 区间，便于修改怪物数值后做前后对比。
		var seed := 20000 + i
		var result: Dictionary = simulator.run_once(test_case["strategy"], str(test_case["mode"]), seed)
		results.append(result)
		if bool(result.get("won", false)):
			wins += 1
		total_elapsed += float(result.get("elapsed", 0.0))
		total_hp += float(result.get("player_hp", 0.0))
		total_damage += float(result.get("total_damage", 0.0))
		total_taken += float(result.get("damage_taken", 0.0))
		min_elapsed = min(min_elapsed, float(result.get("elapsed", 0.0)))
		max_elapsed = max(max_elapsed, float(result.get("elapsed", 0.0)))
		min_hp = min(min_hp, float(result.get("player_hp", 0.0)))
		max_hp = max(max_hp, float(result.get("player_hp", 0.0)))
		var reason := str(result.get("reason", "unknown"))
		reasons[reason] = int(reasons.get(reason, 0)) + 1
		var casts: Dictionary = result.get("skill_casts", {})
		for skill_id in casts.keys():
			skill_totals[skill_id] = int(skill_totals.get(skill_id, 0)) + int(casts[skill_id])
		if samples.size() < 5:
			# 保留前几个样本，方便发现统计异常时回到具体 seed 排查。
			samples.append({
				"seed": seed,
				"won": result.get("won", false),
				"elapsed": result.get("elapsed", 0.0),
				"hp": result.get("player_hp", 0.0),
				"damage": result.get("total_damage", 0.0),
				"taken": result.get("damage_taken", 0.0),
				"casts": result.get("skill_casts", {})
			})

	var runs := float(results.size())
	return {
		"name": test_case["name"],
		"runs": int(runs),
		"wins": wins,
		"win_rate": float(wins) / runs,
		"avg_elapsed": total_elapsed / runs,
		"min_elapsed": min_elapsed,
		"max_elapsed": max_elapsed,
		"avg_hp": total_hp / runs,
		"min_hp": min_hp,
		"max_hp": max_hp,
		"avg_damage": total_damage / runs,
		"avg_taken": total_taken / runs,
		"avg_skill_casts": _average_skill_casts(skill_totals, runs),
		"reasons": reasons,
		"samples": samples
	}


func _average_skill_casts(skill_totals: Dictionary, runs: float) -> Dictionary:
	# 把技能总释放次数转换成“每场平均释放次数”。
	var result := {}
	for skill_id in skill_totals.keys():
		result[skill_id] = float(skill_totals[skill_id]) / runs
	return result


func _print_summary(summary: Dictionary) -> void:
	# 输出保持固定格式，方便复制到文档或和历史结果对比。
	print("CASE %s" % summary.get("name", ""))
	print("  wins=%d/%d win_rate=%.2f" % [
		int(summary.get("wins", 0)),
		int(summary.get("runs", 0)),
		float(summary.get("win_rate", 0.0))
	])
	print("  elapsed avg=%.2f min=%.2f max=%.2f" % [
		float(summary.get("avg_elapsed", 0.0)),
		float(summary.get("min_elapsed", 0.0)),
		float(summary.get("max_elapsed", 0.0))
	])
	print("  player_hp avg=%.2f min=%.2f max=%.2f" % [
		float(summary.get("avg_hp", 0.0)),
		float(summary.get("min_hp", 0.0)),
		float(summary.get("max_hp", 0.0))
	])
	print("  damage avg=%.2f taken avg=%.2f" % [
		float(summary.get("avg_damage", 0.0)),
		float(summary.get("avg_taken", 0.0))
	])
	print("  avg_skill_casts=%s" % str(summary.get("avg_skill_casts", {})))
	print("  reasons=%s" % str(summary.get("reasons", {})))
	print("  samples=%s" % str(summary.get("samples", [])))
