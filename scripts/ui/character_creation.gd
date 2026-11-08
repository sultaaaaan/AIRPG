extends Control
## Character creation screen.
##
## The five steps of the 2024 rules, one tab each, driven entirely by the
## data resources (ClassData / BackgroundData / SpeciesData). Adding a new
## class or species needs no change here: the lists are rebuilt from the
## repositories.
##
## Edits happen on a throwaway copy of the committed character, so "Отмена"
## really discards everything.

const MENU_SCENE := "res://scenes/MainMenu.tscn"

enum Page {
	CLASS,
	BACKGROUND,
	SPECIES,
	ABILITIES,
	SKILLS,
	EQUIPMENT,
}

const PAGE_TITLES := ["Класс", "Предыстория", "Вид", "Хар-ки", "Навыки", "Снаряжение"]

const ACCENT := Color(0.72, 0.85, 1.0)
const MUTED := Color(0.62, 0.7, 0.82)
const ERROR_COLOR := Color(0.95, 0.45, 0.4)
const OK_COLOR := Color(0.55, 0.85, 0.65)

const SKILL_ABILITY_SHORT := {
	&"strength": "СИЛ",
	&"dexterity": "ЛОВ",
	&"constitution": "ТЕЛ",
	&"intelligence": "ИНТ",
	&"wisdom": "МУД",
	&"charisma": "ХАР",
}

const TOOL_NAMES_RU := {
	&"artisans_tools": "ремесленные инструменты",
	&"calligraphers_supplies": "инструменты каллиграфа",
	&"carpenters_tools": "инструменты плотника",
	&"cartographers_tools": "инструменты картографа",
	&"forgery_kit": "набор для подделки",
	&"gaming_set": "игровой набор",
	&"herbalism_kit": "набор травника",
	&"musical_instrument": "музыкальный инструмент",
	&"navigators_tools": "инструменты штурмана",
	&"thieves_tools": "воровские инструменты",
}

const ARMOR_NAMES_RU := {
	&"light": "лёгкие",
	&"medium": "средние",
	&"heavy": "тяжёлые",
	&"shields": "щиты",
}

const WEAPON_NAMES_RU := {
	&"simple": "простое",
	&"martial": "воинское",
	&"martial_light": "воинское со свойством «лёгкое»",
}

const LANGUAGE_NAMES_RU := {
	&"common": "Общий",
	&"dwarvish": "Дварфский",
	&"elvish": "Эльфийский",
	&"giant": "Великаний",
	&"gnomish": "Гномий",
	&"halfling": "Полуросликов",
	&"draconic": "Драконий",
	&"infernal": "Инфернальный",
	&"celestial": "Небесный",
	&"orc": "Орочий",
	&"abyssal": "Бездны",
	&"sylvan": "Сильван",
	&"undercommon": "Подземный",
	&"primordial": "Первозданный",
}

@onready var _tabs: TabContainer = $Margin/Root/Body/Left/LeftMargin/Tabs
@onready var _sheet: RichTextLabel = $Margin/Root/Body/SheetPanel/SheetMargin/Sheet
@onready var _status: Label = $Margin/Root/Footer/StatusLabel
@onready var _name_edit: LineEdit = $Margin/Root/Header/NameEdit
@onready var _level_label: Label = $Margin/Root/Header/LevelLabel
@onready var _level_up: Button = $Margin/Root/Header/LevelUpButton
@onready var _accept: Button = $Margin/Root/Footer/AcceptButton
@onready var _cancel: Button = $Margin/Root/Footer/CancelButton

var draft: CharacterDraft = null

var _pages: Array[Control] = []
var _assignment: Dictionary = {}
var _ability_method: int = 0

var _skill_counter: Label = null
var _points_label: Label = null
var _point_results: Dictionary = {}


func _ready() -> void:
	draft = PlayerProfile.begin_edit()
	_ensure_ability_state()

	_name_edit.text = draft.character_name
	_name_edit.text_changed.connect(_on_name_changed)
	_accept.pressed.connect(_on_accept_pressed)
	_cancel.pressed.connect(_on_cancel_pressed)
	_tabs.tab_changed.connect(_on_tab_changed)
	_level_up.pressed.connect(_on_level_up_pressed)
	# Levelling only makes sense once there is a committed hero to advance.
	_level_up.visible = PlayerProfile.draft != null

	_build_page_shells()
	for index in _pages.size():
		_rebuild_page(index)

	_tabs.current_tab = Page.CLASS
	_refresh_sheet()
	_refresh_footer()
	_name_edit.grab_focus()


# --- setup ------------------------------------------------------------------

## Adopt the committed scores when they already form a valid standard array or
## a point-buy spread. A brand-new draft gets the classic 15..8 descending set.
func _ensure_ability_state() -> void:
	for index in CharacterDraft.ABILITIES.size():
		_assignment[CharacterDraft.ABILITIES[index]] = CharacterDraft.STANDARD_ARRAY[index]

	var values: Array = []
	var untouched := true
	for ability in CharacterDraft.ABILITIES:
		var value := int(draft.base_scores.get(ability, 10))
		values.append(value)
		if value != 10:
			untouched = false

	if untouched:
		draft.apply_standard_array(_assignment)
		return

	var standard: Array = CharacterDraft.STANDARD_ARRAY.duplicate()
	standard.sort()
	var sorted_values: Array = values.duplicate()
	sorted_values.sort()

	for ability in CharacterDraft.ABILITIES:
		_assignment[ability] = int(draft.base_scores[ability])

	if sorted_values != standard:
		_ability_method = 1


func _build_page_shells() -> void:
	for index in PAGE_TITLES.size():
		var page: Control
		if index <= Page.SPECIES:
			page = HBoxContainer.new()
			page.add_theme_constant_override("separation", 12)
		else:
			page = ScrollContainer.new()
			page.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		page.name = "Page%d" % index
		page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		page.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_tabs.add_child(page)
		_pages.append(page)
		_tabs.set_tab_title(index, PAGE_TITLES[index])


func _rebuild_page(index: int) -> void:
	if index < 0 or index >= _pages.size():
		return

	var root := _pages[index]
	for child in root.get_children():
		root.remove_child(child)
		child.queue_free()

	match index:
		Page.CLASS:
			_build_class_page(root)
		Page.BACKGROUND:
			_build_background_page(root)
		Page.SPECIES:
			_build_species_page(root)
		Page.ABILITIES:
			_build_abilities_page(root)
		Page.SKILLS:
			_build_skills_page(root)
		Page.EQUIPMENT:
			_build_equipment_page(root)


# --- list pages -------------------------------------------------------------

func _build_class_page(root: Control) -> void:
	var classes := ClassRepository.load_all()
	var current := &""
	if draft.class_data != null:
		current = draft.class_data.id
	_build_list_page(root, classes, current, _on_class_selected, _fill_class_detail)


func _build_background_page(root: Control) -> void:
	var backgrounds := BackgroundRepository.load_all()
	var current := &""
	if draft.background != null:
		current = draft.background.id
	_build_list_page(root, backgrounds, current, _on_background_selected, _fill_background_detail)


func _build_species_page(root: Control) -> void:
	var species_list := SpeciesRepository.load_all()
	var current := &""
	if draft.species != null:
		current = draft.species.id
	_build_list_page(root, species_list, current, _on_species_selected, _fill_species_detail)


func _build_list_page(root: Control, entries: Array, current_id: StringName, on_select: Callable, fill_detail: Callable) -> void:
	var list := ItemList.new()
	list.custom_minimum_size = Vector2(220, 0)
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var current := -1
	for index in entries.size():
		var entry: Resource = entries[index]
		list.add_item(String(entry.display_name))
		if entry.id == current_id:
			current = index
	root.add_child(list)
	list.item_selected.connect(on_select)
	if current >= 0:
		list.select(current)
		list.ensure_current_is_visible()

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)

	var detail := VBoxContainer.new()
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail.add_theme_constant_override("separation", 6)
	scroll.add_child(detail)
	fill_detail.call(detail)


func _on_class_selected(index: int) -> void:
	var classes := ClassRepository.load_all()
	if index < 0 or index >= classes.size():
		return
	var picked: ClassData = classes[index]
	if draft.class_data != picked:
		draft.class_data = picked
		draft.skill_choices.clear()
		draft.option_choices.clear()
	_rebuild_page.call_deferred(Page.CLASS)
	_refresh_sheet()
	_refresh_footer()


func _on_background_selected(index: int) -> void:
	var backgrounds := BackgroundRepository.load_all()
	if index < 0 or index >= backgrounds.size():
		return
	var picked: BackgroundData = backgrounds[index]
	draft.background = picked
	var targets: Array[StringName] = []
	for ability in picked.ability_options:
		targets.append(ability)
	draft.background_targets = targets
	if draft.background_spread.size() != 3:
		draft.background_spread = CharacterDraft.SPREAD_PRIMARY.duplicate()
	_rebuild_page.call_deferred(Page.BACKGROUND)
	_refresh_sheet()
	_refresh_footer()


func _on_species_selected(index: int) -> void:
	var species_list := SpeciesRepository.load_all()
	if index < 0 or index >= species_list.size():
		return
	var picked: SpeciesData = species_list[index]
	draft.species = picked
	draft.option_choices.clear()

	if picked.has_size_choice():
		draft.chosen_size = picked.size_options[0]
	else:
		draft.chosen_size = picked.size_options[0]

	var languages: Array[StringName] = []
	for _slot in picked.language_choices:
		languages.append(&"")
	draft.chosen_languages = languages

	_rebuild_page.call_deferred(Page.SPECIES)
	_refresh_sheet()
	_refresh_footer()


# --- class detail -----------------------------------------------------------

func _fill_class_detail(detail: Control) -> void:
	var class_data := draft.class_data
	if class_data == null:
		_add_paragraph(detail, "Выберите класс в списке слева.")
		return

	_add_title(detail, class_data.display_name)
	_add_paragraph(detail, class_data.description)
	_add_meta(detail, "Кость хитов: d%d · Навыков на выбор: %d" % [class_data.hit_die, class_data.skill_choice_count])
	_add_meta(detail, "Спасброски: %s" % _ability_list(class_data.saving_throws))
	_add_meta(detail, "Основная характеристика: %s" % _ability_list(class_data.primary_abilities))
	if class_data.weapon_mastery_count > 0:
		_add_meta(detail, "Мастерство оружия: %d вида оружия" % class_data.weapon_mastery_count)

	var subclasses := SubclassRepository.for_class(class_data.id)
	if draft.subclass_required():
		_add_subclass_picker(detail, subclasses)
	elif not subclasses.is_empty():
		var subclass_names := PackedStringArray()
		for entry in subclasses:
			subclass_names.append(entry.display_name)
		_add_section(detail, "Подклассы — выбор на %d уровне" % class_data.subclass_unlock_level)
		_add_meta(detail, ", ".join(subclass_names))
		_add_meta(detail, "На %d уровне подкласс не выбирается." % draft.level)

	_add_section(detail, "Владение")
	_add_meta(detail, "Доспехи: %s" % _named_list(class_data.armor_training, ARMOR_NAMES_RU))
	_add_meta(detail, "Оружие: %s" % _named_list(class_data.weapon_training, WEAPON_NAMES_RU))
	if not class_data.tool_proficiencies.is_empty():
		_add_meta(detail, "Инструменты: %s" % _named_list(class_data.tool_proficiencies, TOOL_NAMES_RU))

	var features := class_data.features_through_level(draft.level)
	if not features.is_empty():
		_add_section(detail, "Умения класса")
		for feature in features:
			_add_feature(detail, feature, draft.level > 1)

	if draft.subclass != null and draft.level >= draft.subclass.unlock_level:
		_add_section(detail, "Умения подкласса")
		for feature in draft.subclass.features:
			_add_feature(detail, feature, true)

	for group in class_data.choices:
		_add_gap(detail, 4)
		_add_choice(detail, group)
	for group in draft.subclass_choices():
		_add_gap(detail, 4)
		_add_choice(detail, group)

	_add_section(detail, "Снаряжение")
	if class_data.equipment_pack.is_empty():
		_add_meta(detail, "%d золотых на снаряжение." % class_data.alternative_gold)
	else:
		for entry in class_data.equipment_pack:
			_add_meta(detail, "• %s ×%d" % [entry.display_name, entry.quantity])
		_add_meta(detail, "или %d золотых" % class_data.alternative_gold)


func _add_subclass_picker(detail: Control, subclasses: Array[SubclassData]) -> void:
	_add_section(detail, "Подкласс — уровень %d" % draft.level)
	if subclasses.is_empty():
		_add_meta(detail, "У этого класса пока нет подклассов.")
		return

	var picker := OptionButton.new()
	picker.add_item("— выберите подкласс —")
	var selected := 0
	for index in subclasses.size():
		picker.add_item(subclasses[index].display_name)
		if draft.subclass != null and draft.subclass.id == subclasses[index].id:
			selected = index + 1
	picker.select(selected)
	picker.item_selected.connect(_on_subclass_selected)
	detail.add_child(picker)

	if draft.subclass != null:
		_add_paragraph(detail, draft.subclass.description)


func _on_subclass_selected(index: int) -> void:
	var subclasses := draft.available_subclasses()
	if index <= 0 or index - 1 >= subclasses.size():
		return
	draft.select_subclass(subclasses[index - 1].id)
	_rebuild_page.call_deferred(Page.CLASS)
	_refresh_sheet()
	_refresh_footer()


# --- background detail ------------------------------------------------------

func _fill_background_detail(detail: Control) -> void:
	var background := draft.background
	if background == null:
		_add_paragraph(detail, "Выберите предысторию в списке слева.")
		return

	_add_title(detail, background.display_name)
	_add_paragraph(detail, background.description)
	_add_section(detail, "Бонусы к характеристикам")
	_add_meta(detail, "%s — распределите +2/+1 или +1/+1/+1 на вкладке «Хар-ки»." % _ability_list(background.ability_options))

	_add_section(detail, "Владение")
	_add_meta(detail, "Навыки: %s" % _named_list(background.skill_proficiencies, CharacterText.SKILL_NAMES_RU))
	if background.tool_proficiency != &"":
		_add_meta(detail, "Инструмент: %s" % String(TOOL_NAMES_RU.get(background.tool_proficiency, background.tool_proficiency)))

	if background.origin_feat != null:
		_add_section(detail, "Черта происхождения")
		_add_feature(detail, background.origin_feat)

	_add_section(detail, "Снаряжение")
	if background.equipment_pack.is_empty():
		_add_meta(detail, "%d золотых." % background.alternative_gold)
	else:
		for entry in background.equipment_pack:
			_add_meta(detail, "• %s ×%d" % [entry.display_name, entry.quantity])
		_add_meta(detail, "или %d золотых" % background.alternative_gold)


# --- species detail ---------------------------------------------------------

func _fill_species_detail(detail: Control) -> void:
	var species := draft.species
	if species == null:
		_add_paragraph(detail, "Выберите вид в списке слева.")
		return

	_add_title(detail, species.display_name)
	_add_paragraph(detail, species.description)
	_add_meta(detail, "Скорость: %d футов" % species.speed)
	if species.darkvision_range > 0:
		_add_meta(detail, "Тёмное зрение: %d футов" % species.darkvision_range)
	else:
		_add_meta(detail, "Тёмное зрение: нет")

	if species.has_size_choice():
		_add_section(detail, "Размер")
		_add_size_picker(detail, species)
	else:
		_add_meta(detail, "Размер: %s" % _size_name(species.size_options[0]))

	_add_section(detail, "Языки")
	_add_meta(detail, "Автоматически: %s" % _named_list(species.languages, LANGUAGE_NAMES_RU))
	for slot in species.language_choices:
		_add_language_picker(detail, species, slot)

	_add_section(detail, "Особенности")
	for entry in species.traits:
		_add_feature(detail, entry)

	for group in species.choices:
		_add_gap(detail, 4)
		_add_choice(detail, group)


func _add_size_picker(parent: Control, species: SpeciesData) -> void:
	var picker := OptionButton.new()
	for size in species.size_options:
		picker.add_item(_size_name(size))
	var selected := species.size_options.find(draft.chosen_size)
	picker.select(maxi(0, selected))
	picker.item_selected.connect(_on_size_selected.bind(species))
	parent.add_child(picker)


func _add_language_picker(parent: Control, species: SpeciesData, slot: int) -> void:
	var options := _extra_languages(species)
	var picker := OptionButton.new()
	picker.add_item("— выберите язык —")
	for language in options:
		picker.add_item(String(LANGUAGE_NAMES_RU.get(language, language)))

	var current := &""
	if slot < draft.chosen_languages.size():
		current = draft.chosen_languages[slot]
	var selected := options.find(current)
	picker.select(maxi(0, selected + 1))
	picker.item_selected.connect(_on_language_selected.bind(slot))
	parent.add_child(picker)


func _on_size_selected(index: int, species: SpeciesData) -> void:
	if index < 0 or index >= species.size_options.size():
		return
	draft.chosen_size = species.size_options[index]
	_rebuild_page.call_deferred(Page.SPECIES)
	_refresh_sheet()
	_refresh_footer()


func _on_language_selected(index: int, slot: int) -> void:
	var species := draft.species
	if species == null or index <= 0:
		return
	var options := _extra_languages(species)
	if index - 1 >= options.size():
		return
	if slot >= draft.chosen_languages.size():
		return
	draft.chosen_languages[slot] = options[index - 1]
	_rebuild_page.call_deferred(Page.SPECIES)
	_refresh_sheet()
	_refresh_footer()


func _extra_languages(species: SpeciesData) -> Array[StringName]:
	var options: Array[StringName] = []
	for language in LANGUAGE_NAMES_RU.keys():
		if language in species.languages:
			continue
		options.append(language)
	return options


# --- ability page -----------------------------------------------------------

func _build_abilities_page(root: Control) -> void:
	var content := _scroll_content(root)
	_add_section(content, "Метод")

	var method := OptionButton.new()
	method.add_item("Стандартный набор (15/14/13/12/10/8)")
	method.add_item("Покупка очков (27)")
	method.select(_ability_method)
	method.item_selected.connect(_on_method_selected)
	content.add_child(method)

	_add_gap(content, 6)

	_points_label = null
	_point_results.clear()

	if _ability_method == 0:
		for ability in CharacterDraft.ABILITIES:
			_add_standard_row(content, ability)
		_add_meta(content, "Значения не повторяются: выбор занятого числа меняет местами две характеристики.")
	else:
		for ability in CharacterDraft.ABILITIES:
			_add_point_buy_row(content, ability)
		_points_label = Label.new()
		_points_label.add_theme_color_override("font_color", ACCENT)
		content.add_child(_points_label)
		_update_point_labels()

	_add_gap(content, 12)
	_add_background_bonuses(content)
	_add_asi_section(content)


func _add_standard_row(content: Control, ability: StringName) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

	var name_label := Label.new()
	name_label.text = String(CharacterDraft.ABILITY_LABELS_RU[ability])
	name_label.custom_minimum_size = Vector2(150, 0)
	row.add_child(name_label)

	var picker := OptionButton.new()
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for value in CharacterDraft.STANDARD_ARRAY:
		picker.add_item(str(value))
	picker.select(maxi(0, CharacterDraft.STANDARD_ARRAY.find(int(_assignment.get(ability, 10)))))
	picker.item_selected.connect(_on_standard_pick.bind(ability))
	row.add_child(picker)

	var result := Label.new()
	result.custom_minimum_size = Vector2(150, 0)
	result.text = _score_preview(ability)
	row.add_child(result)

	content.add_child(row)


func _add_point_buy_row(content: Control, ability: StringName) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

	var name_label := Label.new()
	name_label.text = String(CharacterDraft.ABILITY_LABELS_RU[ability])
	name_label.custom_minimum_size = Vector2(150, 0)
	row.add_child(name_label)

	var spin := SpinBox.new()
	spin.min_value = CharacterDraft.POINT_BUY_MIN
	spin.max_value = CharacterDraft.POINT_BUY_MAX
	spin.step = 1
	spin.value = int(draft.base_scores.get(ability, 10))
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spin.value_changed.connect(_on_point_buy_changed.bind(ability))
	row.add_child(spin)

	var result := Label.new()
	result.custom_minimum_size = Vector2(150, 0)
	result.text = _score_preview(ability)
	row.add_child(result)
	_point_results[ability] = result

	content.add_child(row)


func _add_background_bonuses(content: Control) -> void:
	_add_section(content, "Бонусы предыстории")
	if draft.background == null:
		_add_meta(content, "Сначала выберите предысторию на вкладке «Предыстория».")
		return

	var spread := OptionButton.new()
	spread.add_item("+2 / +1")
	spread.add_item("+1 / +1 / +1")
	spread.select(0 if Array(draft.background_spread) == CharacterDraft.SPREAD_PRIMARY else 1)
	spread.item_selected.connect(_on_spread_selected)
	content.add_child(spread)

	for slot in draft.background_targets.size():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)

		var slot_label := Label.new()
		slot_label.custom_minimum_size = Vector2(150, 0)
		slot_label.text = "Бонус %d" % (slot + 1)
		row.add_child(slot_label)

		var picker := OptionButton.new()
		picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		picker.add_item("— выберите —")
		for ability in draft.background.ability_options:
			picker.add_item(String(CharacterDraft.ABILITY_LABELS_RU[ability]))
		var selected := 0
		for index in draft.background.ability_options.size():
			if draft.background.ability_options[index] == draft.background_targets[slot]:
				selected = index + 1
		picker.select(selected)
		picker.item_selected.connect(_on_background_target_selected.bind(slot))
		row.add_child(picker)

		content.add_child(row)


func _add_asi_section(content: Control) -> void:
	var asi_levels := Progression.asi_levels_through(draft.level)
	if asi_levels.is_empty():
		return

	_add_gap(content, 12)
	_add_section(content, "Улучшение характеристик")
	for asi_level in asi_levels:
		_add_asi_block(content, asi_level)


func _add_asi_block(content: Control, asi_level: int) -> void:
	var mode := draft.asi_mode(asi_level)
	var picks := draft.asi_picks(asi_level)

	_add_meta(content, "Уровень %d" % asi_level)

	var mode_picker := OptionButton.new()
	mode_picker.add_item("Одна характеристика +2")
	mode_picker.add_item("Две характеристики +1/+1")
	mode_picker.select(mode)
	mode_picker.item_selected.connect(_on_asi_mode_selected.bind(asi_level))
	content.add_child(mode_picker)

	var slots := 1 if mode == 0 else 2
	for slot in slots:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)

		var slot_label := Label.new()
		slot_label.custom_minimum_size = Vector2(150, 0)
		slot_label.text = "Характеристика %d" % (slot + 1)
		row.add_child(slot_label)

		var picker := OptionButton.new()
		picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		picker.add_item("— выберите —")
		for ability in CharacterDraft.ABILITIES:
			picker.add_item(String(CharacterDraft.ABILITY_LABELS_RU[ability]))

		var selected := 0
		if slot < picks.size():
			var found := CharacterDraft.ABILITIES.find(picks[slot])
			if found >= 0:
				selected = found + 1
		picker.select(selected)
		picker.item_selected.connect(_on_asi_target_selected.bind(asi_level, slot))
		row.add_child(picker)

		content.add_child(row)


func _on_asi_mode_selected(index: int, asi_level: int) -> void:
	draft.set_asi_mode(asi_level, index)
	_rebuild_page.call_deferred(Page.ABILITIES)
	_refresh_sheet()
	_refresh_footer()


func _on_asi_target_selected(index: int, asi_level: int, slot: int) -> void:
	if index <= 0 or index - 1 >= CharacterDraft.ABILITIES.size():
		return
	var picks := draft.asi_picks(asi_level)
	while picks.size() <= slot:
		picks.append(&"")
	picks[slot] = CharacterDraft.ABILITIES[index - 1]
	draft.set_asi_choice(asi_level, picks)
	_rebuild_page.call_deferred(Page.ABILITIES)
	_refresh_sheet()
	_refresh_footer()


func _on_method_selected(index: int) -> void:
	if index == _ability_method:
		return
	_ability_method = index
	if _ability_method == 0:
		for position in CharacterDraft.ABILITIES.size():
			_assignment[CharacterDraft.ABILITIES[position]] = CharacterDraft.STANDARD_ARRAY[position]
		draft.apply_standard_array(_assignment)
	else:
		var scores := draft.base_scores.duplicate()
		for ability in CharacterDraft.ABILITIES:
			scores[ability] = clampi(int(scores.get(ability, 10)), CharacterDraft.POINT_BUY_MIN, CharacterDraft.POINT_BUY_MAX)
		draft.apply_point_buy(scores)
	_rebuild_page.call_deferred(Page.ABILITIES)
	_refresh_sheet()
	_refresh_footer()


func _on_standard_pick(item_index: int, ability: StringName) -> void:
	if item_index < 0 or item_index >= CharacterDraft.STANDARD_ARRAY.size():
		return
	var value: int = CharacterDraft.STANDARD_ARRAY[item_index]
	var previous: int = int(_assignment.get(ability, 10))
	if previous == value:
		return

	for other in CharacterDraft.ABILITIES:
		if other != ability and int(_assignment.get(other, 10)) == value:
			_assignment[other] = previous
			break
	_assignment[ability] = value
	draft.apply_standard_array(_assignment)
	_rebuild_page.call_deferred(Page.ABILITIES)
	_refresh_sheet()
	_refresh_footer()


func _on_point_buy_changed(value: float, ability: StringName) -> void:
	var scores := draft.base_scores.duplicate()
	scores[ability] = int(value)
	var problems := draft.apply_point_buy(scores)
	_update_point_labels()
	_refresh_sheet()
	if problems.is_empty():
		_refresh_footer()
	else:
		_refresh_footer(problems[0])


func _update_point_labels() -> void:
	if is_instance_valid(_points_label):
		_points_label.text = "Потрачено %d из %d очков." % [draft.point_buy_spent(), CharacterDraft.POINT_BUY_BUDGET]
	for ability in _point_results:
		var label: Label = _point_results[ability]
		if is_instance_valid(label):
			label.text = _score_preview(ability)


func _on_spread_selected(index: int) -> void:
	if index == 0:
		draft.background_spread = CharacterDraft.SPREAD_PRIMARY.duplicate()
	else:
		draft.background_spread = CharacterDraft.SPREAD_BALANCED.duplicate()
	_rebuild_page.call_deferred(Page.ABILITIES)
	_refresh_sheet()
	_refresh_footer()


func _on_background_target_selected(index: int, slot: int) -> void:
	if draft.background == null or index <= 0:
		return
	var ability = draft.background.ability_options[index - 1]
	if slot >= draft.background_targets.size():
		return
	draft.background_targets[slot] = ability
	_rebuild_page.call_deferred(Page.ABILITIES)
	_refresh_sheet()
	_refresh_footer()


# --- skills page ------------------------------------------------------------

func _build_skills_page(root: Control) -> void:
	var content := _scroll_content(root)

	_add_section(content, "Навыки предыстории")
	if draft.background != null:
		_add_meta(content, "%s — уже ваши." % _named_list(draft.background.skill_proficiencies, CharacterText.SKILL_NAMES_RU))
	else:
		_add_meta(content, "Предыстория не выбрана.")

	_add_section(content, "Навыки класса")
	if draft.class_data == null:
		_add_meta(content, "Сначала выберите класс.")
		return

	_skill_counter = Label.new()
	_skill_counter.add_theme_color_override("font_color", ACCENT)
	content.add_child(_skill_counter)
	_refresh_skill_counter()

	var candidates: Array = []
	if draft.class_data.skill_pool_is_any:
		candidates = CharacterDraft.SKILL_ABILITY.keys()
	else:
		for skill in draft.class_data.skill_pool:
			candidates.append(skill)

	for skill in candidates:
		var check := CheckBox.new()
		check.text = "%s  (%s)" % [
			String(CharacterText.SKILL_NAMES_RU.get(skill, skill)),
			String(SKILL_ABILITY_SHORT.get(CharacterDraft.SKILL_ABILITY.get(skill, &""), "?")),
		]
		check.button_pressed = skill in draft.skill_choices
		check.toggled.connect(_on_skill_toggled.bind(skill))
		content.add_child(check)


func _on_skill_toggled(pressed: bool, skill: StringName) -> void:
	if draft.class_data == null:
		return

	if pressed:
		if draft.skill_choices.size() >= draft.class_data.skill_choice_count:
			_refresh_footer("Сначала снимите один из выбранных навыков.")
			_rebuild_page.call_deferred(Page.SKILLS)
			return
		if skill not in draft.skill_choices:
			draft.skill_choices.append(skill)
	else:
		draft.skill_choices.erase(skill)

	_refresh_skill_counter()
	_refresh_sheet()
	_refresh_footer()


func _refresh_skill_counter() -> void:
	if not is_instance_valid(_skill_counter) or draft.class_data == null:
		return
	_skill_counter.text = "Выбрано %d из %d" % [draft.skill_choices.size(), draft.class_data.skill_choice_count]


# --- equipment page ---------------------------------------------------------

func _build_equipment_page(root: Control) -> void:
	var content := _scroll_content(root)

	_add_section(content, "Стартовое снаряжение")
	var picker := OptionButton.new()
	picker.add_item("Пакет от класса и предыстории")
	picker.add_item("Золото вместо пакета")
	picker.select(0 if draft.equipment_mode == CharacterDraft.EquipmentMode.PACK else 1)
	picker.item_selected.connect(_on_equipment_selected)
	content.add_child(picker)

	_add_gap(content, 8)
	_add_section(content, "Вы получите")

	if draft.equipment_mode == CharacterDraft.EquipmentMode.PACK:
		var entries := draft.starting_equipment()
		if entries.is_empty():
			_add_meta(content, "Пока ничего — выберите класс и предысторию.")
		for entry in entries:
			_add_meta(content, "• %s ×%d" % [entry.display_name, entry.quantity])
	else:
		_add_meta(content, "• %d золотых" % draft.starting_gold())
		_add_meta(content, "Класс даёт %d, предыстория %d." % [
			draft.class_data.alternative_gold if draft.class_data != null else 0,
			draft.background.alternative_gold if draft.background != null else 0,
		])


func _on_equipment_selected(index: int) -> void:
	draft.equipment_mode = CharacterDraft.EquipmentMode.PACK if index == 0 else CharacterDraft.EquipmentMode.GOLD
	_rebuild_page.call_deferred(Page.EQUIPMENT)
	_refresh_sheet()
	_refresh_footer()


# --- shared choice widget ---------------------------------------------------

func _add_choice(parent: Control, group: ChoiceGroupData) -> void:
	_add_section(parent, group.prompt)

	var picker := OptionButton.new()
	picker.add_item("— выберите —")
	for option in group.options:
		picker.add_item(option.display_name)

	var picked := draft.selected_options(group.id)
	var selected := 0
	if not picked.is_empty():
		for index in group.options.size():
			if group.options[index].id == picked[0]:
				selected = index + 1
	picker.select(selected)
	picker.item_selected.connect(_on_choice_selected.bind(group))
	parent.add_child(picker)

	var description := Label.new()
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.add_theme_color_override("font_color", MUTED)
	description.add_theme_font_size_override("font_size", 13)
	if selected > 0:
		description.text = group.options[selected - 1].description
	parent.add_child(description)


func _on_choice_selected(item_index: int, group: ChoiceGroupData) -> void:
	if item_index <= 0:
		draft.option_choices.erase(group.id)
	else:
		draft.select_option(group.id, group.options[item_index - 1].id)
	_rebuild_page.call_deferred(_tabs.current_tab)
	_refresh_sheet()
	_refresh_footer()


# --- footer / sheet ---------------------------------------------------------

func _on_name_changed(text: String) -> void:
	draft.character_name = text
	_refresh_sheet()
	_refresh_footer()


func _on_tab_changed(index: int) -> void:
	_rebuild_page(index)
	_refresh_sheet()


func _refresh_footer(message: String = "") -> void:
	var problems := draft.validate()
	_accept.disabled = not problems.is_empty()
	_refresh_level()

	if not message.is_empty():
		_status.text = message
		_status.add_theme_color_override("font_color", ERROR_COLOR)
	elif problems.is_empty():
		_status.text = "Персонаж готов — нажмите «Готово»."
		_status.add_theme_color_override("font_color", OK_COLOR)
	else:
		_status.text = "Осталось: %s" % problems[0]
		_status.add_theme_color_override("font_color", MUTED)


func _refresh_level() -> void:
	_level_up.visible = PlayerProfile.draft != null
	_level_up.disabled = not draft.can_level_up() or not draft.validate().is_empty()

	var text := "Уровень %d" % draft.level
	if draft.level < Progression.MAX_LEVEL:
		text += " · опыт %d/%d" % [draft.xp, Progression.xp_for_level(draft.level + 1)]
	else:
		text += " · максимум (опыт %d)" % draft.xp
	if draft.has_pending_asi():
		text += " · есть улучшение"
	_level_label.text = text


func _on_level_up_pressed() -> void:
	if PlayerProfile.draft == null:
		return
	if not draft.validate().is_empty():
		_refresh_footer()
		return
	if not draft.level_up():
		return

	var target := _tabs.current_tab
	if draft.subclass_required() and draft.subclass == null:
		target = Page.CLASS
	elif not draft.pending_asi_levels().is_empty():
		target = Page.ABILITIES

	if _tabs.current_tab != target:
		_tabs.current_tab = target
	else:
		_rebuild_page(target)
	_refresh_sheet()
	_refresh_footer()


func _refresh_sheet() -> void:
	_sheet.text = _sheet_bbcode()


func _sheet_bbcode() -> String:
	var lines := PackedStringArray()
	var hero := draft.character_name.strip_edges()
	if hero.is_empty():
		hero = "Безымянный"
	lines.append("[font_size=22][b]%s[/b][/font_size]" % _bb(hero))

	var subtitle := PackedStringArray()
	if draft.class_data != null:
		subtitle.append(draft.class_data.display_name)
	if draft.background != null:
		subtitle.append(draft.background.display_name)
	if draft.species != null:
		subtitle.append(draft.species.display_name)
	if not subtitle.is_empty():
		lines.append("[color=#8fb4dd]%s[/color]" % _bb(" · ".join(subtitle)))

	lines.append("")
	for ability in CharacterDraft.ABILITIES:
		lines.append("%s  [b]%d[/b]  (%+d)%s" % [
			String(CharacterDraft.ABILITY_LABELS_RU[ability]),
			draft.ability_score(ability),
			draft.ability_modifier(ability),
			_bonus_suffix(ability),
		])

	lines.append("")
	lines.append("Хиты: [b]%d[/b]    КД: [b]%d[/b]" % [draft.max_hit_points(), draft.armor_class()])
	lines.append("Инициатива: %+d    Пасс. восприятие: %d" % [draft.initiative(), draft.passive_perception()])
	lines.append("Бонус мастерства: +%d" % draft.proficiency_bonus())

	if draft.spellcasting_ability() != &"":
		lines.append("Заклинания: КС [b]%d[/b], атака %+d" % [draft.spell_save_dc(), draft.spell_attack_bonus()])

	lines.append("")
	lines.append("[color=#8fb4dd]Спасброски[/color]")
	var saves := PackedStringArray()
	for ability in CharacterDraft.ABILITIES:
		if ability in draft.saving_throw_proficiencies():
			saves.append("%s %+d" % [String(CharacterDraft.ABILITY_LABELS_RU[ability]), draft.saving_throw_bonus(ability)])
	lines.append(", ".join(saves) if not saves.is_empty() else "—")

	lines.append("")
	lines.append("[color=#8fb4dd]Навыки[/color]")
	var skills := draft.skill_proficiencies()
	if skills.is_empty():
		lines.append("—")
	else:
		for skill in skills:
			lines.append("• %s %+d" % [String(CharacterText.SKILL_NAMES_RU.get(skill, skill)), draft.skill_bonus(skill)])

	lines.append("")
	lines.append("[color=#8fb4dd]Выборы[/color]")
	var picked_any := false
	if draft.class_data != null:
		for group in draft.class_data.choices:
			var picks := draft.selected_options(group.id)
			if picks.is_empty():
				continue
			picked_any = true
			lines.append("• %s: %s" % [_bb(group.prompt), _bb(_option_name(group, picks[0]))])
	if draft.species != null:
		for group in draft.species.choices:
			var picks := draft.selected_options(group.id)
			if picks.is_empty():
				continue
			picked_any = true
			lines.append("• %s: %s" % [_bb(group.prompt), _bb(_option_name(group, picks[0]))])
	if not picked_any:
		lines.append("—")

	lines.append("")
	lines.append("[color=#8fb4dd]Снаряжение[/color]")
	if draft.equipment_mode == CharacterDraft.EquipmentMode.GOLD:
		lines.append("• %d золотых" % draft.starting_gold())
	else:
		var entries := draft.starting_equipment()
		if entries.is_empty():
			lines.append("—")
		for entry in entries:
			lines.append("• %s ×%d" % [_bb(entry.display_name), entry.quantity])

	lines.append("")
	var problems := draft.validate()
	if problems.is_empty():
		lines.append("[color=#8cd9a4]Готов[/color]")
	else:
		lines.append("[color=#f27a6a]Не хватает:[/color]")
		for problem in problems:
			lines.append("[color=#f27a6a]• %s[/color]" % _bb(problem))

	return "\n".join(lines)


func _on_accept_pressed() -> void:
	if not draft.validate().is_empty():
		_refresh_footer()
		return
	PlayerProfile.commit(draft)
	get_tree().change_scene_to_file(MENU_SCENE)


func _on_cancel_pressed() -> void:
	get_tree().change_scene_to_file(MENU_SCENE)


# --- small helpers ----------------------------------------------------------

func _scroll_content(root: Control) -> VBoxContainer:
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 6)
	root.add_child(content)
	return content


func _add_title(parent: Control, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", Color(0.88, 0.94, 1.0))
	parent.add_child(label)


func _add_section(parent: Control, text: String) -> void:
	var label := Label.new()
	label.text = text.to_upper()
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", ACCENT)
	parent.add_child(label)


func _add_paragraph(parent: Control, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", MUTED)
	parent.add_child(label)


func _add_meta(parent: Control, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 13)
	parent.add_child(label)


func _add_feature(parent: Control, feature: FeatureData, show_level: bool = false) -> void:
	if feature == null:
		return
	var prefix := "ур. %d · " % feature.level if show_level else ""
	var title := Label.new()
	title.text = "• %s%s" % [prefix, feature.display_name]
	title.add_theme_color_override("font_color", ACCENT)
	parent.add_child(title)

	var body := Label.new()
	body.text = feature.description
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_color_override("font_color", MUTED)
	body.add_theme_font_size_override("font_size", 13)
	parent.add_child(body)


func _add_gap(parent: Control, height: int) -> void:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, height)
	parent.add_child(spacer)


func _score_preview(ability: StringName) -> String:
	return "%d  (%+d)%s" % [
		draft.ability_score(ability),
		draft.ability_modifier(ability),
		_bonus_suffix(ability),
	]


func _bonus_suffix(ability: StringName) -> String:
	var bonus := draft.background_bonus(ability)
	if bonus <= 0:
		return ""
	return "  фон +%d" % bonus


func _ability_list(abilities: Array) -> String:
	var parts := PackedStringArray()
	for ability in abilities:
		parts.append(String(CharacterDraft.ABILITY_LABELS_RU.get(ability, ability)))
	return ", ".join(parts) if not parts.is_empty() else "нет"


func _named_list(values: Array, names: Dictionary) -> String:
	var parts := PackedStringArray()
	for value in values:
		parts.append(String(names.get(value, value)))
	return ", ".join(parts) if not parts.is_empty() else "нет"


func _size_name(size: StringName) -> String:
	match size:
		&"small":
			return "Маленький"
		&"medium":
			return "Средний"
		_:
			return String(size)


func _option_name(group: ChoiceGroupData, option_id: StringName) -> String:
	for option in group.options:
		if option.id == option_id:
			return option.display_name
	return String(option_id)


func _bb(text: String) -> String:
	return text.replace("[", "[lb]")
