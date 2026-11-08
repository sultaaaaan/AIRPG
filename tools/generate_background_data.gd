extends SceneTree
## One-shot generator for res://data/backgrounds/*.tres.
##
##   godot --headless --path . --script res://tools/generate_background_data.gd
##
## Backgrounds carry the ability score increases and the origin feat in the
## 2024 rules. The small amount of gold inside option A is folded into the
## 50 GP of option B rather than modelled separately.

const OUT_DIR := "res://data/backgrounds"


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))

	var saved := 0
	for definition in _definitions():
		var data := _build(definition)
		var problems := data.validate()
		if not problems.is_empty():
			printerr("[%s] %s" % [data.id, ", ".join(problems)])

		var path := "%s/%s.tres" % [OUT_DIR, data.id]
		var error := ResourceSaver.save(data, path)
		if error != OK:
			printerr("Failed to save %s: %s" % [path, error_string(error)])
		else:
			print("saved %s" % path)
			saved += 1

	print("done: %d backgrounds" % saved)
	quit(0 if saved == 16 else 1)


func _build(d: Dictionary) -> BackgroundData:
	var b := BackgroundData.new()
	b.id = d["id"]
	b.display_name = d["name"]
	b.description = d["desc"]
	b.ability_options = _names(d["abilities"])
	b.skill_proficiencies = _names(d["skills"])
	b.tool_proficiency = d["tool"]
	b.origin_feat = _feature(d["feat"]["id"], d["feat"]["name"], d["feat"]["desc"])
	b.alternative_gold = 50
	for item in d["equipment"]:
		b.equipment_pack.append(_item(item[0], item[1], item[2]))
	return b


func _feature(feature_id: StringName, display_name: String, description: String) -> FeatureData:
	var f := FeatureData.new()
	f.id = feature_id
	f.display_name = display_name
	f.description = description
	return f


func _item(item_id: StringName, display_name: String, quantity: int) -> EquipmentEntry:
	var e := EquipmentEntry.new()
	e.item_id = item_id
	e.display_name = display_name
	e.quantity = quantity
	return e


func _names(values: Array) -> Array[StringName]:
	var out: Array[StringName] = []
	for value in values:
		out.append(StringName(value))
	return out


# --- shared origin feats ----------------------------------------------------

func _feat_alert() -> Dictionary:
	return {"id": &"alert", "name": "Бдительность", "desc": "Добавляйте бонус мастерства к инициативе. Сразу после броска инициативы вы можете обменяться результатами с согласным союзником."}

func _feat_crafter() -> Dictionary:
	return {"id": &"crafter", "name": "Ремесленник", "desc": "Владение тремя ремесленными инструментами. Скидка 20% на немагические предметы и ускоренное изготовление снаряжения."}

func _feat_healer() -> Dictionary:
	return {"id": &"healer", "name": "Лекарь", "desc": "Действием Магии с набором целителя восстановите 1d6 + бонус мастерства хитов. Можете лечить раны и стабилизировать союзников."}

func _feat_lucky() -> Dictionary:
	return {"id": &"lucky", "name": "Удачливый", "desc": "У вас есть очки удачи (равны бонусу мастерства). Потратьте одно, чтобы перебросить d20 или наложить помеху на атаку по вам."}

func _feat_magic_initiate(class_name_ru: String) -> Dictionary:
	return {"id": &"magic_initiate", "name": "Посвящённый в магию (%s)" % class_name_ru, "desc": "Вы знаете два заговора и одно заклинание 1 круга из списка этого класса. Заклинание можно читать без ячейки раз в долгий отдых."}

func _feat_musician() -> Dictionary:
	return {"id": &"musician", "name": "Музыкант", "desc": "Владение тремя музыкальными инструментами. Игрой на инструменте даёте союзникам Героическое вдохновение."}

func _feat_savage_attacker() -> Dictionary:
	return {"id": &"savage_attacker", "name": "Свирепый атакующий", "desc": "Раз в ход при попадании оружием перебросьте кости урона и используйте лучший результат."}

func _feat_skilled() -> Dictionary:
	return {"id": &"skilled", "name": "Умелый", "desc": "Получите владение любыми тремя навыками или инструментами на выбор."}

func _feat_tavern_brawler() -> Dictionary:
	return {"id": &"tavern_brawler", "name": "Драчун из таверны", "desc": "Ваш безоружный удар наносит 1d4 + Сила, перебрасывает 1 на уроне и может толкнуть цель на 1,5 м."}

func _feat_tough() -> Dictionary:
	return {"id": &"tough", "name": "Крепкий", "desc": "Ваш максимум хитов увеличивается на 2 за каждый уровень."}


# --- data -------------------------------------------------------------------

func _definitions() -> Array[Dictionary]:
	var magic_cleric := _feat_magic_initiate("жрец")
	var magic_druid := _feat_magic_initiate("друид")
	var magic_wizard := _feat_magic_initiate("волшебник")

	return [
		{
			"id": &"acolyte", "name": "Прислужник",
			"desc": "Вы провели жизнь в храме, служа божеству и изучая обряды.",
			"abilities": ["intelligence", "wisdom", "charisma"],
			"skills": ["insight", "religion"],
			"tool": &"calligraphers_supplies",
			"feat": magic_cleric,
			"equipment": [
				[&"calligraphers_supplies", "Инструменты каллиграфа", 1],
				[&"book", "Книга (молитвы)", 1],
				[&"holy_symbol", "Священный символ", 1],
				[&"parchment", "Пергамент", 10],
				[&"robe", "Мантия", 1],
			],
		},
		{
			"id": &"artisan", "name": "Ремесленник",
			"desc": "Вы оттачивали мастерство в ремесленной мастерской.",
			"abilities": ["strength", "dexterity", "intelligence"],
			"skills": ["investigation", "persuasion"],
			"tool": &"artisans_tools",
			"feat": _feat_crafter(),
			"equipment": [
				[&"artisans_tools", "Ремесленные инструменты", 1],
				[&"pouch", "Кошель", 2],
				[&"travelers_clothes", "Дорожная одежда", 1],
			],
		},
		{
			"id": &"charlatan", "name": "Шарлатан",
			"desc": "Вы жили обманом, выдавая себя за того, кем не являетесь.",
			"abilities": ["dexterity", "constitution", "charisma"],
			"skills": ["deception", "sleight_of_hand"],
			"tool": &"forgery_kit",
			"feat": _feat_skilled(),
			"equipment": [
				[&"forgery_kit", "Набор для подделки", 1],
				[&"costume", "Костюм", 1],
				[&"fine_clothes", "Роскошная одежда", 1],
			],
		},
		{
			"id": &"criminal", "name": "Преступник",
			"desc": "Вы выживали в преступном мире, зная его законы и тропы.",
			"abilities": ["dexterity", "constitution", "intelligence"],
			"skills": ["sleight_of_hand", "stealth"],
			"tool": &"thieves_tools",
			"feat": _feat_alert(),
			"equipment": [
				[&"dagger", "Кинжал", 2],
				[&"thieves_tools", "Воровские инструменты", 1],
				[&"crowbar", "Лом", 1],
				[&"pouch", "Кошель", 2],
				[&"travelers_clothes", "Дорожная одежда", 1],
			],
		},
		{
			"id": &"entertainer", "name": "Артист",
			"desc": "Вы живёте сценой, очаровывая публику песней и представлением.",
			"abilities": ["strength", "dexterity", "charisma"],
			"skills": ["acrobatics", "performance"],
			"tool": &"musical_instrument",
			"feat": _feat_musician(),
			"equipment": [
				[&"musical_instrument", "Музыкальный инструмент", 1],
				[&"costume", "Костюм", 2],
				[&"mirror", "Зеркало", 1],
				[&"perfume", "Парфюм", 1],
				[&"travelers_clothes", "Дорожная одежда", 1],
			],
		},
		{
			"id": &"farmer", "name": "Фермер",
			"desc": "Вы работали на земле, зная цену труду и погоде.",
			"abilities": ["strength", "constitution", "wisdom"],
			"skills": ["animal_handling", "nature"],
			"tool": &"carpenters_tools",
			"feat": _feat_tough(),
			"equipment": [
				[&"sickle", "Серп", 1],
				[&"carpenters_tools", "Инструменты плотника", 1],
				[&"healers_kit", "Набор целителя", 1],
				[&"iron_pot", "Железный котёл", 1],
				[&"shovel", "Лопата", 1],
				[&"travelers_clothes", "Дорожная одежда", 1],
			],
		},
		{
			"id": &"guard", "name": "Стражник",
			"desc": "Вы несли караул, охраняя городские стены и знать.",
			"abilities": ["strength", "intelligence", "wisdom"],
			"skills": ["athletics", "perception"],
			"tool": &"gaming_set",
			"feat": _feat_alert(),
			"equipment": [
				[&"spear", "Копьё", 1],
				[&"light_crossbow", "Лёгкий арбалет", 1],
				[&"crossbow_bolts", "Арбалетные болты", 20],
				[&"gaming_set", "Игровой набор", 1],
				[&"hooded_lantern", "Фонарь с крышкой", 1],
				[&"manacles", "Кандалы", 1],
				[&"quiver", "Колчан", 1],
				[&"travelers_clothes", "Дорожная одежда", 1],
			],
		},
		{
			"id": &"guide", "name": "Проводник",
			"desc": "Вы водили путников через дикие земли, читая следы и звёзды.",
			"abilities": ["dexterity", "constitution", "wisdom"],
			"skills": ["stealth", "survival"],
			"tool": &"cartographers_tools",
			"feat": magic_druid,
			"equipment": [
				[&"shortbow", "Короткий лук", 1],
				[&"arrow", "Стрела", 20],
				[&"quiver", "Колчан", 1],
				[&"cartographers_tools", "Инструменты картографа", 1],
				[&"bedroll", "Спальник", 1],
				[&"tent", "Палатка", 1],
				[&"travelers_clothes", "Дорожная одежда", 1],
			],
		},
		{
			"id": &"hermit", "name": "Отшельник",
			"desc": "Вы искали истину в уединении и долгих размышлениях.",
			"abilities": ["constitution", "wisdom", "charisma"],
			"skills": ["medicine", "religion"],
			"tool": &"herbalism_kit",
			"feat": _feat_healer(),
			"equipment": [
				[&"quarterstaff", "Боевой посох", 1],
				[&"herbalism_kit", "Набор травника", 1],
				[&"bedroll", "Спальник", 1],
				[&"book", "Книга (философия)", 1],
				[&"lamp", "Лампа", 1],
				[&"oil", "Масло (фляга)", 3],
				[&"travelers_clothes", "Дорожная одежда", 1],
			],
		},
		{
			"id": &"merchant", "name": "Торговец",
			"desc": "Вы умели торговаться, считать прибыль и находить подход к людям.",
			"abilities": ["constitution", "intelligence", "charisma"],
			"skills": ["animal_handling", "persuasion"],
			"tool": &"navigators_tools",
			"feat": _feat_lucky(),
			"equipment": [
				[&"navigators_tools", "Инструменты штурмана", 1],
				[&"pouch", "Кошель", 2],
				[&"travelers_clothes", "Дорожная одежда", 1],
			],
		},
		{
			"id": &"noble", "name": "Дворянин",
			"desc": "Вы выросли в достатке и знати, среди интриг и приличий.",
			"abilities": ["strength", "intelligence", "charisma"],
			"skills": ["history", "persuasion"],
			"tool": &"gaming_set",
			"feat": _feat_skilled(),
			"equipment": [
				[&"gaming_set", "Игровой набор", 1],
				[&"fine_clothes", "Роскошная одежда", 1],
				[&"perfume", "Парфюм", 1],
			],
		},
		{
			"id": &"sage", "name": "Мудрец",
			"desc": "Вы посвятили жизнь книгам, тайнам и научным изысканиям.",
			"abilities": ["constitution", "intelligence", "wisdom"],
			"skills": ["arcana", "history"],
			"tool": &"calligraphers_supplies",
			"feat": magic_wizard,
			"equipment": [
				[&"quarterstaff", "Боевой посох", 1],
				[&"calligraphers_supplies", "Инструменты каллиграфа", 1],
				[&"book", "Книга (история)", 1],
				[&"parchment", "Пергамент", 8],
				[&"robe", "Мантия", 1],
			],
		},
		{
			"id": &"sailor", "name": "Моряк",
			"desc": "Вы жили морем, зная узлы, ветра и шторма.",
			"abilities": ["strength", "dexterity", "wisdom"],
			"skills": ["acrobatics", "perception"],
			"tool": &"navigators_tools",
			"feat": _feat_tavern_brawler(),
			"equipment": [
				[&"dagger", "Кинжал", 1],
				[&"navigators_tools", "Инструменты штурмана", 1],
				[&"rope", "Верёвка", 1],
				[&"travelers_clothes", "Дорожная одежда", 1],
			],
		},
		{
			"id": &"scribe", "name": "Писарь",
			"desc": "Вы переписывали тексты и документы, замечая то, что другие пропускали.",
			"abilities": ["dexterity", "intelligence", "wisdom"],
			"skills": ["investigation", "perception"],
			"tool": &"calligraphers_supplies",
			"feat": _feat_skilled(),
			"equipment": [
				[&"calligraphers_supplies", "Инструменты каллиграфа", 1],
				[&"fine_clothes", "Роскошная одежда", 1],
				[&"lamp", "Лампа", 1],
				[&"oil", "Масло (фляга)", 3],
				[&"parchment", "Пергамент", 12],
			],
		},
		{
			"id": &"soldier", "name": "Солдат",
			"desc": "Вы служили в армии, зная строй, приказ и цену дисциплины.",
			"abilities": ["strength", "dexterity", "constitution"],
			"skills": ["athletics", "intimidation"],
			"tool": &"gaming_set",
			"feat": _feat_savage_attacker(),
			"equipment": [
				[&"spear", "Копьё", 1],
				[&"shortbow", "Короткий лук", 1],
				[&"arrow", "Стрела", 20],
				[&"gaming_set", "Игровой набор", 1],
				[&"healers_kit", "Набор целителя", 1],
				[&"quiver", "Колчан", 1],
				[&"travelers_clothes", "Дорожная одежда", 1],
			],
		},
		{
			"id": &"wayfarer", "name": "Странник",
			"desc": "Вы выросли на улице, выживая смекалкой и быстрыми ногами.",
			"abilities": ["dexterity", "wisdom", "charisma"],
			"skills": ["insight", "stealth"],
			"tool": &"thieves_tools",
			"feat": _feat_lucky(),
			"equipment": [
				[&"dagger", "Кинжал", 2],
				[&"thieves_tools", "Воровские инструменты", 1],
				[&"gaming_set", "Игровой набор", 1],
				[&"bedroll", "Спальник", 1],
				[&"pouch", "Кошель", 2],
				[&"travelers_clothes", "Дорожная одежда", 1],
			],
		},
	]
