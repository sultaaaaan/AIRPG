class_name ChoiceOptionData
extends Resource
## One selectable option inside a ClassChoiceData.
##
## Example: "Protector" for the Cleric's Divine Order, or "Archery" for a
## Fighter's Fighting Style. Options can both grant proficiencies and add
## features, which covers every level-1 choice in the 2024 PHB.

@export var id: StringName = &""
@export var display_name: String = ""
@export_multiline var description: String = ""

@export_group("Grants")
## Armour categories added by this option, e.g. &"heavy".
@export var granted_armor_training: Array[StringName] = []
## Weapon categories added by this option, e.g. &"martial".
@export var granted_weapon_training: Array[StringName] = []
@export var features: Array[FeatureData] = []
