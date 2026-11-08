class_name SpeciesData
extends Resource
## A D&D 2024 species. One .tres per species under res://data/species/.
##
## In the 2024 rules a species grants NO ability score increases — those live
## on the background. A species grants size, speed, senses, languages and
## traits, plus optional lineage/ancestry sub-choices.

@export var id: StringName = &""
@export var display_name: String = ""
@export_multiline var description: String = ""

@export_group("Body")
## One or more allowed sizes: &"small", &"medium". Human and Tiefling offer both.
@export var size_options: Array[StringName] = [&"medium"]
@export_range(20, 50, 5) var speed: int = 30
## Almost always &"humanoid".
@export var creature_type: StringName = &"humanoid"
## 0 means no darkvision.
@export_range(0, 120, 30) var darkvision_range: int = 0

@export_group("Languages")
## Languages granted automatically, usually including Common.
@export var languages: Array[StringName] = [&"common"]
## Extra languages the player picks freely (Human: 1).
@export_range(0, 3, 1) var language_choices: int = 0

@export_group("Traits")
@export var traits: Array[FeatureData] = []
## Lineage / legacy / ancestry picks (Elf, Gnome, Tiefling, Goliath).
@export var choices: Array[ChoiceGroupData] = []


## True when the player must choose between two sizes.
func has_size_choice() -> bool:
	return size_options.size() > 1


func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	if id == &"":
		problems.append("id is empty")
	if display_name.is_empty():
		problems.append("display_name is empty")
	if size_options.is_empty():
		problems.append("no size option")
	if speed <= 0:
		problems.append("speed must be positive")
	if languages.is_empty():
		problems.append("no languages")
	if traits.is_empty():
		problems.append("no traits")
	return problems
