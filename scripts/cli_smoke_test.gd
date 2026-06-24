extends SceneTree


# 冒烟测试脚本：用最短路径确认配置、单局、批量和导出都能跑通。
# 和 cli_tests.gd 相比，它更像“运行前快速自检”。
const ConfigLoaderScript = preload("res://scripts/core/config_loader.gd")
const BattleSimulatorScript = preload("res://scripts/core/battle_simulator.gd")
const ResultExporterScript = preload("res://scripts/core/result_exporter.gd")
const CritBurstStrategyScript = preload("res://scripts/strategies/crit_burst_strategy.gd")
const CorrosionStrategyScript = preload("res://scripts/strategies/corrosion_strategy.gd")


func _initialize() -> void:
	# 失败时立即 quit(1)，方便在命令行或 CI 中判断项目是否可运行。
	var loader = ConfigLoaderScript.new()
	var config: Dictionary = loader.load_config("res://data/sample_adventure.json")
	if config.is_empty():
		printerr("CONFIG_ERROR: %s" % loader.error_message)
		quit(1)
		return

	var simulator = BattleSimulatorScript.new(config)
	# 覆盖两个流派、两种典型模式，以及批量统计。
	var crit_once: Dictionary = simulator.run_once(CritBurstStrategyScript.new(), "tick", 1001)
	var corrosion_once: Dictionary = simulator.run_once(CorrosionStrategyScript.new(), "turn", 1002)
	var crit_batch: Dictionary = simulator.run_batch(CritBurstStrategyScript.new(), "tick", 10)
	var corrosion_batch: Dictionary = simulator.run_batch(CorrosionStrategyScript.new(), "tick", 10)

	var exporter = ResultExporterScript.new()
	# 冒烟测试也检查一次导出路径，避免文件写入权限或格式化问题漏掉。
	var json_error: String = exporter.export_json(crit_once, "res://exports/smoke_last.json")
	var csv_error: String = exporter.export_csv(crit_once, "res://exports/smoke_last.csv")
	if not json_error.is_empty() or not csv_error.is_empty():
		printerr("EXPORT_ERROR: %s %s" % [json_error, csv_error])
		quit(1)
		return

	print("SMOKE_OK")
	print("crit_once won=%s elapsed=%.1f hp=%.1f damage=%.1f" % [
		str(crit_once.get("won", false)),
		float(crit_once.get("elapsed", 0.0)),
		float(crit_once.get("player_hp", 0.0)),
		float(crit_once.get("total_damage", 0.0))
	])
	print("corrosion_once won=%s elapsed=%.1f hp=%.1f damage=%.1f" % [
		str(corrosion_once.get("won", false)),
		float(corrosion_once.get("elapsed", 0.0)),
		float(corrosion_once.get("player_hp", 0.0)),
		float(corrosion_once.get("total_damage", 0.0))
	])
	print("crit_batch win_rate=%.2f avg_elapsed=%.1f" % [
		float(crit_batch.get("win_rate", 0.0)),
		float(crit_batch.get("average_elapsed", 0.0))
	])
	print("corrosion_batch win_rate=%.2f avg_elapsed=%.1f" % [
		float(corrosion_batch.get("win_rate", 0.0)),
		float(corrosion_batch.get("average_elapsed", 0.0))
	])
	quit(0)
