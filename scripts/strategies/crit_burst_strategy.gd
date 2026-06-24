class_name CritBurstStrategy
extends "res://scripts/strategies/strategy_base.gd"


# 暴击爆发流：偏向攻击、暴击和速度，目标是更快结束战斗。
func get_strategy_id() -> String:
	return "crit_burst"


func allocate_attributes(context: Dictionary) -> Dictionary:
	var points := int(context.get("points", 0))
	# 加点优先级：先补攻击，再补暴击，剩余点数给速度。
	# 返回的是“点数分配”，具体每点换算多少属性由 BattleSimulator 统一处理。
	var result := {
		"attack": 0,
		"crit": 0,
		"speed": 0
	}
	while points > 0:
		if result["attack"] < 3:
			result["attack"] += 1
		elif result["crit"] < 2:
			result["crit"] += 1
		else:
			result["speed"] += 1
		points -= 1
	return result


func choose_items(context: Dictionary) -> Array:
	# 专注透镜提供暴击收益，复习手册提高技能周转，都是爆发流的核心装备。
	return _filter_available_items(["razor_lens", "battle_manual"], context.get("available_items", []))


func decide_action(context: Dictionary) -> Dictionary:
	var skills: Array = context.get("skills", [])
	# 技能优先级：重点标注伤害和暴击收益最高，其次快速翻检，最后用情绪净化补伤害。
	# 策略只提出“想放哪个技能”，冷却/能量/伤害结算仍由战斗模拟器负责。
	for skill_id in ["rupture_mark", "quick_slash", "ember_bloom"]:
		if _can_cast(skills, skill_id):
			return {
				"type": "cast_skill",
				"skill": skill_id
			}
	return {"type": "wait"}


func _can_cast(skills: Array, skill_id: String) -> bool:
	# context 中的 skill 状态由模拟器生成，策略只读取冷却和能量是否满足。
	for skill in skills:
		if str(skill.get("id", "")) == skill_id and float(skill.get("cooldown_left", 0.0)) <= 0.0 and bool(skill.get("enough_energy", false)):
			return true
	return false
