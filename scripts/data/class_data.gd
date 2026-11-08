class_name ClassData
extends Resource
## Level-1 definition of a D&D 2024 class.
##
## One .tres per class under res://data/classes/. The character builder reads
## these to drive character creation; nothing here mutates at runtime, so the
## resources are safe to share.
##
## Derived values (HP, AC, save DC) are *not* stored: they are computed from
## ClassData + ability scores + background by the builder.

## Stable machine id, e.g. &"fighter". Never localise this.
@export var id: StringName = &""
## Localised name shown in the UI.
@export var display_name: String = ""
## Localised one-line fantasy of the class.
@export_multiline var description: String = ""

@export_group("Core")
## Hit die size: 6, 8, 10 or 12.
@export_enum("d6:6", "d8:8", "d10:10", "d12:12") var hit_die: int = 8
## Primary ability score(s). Two entries means "Strength and Charisma".
@export var primary_abilities: Array[StringName] = []
## Saving throw proficiencies (always two).
@export var saving_throws: Array[StringName] = []
## How many weapons the class bonds with via Weapon Mastery. 0 = no feature.
@export_range(0, 6, 1) var weapon_mastery_count: int = 0
## Ability added to AC while unarmoured, e.g. &"constitution" for Barbarian.
## Empty means the class has no Unarmoured Defense.
@export var unarmored_defense_ability: StringName = &""
## Barbarian may hold a shield and keep Unarmoured Defense; Monk may not.
@export var unarmored_defense_allows_shield: bool = true

@export_group("Proficiencies")
## Armour categories: &"light", &"medium", &"heavy", &"shields".
@export var armor_training: Array[StringName] = []
## Weapon categories: &"simple", &"martial", &"martial_light".
@export var weapon_training: Array[StringName] = []
@export var tool_proficiencies: Array[StringName] = []

@export_group("Skills")
## How many skills the player picks.
@export_range(1, 6, 1) var skill_choice_count: int = 2
## Allowed skill ids. Ignored when skill_pool_is_any is true.
@export var skill_pool: Array[StringName] = []
## Bard picks any three skills, so the pool is not enumerated.
@export var skill_pool_is_any: bool = false

@export_group("Level 1")
@export var features: Array[FeatureData] = []
## Mandatory sub-choices (Fighting Style, Divine Order, ...).
@export var choices: Array[ChoiceGroupData] = []
## Null when the class has no spellcasting at level 1 (Paladin, Ranger here
## still describe their level-1 state: Paladin has none, Ranger has Druidcraft).
@export var spellcasting: SpellcastingData = null

@export_group("Starting Equipment")
## Option A: the ready-made pack.
@export var equipment_pack: Array[EquipmentEntry] = []
## Option B: take this much gold instead of the pack.
@export_range(0, 999, 1) var alternative_gold: int = 0

@export_group("Progression")
## Subclass level. Unified at 3 in the 2024 rules.
@export_range(1, 20, 1) var subclass_unlock_level: int = 3


## Features gained up to (and including) `max_level`, in author order.
func features_through_level(max_level: int) -> Array[FeatureData]:
	var out: Array[FeatureData] = []
	for feature in features:
		if feature != null and feature.level <= max_level:
			out.append(feature)
	return out


## Features granted exactly at `level`.
func features_at_level(level: int) -> Array[FeatureData]:
	var out: Array[FeatureData] = []
	for feature in features:
		if feature != null and feature.level == level:
			out.append(feature)
	return out

const VALID_HIT_DICE: Array[int] = [6, 8, 10, 12]


## Level-1 hit points before any Tough-style bonuses.
func hit_points_at_level_1(constitution_modifier: int) -> int:
	return maxi(1, hit_die + constitution_modifier)


## True when the class grants spell slots at level 1. Paladin returns false.
func casts_spells_at_level_1() -> bool:
	return spellcasting != null and spellcasting.level_1_slots > 0


## Localised names of the primary abilities, e.g. ["Сила", "Харизма"].
func primary_ability_names() -> PackedStringArray:
	var names := PackedStringArray()
	for ability in primary_abilities:
		names.append(String(ability))
	return names


## Cheap sanity check used by the validator and by tests.
## Returns an empty array when the resource is consistent.
func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	if id == &"":
		problems.append("id is empty")
	if display_name.is_empty():
		problems.append("display_name is empty")
	if hit_die not in VALID_HIT_DICE:
		problems.append("hit_die %d is not 6/8/10/12" % hit_die)
	if saving_throws.size() != 2:
		problems.append("expected 2 saving throws, got %d" % saving_throws.size())
	if primary_abilities.is_empty():
		problems.append("no primary abilities")
	if not skill_pool_is_any and skill_pool.size() < skill_choice_count:
		problems.append("skill pool smaller than the number of picks")
	if weapon_mastery_count > 0 and not _has_feature(&"weapon_mastery"):
		problems.append("weapon_mastery_count set but no weapon_mastery feature")
	if equipment_pack.is_empty() and alternative_gold <= 0:
		problems.append("no starting equipment and no gold")
	return problems


func _has_feature(feature_id: StringName) -> bool:
	for feature in features:
		if feature != null and feature.id == feature_id:
			return true
	for choice in choices:
		for option in choice.options:
			for feature in option.features:
				if feature != null and feature.id == feature_id:
					return true
	return false
