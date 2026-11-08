class_name BackgroundData
extends Resource
## A D&D 2024 background — the source of ability score increases and the
## origin feat. One .tres per background under res://data/backgrounds/.
##
## In the 2024 rules backgrounds carry the ability bonuses that species used
## to carry in 2014, so this resource is mandatory for character creation.

@export var id: StringName = &""
@export var display_name: String = ""
@export_multiline var description: String = ""

@export_group("Ability Scores")
## Exactly three abilities the player may raise. The player assigns either
## +2/+1 or +1/+1/+1 across them.
@export var ability_options: Array[StringName] = []

@export_group("Proficiencies")
@export var skill_proficiencies: Array[StringName] = []
@export var tool_proficiency: StringName = &""

@export_group("Origin Feat")
@export var origin_feat: FeatureData = null

@export_group("Starting Equipment")
@export var equipment_pack: Array[EquipmentEntry] = []
## Option B: take this much gold instead of the pack.
@export_range(0, 999, 1) var alternative_gold: int = 50


func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	if id == &"":
		problems.append("id is empty")
	if display_name.is_empty():
		problems.append("display_name is empty")
	if ability_options.size() != 3:
		problems.append("expected 3 ability options, got %d" % ability_options.size())
	if skill_proficiencies.size() != 2:
		problems.append("expected 2 skill proficiencies, got %d" % skill_proficiencies.size())
	if origin_feat == null:
		problems.append("no origin feat")
	if equipment_pack.is_empty() and alternative_gold <= 0:
		problems.append("no starting equipment and no gold")
	return problems
