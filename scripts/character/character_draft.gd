class_name CharacterDraft
extends RefCounted
## Mutable in-progress character.
##
## Collects the player's selections for one character and derives every number
## the sheet needs. It is a plain RefCounted, not a Resource: two drafts must
## never share state, and a half-finished draft is not something to save as a
## game asset.
##
## Usage:
##     var draft := CharacterDraft.new()
##     draft.class_data = ClassRepository.find(&"fighter")
##     draft.background = BackgroundRepository.find(&"soldier")
##     draft.species = SpeciesRepository.find(&"dwarf")
##     draft.apply_standard_array({...})
##     draft.background_targets = [&"strength", &"constitution", &"dexterity"]
##     draft.skill_choices = [&"athletics", &"perception"]
##     draft.select_option(&"fighting_style", &"dueling")
##     print(draft.max_hit_points(), draft.armor_class())
##
## Everything here is rules arithmetic over ClassData / BackgroundData /
## SpeciesData. No scene tree, no signals, safe to unit test headless.

enum EquipmentMode {
	PACK,
	GOLD,
}

## How a class scales its spell slots.
enum CasterKind {
	NONE,
	FULL,
	HALF,
	PACT,
}

const ABILITIES := [&"strength", &"dexterity", &"constitution", &"intelligence", &"wisdom", &"charisma"]

## Standard languages a player may pick for species language choices.
const LANGUAGES := [
	&"common", &"dwarvish", &"elvish", &"giant", &"gnomish", &"halfling",
	&"draconic", &"infernal", &"celestial", &"orc", &"abyssal", &"sylvan",
	&"undercommon", &"primordial",
]

const ABILITY_LABELS_RU := {
	&"strength": "Сила",
	&"dexterity": "Ловкость",
	&"constitution": "Телосложение",
	&"intelligence": "Интеллект",
	&"wisdom": "Мудрость",
	&"charisma": "Харизма",
}

## Which ability each skill rolls with. Also drives passive scores.
const SKILL_ABILITY := {
	&"acrobatics": &"dexterity",
	&"animal_handling": &"wisdom",
	&"arcana": &"intelligence",
	&"athletics": &"strength",
	&"deception": &"charisma",
	&"history": &"intelligence",
	&"insight": &"wisdom",
	&"intimidation": &"charisma",
	&"investigation": &"intelligence",
	&"medicine": &"wisdom",
	&"nature": &"intelligence",
	&"perception": &"wisdom",
	&"performance": &"charisma",
	&"persuasion": &"charisma",
	&"religion": &"intelligence",
	&"sleight_of_hand": &"dexterity",
	&"stealth": &"dexterity",
	&"survival": &"wisdom",
}

const STANDARD_ARRAY := [15, 14, 13, 12, 10, 8]
const POINT_BUY_MIN := 8
const POINT_BUY_MAX := 15
const POINT_BUY_BUDGET := 27
const POINT_BUY_COST := {8: 0, 9: 1, 10: 2, 11: 3, 12: 4, 13: 5, 14: 7, 15: 9}

## Armour from the starting packs. [base AC, max DEX bonus] where -1 = no cap.
## TODO: move to ItemData once the item catalogue exists.
const ARMOR_TABLE := {
	&"leather_armor": [11, -1],
	&"studded_leather_armor": [12, -1],
	&"chain_shirt": [13, 2],
	&"chain_mail": [16, 0],
}
const SHIELD_BONUS := 2

const SPREAD_PRIMARY := [2, 1, 0]
const SPREAD_BALANCED := [1, 1, 1]

# --- selections -------------------------------------------------------------

var character_name: String = ""
var level: int = 1
## Experience total. Levels are milestone-friendly too: level_up() raises the
## level directly and syncs xp to the new threshold.
var xp: int = 0

var class_data: ClassData = null
## Chosen at `class_data.subclass_unlock_level` (3). Null below that level.
var subclass: SubclassData = null
var background: BackgroundData = null
var species: SpeciesData = null

## Ability scores before background bonuses. Keys are ability ids.
var base_scores: Dictionary = {}
## The three abilities that receive the background bonuses, in bonus order.
var background_targets: Array[StringName] = []
## Either [2, 1, 0] or [1, 1, 1].
var background_spread: Array = SPREAD_PRIMARY

## Class skill picks (must be inside class_data.skill_pool unless "any").
var skill_choices: Array[StringName] = []

## choice id -> Array[StringName] of chosen option ids. Works for class and
## species choices because both use ChoiceGroupData.
var option_choices: Dictionary = {}

## ASI level -> chosen ability ids. One id means +2, two ids mean +1/+1.
var asi_choices: Dictionary = {}
## ASI level -> 0 for +2, 1 for +1/+1. Keeps an empty allocation readable.
var asi_modes: Dictionary = {}

var chosen_size: StringName = &""
var chosen_languages: Array[StringName] = []

var equipment_mode: EquipmentMode = EquipmentMode.PACK


func _init() -> void:
	reset_base_scores()


# --- ability scores ---------------------------------------------------------

func reset_base_scores() -> void:
	for ability in ABILITIES:
		base_scores[ability] = 10


func set_base_score(ability: StringName, value: int) -> void:
	if ability not in ABILITIES:
		push_error("CharacterDraft: unknown ability %s" % ability)
		return
	base_scores[ability] = clampi(value, 1, 20)


## Assign the standard array. `assignment` maps ability id -> value and must be
## a permutation of [15, 14, 13, 12, 10, 8].
func apply_standard_array(assignment: Dictionary) -> PackedStringArray:
	var problems := PackedStringArray()
	for ability in ABILITIES:
		if not assignment.has(ability):
			problems.append("нет значения для %s" % ability)
	if not problems.is_empty():
		return problems

	var values: Array = []
	for ability in ABILITIES:
		values.append(int(assignment[ability]))
	values.sort()

	var expected: Array = STANDARD_ARRAY.duplicate()
	expected.sort()
	if values != expected:
		problems.append("набор должен быть перестановкой 15/14/13/12/10/8")
		return problems

	for ability in ABILITIES:
		base_scores[ability] = int(assignment[ability])
	return problems


## Spend 27 points across the six abilities (each 8..15 before bonuses).
func apply_point_buy(assignment: Dictionary) -> PackedStringArray:
	var problems := PackedStringArray()
	var spent := 0
	for ability in ABILITIES:
		if not assignment.has(ability):
			problems.append("нет значения для %s" % ability)
			continue
		var value := int(assignment[ability])
		if value < POINT_BUY_MIN or value > POINT_BUY_MAX:
			problems.append("%s вне диапазона 8..15" % ability)
			continue
		spent += int(POINT_BUY_COST[value])

	if not problems.is_empty():
		return problems
	if spent > POINT_BUY_BUDGET:
		problems.append("потрачено %d очков из %d" % [spent, POINT_BUY_BUDGET])
		return problems

	for ability in ABILITIES:
		base_scores[ability] = int(assignment[ability])
	return problems


## How many point-buy points the current base scores consume.
func point_buy_spent() -> int:
	var spent := 0
	for ability in ABILITIES:
		var value := int(base_scores.get(ability, 8))
		if POINT_BUY_COST.has(value):
			spent += int(POINT_BUY_COST[value])
	return spent


func background_bonus(ability: StringName) -> int:
	var index := background_targets.find(ability)
	if index == -1 or index >= background_spread.size():
		return 0
	return int(background_spread[index])


func ability_score(ability: StringName) -> int:
	return mini(20, int(base_scores.get(ability, 10)) + background_bonus(ability) + asi_bonus(ability))


## Bonus from every Ability Score Improvement already reached. One pick is +2,
## two picks are +1 each.
func asi_bonus(ability: StringName) -> int:
	var total := 0
	for asi_level in Progression.asi_levels_through(level):
		var picks: Array[StringName] = _asi_picks(asi_level)
		if picks.size() == 1 and picks[0] == ability:
			total += 2
		elif picks.size() == 2 and ability in picks:
			total += 1
	return total


func _asi_picks(asi_level: int) -> Array[StringName]:
	var out: Array[StringName] = []
	for value in asi_choices.get(asi_level, []):
		out.append(StringName(value))
	return out


func ability_scores() -> Dictionary:
	var scores := {}
	for ability in ABILITIES:
		scores[ability] = ability_score(ability)
	return scores


func ability_modifier(ability: StringName) -> int:
	return floori(float(ability_score(ability) - 10) / 2.0)


func ability_modifier_total() -> int:
	var total := 0
	for ability in ABILITIES:
		total += ability_modifier(ability)
	return total


# --- derived numbers --------------------------------------------------------

func proficiency_bonus() -> int:
	return 2 + (level - 1) / 4


## Extra hit points per level from species traits and the origin feat.
func bonus_hp_per_level() -> int:
	var bonus := 0
	if species != null and has_species_trait(&"dwarven_toughness"):
		bonus += 1
	if background != null and background.origin_feat != null and background.origin_feat.id == &"tough":
		bonus += 2
	return bonus


func max_hit_points() -> int:
	if class_data == null:
		return 0
	var constitution := ability_modifier(&"constitution")
	var hp := class_data.hit_points_at_level_1(constitution)
	# Fixed hit points per level after the first: die average rounded up + CON.
	hp += (level - 1) * (Progression.hit_points_per_level(class_data.hit_die) + constitution)
	hp += bonus_hp_per_level() * level
	return maxi(1, hp)


func initiative() -> int:
	var value := ability_modifier(&"dexterity")
	if background != null and background.origin_feat != null and background.origin_feat.id == &"alert":
		value += proficiency_bonus()
	return value


## All save proficiencies, class plus any granted by chosen options.
func saving_throw_proficiencies() -> Array[StringName]:
	var out: Array[StringName] = []
	if class_data != null:
		out.append_array(class_data.saving_throws)
	return out


## Armour categories from the class plus every option the player picked.
func armor_training() -> Array[StringName]:
	var out: Array[StringName] = []
	if class_data != null:
		_add_unique(out, class_data.armor_training)
	for group in _choice_groups():
		for option in _selected_option_data(group):
			_add_unique(out, option.granted_armor_training)
	return out


## Weapon categories from the class plus every option the player picked.
func weapon_training() -> Array[StringName]:
	var out: Array[StringName] = []
	if class_data != null:
		_add_unique(out, class_data.weapon_training)
	for group in _choice_groups():
		for option in _selected_option_data(group):
			_add_unique(out, option.granted_weapon_training)
	return out


func _choice_groups() -> Array[ChoiceGroupData]:
	var out: Array[ChoiceGroupData] = []
	if class_data != null:
		out.append_array(class_data.choices)
	if subclass != null:
		out.append_array(subclass.choices)
	if species != null:
		out.append_array(species.choices)
	return out


func _selected_option_data(group: ChoiceGroupData) -> Array[ChoiceOptionData]:
	var out: Array[ChoiceOptionData] = []
	for picked_id in selected_options(group.id):
		for option in group.options:
			if option.id == picked_id and option not in out:
				out.append(option)
	return out


func _add_unique(target: Array[StringName], values: Array) -> void:
	for value in values:
		var category := StringName(value)
		if category not in target:
			target.append(category)


func saving_throw_bonus(ability: StringName) -> int:
	var value := ability_modifier(ability)
	if ability in saving_throw_proficiencies():
		value += proficiency_bonus()
	return value


## Background skills plus the class picks, without duplicates.
func skill_proficiencies() -> Array[StringName]:
	var out: Array[StringName] = []
	if background != null:
		for skill in background.skill_proficiencies:
			if skill not in out:
				out.append(skill)
	for skill in skill_choices:
		if skill not in out:
			out.append(skill)
	return out


func skill_bonus(skill: StringName) -> int:
	var ability: StringName = SKILL_ABILITY.get(skill, &"")
	var value := ability_modifier(ability) if ability != &"" else 0
	if skill in skill_proficiencies():
		value += proficiency_bonus()
	return value


func passive_perception() -> int:
	return 10 + skill_bonus(&"perception")


func spellcasting_ability() -> StringName:
	if class_data == null or class_data.spellcasting == null:
		return &""
	return class_data.spellcasting.ability


func spell_save_dc() -> int:
	var ability := spellcasting_ability()
	if ability == &"":
		return 0
	return 8 + proficiency_bonus() + ability_modifier(ability)


func spell_attack_bonus() -> int:
	var ability := spellcasting_ability()
	if ability == &"":
		return 0
	return proficiency_bonus() + ability_modifier(ability)


## Which progression table this class follows.
func caster_kind() -> CasterKind:
	if class_data == null or class_data.spellcasting == null:
		return CasterKind.NONE
	if class_data.spellcasting.recovery == SpellcastingData.Recovery.SHORT_REST:
		return CasterKind.PACT
	if class_data.id == &"ranger" or class_data.id == &"paladin":
		return CasterKind.HALF
	return CasterKind.FULL


## Spell slots per spell level 1..n. Empty for non-casters.
func spell_slots() -> Array[int]:
	match caster_kind():
		CasterKind.FULL:
			return Progression.full_slots(level)
		CasterKind.HALF:
			return Progression.half_slots(level)
		_:
			return []


## [slot count, slot level] for Pact Magic, empty for everyone else.
func pact_slots() -> Array[int]:
	if caster_kind() != CasterKind.PACT:
		return []
	return Progression.pact_slots(level)


## Human-readable slot strip for the sheet, e.g. "1 ур.: 4 · 2 ур.: 2".
func spell_slots_text() -> String:
	if caster_kind() == CasterKind.PACT:
		var pact := pact_slots()
		if pact.size() < 2:
			return ""
		return "%d ячейк(и) %d уровня (договор)" % [pact[0], pact[1]]

	var slots := spell_slots()
	var parts := PackedStringArray()
	for index in slots.size():
		parts.append("%d ур.: %d" % [index + 1, slots[index]])
	return " · ".join(parts)


func armor_class() -> int:
	var dex := ability_modifier(&"dexterity")
	var shield := equipment_mode == EquipmentMode.PACK and has_equipment(&"shield")
	var armor := _equipped_armor_id()

	if armor != &"":
		var row: Array = ARMOR_TABLE[armor]
		var base: int = row[0]
		var dex_cap: int = row[1]
		var dex_part := dex if dex_cap < 0 else mini(dex, dex_cap)
		return base + dex_part + (SHIELD_BONUS if shield else 0)

	var base := 10 + dex
	if class_data != null and class_data.unarmored_defense_ability != &"":
		if class_data.unarmored_defense_allows_shield or not shield:
			base += ability_modifier(class_data.unarmored_defense_ability)
	if shield:
		base += SHIELD_BONUS
	return base


# --- equipment --------------------------------------------------------------

func starting_equipment() -> Array[EquipmentEntry]:
	var out: Array[EquipmentEntry] = []
	if equipment_mode == EquipmentMode.GOLD:
		return out
	if class_data != null:
		out.append_array(class_data.equipment_pack)
	if background != null:
		out.append_array(background.equipment_pack)
	return out


func starting_gold() -> int:
	if equipment_mode != EquipmentMode.GOLD:
		return 0
	var gold := 0
	if class_data != null:
		gold += class_data.alternative_gold
	if background != null:
		gold += background.alternative_gold
	return gold


func has_equipment(item_id: StringName) -> bool:
	for entry in starting_equipment():
		if entry.item_id == item_id:
			return true
	return false


func _equipped_armor_id() -> StringName:
	for entry in starting_equipment():
		if ARMOR_TABLE.has(entry.item_id):
			return entry.item_id
	return &""


# --- progression ------------------------------------------------------------

func can_level_up() -> bool:
	return class_data != null and Progression.can_level_up(level)


## Milestone level-up: raises the level and records the matching XP threshold.
## Decisions unlocked by the level (subclass, ASI) are validated afterwards.
func level_up() -> bool:
	if not can_level_up():
		return false
	level = Progression.clamp_level(level + 1)
	xp = maxi(xp, Progression.xp_for_level(level))
	return true


## Awards experience and raises the level for every threshold crossed.
## Returns how many levels were gained.
func add_xp(amount: int) -> int:
	if amount <= 0:
		return 0
	xp += amount
	var target := mini(Progression.MAX_LEVEL, Progression.level_for_xp(xp))
	var gained := maxi(0, target - level)
	if gained > 0:
		level = target
	return gained


func xp_to_next() -> int:
	return Progression.xp_to_next(level, xp)


## True when the level grants an ASI that has not been allocated yet.
func has_pending_asi() -> bool:
	return not pending_asi_levels().is_empty()


func pending_asi_levels() -> Array[int]:
	var out: Array[int] = []
	for asi_level in Progression.asi_levels_through(level):
		if _validate_asi_level(asi_level).is_empty():
			continue
		out.append(asi_level)
	return out


## One ability id means +2; two distinct ids mean +1/+1.
func set_asi_choice(asi_level: int, picks: Array) -> void:
	var cleaned: Array[StringName] = []
	for value in picks:
		var ability := StringName(value)
		if ability in ABILITIES and ability not in cleaned:
			cleaned.append(ability)
	asi_choices[asi_level] = cleaned


## 0 = one ability +2, 1 = two abilities +1/+1. Drops picks beyond the mode.
func set_asi_mode(asi_level: int, mode: int) -> void:
	asi_modes[asi_level] = clampi(mode, 0, 1)
	var picks := _asi_picks(asi_level)
	var limit := 1 if mode == 0 else 2
	var trimmed: Array[StringName] = []
	for index in mini(limit, picks.size()):
		trimmed.append(picks[index])
	asi_choices[asi_level] = trimmed


func asi_mode(asi_level: int) -> int:
	return int(asi_modes.get(asi_level, 0))


func asi_picks(asi_level: int) -> Array[StringName]:
	return _asi_picks(asi_level)


func subclass_required() -> bool:
	return class_data != null and level >= class_data.subclass_unlock_level


func available_subclasses() -> Array[SubclassData]:
	if class_data == null:
		return []
	return SubclassRepository.for_class(class_data.id)


## Picks a subclass, clearing sub-choices that belonged to the previous one.
func select_subclass(subclass_id: StringName) -> void:
	if class_data == null:
		return
	var picked := SubclassRepository.find(subclass_id)
	if picked == null or picked.class_id != class_data.id:
		return
	if picked == subclass:
		return
	if subclass != null:
		for group in subclass.choices:
			option_choices.erase(group.id)
	subclass = picked


## Class features up to the current level, plus the chosen subclass features.
func features_through_level() -> Array[FeatureData]:
	var out: Array[FeatureData] = []
	if class_data != null:
		out.append_array(class_data.features_through_level(level))
	if subclass != null and level >= subclass.unlock_level:
		out.append_array(subclass.features)
	return out


## Choices currently open from the selected subclass (level 3+).
func subclass_choices() -> Array[ChoiceGroupData]:
	var out: Array[ChoiceGroupData] = []
	if subclass != null and level >= subclass.unlock_level:
		out.append_array(subclass.choices)
	return out


# --- choices ----------------------------------------------------------------

func select_option(choice_id: StringName, option_id: StringName) -> void:
	var picks: Array[StringName] = [option_id]
	option_choices[choice_id] = picks


func selected_options(choice_id: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	for value in option_choices.get(choice_id, []):
		out.append(StringName(value))
	return out


func has_species_trait(trait_id: StringName) -> bool:
	if species == null:
		return false
	for entry in species.traits:
		if entry.id == trait_id:
			return true
	for choice in species.choices:
		for option_id in selected_options(choice.id):
			for option in choice.options:
				if option.id != option_id:
					continue
				for entry in option.features:
					if entry.id == trait_id:
						return true
	return false


## Size after resolving the species options. Empty when a choice is still open.
func resolved_size() -> StringName:
	if chosen_size != &"":
		return chosen_size
	if species != null and species.size_options.size() == 1:
		return species.size_options[0]
	return &""


# --- validation -------------------------------------------------------------

## Empty array means the draft is complete and consistent.
func validate() -> PackedStringArray:
	var problems := PackedStringArray()

	if class_data == null:
		problems.append("класс не выбран")
	if background == null:
		problems.append("предыстория не выбрана")
	if species == null:
		problems.append("вид не выбран")
	if character_name.strip_edges().is_empty():
		problems.append("имя не задано")
	if level < 1 or level > Progression.MAX_LEVEL:
		problems.append("уровень вне 1..%d" % Progression.MAX_LEVEL)

	for ability in ABILITIES:
		var value := int(base_scores.get(ability, 0))
		if value < 3 or value > 18:
			problems.append("базовое значение %s вне 3..18" % ability)

	if background != null:
		problems.append_array(_validate_background())
	if class_data != null:
		problems.append_array(_validate_class())
		problems.append_array(_validate_progression())
	if species != null:
		problems.append_array(_validate_species())

	return problems


func _validate_background() -> PackedStringArray:
	var problems := PackedStringArray()
	if background_targets.size() != 3:
		problems.append("предыстория: нужно ровно 3 характеристики")
		return problems

	var seen: Array[StringName] = []
	for ability in background_targets:
		if ability in seen:
			problems.append("предыстория: %s выбрана дважды" % ability)
		seen.append(ability)
		if ability not in background.ability_options:
			problems.append("предыстория: %s недоступна" % ability)

	var spread := Array(background_spread)
	if spread != SPREAD_PRIMARY and spread != SPREAD_BALANCED:
		problems.append("предыстория: бонусы должны быть +2/+1 или +1/+1/+1")
	return problems


func _validate_class() -> PackedStringArray:
	var problems := PackedStringArray()

	var unlock := class_data.subclass_unlock_level
	if level >= unlock:
		if subclass == null:
			problems.append("класс: выберите подкласс")
		elif subclass.class_id != class_data.id:
			problems.append("класс: подкласс принадлежит другому классу")
	elif subclass != null:
		problems.append("класс: подкласс откроется на %d уровне" % unlock)

	if skill_choices.size() != class_data.skill_choice_count:
		problems.append("класс: нужно %d навыков, выбрано %d" % [class_data.skill_choice_count, skill_choices.size()])
	else:
		for skill in skill_choices:
			if not class_data.skill_pool_is_any and skill not in class_data.skill_pool:
				problems.append("класс: навык %s недоступен" % skill)

	problems.append_array(_validate_choices(class_data.choices, "класс"))
	if subclass != null:
		problems.append_array(_validate_choices(subclass.choices, "подкласс"))
	return problems


## Ability Score Improvements: every reached ASI level must be allocated, and
## no score may exceed 20.
func _validate_progression() -> PackedStringArray:
	var problems := PackedStringArray()
	for asi_level in Progression.asi_levels_through(level):
		for problem in _validate_asi_level(asi_level):
			problems.append("уровень %d: %s" % [asi_level, problem])

	for key in asi_choices.keys():
		if int(key) > level:
			problems.append("характеристики: улучшение уровня %s ещё недоступно" % key)
	return problems


func _validate_asi_level(asi_level: int) -> PackedStringArray:
	var problems := PackedStringArray()
	var picks := _asi_picks(asi_level)
	var expected := 1 if asi_mode(asi_level) == 0 else 2
	if picks.is_empty():
		problems.append("распределите улучшение характеристик")
		return problems
	if picks.size() != expected:
		problems.append("нужно %d характеристик(и) для выбранного варианта" % expected)
		return problems
	if picks.size() == 2 and picks[0] == picks[1]:
		problems.append("две разные характеристики для +1/+1")
		return problems

	for ability in picks:
		if ability not in ABILITIES:
			problems.append("неизвестная характеристика %s" % ability)
			continue
		var raw := int(base_scores.get(ability, 10)) + background_bonus(ability) + asi_bonus(ability)
		if raw > 20:
			problems.append("%s выше 20" % String(ABILITY_LABELS_RU[ability]))
	return problems


func _validate_species() -> PackedStringArray:
	var problems := PackedStringArray()

	if species.has_size_choice() and chosen_size == &"":
		problems.append("вид: выберите размер")
	elif chosen_size != &"" and chosen_size not in species.size_options:
		problems.append("вид: размер %s недоступен" % chosen_size)

	if chosen_languages.size() != species.language_choices:
		problems.append("вид: нужно %d языков, выбрано %d" % [species.language_choices, chosen_languages.size()])
	else:
		var seen_languages: Array[StringName] = []
		for language in chosen_languages:
			if language == &"":
				problems.append("вид: выберите язык")
				break
			if language not in LANGUAGES:
				problems.append("вид: неизвестный язык %s" % language)
			elif language in seen_languages:
				problems.append("вид: язык %s выбран дважды" % language)
			seen_languages.append(language)

	problems.append_array(_validate_choices(species.choices, "вид"))
	return problems


func _validate_choices(groups: Array, owner: String) -> PackedStringArray:
	var problems := PackedStringArray()
	for group in groups:
		var picks := selected_options(group.id)
		if picks.size() != group.count:
			problems.append("%s: выбор «%s» не сделан" % [owner, group.prompt])
			continue
		for pick in picks:
			var found := false
			for option in group.options:
				if option.id == pick:
					found = true
					break
			if not found:
				problems.append("%s: вариант %s не существует" % [owner, pick])
	return problems


# --- copy ------------------------------------------------------------------

## Copies every selection from another draft. Used so the creation screen can
## edit a throwaway copy and only commit on "Готово".
func copy_from(other: CharacterDraft) -> void:
	character_name = other.character_name
	level = other.level
	xp = other.xp
	class_data = other.class_data
	subclass = other.subclass
	background = other.background
	species = other.species
	base_scores = other.base_scores.duplicate(true)
	background_targets = other.background_targets.duplicate()
	background_spread = other.background_spread.duplicate()
	skill_choices = other.skill_choices.duplicate()
	option_choices = other.option_choices.duplicate(true)
	asi_choices = other.asi_choices.duplicate(true)
	asi_modes = other.asi_modes.duplicate(true)
	chosen_size = other.chosen_size
	chosen_languages = other.chosen_languages.duplicate()
	equipment_mode = other.equipment_mode


# --- payload ----------------------------------------------------------------

## Plain-data snapshot for RPCs and save files. Primitives, Arrays and
## Dictionaries only, so it survives serialisation.
##
## The top-level fields describe the *build*: they are enough for the server to
## rebuild the draft with from_payload() and re-run validate(). `derived` is a
## convenience cache for the UI; the server recomputes it and never trusts the
## numbers a client sends.
func to_payload() -> Dictionary:
	var scores := {}
	for ability in ABILITIES:
		scores[String(ability)] = int(base_scores.get(ability, 10))
	return {
		"name": character_name.strip_edges(),
		"level": level,
		"xp": xp,
		"class": String(class_data.id) if class_data != null else "",
		"class_name": class_data.display_name if class_data != null else "",
		"subclass": String(subclass.id) if subclass != null else "",
		"subclass_name": subclass.display_name if subclass != null else "",
		"species": String(species.id) if species != null else "",
		"species_name": species.display_name if species != null else "",
		"background": String(background.id) if background != null else "",
		"background_name": background.display_name if background != null else "",
		"base_scores": scores,
		"background_targets": _string_array(background_targets),
		"background_spread": Array(background_spread),
		"skill_choices": _string_array(skill_choices),
		"option_choices": _option_choices_payload(),
		"asi_choices": _asi_choices_payload(),
		"asi_modes": asi_modes.duplicate(true),
		"size": String(chosen_size),
		"languages": _string_array(chosen_languages),
		"equipment_mode": int(equipment_mode),
		"derived": _derived_payload(),
	}


## Rebuilds a draft from to_payload() data. Unknown ids and out-of-range
## numbers are clamped or left null; call validate() to decide whether the
## resulting build is acceptable. Used by the server before trusting a client.
static func from_payload(data: Dictionary) -> CharacterDraft:
	if data.is_empty():
		return null

	var draft := CharacterDraft.new()
	draft.character_name = str(data.get("name", "")).strip_edges().left(40)
	draft.level = Progression.clamp_level(int(data.get("level", 1)))
	draft.xp = maxi(int(data.get("xp", 0)), Progression.xp_for_level(draft.level))
	draft.class_data = ClassRepository.find(StringName(str(data.get("class", ""))))
	draft.background = BackgroundRepository.find(StringName(str(data.get("background", ""))))
	draft.species = SpeciesRepository.find(StringName(str(data.get("species", ""))))

	var subclass_id := StringName(str(data.get("subclass", "")))
	if subclass_id != &"":
		var picked := SubclassRepository.find(subclass_id)
		if picked != null and draft.class_data != null and picked.class_id == draft.class_data.id:
			draft.subclass = picked

	var scores: Variant = data.get("base_scores", {})
	if scores is Dictionary:
		for ability in ABILITIES:
			draft.base_scores[ability] = clampi(int(scores.get(String(ability), 10)), 3, 18)

	draft.background_targets = _read_string_names(data.get("background_targets", []))
	var spread: Variant = data.get("background_spread", [])
	if spread is Array and spread.size() == 3:
		var values: Array = []
		for value in spread:
			values.append(int(value))
		draft.background_spread = values

	draft.skill_choices = _read_string_names(data.get("skill_choices", []))
	draft.chosen_languages = _read_string_names(data.get("languages", []))
	draft.chosen_size = StringName(str(data.get("size", "")))
	draft.equipment_mode = clampi(int(data.get("equipment_mode", 0)), 0, 1)

	var options: Variant = data.get("option_choices", {})
	if options is Dictionary:
		for key in options:
			draft.option_choices[StringName(str(key))] = _read_string_names(options[key])

	var asi: Variant = data.get("asi_choices", {})
	if asi is Dictionary:
		for key in asi:
			draft.asi_choices[int(key)] = _read_string_names(asi[key])

	var modes: Variant = data.get("asi_modes", {})
	if modes is Dictionary:
		for key in modes:
			draft.asi_modes[int(key)] = int(modes[key])

	return draft


static func _string_array(values: Array) -> Array:
	var out: Array = []
	for value in values:
		out.append(String(value))
	return out


static func _read_string_names(value: Variant) -> Array[StringName]:
	var out: Array[StringName] = []
	if value is Array:
		for entry in value:
			out.append(StringName(str(entry)))
	return out


func _option_choices_payload() -> Dictionary:
	var out := {}
	for key in option_choices:
		out[String(key)] = _string_array(option_choices[key])
	return out


func _asi_choices_payload() -> Dictionary:
	var out := {}
	for key in asi_choices:
		out[int(key)] = _string_array(asi_choices[key])
	return out


func _derived_payload() -> Dictionary:
	var scores := {}
	var saves := {}
	var skills := {}
	for ability in ABILITIES:
		scores[String(ability)] = ability_score(ability)
		saves[String(ability)] = saving_throw_bonus(ability)
	for skill in skill_proficiencies():
		skills[String(skill)] = skill_bonus(skill)

	var equipment: Array = []
	for entry in starting_equipment():
		equipment.append({
			"item_id": String(entry.item_id),
			"display_name": entry.display_name,
			"quantity": entry.quantity,
		})

	return {
		"scores": scores,
		"saves": saves,
		"skills": skills,
		"hp": max_hit_points(),
		"ac": armor_class(),
		"proficiency": proficiency_bonus(),
		"initiative": initiative(),
		"passive_perception": passive_perception(),
		"speed_ft": species.speed if species != null else 30,
		"size": String(resolved_size()),
		"armor_training": _string_array(armor_training()),
		"weapon_training": _string_array(weapon_training()),
		"equipment": equipment,
		"gold": starting_gold(),
		"spell_slots": spell_slots_text(),
	}


# --- debug ------------------------------------------------------------------

func summary() -> String:
	var lines := PackedStringArray()
	lines.append("Имя: %s" % character_name)
	if class_data != null:
		lines.append("Класс: %s (d%d), уровень %d" % [class_data.display_name, class_data.hit_die, level])
	if subclass != null:
		lines.append("Подкласс: %s" % subclass.display_name)
	if background != null:
		lines.append("Предыстория: %s" % background.display_name)
	if species != null:
		lines.append("Вид: %s, размер %s, скорость %d" % [species.display_name, resolved_size(), species.speed])

	for ability in ABILITIES:
		lines.append("  %-14s %2d (%+d)" % [ABILITY_LABELS_RU[ability], ability_score(ability), ability_modifier(ability)])

	lines.append("HP: %d  КД: %d  Инициатива: %+d  Пасс. Восприятие: %d" % [
		max_hit_points(), armor_class(), initiative(), passive_perception(),
	])
	if spellcasting_ability() != &"":
		lines.append("Заклинания: КС %d, атака %+d" % [spell_save_dc(), spell_attack_bonus()])
		if not spell_slots_text().is_empty():
			lines.append("Ячейки: %s" % spell_slots_text())
	lines.append("Навыки: %s" % ", ".join(skill_proficiencies()))
	lines.append("Золото: %d" % starting_gold())

	var problems := validate()
	if problems.is_empty():
		lines.append("Статус: готов")
	else:
		lines.append("Статус: %d проблем(ы)" % problems.size())
		for problem in problems:
			lines.append("  ! %s" % problem)
	return "\n".join(lines)
