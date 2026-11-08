class_name SubclassData
extends Resource
## A class subclass. One .tres per subclass under res://data/subclasses/.
##
## In the 2024 rules every class picks its subclass at level 3, so a level-1
## character has `subclass == null` and that is valid. Level-3 features are
## stored here; higher-level ones will be added when levelling exists.

@export var id: StringName = &""
## The ClassData id this subclass belongs to, e.g. &"fighter".
@export var class_id: StringName = &""
@export var display_name: String = ""
@export_multiline var description: String = ""
@export_range(1, 20, 1) var unlock_level: int = 3

## Features gained when the subclass is chosen (level 3).
@export var features: Array[FeatureData] = []
## Sub-choices inside the subclass, e.g. the Wildheart animal aspect.
@export var choices: Array[ChoiceGroupData] = []


func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	if id == &"":
		problems.append("id is empty")
	if class_id == &"":
		problems.append("class_id is empty")
	if display_name.is_empty():
		problems.append("display_name is empty")
	if features.is_empty():
		problems.append("no features")
	if unlock_level < 1 or unlock_level > 20:
		problems.append("unlock_level out of range")
	return problems
