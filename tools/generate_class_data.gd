extends SceneTree
## One-shot generator for res://data/classes/*.tres.
##
## Run headless after changing the tables below:
##   godot --headless --path . --script res://tools/generate_class_data.gd
##
## The .tres files are normal Godot resources: once generated you can edit
## them in the Inspector. Regenerating overwrites those edits, so treat this
## script as the source of truth or drop it from the pipeline later.

const OUT_DIR := "res://data/classes"


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))

	var saved := 0
	for definition in _definitions():
		var class_data := _build_class(definition)
		var problems := class_data.validate()
		if not problems.is_empty():
			printerr("[%s] %s" % [class_data.id, ", ".join(problems)])

		var path := "%s/%s.tres" % [OUT_DIR, class_data.id]
		var error := ResourceSaver.save(class_data, path)
		if error != OK:
			printerr("Failed to save %s: %s" % [path, error_string(error)])
		else:
			print("saved %s" % path)
			saved += 1

	print("done: %d classes" % saved)
	quit(0 if saved == 12 else 1)


# --- builders ---------------------------------------------------------------

func _build_class(d: Dictionary) -> ClassData:
	var c := ClassData.new()
	c.id = d["id"]
	c.display_name = d["name"]
	c.description = d["desc"]
	c.hit_die = d["hit_die"]
	c.primary_abilities = _names(d["primary"])
	c.saving_throws = _names(d["saves"])
	c.armor_training = _names(d["armor"])
	c.weapon_training = _names(d["weapons"])
	c.tool_proficiencies = _names(d["tools"])
	c.skill_choice_count = d["skills"]
	c.skill_pool = _names(d["pool"])
	c.skill_pool_is_any = d["any"]
	c.weapon_mastery_count = d["mastery"]
	c.alternative_gold = d["gold"]
	c.unarmored_defense_ability = d.get("unarmored_ability", &"")
	c.unarmored_defense_allows_shield = d.get("unarmored_shield", true)

	for feature in d["features"]:
		c.features.append(_feature(feature["id"], feature["name"], feature["desc"]))
	for choice in d["choices"]:
		c.choices.append(_choice(choice))
	if d["casting"] != null:
		c.spellcasting = _casting(d["casting"])
	for item in d["equipment"]:
		c.equipment_pack.append(_item(item[0], item[1], item[2]))

	return c


func _feature(feature_id: StringName, display_name: String, description: String) -> FeatureData:
	var f := FeatureData.new()
	f.id = feature_id
	f.display_name = display_name
	f.description = description
	f.level = 1
	return f


func _choice(d: Dictionary) -> ChoiceGroupData:
	var ch := ChoiceGroupData.new()
	ch.id = d["id"]
	ch.prompt = d["prompt"]
	ch.count = 1
	for option in d["options"]:
		var o := ChoiceOptionData.new()
		o.id = option["id"]
		o.display_name = option["name"]
		o.description = option["desc"]
		o.granted_armor_training = _names(option.get("armor", []))
		o.granted_weapon_training = _names(option.get("weapons", []))
		for feat in option.get("features", []):
			o.features.append(_feature(feat["id"], feat["name"], feat["desc"]))
		ch.options.append(o)
	return ch


func _casting(d: Dictionary) -> SpellcastingData:
	var s := SpellcastingData.new()
	s.ability = d["ability"]
	s.cantrips_known = d["cantrips"]
	s.spells_prepared = d["prepared"]
	s.spellbook_spells = d.get("spellbook", 0)
	s.level_1_slots = d["slots"]
	s.recovery = SpellcastingData.Recovery.SHORT_REST if d.get("short_rest", false) else SpellcastingData.Recovery.LONG_REST
	s.ritual_caster = d.get("ritual", false)
	s.secret_language = d.get("secret_language", &"")
	return s


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


# --- data -------------------------------------------------------------------

func _definitions() -> Array[Dictionary]:
	return [
		{
			"id": &"barbarian",
			"name": "Варвар",
			"desc": "Неукротимый воин, черпающий силу из первобытной ярости.",
			"hit_die": 12,
			"primary": ["strength"],
			"saves": ["strength", "constitution"],
			"armor": ["light", "medium", "shields"],
			"weapons": ["simple", "martial"],
			"tools": [],
			"skills": 2,
			"pool": ["animal_handling", "athletics", "intimidation", "nature", "perception", "survival"],
			"any": false,
			"mastery": 2,
			"gold": 75,
			"unarmored_ability": &"constitution",
			"unarmored_shield": true,
			"features": [
				{"id": &"rage", "name": "Ярость", "desc": "Бонусное действие, 2 применения на долгий отдых. На 1 минуту: +2 к урону силовым оружием, сопротивление дробящему, колющему и рубящему урону, преимущество на проверки и спасброски Силы. Нельзя поддерживать концентрацию и колдовать."},
				{"id": &"unarmored_defense", "name": "Защита без доспехов", "desc": "Пока вы не носите доспех, КД = 10 + модификатор Ловкости + модификатор Телосложения. Щит можно использовать."},
				{"id": &"weapon_mastery", "name": "Мастерство оружия", "desc": "Вы владеете особыми приёмами двух видов оружия на свой выбор и можете переключать их после долгого отдыха."},
			],
			"choices": [],
			"casting": null,
			"equipment": [
				[&"greataxe", "Секира", 1],
				[&"handaxe", "Ручной топор", 4],
				[&"explorers_pack", "Набор путешественника", 1],
			],
		},
		{
			"id": &"bard",
			"name": "Бард",
			"desc": "Вдохновляющий артист, чьё искусство обретает силу заклинаний.",
			"hit_die": 8,
			"primary": ["charisma"],
			"saves": ["dexterity", "charisma"],
			"armor": ["light"],
			"weapons": ["simple"],
			"tools": ["musical_instrument"],
			"skills": 3,
			"pool": [],
			"any": true,
			"mastery": 0,
			"gold": 90,
			"features": [
				{"id": &"bardic_inspiration", "name": "Бардовское вдохновение", "desc": "Бонусным действием дайте союзнику в пределах 18 м кость d6. В течение часа он может добавить её к одному броску d20. Применений = модификатор Харизмы (минимум 1), восстанавливаются на долгий отдых."},
			],
			"choices": [],
			"casting": {"ability": &"charisma", "cantrips": 2, "prepared": 4, "slots": 2},
			"equipment": [
				[&"leather_armor", "Кожаный доспех", 1],
				[&"dagger", "Кинжал", 2],
				[&"musical_instrument", "Музыкальный инструмент", 1],
				[&"entertainers_pack", "Набор артиста", 1],
			],
		},
		{
			"id": &"cleric",
			"name": "Жрец",
			"desc": "Проводник воли божества, лечащий союзников и карающий нечестивых.",
			"hit_die": 8,
			"primary": ["wisdom"],
			"saves": ["wisdom", "charisma"],
			"armor": ["light", "medium", "shields"],
			"weapons": ["simple"],
			"tools": [],
			"skills": 2,
			"pool": ["history", "insight", "medicine", "persuasion", "religion"],
			"any": false,
			"mastery": 0,
			"gold": 110,
			"features": [],
			"choices": [
				{
					"id": &"divine_order",
					"prompt": "Выберите божественный орден",
					"options": [
						{"id": &"protector", "name": "Защитник", "desc": "Вы получаете владение воинским оружием и тяжёлыми доспехами.", "armor": ["heavy"], "weapons": ["martial"]},
						{"id": &"thaumaturge", "name": "Чудотворец", "desc": "Вы знаете один дополнительный заговор жреца и добавляете модификатор Мудрости к проверкам Интеллекта (Религия).", "features": [{"id": &"thaumaturge_bonus", "name": "Богословская учёность", "desc": "+модификатор Мудрости к проверкам Религии и один дополнительный заговор."}]},
					],
				},
			],
			"casting": {"ability": &"wisdom", "cantrips": 3, "prepared": 4, "slots": 2},
			"equipment": [
				[&"chain_shirt", "Кольчужная рубаха", 1],
				[&"shield", "Щит", 1],
				[&"mace", "Булава", 1],
				[&"holy_symbol", "Священный символ", 1],
				[&"priests_pack", "Набор священника", 1],
			],
		},
		{
			"id": &"druid",
			"name": "Друид",
			"desc": "Хранитель природного равновесия, повелевающий стихиями и зверями.",
			"hit_die": 8,
			"primary": ["wisdom"],
			"saves": ["intelligence", "wisdom"],
			"armor": ["light", "medium", "shields"],
			"weapons": ["simple"],
			"tools": ["herbalism_kit"],
			"skills": 2,
			"pool": ["animal_handling", "arcana", "insight", "medicine", "nature", "perception", "religion", "survival"],
			"any": false,
			"mastery": 0,
			"gold": 100,
			"features": [
				{"id": &"druidic", "name": "Друидический язык", "desc": "Вы знаете тайный язык друидов и можете оставлять на нём скрытые послания."},
			],
			"choices": [
				{
					"id": &"primal_order",
					"prompt": "Выберите первобытный орден",
					"options": [
						{"id": &"magician", "name": "Маг", "desc": "Вы знаете один дополнительный заговор друида и добавляете модификатор Мудрости к проверкам Тайных знаний (Магия) и Природы.", "features": [{"id": &"magician_bonus", "name": "Тайные знания", "desc": "+модификатор Мудрости к проверкам Магии и Природы, один дополнительный заговор."}]},
						{"id": &"warden", "name": "Хранитель", "desc": "Вы получаете владение воинским оружием и средними доспехами.", "armor": ["medium"], "weapons": ["martial"]},
					],
				},
			],
			"casting": {"ability": &"wisdom", "cantrips": 2, "prepared": 4, "slots": 2, "secret_language": &"druidic"},
			"equipment": [
				[&"leather_armor", "Кожаный доспех", 1],
				[&"shield", "Щит", 1],
				[&"sickle", "Серп", 1],
				[&"druidic_focus", "Друидический фокус", 1],
				[&"explorers_pack", "Набор путешественника", 1],
				[&"herbalism_kit", "Набор травника", 1],
			],
		},
		{
			"id": &"fighter",
			"name": "Воин",
			"desc": "Мастер оружия и доспеха, полагающийся на дисциплину и тренировку.",
			"hit_die": 10,
			"primary": ["strength", "dexterity"],
			"saves": ["strength", "constitution"],
			"armor": ["light", "medium", "heavy", "shields"],
			"weapons": ["simple", "martial"],
			"tools": [],
			"skills": 2,
			"pool": ["acrobatics", "animal_handling", "athletics", "history", "insight", "intimidation", "persuasion", "perception", "survival"],
			"any": false,
			"mastery": 3,
			"gold": 155,
			"features": [
				{"id": &"second_wind", "name": "Второе дыхание", "desc": "Бонусным действием восстановите 1d10 + уровень воина хитов. 2 применения: одно возвращается на коротком отдыхе, все — на долгом."},
				{"id": &"weapon_mastery", "name": "Мастерство оружия", "desc": "Вы владеете особыми приёмами трёх видов оружия на свой выбор."},
			],
			"choices": [
				{
					"id": &"fighting_style",
					"prompt": "Выберите боевой стиль",
					"options": [
						{"id": &"archery", "name": "Стрельба", "desc": "+2 к броскам атаки дальнобойным оружием."},
						{"id": &"blind_fighting", "name": "Слепой бой", "desc": "Вы чувствуете невидимых существ в пределах 3 м."},
						{"id": &"defense", "name": "Оборона", "desc": "+1 к КД, пока вы носите доспех."},
						{"id": &"dueling", "name": "Фехтование", "desc": "+2 к урону одноручным оружием, если в другой руке нет оружия."},
						{"id": &"great_weapon_fighting", "name": "Бой большим оружием", "desc": "Перебрасывайте 1 и 2 на костях урона двуручным оружием."},
						{"id": &"interception", "name": "Перехват", "desc": "Реакцией снизьте урон, получаемый союзником в 1,5 м."},
						{"id": &"protection", "name": "Защита", "desc": "Реакцией со щитом наложите помеху на атаку по союзнику в 1,5 м."},
						{"id": &"thrown_weapon_fighting", "name": "Метательное оружие", "desc": "+2 к урону метательным оружием."},
						{"id": &"two_weapon_fighting", "name": "Бой двумя оружиями", "desc": "Добавляйте модификатор характеристики к урону второй атаки."},
						{"id": &"unarmed_fighting", "name": "Безоружный бой", "desc": "Ваш безоружный удар наносит 1d6 + Сила."},
					],
				},
			],
			"casting": null,
			"equipment": [
				[&"chain_mail", "Кольчуга", 1],
				[&"greatsword", "Двуручный меч", 1],
				[&"flail", "Цеп", 1],
				[&"javelin", "Метательное копьё", 8],
				[&"dungeoneers_pack", "Набор исследователя подземелий", 1],
			],
		},
		{
			"id": &"monk",
			"name": "Монах",
			"desc": "Боец, превращающий тело в оружие через дисциплину и внутреннюю энергию.",
			"hit_die": 8,
			"primary": ["dexterity", "wisdom"],
			"saves": ["strength", "dexterity"],
			"armor": [],
			"weapons": ["simple", "martial_light"],
			"tools": ["artisan_tools"],
			"skills": 2,
			"pool": ["acrobatics", "athletics", "history", "insight", "religion", "stealth"],
			"any": false,
			"mastery": 0,
			"gold": 50,
			"unarmored_ability": &"wisdom",
			"unarmored_shield": false,
			"features": [
				{"id": &"martial_arts", "name": "Боевые искусства", "desc": "Безоружные удары и monk-оружие наносят 1d6, используют Ловкость вместо Силы. Бонусным действием — ещё один безоружный удар."},
				{"id": &"unarmored_defense", "name": "Защита без доспехов", "desc": "Без доспеха и щита КД = 10 + модификатор Ловкости + модификатор Мудрости."},
			],
			"choices": [],
			"casting": null,
			"equipment": [
				[&"spear", "Копьё", 1],
				[&"dagger", "Кинжал", 5],
				[&"artisan_tools", "Ремесленный инструмент", 1],
				[&"explorers_pack", "Набор путешественника", 1],
			],
		},
		{
			"id": &"paladin",
			"name": "Паладин",
			"desc": "Клятвенный воин, соединяющий сталь и божественную силу.",
			"hit_die": 10,
			"primary": ["strength", "charisma"],
			"saves": ["wisdom", "charisma"],
			"armor": ["light", "medium", "heavy", "shields"],
			"weapons": ["simple", "martial"],
			"tools": [],
			"skills": 2,
			"pool": ["athletics", "insight", "intimidation", "medicine", "persuasion", "religion"],
			"any": false,
			"mastery": 2,
			"gold": 150,
			"features": [
				{"id": &"lay_on_hands", "name": "Возложение рук", "desc": "Запас лечения равен 5 × уровень паладина. Бонусным действием касанием восстановите любое количество хитов из запаса или снимите отраву/болезнь."},
				{"id": &"divine_sense", "name": "Божественное чувство", "desc": "Бонусным действием ощутите небожителей, исчадий и нежить в пределах 18 м. Применений = модификатор Харизмы (минимум 1)."},
				{"id": &"weapon_mastery", "name": "Мастерство оружия", "desc": "Вы владеете особыми приёмами двух видов оружия на свой выбор."},
			],
			"choices": [],
			"casting": {"ability": &"charisma", "cantrips": 0, "prepared": 2, "slots": 2},
			"equipment": [
				[&"chain_mail", "Кольчуга", 1],
				[&"shield", "Щит", 1],
				[&"longsword", "Длинный меч", 1],
				[&"javelin", "Метательное копьё", 6],
				[&"holy_symbol", "Священный символ", 1],
				[&"priests_pack", "Набор священника", 1],
			],
		},
		{
			"id": &"ranger",
			"name": "Следопыт",
			"desc": "Охотник на границе диких земель, владеющий оружием и первичной магией.",
			"hit_die": 10,
			"primary": ["dexterity", "wisdom"],
			"saves": ["strength", "dexterity"],
			"armor": ["light", "medium", "shields"],
			"weapons": ["simple", "martial"],
			"tools": [],
			"skills": 3,
			"pool": ["animal_handling", "athletics", "insight", "investigation", "nature", "perception", "stealth", "survival"],
			"any": false,
			"mastery": 2,
			"gold": 150,
			"features": [
				{"id": &"favored_enemy", "name": "Избранный враг", "desc": "Заклинание «Метка охотника» всегда подготовлено. Вы можете читать его без ячейки число раз, равное модификатору Мудрости (минимум 1), до долгого отдыха."},
				{"id": &"weapon_mastery", "name": "Мастерство оружия", "desc": "Вы владеете особыми приёмами двух видов оружия на свой выбор."},
			],
			"choices": [],
			"casting": {"ability": &"wisdom", "cantrips": 1, "prepared": 2, "slots": 2},
			"equipment": [
				[&"studded_leather_armor", "Проклёпанный кожаный доспех", 1],
				[&"scimitar", "Ятаган", 1],
				[&"shortsword", "Короткий меч", 1],
				[&"longbow", "Длинный лук", 1],
				[&"arrow", "Стрела", 20],
				[&"quiver", "Колчан", 1],
				[&"druidic_focus", "Друидический фокус", 1],
				[&"explorers_pack", "Набор путешественника", 1],
			],
		},
		{
			"id": &"rogue",
			"name": "Плут",
			"desc": "Мастер скрытности и точного удара, решающий проблемы хитростью.",
			"hit_die": 8,
			"primary": ["dexterity"],
			"saves": ["dexterity", "intelligence"],
			"armor": ["light"],
			"weapons": ["simple", "martial_light"],
			"tools": ["thieves_tools"],
			"skills": 4,
			"pool": ["acrobatics", "athletics", "deception", "insight", "intimidation", "investigation", "perception", "performance", "persuasion", "sleight_of_hand", "stealth"],
			"any": false,
			"mastery": 2,
			"gold": 100,
			"features": [
				{"id": &"expertise", "name": "Компетентность", "desc": "Выберите два навыка: ваш бонус мастерства для них удваивается."},
				{"id": &"sneak_attack", "name": "Скрытая атака", "desc": "Раз за ход наносите дополнительно 1d6 урона, если у вас преимущество или рядом с целью есть ваш союзник."},
				{"id": &"thieves_cant", "name": "Воровской жаргон", "desc": "Вы знаете тайный язык преступного мира и шифр для скрытых посланий."},
				{"id": &"weapon_mastery", "name": "Мастерство оружия", "desc": "Вы владеете особыми приёмами двух видов оружия на свой выбор."},
			],
			"choices": [],
			"casting": null,
			"equipment": [
				[&"leather_armor", "Кожаный доспех", 1],
				[&"dagger", "Кинжал", 2],
				[&"shortsword", "Короткий меч", 1],
				[&"shortbow", "Короткий лук", 1],
				[&"arrow", "Стрела", 20],
				[&"quiver", "Колчан", 1],
				[&"thieves_tools", "Воровские инструменты", 1],
				[&"burglars_pack", "Набор взломщика", 1],
			],
		},
		{
			"id": &"sorcerer",
			"name": "Чародей",
			"desc": "Прирождённый носитель магии, чья сила течёт в крови.",
			"hit_die": 6,
			"primary": ["charisma"],
			"saves": ["constitution", "charisma"],
			"armor": [],
			"weapons": ["simple"],
			"tools": [],
			"skills": 2,
			"pool": ["arcana", "deception", "insight", "intimidation", "persuasion", "religion"],
			"any": false,
			"mastery": 0,
			"gold": 50,
			"features": [
				{"id": &"innate_sorcery", "name": "Врождённое волшебство", "desc": "Бонусным действием на 1 минуту: +1 к КС спасброска от ваших заклинаний и преимущество на броски атаки заклинаниями. 2 применения на долгий отдых."},
			],
			"choices": [],
			"casting": {"ability": &"charisma", "cantrips": 4, "prepared": 2, "slots": 2},
			"equipment": [
				[&"spear", "Копьё", 1],
				[&"dagger", "Кинжал", 2],
				[&"arcane_focus", "Магический фокус", 1],
				[&"dungeoneers_pack", "Набор исследователя подземелий", 1],
			],
		},
		{
			"id": &"warlock",
			"name": "Колдун",
			"desc": "Искатель тайных знаний, обменявший часть себя на силу покровителя.",
			"hit_die": 8,
			"primary": ["charisma"],
			"saves": ["wisdom", "charisma"],
			"armor": ["light"],
			"weapons": ["simple"],
			"tools": [],
			"skills": 2,
			"pool": ["arcana", "deception", "history", "intimidation", "investigation", "nature", "religion"],
			"any": false,
			"mastery": 0,
			"gold": 100,
			"features": [
				{"id": &"eldritch_invocations", "name": "Мистические воззвания", "desc": "Вы знаете одно воззвание на 1 уровне и получаете новые с ростом уровня. Воззвания — отдельный каталог, зависящий от покровителя."},
				{"id": &"pact_magic", "name": "Магия договора", "desc": "Ваши ячейки заклинаний восстанавливаются на коротком отдыхе, а не на долгом. На 1 уровне — одна ячейка 1 круга."},
			],
			"choices": [],
			"casting": {"ability": &"charisma", "cantrips": 2, "prepared": 2, "slots": 1, "short_rest": true},
			"equipment": [
				[&"leather_armor", "Кожаный доспех", 1],
				[&"sickle", "Серп", 1],
				[&"dagger", "Кинжал", 2],
				[&"arcane_focus", "Магический фокус", 1],
				[&"scholars_pack", "Набор учёного", 1],
			],
		},
		{
			"id": &"wizard",
			"name": "Волшебник",
			"desc": "Учёный магии, чья сила выкована изучением и книгой заклинаний.",
			"hit_die": 6,
			"primary": ["intelligence"],
			"saves": ["intelligence", "wisdom"],
			"armor": [],
			"weapons": ["simple"],
			"tools": [],
			"skills": 2,
			"pool": ["arcana", "history", "insight", "investigation", "medicine", "nature", "religion"],
			"any": false,
			"mastery": 0,
			"gold": 55,
			"features": [
				{"id": &"ritual_adept", "name": "Мастер ритуалов", "desc": "Заклинания с меткой «ритуал», записанные в книге, вы можете читать как ритуалы, не подготавливая их."},
				{"id": &"arcane_recovery", "name": "Магическое восстановление", "desc": "Один раз в день на коротком отдыхе восстановите часть потраченных ячеек заклинаний."},
			],
			"choices": [],
			"casting": {"ability": &"intelligence", "cantrips": 3, "prepared": 4, "spellbook": 6, "slots": 2, "ritual": true},
			"equipment": [
				[&"dagger", "Кинжал", 2],
				[&"arcane_focus", "Магический фокус", 1],
				[&"robe", "Мантия", 1],
				[&"spellbook", "Книга заклинаний", 1],
				[&"scholars_pack", "Набор учёного", 1],
			],
		},
	]
