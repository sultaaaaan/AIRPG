extends SceneTree
## One-shot generator for res://data/species/*.tres.
##
##   godot --headless --path . --script res://tools/generate_species_data.gd
##
## Species grant no ability score increases in the 2024 rules. Lineage /
## legacy / ancestry picks are ChoiceGroupData, the same type classes use,
## so the creation UI needs only one choice widget.

const OUT_DIR := "res://data/species"


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

	print("done: %d species" % saved)
	quit(0 if saved == 10 else 1)


func _build(d: Dictionary) -> SpeciesData:
	var s := SpeciesData.new()
	s.id = d["id"]
	s.display_name = d["name"]
	s.description = d["desc"]
	s.size_options = _names(d["sizes"])
	s.speed = d["speed"]
	s.creature_type = d.get("type", &"humanoid")
	s.darkvision_range = d.get("darkvision", 0)
	s.languages = _names(d["languages"])
	s.language_choices = d.get("language_choices", 0)
	for entry in d["traits"]:
		s.traits.append(_feature(entry["id"], entry["name"], entry["desc"]))
	for choice in d.get("choices", []):
		s.choices.append(_choice(choice))
	return s


func _feature(feature_id: StringName, display_name: String, description: String) -> FeatureData:
	var f := FeatureData.new()
	f.id = feature_id
	f.display_name = display_name
	f.description = description
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
		for entry in option.get("traits", []):
			o.features.append(_feature(entry["id"], entry["name"], entry["desc"]))
		ch.options.append(o)
	return ch


func _names(values: Array) -> Array[StringName]:
	var out: Array[StringName] = []
	for value in values:
		out.append(StringName(value))
	return out


# --- data -------------------------------------------------------------------

func _definitions() -> Array[Dictionary]:
	return [
		{
			"id": &"aasimar", "name": "Аазимар",
			"desc": "Смертный, в чьих жилах течёт свет небес.",
			"sizes": ["medium"], "speed": 30, "darkvision": 60,
			"languages": ["common", "celestial"],
			"traits": [
				{"id": &"celestial_resistance", "name": "Небесное сопротивление", "desc": "Сопротивление урону некротической энергией и излучением."},
				{"id": &"healing_hands", "name": "Исцеляющие руки", "desc": "Действием Магии коснитесь существа и восстановите ему количество d4 хитов, равное вашему бонусу мастерства."},
				{"id": &"light_bearer", "name": "Носитель света", "desc": "Вы знаете заговор «Свет». Базовая характеристика — Харизма."},
			],
		},
		{
			"id": &"dragonborn", "name": "Драконорождённый",
			"desc": "Потомок драконов, несущий в крови стихийную мощь.",
			"sizes": ["medium"], "speed": 30, "darkvision": 60,
			"languages": ["common", "draconic"],
			"traits": [
				{"id": &"draconic_ancestry", "name": "Драконье наследие", "desc": "Выберите вид дракона: он определяет тип урона дыхания и сопротивление."},
				{"id": &"breath_weapon", "name": "Дыхание дракона", "desc": "Действием Атаки выдохните стихию в конусе 4,5 м или линии 9 м. Урон 1d10, растёт с уровнем."},
				{"id": &"damage_resistance", "name": "Сопротивление урону", "desc": "Сопротивление типу урона, связанному с вашим драконьим наследием."},
			],
		},
		{
			"id": &"dwarf", "name": "Дварф",
			"desc": "Стойкий народ камня, упорный в труде и бою.",
			"sizes": ["medium"], "speed": 30, "darkvision": 120,
			"languages": ["common", "dwarvish"],
			"traits": [
				{"id": &"dwarven_resilience", "name": "Дварфская стойкость", "desc": "Сопротивление урону ядом и преимущество на спасброски от отравления."},
				{"id": &"dwarven_toughness", "name": "Дварфская выносливость", "desc": "Ваш максимум хитов увеличивается на 1 за каждый уровень."},
				{"id": &"stonecunning", "name": "Камнечутьё", "desc": "Бонусным действием на 10 минут получите чувство вибрации 18 м, пока стоите на камне. Применений = бонус мастерства."},
			],
		},
		{
			"id": &"elf", "name": "Эльф",
			"desc": "Долгоживущий народ лесов и звёзд, связанный с фейри.",
			"sizes": ["medium"], "speed": 30, "darkvision": 60,
			"languages": ["common", "elvish"],
			"traits": [
				{"id": &"fey_ancestry", "name": "Фейское наследие", "desc": "Преимущество на спасброски от очарования; магия не усыпляет вас."},
				{"id": &"keen_senses", "name": "Острые чувства", "desc": "Владение навыками Проницательность, Восприятие и Выживание."},
				{"id": &"trance", "name": "Транс", "desc": "Долгий отдых занимает 4 часа медитации вместо 8 часов сна."},
			],
			"choices": [
				{
					"id": &"elven_lineage", "prompt": "Выберите эльфийское наследие",
					"options": [
						{"id": &"drow", "name": "Дроу", "desc": "Заговор «Пляшущие огни». С 3 уровня — «Огонь фей», с 5 — «Тьма»."},
						{"id": &"high_elf", "name": "Высший эльф", "desc": "Заговор «Малый образ». С 3 уровня — «Обнаружение магии», с 5 — «Туманный шаг»."},
						{"id": &"wood_elf", "name": "Лесной эльф", "desc": "Заговор «Друидизм». С 3 уровня — «Скороход», с 5 — «Без следа». Скорость 10,5 м."},
					],
				},
			],
		},
		{
			"id": &"gnome", "name": "Гном",
			"desc": "Малый народ изобретателей и иллюзионистов с неуёмным любопытством.",
			"sizes": ["small"], "speed": 30, "darkvision": 60,
			"languages": ["common", "gnomish"],
			"traits": [
				{"id": &"gnomish_cunning", "name": "Гномья хитрость", "desc": "Преимущество на спасброски Интеллекта, Мудрости и Харизмы от магии."},
			],
			"choices": [
				{
					"id": &"gnomish_lineage", "prompt": "Выберите гномье наследие",
					"options": [
						{"id": &"forest_gnome", "name": "Лесной гном", "desc": "Заговор «Малый образ»; «Разговор с животными» всегда подготовлен."},
						{"id": &"rock_gnome", "name": "Скальный гном", "desc": "Заговоры «Починка» и «Малый образ»; можете создавать маленькие механизмы."},
					],
				},
			],
		},
		{
			"id": &"goliath", "name": "Голиаф",
			"desc": "Потомок великанов, рождённый для суровых вершин.",
			"sizes": ["medium"], "speed": 35,
			"languages": ["common", "giant"],
			"traits": [
				{"id": &"powerful_build", "name": "Могучий сложение", "desc": "Вы считаетесь на одну категорию больше при определении грузоподъёмности и переноса."},
				{"id": &"large_form", "name": "Большая форма", "desc": "С 5 уровня бонусным действием становитесь Большим на 10 минут."},
			],
			"choices": [
				{
					"id": &"giant_ancestry", "prompt": "Выберите наследие великана",
					"options": [
						{"id": &"cloud", "name": "Облачный", "desc": "Бонусным действием телепортируйтесь на 9 м. Применений = бонус мастерства."},
						{"id": &"fire", "name": "Огненный", "desc": "При попадании добавьте 1d10 урона огнём. Применений = бонус мастерства."},
						{"id": &"frost", "name": "Морозный", "desc": "При попадании добавьте 1d6 урона холодом и снизьте скорость цели на 3 м."},
						{"id": &"hill", "name": "Холмовой", "desc": "При попадании сбейте цель с ног (спасбросок Силы)."},
						{"id": &"stone", "name": "Каменный", "desc": "Реакцией снизьте получаемый урон на 1d12 + модификатор Телосложения."},
						{"id": &"storm", "name": "Грозовой", "desc": "Реакцией нанесите 1d8 урона звуком атакующему вас существу."},
					],
				},
			],
		},
		{
			"id": &"halfling", "name": "Полурослик",
			"desc": "Маленький народ, чья главная сила — удача и отвага.",
			"sizes": ["small"], "speed": 30,
			"languages": ["common", "halfling"],
			"traits": [
				{"id": &"brave", "name": "Отвага", "desc": "Преимущество на спасброски от состояния «Испуган»."},
				{"id": &"halfling_nimbleness", "name": "Ловкость полурослика", "desc": "Вы можете проходить через пространство существ, которые больше вас."},
				{"id": &"luck", "name": "Удача", "desc": "Если на d20 выпала 1, перебросьте кость и используйте новый результат."},
				{"id": &"naturally_stealthy", "name": "Прирождённая скрытность", "desc": "Можете прятаться, даже если вас заслоняет только существо больше вас."},
			],
		},
		{
			"id": &"human", "name": "Человек",
			"desc": "Самый приспособляемый народ, чья сила — в разнообразии.",
			"sizes": ["medium", "small"], "speed": 30,
			"languages": ["common"], "language_choices": 1,
			"traits": [
				{"id": &"resourceful", "name": "Находчивость", "desc": "После долгого отдыха получаете Героическое вдохновение."},
				{"id": &"skillful", "name": "Умелость", "desc": "Владение одним навыком на выбор."},
				{"id": &"versatile", "name": "Универсальность", "desc": "Получаете одну черту происхождения на выбор."},
			],
		},
		{
			"id": &"orc", "name": "Орк",
			"desc": "Свирепый народ, чья кровь помнит бесконечные битвы.",
			"sizes": ["medium"], "speed": 30, "darkvision": 120,
			"languages": ["common", "orc"],
			"traits": [
				{"id": &"adrenaline_rush", "name": "Прилив адреналина", "desc": "Бонусным действием совершите Рывок и получите временные хиты, равные бонусу мастерства. Применений = бонус мастерства."},
				{"id": &"relentless_endurance", "name": "Неукротимая выносливость", "desc": "Раз в долгий отдых вместо падения до 0 хитов останьтесь с 1 хитом."},
			],
		},
		{
			"id": &"tiefling", "name": "Тифлинг",
			"desc": "Носитель инфернальной крови, наследующий силу предка.",
			"sizes": ["medium", "small"], "speed": 30, "darkvision": 60,
			"languages": ["common", "infernal"],
			"traits": [
				{"id": &"otherworldly_presence", "name": "Потустороннее присутствие", "desc": "Вы знаете заговор «Чудотворство». Базовая характеристика — Харизма."},
			],
			"choices": [
				{
					"id": &"fiendish_legacy", "prompt": "Выберите инфернальное наследие",
					"options": [
						{"id": &"abyssal", "name": "Бездны", "desc": "Заговор «Ядовитый брызг»; сопротивление яду. С 3 — «Порча», с 5 — «Удержание личности»."},
						{"id": &"chthonic", "name": "Хтоническое", "desc": "Заговор «Ледяное прикосновение»; сопротивление некротике. С 3 — «Ложная жизнь», с 5 — «Луч слабости»."},
						{"id": &"infernal", "name": "Инфернальное", "desc": "Заговор «Огненный снаряд»; сопротивление огню. С 3 — «Адское возмездие», с 5 — «Тьма»."},
					],
				},
			],
		},
	]
