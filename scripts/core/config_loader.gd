class_name ConfigLoader
extends RefCounted


# 最近一次加载失败的原因。UI 和 CLI 测试会读取它来给出明确错误信息。
var error_message := ""


# 读取并校验 JSON 配置。
# 返回空字典表示失败，调用方应同时查看 error_message。
func load_config(path: String) -> Dictionary:
	error_message = ""
	if not FileAccess.file_exists(path):
		error_message = "Config file not found: %s" % path
		return {}

	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		error_message = "Config file is empty: %s" % path
		return {}

	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		error_message = "Config file is not a valid JSON object: %s" % path
		return {}

	# JSON 格式合法不代表策划数据可用，所以还要做跨表引用校验。
	var config: Dictionary = parsed
	var validation_error := _validate_config(config)
	if not validation_error.is_empty():
		error_message = validation_error
		return {}

	return config


# 把带 id 的数组转换成 id -> 配置对象的字典，便于模拟器快速查技能、道具、怪物。
func index_by_id(items: Array) -> Dictionary:
	var result := {}
	for item in items:
		if typeof(item) == TYPE_DICTIONARY:
			result[str(item.get("id", ""))] = item
	return result


func _validate_config(config: Dictionary) -> String:
	# 必做配置：角色、技能、道具、怪物、关卡都必须存在。
	for key in ["schema_version", "characters", "skills", "items", "monsters", "levels"]:
		if not config.has(key):
			return "Config missing required key: %s" % key

	# 每类配置都要求是数组，并且每个对象必须有唯一 id。
	for array_key in ["characters", "skills", "items", "monsters", "levels"]:
		if typeof(config[array_key]) != TYPE_ARRAY:
			return "Config key '%s' must be an array." % array_key
		var id_error := _validate_array_ids(config[array_key], array_key)
		if not id_error.is_empty():
			return id_error

	# 道具随机加成是扩展项，不是必填；如果配置了，同样要求数组和唯一 id。
	if config.has("affix_pool"):
		if typeof(config["affix_pool"]) != TYPE_ARRAY:
			return "Config key 'affix_pool' must be an array."
		var affix_error := _validate_array_ids(config["affix_pool"], "affix_pool")
		if not affix_error.is_empty():
			return affix_error

	if config["characters"].is_empty():
		return "Config needs at least one character."
	if config["levels"].is_empty():
		return "Config needs at least one level."

	var skills := index_by_id(config["skills"])
	var items := index_by_id(config["items"])
	var monsters := index_by_id(config["monsters"])

	# 角色引用的技能/道具必须真实存在，否则战斗开始时会查不到配置。
	for character in config["characters"]:
		for skill_id in character.get("skills", []):
			if not skills.has(str(skill_id)):
				return "Character '%s' references missing skill '%s'." % [character.get("id", ""), skill_id]
		for item_id in character.get("items", []):
			if not items.has(str(item_id)):
				return "Character '%s' references missing item '%s'." % [character.get("id", ""), item_id]

	# 关卡 wave 中引用的怪物必须存在，数量也必须为正数，保证队列能正常生成。
	for level in config["levels"]:
		for wave in level.get("waves", []):
			var monster_id := str(wave.get("monster", ""))
			if not monsters.has(monster_id):
				return "Level '%s' references missing monster '%s'." % [level.get("id", ""), monster_id]
			if int(wave.get("count", 0)) <= 0:
				return "Level '%s' has wave with non-positive count." % level.get("id", "")

	return ""


func _validate_array_ids(items: Array, key: String) -> String:
	var seen := {}
	for index in items.size():
		var item = items[index]
		if typeof(item) != TYPE_DICTIONARY:
			return "Config '%s[%d]' must be an object." % [key, index]
		var id := str(item.get("id", ""))
		if id.is_empty():
			return "Config '%s[%d]' missing id." % [key, index]
		# 重复 id 会导致 index_by_id 后面的对象覆盖前面的对象，所以这里提前拒绝。
		if seen.has(id):
			return "Config '%s' has duplicate id '%s'." % [key, id]
		seen[id] = true
	return ""
