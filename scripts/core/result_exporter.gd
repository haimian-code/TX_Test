class_name ResultExporter
extends RefCounted


# 导出完整结果。单局、批量、流派对比都可以直接转成 JSON 保存。
func export_json(result: Dictionary, path: String) -> String:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return "Failed to open JSON export path: %s" % path
	file.store_string(JSON.stringify(result, "\t"))
	file.close()
	return ""


# 导出单局战斗曲线，方便用表格工具查看时间、伤害、血量变化。
# 批量结果没有统一的一条 damage_curve，所以 UI 只在 last_result 不为空时导出 CSV。
func export_csv(result: Dictionary, path: String) -> String:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return "Failed to open CSV export path: %s" % path

	file.store_line("time,total_damage,player_hp,enemy_hp,event")
	for point in result.get("damage_curve", []):
		file.store_line("%s,%s,%s,%s,%s" % [
			_format_number(point.get("time", 0.0)),
			_format_number(point.get("total_damage", 0.0)),
			_format_number(point.get("player_hp", 0.0)),
			_format_number(point.get("enemy_hp", 0.0)),
			_escape_csv(str(point.get("event", "")))
		])
	file.close()
	return ""


func _format_number(value) -> String:
	# 固定三位小数，避免 CSV 中同一列精度忽高忽低。
	return "%.3f" % float(value)


func _escape_csv(value: String) -> String:
	# 事件文本可能包含逗号或引号，必须按 CSV 规则转义。
	if value.contains(",") or value.contains("\"") or value.contains("\n"):
		return "\"%s\"" % value.replace("\"", "\"\"")
	return value
