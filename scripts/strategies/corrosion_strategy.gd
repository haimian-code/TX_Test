class_name CorrosionStrategy
extends "res://scripts/strategies/strategy_base.gd"


# 情绪净化流：偏向持续伤害覆盖率和生存，胜利速度较慢但更稳定。
func get_strategy_id() -> String:
	return "corrosion"


func allocate_attributes(context: Dictionary) -> Dictionary:
	var points := int(context.get("points", 0))
	# 加点优先级：先保证攻击让持续伤害有基础值，再补防御和生命提升容错。
	var result := {
		"attack": 0,
		"defense": 0,
		"max_hp": 0
	}
	while points > 0:
		if result["attack"] < 2:
			result["attack"] += 1
		elif result["defense"] < 2:
			result["defense"] += 1
		else:
			result["max_hp"] += 1
		points -= 1
	return result


func choose_items(context: Dictionary) -> Array:
	# 情绪中和剂强化持续伤害，复习手册缩短技能循环，配合情绪净化维持覆盖率。
	return _filter_available_items(["toxin_vial", "battle_manual"], context.get("available_items", []))


func decide_action(context: Dictionary) -> Dictionary:
	var skills: Array = context.get("skills", [])
	var effects: Array = context.get("active_effects", [])
	var player: Dictionary = context.get("player", {})
	var has_dot := false
	# 先检查目标身上是否还有较长时间的情绪净化效果，避免无脑重复施放浪费能量。
	for effect in effects:
		if str(effect.get("source_skill", "")) == "ember_bloom" and float(effect.get("remaining", 0.0)) > 1.0:
			has_dot = true
			break
	if not has_dot:
		var ember := _skill_state(skills, "ember_bloom")
		if not ember.is_empty():
			if _can_cast(skills, "ember_bloom"):
				return {
					"type": "cast_skill",
					"skill": "ember_bloom"
				}
			# 如果持续伤害快断档，但当前能量或冷却还差一点，选择等待，优先保证 DOT 覆盖率。
			var energy := float(player.get("energy", 0.0))
			var cost := float(ember.get("cost", 0.0))
			var cooldown_left := float(ember.get("cooldown_left", 0.0))
			if energy < cost or cooldown_left <= 1.0:
				return {"type": "wait"}
	# DOT 已经挂上后，再用直接伤害技能补输出。
	for skill_id in ["quick_slash", "rupture_mark"]:
		if _can_cast(skills, skill_id):
			return {
				"type": "cast_skill",
				"skill": skill_id
			}
	return {"type": "wait"}


func _can_cast(skills: Array, skill_id: String) -> bool:
	# 只根据模拟器暴露的技能状态做判断，不直接访问战斗内部对象。
	for skill in skills:
		if str(skill.get("id", "")) == skill_id and float(skill.get("cooldown_left", 0.0)) <= 0.0 and bool(skill.get("enough_energy", false)):
			return true
	return false


func _skill_state(skills: Array, skill_id: String) -> Dictionary:
	# 取单个技能的冷却、消耗、能量状态，便于做 DOT 覆盖率判断。
	for skill in skills:
		if str(skill.get("id", "")) == skill_id:
			return skill
	return {}
