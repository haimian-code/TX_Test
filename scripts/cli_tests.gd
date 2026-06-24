extends SceneTree


# 核心回归测试脚本。
# 覆盖配置加载、策略 API 输出、确定性 seed、双模式、道具随机加成、敌人进度和导出功能。
const ConfigLoaderScript = preload("res://scripts/core/config_loader.gd")
const BattleSimulatorScript = preload("res://scripts/core/battle_simulator.gd")
const ResultExporterScript = preload("res://scripts/core/result_exporter.gd")
const CritBurstStrategyScript = preload("res://scripts/strategies/crit_burst_strategy.gd")
const CorrosionStrategyScript = preload("res://scripts/strategies/corrosion_strategy.gd")

var failures := 0


func _initialize() -> void:
	# Godot --script 入口：逐组执行断言，任何失败都会用非 0 状态退出。
	print("CLI_TESTS_START")
	_test_valid_config_loads()
	_test_bad_configs_report_errors()
	_test_strategy_outputs()
	_test_deterministic_seed()
	_test_tick_and_turn_results()
	_test_mode_markers_are_recorded()
	_test_corrosion_uses_dot()
	_test_random_affixes_are_recorded()
	_test_enemy_progress_is_recorded()
	_test_turn_mode_respects_attack_interval()
	_test_export_outputs()
	if failures == 0:
		print("CLI_TESTS_OK")
		quit(0)
	else:
		printerr("CLI_TESTS_FAILED count=%d" % failures)
		quit(1)


func _test_valid_config_loads() -> void:
	# 验证主配置满足必做模块需要的基础数据类型和数量。
	var loader = ConfigLoaderScript.new()
	var config: Dictionary = loader.load_config("res://data/sample_adventure.json")
	_assert(not config.is_empty(), "valid config loads")
	_assert(config.get("characters", []).size() == 1, "valid config has one character")
	_assert(config.get("skills", []).size() >= 3, "valid config has at least three skills")
	_assert(config.get("items", []).size() >= 3, "valid config has at least three items")
	_assert(config.get("monsters", []).size() >= 2, "valid config has at least two monsters")


func _test_bad_configs_report_errors() -> void:
	# 验证配置加载器能拒绝缺失引用、重复 id 和不存在文件，并给出可读错误。
	var loader = ConfigLoaderScript.new()
	var missing_skill: Dictionary = loader.load_config("res://data/test_fixtures/missing_skill.json")
	_assert(missing_skill.is_empty(), "missing skill config rejected")
	_assert(loader.error_message.contains("missing skill"), "missing skill error is clear")

	var duplicate: Dictionary = loader.load_config("res://data/test_fixtures/duplicate_id.json")
	_assert(duplicate.is_empty(), "duplicate id config rejected")
	_assert(loader.error_message.contains("duplicate id"), "duplicate id error is clear")

	var missing_file: Dictionary = loader.load_config("res://data/test_fixtures/not_found.json")
	_assert(missing_file.is_empty(), "missing file rejected")
	_assert(loader.error_message.contains("not found"), "missing file error is clear")


func _test_strategy_outputs() -> void:
	# 直接调用策略 API，确认策略不会超点数，并能选到各自核心装备。
	var loader = ConfigLoaderScript.new()
	var config: Dictionary = loader.load_config("res://data/sample_adventure.json")
	var character: Dictionary = config.get("characters", [])[0]
	var level: Dictionary = config.get("levels", [])[0]
	var context := {
		"points": int(character.get("attribute_points", 0)),
		"character": character,
		"level": level
	}

	var crit = CritBurstStrategyScript.new()
	var crit_alloc: Dictionary = crit.allocate_attributes(context)
	_assert(_sum_values(crit_alloc) <= int(context["points"]), "crit allocation within point budget")
	_assert(int(crit_alloc.get("attack", 0)) >= 1, "crit allocation invests in attack")

	var corrosion = CorrosionStrategyScript.new()
	var corrosion_alloc: Dictionary = corrosion.allocate_attributes(context)
	_assert(_sum_values(corrosion_alloc) <= int(context["points"]), "corrosion allocation within point budget")
	_assert(int(corrosion_alloc.get("defense", 0)) >= 1, "corrosion allocation invests in defense")

	var item_context := {
		"available_items": character.get("items", []),
		"character": character,
		"level": level
	}
	_assert(crit.choose_items(item_context).has("razor_lens"), "crit chooses razor lens")
	_assert(corrosion.choose_items(item_context).has("toxin_vial"), "corrosion chooses toxin vial")


func _test_deterministic_seed() -> void:
	# 固定 seed 是做可复现模拟的基础，同一输入应得到同一核心结果。
	var simulator = _build_simulator()
	var first: Dictionary = simulator.run_once(CritBurstStrategyScript.new(), "tick", 777)
	var second: Dictionary = simulator.run_once(CritBurstStrategyScript.new(), "tick", 777)
	_assert(_same_core_result(first, second), "same seed produces same core result")


func _test_tick_and_turn_results() -> void:
	# 验证两个流派在两种模式下都能跑出有效结果，并保持基本流派差异。
	var simulator = _build_simulator()
	var crit_tick: Dictionary = simulator.run_once(CritBurstStrategyScript.new(), "tick", 20000)
	var crit_turn: Dictionary = simulator.run_once(CritBurstStrategyScript.new(), "turn", 20000)
	var corrosion_tick: Dictionary = simulator.run_once(CorrosionStrategyScript.new(), "tick", 20000)
	var corrosion_turn: Dictionary = simulator.run_once(CorrosionStrategyScript.new(), "turn", 20000)
	_assert(crit_tick.has("won") and float(crit_tick.get("elapsed", 0.0)) > 0.0, "crit tick produces a valid result")
	_assert(crit_turn.has("won") and float(crit_turn.get("elapsed", 0.0)) > 0.0, "crit turn produces a valid result")
	_assert(corrosion_tick.has("won") and float(corrosion_tick.get("elapsed", 0.0)) > 0.0, "corrosion tick produces a valid result")
	_assert(corrosion_turn.has("won") and float(corrosion_turn.get("elapsed", 0.0)) > 0.0, "corrosion turn produces a valid result")
	_assert(float(crit_tick.get("elapsed", 0.0)) < float(corrosion_tick.get("elapsed", 0.0)), "crit tick faster than corrosion tick")
	_assert(float(crit_turn.get("elapsed", 0.0)) < float(corrosion_turn.get("elapsed", 0.0)), "crit turn faster than corrosion turn")
	var crit_batch: Dictionary = simulator.run_batch(CritBurstStrategyScript.new(), "tick", 30)
	var corrosion_batch: Dictionary = simulator.run_batch(CorrosionStrategyScript.new(), "tick", 30)
	_assert(float(crit_batch.get("win_rate", 0.0)) < 1.0 or float(corrosion_batch.get("win_rate", 0.0)) < 1.0, "batch win rate is not saturated for all strategies")


func _test_mode_markers_are_recorded() -> void:
	# UI 需要根据曲线/日志区分 Tick 和回合制，所以这里检查模式标记是否写入。
	var simulator = _build_simulator()
	var tick_result: Dictionary = simulator.run_once(CritBurstStrategyScript.new(), "tick", 20000)
	var turn_result: Dictionary = simulator.run_once(CritBurstStrategyScript.new(), "turn", 20000)
	var tick_curve: Array = tick_result.get("damage_curve", [])
	var turn_curve: Array = turn_result.get("damage_curve", [])
	_assert(not tick_curve.is_empty() and str(tick_curve[0].get("mode", "")) == "tick", "tick curve records mode")
	_assert(not turn_curve.is_empty() and str(turn_curve[0].get("mode", "")) == "turn", "turn curve records mode")
	_assert(not tick_curve.is_empty() and int(tick_curve[0].get("tick", 0)) > 0, "tick curve records tick number")
	_assert(not turn_curve.is_empty() and int(turn_curve[0].get("turn", 0)) > 0, "turn curve records turn number")
	_assert(_logs_have_text(tick_result.get("logs", []), "Tick"), "tick logs show tick marker")
	_assert(_logs_have_text(turn_result.get("logs", []), "回合"), "turn logs show turn marker")


func _test_corrosion_uses_dot() -> void:
	# 腐蚀流的核心是持续伤害覆盖率，不能退化成只靠普攻或直伤技能。
	var simulator = _build_simulator()
	var tick_result: Dictionary = simulator.run_once(CorrosionStrategyScript.new(), "tick", 20000)
	var turn_result: Dictionary = simulator.run_once(CorrosionStrategyScript.new(), "turn", 20000)
	_assert(int(tick_result.get("skill_casts", {}).get("ember_bloom", 0)) >= 5, "corrosion tick keeps dot coverage")
	_assert(int(turn_result.get("skill_casts", {}).get("ember_bloom", 0)) >= 5, "corrosion turn keeps dot coverage")
	_assert(_curve_has_event(tick_result.get("damage_curve", []), "持续伤害"), "corrosion tick curve has dot events")
	_assert(_curve_has_event(turn_result.get("damage_curve", []), "持续伤害"), "corrosion turn curve has dot events")


func _test_random_affixes_are_recorded() -> void:
	# 道具随机加成既要出现在单局结果中，也要能被批量统计；固定 seed 下加成也应可复现。
	var simulator = _build_simulator()
	var first: Dictionary = simulator.run_once(CritBurstStrategyScript.new(), "tick", 9090)
	var second: Dictionary = simulator.run_once(CritBurstStrategyScript.new(), "tick", 9090)
	var batch: Dictionary = simulator.run_batch(CritBurstStrategyScript.new(), "tick", 5)
	_assert(first.get("affixes", []).size() == first.get("items", []).size(), "single result records one random bonus per chosen item")
	_assert(str(first.get("affixes", [])) == str(second.get("affixes", [])), "same seed produces same random bonuses")
	_assert(not batch.get("affix_counts", {}).is_empty(), "batch result includes random bonus counts")


func _test_enemy_progress_is_recorded() -> void:
	# 敌人进度是 UI 实时展示的依据，结果和曲线点都必须记录总敌人数和当前敌人。
	var simulator = _build_simulator()
	var result: Dictionary = simulator.run_once(CritBurstStrategyScript.new(), "tick", 20000)
	var curve: Array = result.get("damage_curve", [])
	_assert(int(result.get("enemy_total", 0)) == 6, "result records total enemies")
	_assert(int(result.get("enemies_defeated", 0)) == 6, "result records defeated enemies")
	_assert(str(result.get("enemy_progress", "")) == "6/6", "result records final enemy progress")
	_assert(not curve.is_empty(), "damage curve exists for enemy progress")
	_assert(int(curve[0].get("enemy_total", 0)) == 6, "curve point records total enemies")
	_assert(str(curve[0].get("enemy_name", "")).length() > 0, "curve point records enemy name")


func _test_turn_mode_respects_attack_interval() -> void:
	# 回合制中怪物不应该每一回合都必定攻击，attack_interval 仍需生效。
	var simulator = _build_simulator()
	var turn_result: Dictionary = simulator.run_once(CorrosionStrategyScript.new(), "turn", 20000)
	var enemy_attack_logs := _count_log_contains(turn_result.get("logs", []), "攻击玩家")
	_assert(enemy_attack_logs < int(turn_result.get("turns", 0)), "turn enemy attacks fewer times than turns")
	_assert(enemy_attack_logs <= 16, "turn enemy attack count stays in expected range")


func _test_export_outputs() -> void:
	# 验证结果导出模块能写 JSON 和 CSV，CSV 表头保持稳定。
	var simulator = _build_simulator()
	var result: Dictionary = simulator.run_once(CritBurstStrategyScript.new(), "tick", 333)
	var exporter = ResultExporterScript.new()
	var json_path := "res://exports/test_result.json"
	var csv_path := "res://exports/test_result.csv"
	var json_error: String = exporter.export_json(result, json_path)
	var csv_error: String = exporter.export_csv(result, csv_path)
	_assert(json_error.is_empty(), "json export has no error")
	_assert(csv_error.is_empty(), "csv export has no error")
	_assert(FileAccess.file_exists(json_path), "json export file exists")
	_assert(FileAccess.file_exists(csv_path), "csv export file exists")
	var csv_text := FileAccess.get_file_as_string(csv_path)
	_assert(csv_text.begins_with("time,total_damage,player_hp,enemy_hp,event"), "csv header is correct")


func _build_simulator() -> RefCounted:
	# 测试统一从主配置构建模拟器，避免各测试重复加载代码。
	var loader = ConfigLoaderScript.new()
	var config: Dictionary = loader.load_config("res://data/sample_adventure.json")
	return BattleSimulatorScript.new(config)


func _same_core_result(left: Dictionary, right: Dictionary) -> bool:
	# 忽略日志对象地址等非核心字段，只比较会影响战斗结论的核心指标。
	return bool(left.get("won", false)) == bool(right.get("won", false)) \
		and is_equal_approx(float(left.get("elapsed", 0.0)), float(right.get("elapsed", 0.0))) \
		and is_equal_approx(float(left.get("player_hp", 0.0)), float(right.get("player_hp", 0.0))) \
		and is_equal_approx(float(left.get("total_damage", 0.0)), float(right.get("total_damage", 0.0))) \
		and str(left.get("skill_casts", {})) == str(right.get("skill_casts", {}))


func _sum_values(values: Dictionary) -> int:
	# 统计策略返回的非负加点总和，用于检查是否超过可用点数。
	var total := 0
	for key in values.keys():
		total += max(0, int(values[key]))
	return total


func _curve_has_event(curve: Array, needle: String) -> bool:
	for point in curve:
		if str(point.get("event", "")).contains(needle):
			return true
	return false


func _count_log_contains(logs: Array, needle: String) -> int:
	var count := 0
	for line in logs:
		if str(line).contains(needle):
			count += 1
	return count


func _logs_have_text(logs: Array, needle: String) -> bool:
	for line in logs:
		if str(line).contains(needle):
			return true
	return false


func _assert(condition: bool, label: String) -> void:
	if condition:
		print("PASS %s" % label)
	else:
		failures += 1
		printerr("FAIL %s" % label)
