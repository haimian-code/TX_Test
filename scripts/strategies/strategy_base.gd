class_name StrategyBase
extends RefCounted


# 策略基类定义了战斗模拟器和“流派策略”之间的函数 API。
# 新增流派时，不需要改战斗模拟器，只要继承/仿照这个接口实现下面几个函数。
func get_strategy_id() -> String:
	return "base"


# 属性分配 API：战斗开始前调用。
# context 会给出可分配点数、角色配置、关卡配置；返回值是属性名到点数的映射。
func allocate_attributes(_context: Dictionary) -> Dictionary:
	return {}


# 装备选择 API：战斗开始前调用。
# context["available_items"] 是角色可用道具 ID 列表；返回值是本流派实际选择的道具 ID。
func choose_items(_context: Dictionary) -> Array:
	return []


# 行动决策 API：战斗过程中反复调用。
# 返回 {"type": "cast_skill", "skill": "技能ID"} 表示请求施放技能；返回 wait 表示暂不施法。
func decide_action(_context: Dictionary) -> Dictionary:
	return {"type": "wait"}


# 小工具：按优先级从 preferred_items 中挑出角色实际拥有的道具，避免策略返回非法道具。
func _filter_available_items(preferred_items: Array, available_items: Array) -> Array:
	var chosen: Array = []
	for item_id in preferred_items:
		if available_items.has(item_id):
			chosen.append(item_id)
	return chosen
