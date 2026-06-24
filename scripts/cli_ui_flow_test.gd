extends SceneTree


# UI 流程回归测试。
# 这个脚本不检查战斗数值细节，而是模拟用户点击主界面的关键按钮，防止 UI 状态残留或格式化报错。
const MainScene = preload("res://scenes/main.tscn")

var failures := 0


func _initialize() -> void:
	# 延迟到下一帧运行，确保实例化的主界面能执行 _ready 和配置加载。
	call_deferred("_run_flow")


func _run_flow() -> void:
	print("UI_FLOW_TEST_START")
	var ui = MainScene.instantiate()
	root.add_child(ui)
	# 等两帧让 UI 树完成 ready、控件创建和配置加载。
	await process_frame
	await process_frame

	# 初始状态必须是“等待运行”，不能预先显示上一次模拟或对比数据。
	_assert(ui.simulator != null, "config is loaded by main scene")
	_assert(ui.summary_label.text.contains("暂无模拟结果"), "initial summary is empty")
	_assert(ui.curve_label.text.contains("等待运行模拟"), "initial curve area is waiting")
	_assert(ui.log_label.text.contains("等待运行模拟"), "initial log area is waiting")
	_assert(float(ui.player_hp_bar.value) == 0.0, "initial player hp bar is empty")
	_assert(float(ui.enemy_hp_bar.value) == 0.0, "initial enemy hp bar is empty")
	_assert(not ui.curve_label.text.contains("流派对比统计"), "comparison is not precomputed")
	_assert(ui.play_batch_button.disabled, "batch replay is disabled before batch run")
	_assert(ui.batch_summary_button.disabled, "batch summary button is disabled before batch run")

	# 未运行时导出应给出提示，而不是写空文件或崩溃。
	ui._on_export_last()
	await process_frame
	_assert(ui.status_label.text.contains("还没有可导出的结果"), "export before run is blocked")

	# 单局流程：生成结果、摘要、曲线和日志。
	ui._on_run_once()
	await process_frame
	_assert(not ui.last_result.is_empty(), "single run creates result")
	_assert(ui.summary_label.text.contains("流派："), "single run summary is shown")
	_assert(ui.summary_label.text.contains("快速翻检") or ui.summary_label.text.contains("重点标注") or ui.summary_label.text.contains("情绪净化"), "single run skill casts use Chinese names")
	_assert(not ui.summary_label.text.contains("quick_slash"), "single run summary hides internal skill id")
	_assert(ui.curve_label.text.contains("时间/回合"), "single run curve is shown")
	_assert(ui.log_label.text.length() > 0, "single run log is shown")

	# 批量流程：用小次数验证逐场结果表和“当前日志是哪一场”的说明。
	ui.runs_spin.value = 3
	ui._on_run_batch()
	await process_frame
	_assert(int(ui.last_batch.get("runs", 0)) == 3, "batch run count is honored")
	_assert(ui.curve_label.text.contains("逐场结果"), "batch table is shown")
	_assert(ui.curve_label.text.contains("1 |"), "batch row 1 is shown")
	_assert(ui.curve_label.text.contains("2 |"), "batch row 2 is shown")
	_assert(ui.curve_label.text.contains("3 |"), "batch row 3 is shown")
	_assert(ui.log_label.text.contains("当前详细日志：第 3 场 / 共 3 场"), "batch log identifies shown battle")
	_assert(not ui.play_batch_button.disabled, "batch replay is enabled after batch run")
	_assert(not ui.batch_summary_button.disabled, "batch summary button is enabled after batch run")
	_assert(int(ui.batch_replay_spin.max_value) == 3, "batch replay max run is updated")
	_assert(not ui.curve_label.text.contains("razor_lens"), "batch table uses Chinese item names")
	_assert(not ui.curve_label.text.contains("sharp"), "batch table uses Chinese random bonus names")
	_assert(ui.curve_label.text.contains("道具随机加成"), "batch table explains random item bonuses")

	ui.batch_replay_spin.value = 2
	ui._on_play_batch_run()
	await process_frame
	_assert(ui.summary_label.text.contains("批量回放 | 第 2 / 3 场"), "selected batch run summary is shown")
	_assert(not ui.summary_label.text.contains("quick_slash"), "selected batch replay hides internal skill id")
	_assert(ui.log_label.text.contains("批量模拟第 2 / 3 场详细日志"), "selected batch run log is shown")
	_assert(ui.curve_label.text.contains("时间/回合"), "selected batch run curve is shown")

	ui._on_show_batch_summary()
	await process_frame
	_assert(ui.summary_label.text.contains("批量模拟 |"), "batch summary can be restored")
	_assert(ui.curve_label.text.contains("逐场结果"), "batch table is restored")
	_assert(int(ui.batch_replay_spin.value) == 2, "batch replay selected run is preserved")

	# 对比流程：验证统计表、中文随机加成，以及早期文本柱状图的 # 和 . 不再出现。
	ui._on_compare()
	await process_frame
	_assert(str(ui.last_batch.get("type", "")) == "comparison", "comparison batch is saved")
	_assert(ui.curve_label.text.contains("流派对比统计"), "comparison table is shown")
	_assert(ui.curve_label.text.contains("暴击流随机加成统计"), "crit random bonuses are shown")
	_assert(ui.curve_label.text.contains("净化流随机加成统计"), "purification random bonuses are shown")
	_assert(ui.player_hp_text.text.contains("对比模式不显示单局血量"), "comparison clears player hp display")
	_assert(ui.enemy_hp_text.text.contains("对比模式不显示单局血量"), "comparison clears enemy hp display")
	_assert(ui.enemy_progress_text.text.contains("对比模式显示统计结果"), "comparison explains progress display")
	_assert(ui.play_batch_button.disabled, "plain batch replay is disabled during comparison")
	_assert(not ui.curve_label.text.contains("###"), "comparison has no text bar hashes")
	_assert(not ui.curve_label.text.contains("..."), "comparison has no text bar dots")
	_assert(not ui.log_label.text.contains("暴击流随机加成统计"), "comparison log does not repeat crit random bonuses")
	_assert(not ui.log_label.text.contains("净化流随机加成统计"), "comparison log does not repeat purification random bonuses")

	# 对比后导出覆盖“last_batch 为 comparison 结构”的路径。
	ui._on_export_last()
	await process_frame
	_assert(ui.status_label.text.contains("已导出到"), "export after comparison succeeds")

	root.remove_child(ui)
	ui.queue_free()
	if failures == 0:
		print("UI_FLOW_TEST_OK")
		quit(0)
	else:
		printerr("UI_FLOW_TEST_FAILED count=%d" % failures)
		quit(1)


func _assert(condition: bool, message: String) -> void:
	# 统一输出 PASS/FAIL，便于命令行中快速定位失败步骤。
	if condition:
		print("PASS %s" % message)
	else:
		failures += 1
		printerr("FAIL %s" % message)
