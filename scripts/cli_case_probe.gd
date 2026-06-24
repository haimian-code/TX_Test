extends SceneTree


# 单 seed 探针脚本。
# 用固定 seed 打印一场战斗的关键指标和前后日志，适合排查“某场为什么赢/输”。
const ConfigLoaderScript = preload("res://scripts/core/config_loader.gd")
const BattleSimulatorScript = preload("res://scripts/core/battle_simulator.gd")
const CritBurstStrategyScript = preload("res://scripts/strategies/crit_burst_strategy.gd")
const CorrosionStrategyScript = preload("res://scripts/strategies/corrosion_strategy.gd")


func _initialize() -> void:
	# 同一个 seed 分别跑四种组合，便于横向比较模式和流派差异。
	var loader = ConfigLoaderScript.new()
	var config: Dictionary = loader.load_config("res://data/sample_adventure.json")
	if config.is_empty():
		printerr("CONFIG_ERROR: %s" % loader.error_message)
		quit(1)
		return

	var simulator = BattleSimulatorScript.new(config)
	_probe(simulator, "crit_tick", CritBurstStrategyScript.new(), "tick", 20000)
	_probe(simulator, "crit_turn", CritBurstStrategyScript.new(), "turn", 20000)
	_probe(simulator, "corrosion_tick", CorrosionStrategyScript.new(), "tick", 20000)
	_probe(simulator, "corrosion_turn", CorrosionStrategyScript.new(), "turn", 20000)
	quit(0)


func _probe(simulator: RefCounted, title: String, strategy: RefCounted, mode: String, seed: int) -> void:
	# 打印摘要、技能释放次数和日志切片，不输出完整曲线，避免终端被刷屏。
	var result: Dictionary = simulator.run_once(strategy, mode, seed)
	var logs: Array = result.get("logs", [])
	var enemy_attacks: int = _count_contains(logs, "攻击玩家")
	var casts: Dictionary = result.get("skill_casts", {})
	print("PROBE %s seed=%d won=%s elapsed=%.1f hp=%.1f damage=%.1f taken=%.1f enemy_attacks=%d casts=%s" % [
		title,
		seed,
		str(result.get("won", false)),
		float(result.get("elapsed", 0.0)),
		float(result.get("player_hp", 0.0)),
		float(result.get("total_damage", 0.0)),
		float(result.get("damage_taken", 0.0)),
		enemy_attacks,
		str(casts)
	])
	print("  first_logs=%s" % str(logs.slice(0, min(12, logs.size()))))
	print("  last_logs=%s" % str(logs.slice(max(0, logs.size() - 12), logs.size())))


func _count_contains(logs: Array, needle: String) -> int:
	# 这里主要用来统计怪物攻击次数，辅助检查 attack_interval 是否符合预期。
	var count := 0
	for line in logs:
		if str(line).contains(needle):
			count += 1
	return count
