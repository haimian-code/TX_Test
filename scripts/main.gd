extends Control


# 主界面脚本负责把 UI 控件、配置加载、模拟器调用、结果展示串起来。
# 战斗规则不写在这里，实际结算都在 BattleSimulator 中。
const BattleSimulatorScript = preload("res://scripts/core/battle_simulator.gd")
const ConfigLoaderScript = preload("res://scripts/core/config_loader.gd")
const ResultExporterScript = preload("res://scripts/core/result_exporter.gd")
const CritBurstStrategyScript = preload("res://scripts/strategies/crit_burst_strategy.gd")
const CorrosionStrategyScript = preload("res://scripts/strategies/corrosion_strategy.gd")

const CONFIG_PATH := "res://data/sample_adventure.json"
const MODE_TICK := "tick"
const MODE_TURN := "turn"

# 当前加载的配置和模拟器实例。配置加载成功后才允许运行模拟。
var config: Dictionary = {}
var simulator: RefCounted

# 最近一次单局结果和最近一次批量/对比结果，用于 UI 展示和导出。
var last_result: Dictionary = {}
var last_batch: Dictionary = {}

# UI 节点由 _build_ui 动态创建，避免手工维护复杂场景树。
var status_label: Label
var strategy_option: OptionButton
var mode_option: OptionButton
var runs_spin: SpinBox
var summary_label: Label
var curve_label: RichTextLabel
var log_label: RichTextLabel
var player_hp_bar: ProgressBar
var enemy_hp_bar: ProgressBar
var player_hp_text: Label
var enemy_hp_text: Label
var enemy_progress_text: Label
var mode_info_text: Label
var replay_status_text: Label
var batch_replay_spin: SpinBox
var play_batch_button: Button
var batch_summary_button: Button

# 单局回放是异步播放的；token 用来在新模拟开始时取消旧回放。
var replay_token := 0


func _ready() -> void:
	_build_ui()
	_load_config()


func _build_ui() -> void:
	# 这里用代码搭建界面，便于在一个文件里看清 UI 控件和信号绑定关系。
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 8)
	root.offset_left = 16
	root.offset_top = 12
	root.offset_right = -16
	root.offset_bottom = -12
	add_child(root)

	var title := Label.new()
	title.text = "肉鸽流派模拟验证器"
	title.add_theme_font_size_override("font_size", 24)
	root.add_child(title)

	status_label = Label.new()
	status_label.text = "正在加载..."
	root.add_child(status_label)

	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation", 10)
	root.add_child(controls)

	# 流派下拉框存显示名和策略 id；创建策略时读取 metadata。
	strategy_option = OptionButton.new()
	strategy_option.add_item("暴击爆发流", 0)
	strategy_option.set_item_metadata(0, "crit_burst")
	strategy_option.add_item("情绪净化流", 1)
	strategy_option.set_item_metadata(1, "corrosion")
	controls.add_child(_labeled_control("流派策略", strategy_option))

	# 模式下拉框存 tick/turn 两种内部模式 id。
	mode_option = OptionButton.new()
	mode_option.add_item("实时 Tick", 0)
	mode_option.set_item_metadata(0, MODE_TICK)
	mode_option.add_item("回合制", 1)
	mode_option.set_item_metadata(1, MODE_TURN)
	controls.add_child(_labeled_control("战斗模式", mode_option))

	# 批量次数控制 run_batch 的重复场数，越大统计越稳定但 UI 文本越长。
	runs_spin = SpinBox.new()
	runs_spin.min_value = 1
	runs_spin.max_value = 500
	runs_spin.step = 1
	runs_spin.value = 50
	runs_spin.custom_minimum_size.x = 96
	controls.add_child(_labeled_control("批量次数", runs_spin))

	var run_once_button := Button.new()
	run_once_button.text = "运行单局"
	run_once_button.pressed.connect(_on_run_once)
	controls.add_child(run_once_button)

	var batch_button := Button.new()
	batch_button.text = "批量模拟"
	batch_button.pressed.connect(_on_run_batch)
	controls.add_child(batch_button)

	var compare_button := Button.new()
	compare_button.text = "对比流派"
	compare_button.pressed.connect(_on_compare)
	controls.add_child(compare_button)

	var export_button := Button.new()
	export_button.text = "导出结果"
	export_button.pressed.connect(_on_export_last)
	controls.add_child(export_button)

	var batch_replay_controls := HBoxContainer.new()
	batch_replay_controls.add_theme_constant_override("separation", 10)
	root.add_child(batch_replay_controls)

	batch_replay_spin = SpinBox.new()
	batch_replay_spin.min_value = 1
	batch_replay_spin.max_value = 1
	batch_replay_spin.step = 1
	batch_replay_spin.value = 1
	batch_replay_spin.custom_minimum_size.x = 96
	batch_replay_controls.add_child(_labeled_control("批量回放场次", batch_replay_spin))

	play_batch_button = Button.new()
	play_batch_button.text = "播放场次"
	play_batch_button.pressed.connect(_on_play_batch_run)
	batch_replay_controls.add_child(play_batch_button)

	batch_summary_button = Button.new()
	batch_summary_button.text = "返回批量统计"
	batch_summary_button.pressed.connect(_on_show_batch_summary)
	batch_replay_controls.add_child(batch_summary_button)

	# 顶部生命条显示单局回放的当前状态；批量/对比时显示代表性最终状态或等待态。
	var bars := GridContainer.new()
	bars.columns = 2
	bars.add_theme_constant_override("h_separation", 12)
	bars.add_theme_constant_override("v_separation", 4)
	root.add_child(bars)

	player_hp_text = Label.new()
	player_hp_text.text = "玩家生命"
	bars.add_child(player_hp_text)
	enemy_hp_text = Label.new()
	enemy_hp_text.text = "敌人生命"
	bars.add_child(enemy_hp_text)

	player_hp_bar = ProgressBar.new()
	player_hp_bar.custom_minimum_size = Vector2(420, 22)
	player_hp_bar.max_value = 1
	player_hp_bar.value = 0
	bars.add_child(player_hp_bar)

	enemy_hp_bar = ProgressBar.new()
	enemy_hp_bar.custom_minimum_size = Vector2(420, 22)
	enemy_hp_bar.max_value = 1
	enemy_hp_bar.value = 0
	bars.add_child(enemy_hp_bar)

	enemy_progress_text = Label.new()
	enemy_progress_text.text = "敌人进度 0 / 0"
	enemy_progress_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(enemy_progress_text)

	mode_info_text = Label.new()
	mode_info_text.text = "模式说明：尚未开始模拟"
	mode_info_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(mode_info_text)

	replay_status_text = Label.new()
	replay_status_text.text = "回放状态：等待运行"
	replay_status_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(replay_status_text)

	summary_label = Label.new()
	summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	summary_label.text = "暂无模拟结果。"
	root.add_child(summary_label)

	# 左右输出区：左侧偏统计/曲线，右侧偏战斗日志。
	var output := HSplitContainer.new()
	output.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(output)

	curve_label = RichTextLabel.new()
	curve_label.fit_content = false
	curve_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	curve_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	curve_label.bbcode_enabled = false
	output.add_child(curve_label)

	log_label = RichTextLabel.new()
	log_label.fit_content = false
	log_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	log_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_label.bbcode_enabled = false
	output.add_child(log_label)

	_reset_output()


func _labeled_control(label_text: String, control: Control) -> Control:
	# 小型布局工具：给下拉框、数字框等控件统一加标题。
	var box := VBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	box.add_child(label)
	box.add_child(control)
	return box


func _load_config() -> void:
	var loader = ConfigLoaderScript.new()
	config = loader.load_config(CONFIG_PATH)
	if config.is_empty():
		status_label.text = "配置加载失败：%s" % loader.error_message
		return
	simulator = BattleSimulatorScript.new(config)
	status_label.text = "已加载配置：%s" % config.get("adventure", {}).get("name", "未命名")
	# 配置重新加载后清空旧结果，避免界面显示和当前配置不一致。
	_reset_output()


func _reset_output() -> void:
	# 新开界面或重新加载配置时，所有结果区回到明确的“等待运行”状态。
	replay_token += 1
	last_result = {}
	last_batch = {}
	_set_batch_replay_controls(false, 1, 1)
	player_hp_bar.max_value = 1.0
	player_hp_bar.value = 0.0
	enemy_hp_bar.max_value = 1.0
	enemy_hp_bar.value = 0.0
	player_hp_text.text = "玩家生命：等待运行"
	enemy_hp_text.text = "敌人生命：等待运行"
	enemy_progress_text.text = "敌人进度：等待运行"
	mode_info_text.text = "模式说明：请选择模式后运行模拟"
	replay_status_text.text = "回放状态：等待运行"
	summary_label.text = "暂无模拟结果。"
	curve_label.text = "等待运行模拟。这里会在单局/批量/对比后显示伤害曲线或统计结果。"
	log_label.text = "等待运行模拟。这里会在运行后显示战斗日志。"


func _on_run_once() -> void:
	if simulator == null:
		return
	# 单局模拟：创建当前选中的策略，交给模拟器运行一次，然后播放过程。
	var strategy := _create_selected_strategy()
	var mode := _selected_mode()
	last_result = simulator.run_once(strategy, mode)
	last_batch = {}
	_set_batch_replay_controls(false, 1, 1)
	_show_single_result(last_result)


func _on_run_batch() -> void:
	if simulator == null:
		return
	# 批量模拟：同一个策略重复运行多场，用来观察胜率和结果分布。
	var strategy := _create_selected_strategy()
	var mode := _selected_mode()
	last_batch = simulator.run_batch(strategy, mode, int(runs_spin.value))
	if not last_batch.get("results", []).is_empty():
		# 详细日志和生命条默认使用最后一场；所有场次的最终结果会在表格中列出。
		last_result = last_batch["results"][-1]
	_show_batch_result(last_batch, last_batch.get("results", []).size())


func _on_compare() -> void:
	if simulator == null:
		return
	# 对比流派：同一模式和次数下分别跑两个策略，生成并列统计。
	var mode := _selected_mode()
	var runs := int(runs_spin.value)
	var crit: Dictionary = simulator.run_batch(CritBurstStrategyScript.new(), mode, runs)
	var corrosion: Dictionary = simulator.run_batch(CorrosionStrategyScript.new(), mode, runs)
	last_batch = {
		"type": "comparison",
		"mode": mode,
		"runs": runs,
		"crit_burst": crit,
		"corrosion": corrosion
	}
	if not crit.get("results", []).is_empty():
		# 对比时也保留一个 last_result，方便导出 CSV 时有单场曲线。
		last_result = crit["results"][-1]
	_set_batch_replay_controls(false, 1, 1)
	_show_compare_result(crit, corrosion)


func _on_play_batch_run() -> void:
	if not _has_plain_batch_results():
		status_label.text = "请先运行“批量模拟”，再选择要回放的场次。"
		return
	var results: Array = last_batch.get("results", [])
	var run_number: int = clamp(int(batch_replay_spin.value), 1, results.size())
	var result: Dictionary = results[run_number - 1]
	last_result = result
	_show_batch_replay_result(result, run_number, results.size())


func _on_show_batch_summary() -> void:
	if not _has_plain_batch_results():
		status_label.text = "当前没有可返回的批量统计。"
		return
	if not last_batch.get("results", []).is_empty():
		var results: Array = last_batch.get("results", [])
		last_result = results[clamp(int(batch_replay_spin.value), 1, results.size()) - 1]
		_show_batch_result(last_batch, int(batch_replay_spin.value))


func _on_export_last() -> void:
	if last_result.is_empty() and last_batch.is_empty():
		status_label.text = "还没有可导出的结果。"
		return

	var dir := DirAccess.open("res://")
	if dir != null and not dir.dir_exists("exports"):
		dir.make_dir("exports")

	var exporter = ResultExporterScript.new()
	var stamp := Time.get_datetime_string_from_system().replace(":", "-")
	# JSON 优先导出批量/对比完整结构；如果只有单局，则导出单局结果。
	var target := last_batch if not last_batch.is_empty() else last_result
	var json_path := "res://exports/result_%s.json" % stamp
	var csv_path := "res://exports/result_%s.csv" % stamp
	var json_error: String = exporter.export_json(target, json_path)
	var csv_error := ""
	if not last_result.is_empty():
		# CSV 是单场伤害曲线格式，所以只导出最近一场 last_result。
		csv_error = exporter.export_csv(last_result, csv_path)
	if json_error.is_empty() and csv_error.is_empty():
		status_label.text = "已导出到 exports/result_%s.json 和 .csv" % stamp
	else:
		status_label.text = "导出失败：%s %s" % [json_error, csv_error]


func _create_selected_strategy() -> RefCounted:
	# UI 层负责把下拉框选项转成策略实例；战斗模拟器只接收策略接口对象。
	var selected := str(strategy_option.get_selected_metadata())
	match selected:
		"corrosion":
			return CorrosionStrategyScript.new()
		_:
			return CritBurstStrategyScript.new()


func _selected_mode() -> String:
	# 返回内部模式 id，而不是显示文本，避免 UI 文案变化影响逻辑。
	return str(mode_option.get_selected_metadata())


func _display_strategy(strategy_id) -> String:
	match str(strategy_id):
		"crit_burst":
			return "暴击爆发流"
		"corrosion":
			return "情绪净化流"
		_:
			return str(strategy_id)


func _display_mode(mode_id) -> String:
	match str(mode_id):
		MODE_TICK:
			return "实时 Tick"
		MODE_TURN:
			return "回合制"
		_:
			return str(mode_id)


func _display_bool(value) -> String:
	return "胜利" if bool(value) else "失败"


func _display_reason(reason) -> String:
	match str(reason):
		"victory":
			return "胜利"
		"defeat":
			return "失败"
		"time_limit":
			return "达到时间上限"
		_:
			return str(reason)


func _show_single_result(result: Dictionary) -> void:
	replay_token += 1
	_update_mode_info(result.get("mode", ""))
	_update_bars(result)
	# 单局摘要展示最关键的结论，完整过程放在曲线和日志里。
	summary_label.text = "流派：%s | 模式：%s | 结果：%s | 原因：%s | 耗时：%.1f | 生命：%.1f/%.1f | 伤害：%.1f | 承伤：%.1f | 技能：%s | 道具随机加成：%s" % [
		_display_strategy(result.get("strategy", "")),
		_display_mode(result.get("mode", "")),
		_display_bool(result.get("won", false)),
		_display_reason(result.get("reason", "")),
		float(result.get("elapsed", 0.0)),
		float(result.get("player_hp", 0.0)),
		float(result.get("player_max_hp", 0.0)),
		float(result.get("total_damage", 0.0)),
		float(result.get("damage_taken", 0.0)),
		_format_skill_casts(result.get("skill_casts", {})),
		_format_item_bonuses(result.get("affixes", []))
	]
	curve_label.text = _format_curve(result.get("damage_curve", []))
	log_label.text = "\n".join(result.get("logs", []))
	# 异步播放血量变化，让单局效果不只是最终数字。
	_replay_single_result(result, replay_token)


func _show_batch_result(batch: Dictionary, selected_run: int = -1) -> void:
	replay_token += 1
	_update_mode_info(batch.get("mode", ""))
	var results: Array = batch.get("results", [])
	var shown_run: int = results.size()
	var selected: int = shown_run if selected_run <= 0 else int(clamp(selected_run, 1, max(1, shown_run)))
	_set_batch_replay_controls(not results.is_empty(), max(1, shown_run), selected)
	# 批量模式不播放每场过程，重点是统计和逐场最终结果。
	replay_status_text.text = "回放状态：批量模拟显示统计结果，不播放单局过程；可选择 1-%d 场回放" % shown_run
	summary_label.text = "批量模拟 | 流派：%s | 模式：%s | 次数：%d | 胜率：%.1f%% | 平均耗时：%.1f | 平均生命：%.1f | 平均伤害：%.1f | 已列出全部场次结果" % [
		_display_strategy(batch.get("strategy", "")),
		_display_mode(batch.get("mode", "")),
		int(batch.get("runs", 0)),
		float(batch.get("win_rate", 0.0)) * 100.0,
		float(batch.get("average_elapsed", 0.0)),
		float(batch.get("average_player_hp", 0.0)),
		float(batch.get("average_total_damage", 0.0))
	]
	curve_label.text = "道具随机加成统计：%s\n\n%s" % [_format_item_bonus_counts(batch.get("affix_counts", {})), _format_batch_rows(batch)]
	if not last_result.is_empty():
		_update_bars(last_result)
		# 完整展示所有场次日志会淹没信息，所以右侧只显示最后一场详细日志。
		log_label.text = "当前详细日志：第 %d 场 / 共 %d 场。可修改“批量回放场次”并点击“播放场次”查看任意一场。\n\n%s" % [
			selected,
			shown_run,
			"\n".join(last_result.get("logs", []))
		]


func _show_batch_replay_result(result: Dictionary, run_number: int, total_runs: int) -> void:
	replay_token += 1
	_update_mode_info(result.get("mode", ""))
	_update_bars(result)
	summary_label.text = "批量回放 | 第 %d / %d 场 | 流派：%s | 模式：%s | 结果：%s | 原因：%s | 耗时：%.1f | 生命：%.1f/%.1f | 伤害：%.1f | 承伤：%.1f | 技能：%s | 道具随机加成：%s" % [
		run_number,
		total_runs,
		_display_strategy(result.get("strategy", "")),
		_display_mode(result.get("mode", "")),
		_display_bool(result.get("won", false)),
		_display_reason(result.get("reason", "")),
		float(result.get("elapsed", 0.0)),
		float(result.get("player_hp", 0.0)),
		float(result.get("player_max_hp", 0.0)),
		float(result.get("total_damage", 0.0)),
		float(result.get("damage_taken", 0.0)),
		_format_skill_casts(result.get("skill_casts", {})),
		_format_item_bonuses(result.get("affixes", []))
	]
	curve_label.text = _format_curve(result.get("damage_curve", []))
	log_label.text = "批量模拟第 %d / %d 场详细日志：\n\n%s" % [
		run_number,
		total_runs,
		"\n".join(result.get("logs", []))
	]
	_replay_single_result(result, replay_token)


func _has_plain_batch_results() -> bool:
	return not last_batch.is_empty() and not last_batch.has("type") and not last_batch.get("results", []).is_empty()


func _set_batch_replay_controls(enabled: bool, max_run: int, selected_run: int) -> void:
	var safe_max: int = max(1, max_run)
	var safe_selected: int = clamp(selected_run, 1, safe_max)
	batch_replay_spin.max_value = safe_max
	batch_replay_spin.value = safe_selected
	batch_replay_spin.editable = enabled
	play_batch_button.disabled = not enabled
	batch_summary_button.disabled = not enabled


func _show_compare_result(crit: Dictionary, corrosion: Dictionary) -> void:
	replay_token += 1
	_update_mode_info(crit.get("mode", ""))
	# 对比模式只展示统计结果，不播放单局动画，否则两套策略的过程会混在一起。
	_set_compare_bars_state()
	summary_label.text = "流派对比 | 模式：%s | 次数：%d\n暴击爆发流：胜率 %.1f%%，平均耗时 %.1f，平均生命 %.1f，平均伤害 %.1f\n情绪净化流：胜率 %.1f%%，平均耗时 %.1f，平均生命 %.1f，平均伤害 %.1f" % [
		_display_mode(crit.get("mode", "")),
		int(crit.get("runs", 0)),
		float(crit.get("win_rate", 0.0)) * 100.0,
		float(crit.get("average_elapsed", 0.0)),
		float(crit.get("average_player_hp", 0.0)),
		float(crit.get("average_total_damage", 0.0)),
		float(corrosion.get("win_rate", 0.0)) * 100.0,
		float(corrosion.get("average_elapsed", 0.0)),
		float(corrosion.get("average_player_hp", 0.0)),
		float(corrosion.get("average_total_damage", 0.0))
	]
	curve_label.text = "%s\n\n%s\n\n%s" % [_format_compare_table(crit, corrosion), _format_batch_rows(crit), _format_batch_rows(corrosion)]
	log_label.text = "对比完成。可点击“导出结果”保存 JSON。\n道具随机加成统计已在左侧“流派对比统计”中展示。"


func _set_compare_bars_state() -> void:
	# 对比模式是多场统计，不对应某一场实时血量；这里明确清空血量条，避免用户误读。
	player_hp_bar.max_value = 1.0
	player_hp_bar.value = 0.0
	enemy_hp_bar.max_value = 1.0
	enemy_hp_bar.value = 0.0
	player_hp_text.text = "玩家生命：对比模式不显示单局血量"
	enemy_hp_text.text = "敌人生命：对比模式不显示单局血量"
	enemy_progress_text.text = "敌人进度：对比模式显示统计结果"
	replay_status_text.text = "回放状态：流派对比显示统计结果，不播放单局过程"


func _update_bars(result: Dictionary) -> void:
	# 把单场结果的最终点同步到顶部血量条。
	var max_hp: float = max(1.0, float(result.get("player_max_hp", 1.0)))
	var hp := float(result.get("player_hp", 0.0))
	player_hp_bar.max_value = max_hp
	player_hp_bar.value = hp
	player_hp_text.text = "玩家生命 %.1f / %.1f" % [hp, max_hp]

	var curve: Array = result.get("damage_curve", [])
	if not curve.is_empty():
		# 如果有曲线，最后一个点包含最终敌人血量和进度。
		_apply_curve_point(curve[-1])
	else:
		enemy_hp_bar.max_value = 1.0
		enemy_hp_bar.value = 0.0
		enemy_hp_text.text = "敌人生命 0.0 / 0.0"
		enemy_progress_text.text = "敌人进度 %s" % result.get("enemy_progress", "0/0")


func _apply_curve_point(point: Dictionary) -> void:
	# 单个曲线点同时驱动玩家血量、当前敌人血量、敌人进度和回放状态。
	var player_max_hp: float = max(1.0, float(point.get("player_max_hp", player_hp_bar.max_value)))
	var player_hp: float = clamp(float(point.get("player_hp", 0.0)), 0.0, player_max_hp)
	player_hp_bar.max_value = player_max_hp
	player_hp_bar.value = player_hp
	player_hp_text.text = "玩家生命 %.1f / %.1f" % [player_hp, player_max_hp]

	var enemy_max_hp: float = max(1.0, float(point.get("enemy_max_hp", 1.0)))
	var enemy_hp: float = clamp(float(point.get("enemy_hp", 0.0)), 0.0, enemy_max_hp)
	var enemy_name := str(point.get("enemy_name", ""))
	var enemy_index := int(point.get("enemy_index", 0))
	var enemy_total := int(point.get("enemy_total", 0))
	var defeated := int(point.get("enemies_defeated", 0))
	enemy_hp_bar.max_value = enemy_max_hp
	enemy_hp_bar.value = enemy_hp
	if enemy_name.is_empty():
		enemy_hp_text.text = "敌人生命 0.0 / %.1f" % enemy_max_hp
	else:
		enemy_hp_text.text = "%s 生命 %.1f / %.1f" % [enemy_name, enemy_hp, enemy_max_hp]
	enemy_progress_text.text = "敌人进度 %d / %d 已击败，当前第 %d 只" % [defeated, enemy_total, enemy_index]
	replay_status_text.text = _format_replay_status(point)


func _replay_single_result(result: Dictionary, token: int) -> void:
	var curve: Array = result.get("damage_curve", [])
	if not curve.is_empty():
		replay_status_text.text = "回放状态：开始播放单局过程"
		# 曲线可能很多点，按比例抽样播放，保证动画不会拖太久。
		var step: int = max(1, int(ceil(float(curve.size()) / 80.0)))
		var previous_turn := -1
		for i in range(0, curve.size(), step):
			# 新模拟开始时 replay_token 会变化，旧回放立即停止。
			if token != replay_token:
				return
			_apply_curve_point(curve[i])
			var delay := _replay_delay(curve[i], previous_turn)
			previous_turn = int(curve[i].get("turn", previous_turn))
			await get_tree().create_timer(delay).timeout
		if token == replay_token:
			_apply_curve_point(curve[-1])
			enemy_progress_text.text = "敌人进度 %d / %d 已击败，战斗结束" % [
				int(result.get("enemies_defeated", 0)),
				int(result.get("enemy_total", 0))
			]
			replay_status_text.text = "回放状态：战斗结束，%s" % _format_time_marker(result.get("damage_curve", [])[-1])


func _update_mode_info(mode_id) -> void:
	# 明确解释两种模式差异，避免用户只看到名字却感觉表现接近。
	if str(mode_id) == MODE_TURN:
		mode_info_text.text = "模式说明：回合制。每回合按速度决定先后手，技能冷却、能量和持续伤害按回合结算。"
	else:
		mode_info_text.text = "模式说明：实时 Tick。每 0.1 秒推进一次，技能冷却、能量、攻击间隔和持续伤害连续结算。"


func _format_replay_status(point: Dictionary) -> String:
	return "回放状态：%s，事件：%s" % [_format_time_marker(point), str(point.get("event", ""))]


func _format_time_marker(point: Dictionary) -> String:
	if str(point.get("mode", "")) == MODE_TURN:
		return "第 %d 回合" % int(point.get("turn", 0))
	return "%.1f 秒 / Tick %d" % [float(point.get("time", 0.0)), int(point.get("tick", 0))]


func _replay_delay(point: Dictionary, previous_turn: int) -> float:
	# 回合制按回合节奏播放，Tick 模式用更短延迟表现连续推进。
	if str(point.get("mode", "")) == MODE_TURN:
		var turn := int(point.get("turn", 0))
		return 0.20 if turn != previous_turn else 0.06
	return 0.035


func _format_curve(curve: Array) -> String:
	if curve.is_empty():
		return "暂无伤害曲线。"
	var lines: Array[String] = ["时间/回合 | 累计伤害 | 玩家生命 | 敌人 | 敌人生命 | 进度 | 事件"]
	# UI 只显示最近 80 个点，避免长战斗把文本区撑得太乱；完整数据仍在导出 JSON 中。
	var start: int = max(0, curve.size() - 80)
	for i in range(start, curve.size()):
		var point: Dictionary = curve[i]
		lines.append("%s | %12.1f | %9.1f | %s | %8.1f | %d/%d | %s" % [
			_format_time_marker(point),
			float(point.get("total_damage", 0.0)),
			float(point.get("player_hp", 0.0)),
			str(point.get("enemy_name", "")),
			float(point.get("enemy_hp", 0.0)),
			int(point.get("enemies_defeated", 0)),
			int(point.get("enemy_total", 0)),
			str(point.get("event", ""))
		])
	return "\n".join(lines)


func _format_batch_rows(batch: Dictionary) -> String:
	var results: Array = batch.get("results", [])
	# 批量表列出全部场次的最终结果，用于观察道具随机加成和暴击导致的分布差异。
	var lines: Array[String] = ["逐场结果 %s（%s，共 %d 场）" % [
		_display_strategy(batch.get("strategy", "")),
		_display_mode(batch.get("mode", "")),
		results.size()
	]]
	lines.append("场次 | 种子 | 结果 | 原因 | 耗时 | 剩余生命 | 敌人进度 | 总伤害 | 承伤 | 道具随机加成")
	for i in results.size():
		var result: Dictionary = results[i]
		lines.append("%d | %s | %s | %s | %.1f | %.1f/%.1f | %d/%d | %.1f | %.1f | %s" % [
			i + 1,
			str(result.get("seed", "")),
			_display_bool(result.get("won", false)),
			_display_reason(result.get("reason", "")),
			float(result.get("elapsed", 0.0)),
			float(result.get("player_hp", 0.0)),
			float(result.get("player_max_hp", 0.0)),
			int(result.get("enemies_defeated", 0)),
			int(result.get("enemy_total", 0)),
			float(result.get("total_damage", 0.0)),
			float(result.get("damage_taken", 0.0)),
			_format_item_bonuses(result.get("affixes", []))
		])
	return "\n".join(lines)


func _format_compare_table(crit: Dictionary, corrosion: Dictionary) -> String:
	# 对比面板使用纯数字表，避免早期文本柱状图中的 # 和 . 造成误解。
	var lines: Array[String] = ["流派对比统计"]
	lines.append("指标 | 暴击爆发流 | 情绪净化流")
	lines.append("胜率 | %.1f%% | %.1f%%" % [
		float(crit.get("win_rate", 0.0)) * 100.0,
		float(corrosion.get("win_rate", 0.0)) * 100.0
	])
	lines.append("平均耗时 | %.1f | %.1f" % [
		float(crit.get("average_elapsed", 0.0)),
		float(corrosion.get("average_elapsed", 0.0))
	])
	lines.append("平均剩余生命 | %.1f | %.1f" % [
		float(crit.get("average_player_hp", 0.0)),
		float(corrosion.get("average_player_hp", 0.0))
	])
	lines.append("平均总伤害 | %.1f | %.1f" % [
		float(crit.get("average_total_damage", 0.0)),
		float(corrosion.get("average_total_damage", 0.0))
	])
	lines.append("暴击流随机加成统计：%s" % _format_item_bonus_counts(crit.get("affix_counts", {})))
	lines.append("净化流随机加成统计：%s" % _format_item_bonus_counts(corrosion.get("affix_counts", {})))
	return "\n".join(lines)


func _format_item_bonuses(bonuses: Array) -> String:
	if bonuses.is_empty():
		return "无"
	var names: Array[String] = []
	for bonus in bonuses:
		# 导出字段沿用 affix，但界面按“道具随机加成”解释，并展示具体属性效果。
		names.append("%s获得%s（%s）" % [
			_display_item_id(bonus.get("item", "")),
			str(bonus.get("name", "")),
			_format_modifiers(bonus.get("modifiers", {}))
		])
	return ", ".join(names)


func _format_skill_casts(skill_casts: Dictionary) -> String:
	if skill_casts.is_empty():
		return "无"
	var parts: Array[String] = []
	var keys := skill_casts.keys()
	keys.sort()
	for key in keys:
		parts.append("%s %d 次" % [_display_skill_id(key), int(skill_casts[key])])
	return "，".join(parts)


func _format_item_bonus_counts(counts: Dictionary) -> String:
	if counts.is_empty():
		return "无"
	var parts: Array[String] = []
	var keys := counts.keys()
	keys.sort()
	for key in keys:
		# 批量统计里保存的是内部随机加成 id，展示时转成配置中的中文名。
		parts.append("%s %d 次" % [_display_random_bonus_id(key), int(counts[key])])
	return ", ".join(parts)


func _format_modifiers(modifiers: Dictionary) -> String:
	if modifiers.is_empty():
		return "无属性变化"
	var parts: Array[String] = []
	var keys := modifiers.keys()
	keys.sort()
	for key in keys:
		parts.append(_format_modifier(str(key), float(modifiers[key])))
	return "，".join(parts)


func _format_modifier(key: String, value: float) -> String:
	match key:
		"attack":
			return "攻击 %s" % _format_signed_number(value)
		"defense":
			return "防御 %s" % _format_signed_number(value)
		"max_hp":
			return "最大生命 %s" % _format_signed_number(value)
		"crit_chance":
			return "暴击率 %s" % _format_signed_percent(value)
		"crit_damage":
			return "暴击伤害 %s" % _format_signed_percent(value)
		"speed":
			return "速度 %s" % _format_signed_number(value)
		"energy_regen":
			return "能量恢复 %s" % _format_signed_number(value)
		"cooldown_multiplier":
			if value < 0.0:
				return "技能冷却缩短 %.0f%%" % (abs(value) * 100.0)
			return "技能冷却延长 %.0f%%" % (value * 100.0)
		"dot_multiplier":
			return "持续净化伤害 %s" % _format_signed_percent(value)
		_:
			return "%s %s" % [key, _format_signed_number(value)]


func _format_signed_number(value: float) -> String:
	var sign := "+" if value >= 0.0 else ""
	if is_equal_approx(value, round(value)):
		return "%s%d" % [sign, int(round(value))]
	return "%s%.1f" % [sign, value]


func _format_signed_percent(value: float) -> String:
	var percent := value * 100.0
	var sign := "+" if percent >= 0.0 else ""
	return "%s%.0f%%" % [sign, percent]


func _display_item_id(item_id) -> String:
	# 从配置中查中文道具名；查不到时退回原 id，方便定位配置问题。
	var id := str(item_id)
	for item in config.get("items", []):
		if str(item.get("id", "")) == id:
			return str(item.get("name", id))
	return id


func _display_skill_id(skill_id) -> String:
	# 从配置中查中文技能名；查不到时退回原 id，方便定位配置问题。
	var id := str(skill_id)
	for skill in config.get("skills", []):
		if str(skill.get("id", "")) == id:
			return str(skill.get("name", id))
	return id


func _display_random_bonus_id(bonus_id) -> String:
	# 从配置中查中文随机加成名；查不到时退回原 id，方便定位配置问题。
	var id := str(bonus_id)
	for bonus in config.get("affix_pool", []):
		if str(bonus.get("id", "")) == id:
			return str(bonus.get("name", id))
	return id
