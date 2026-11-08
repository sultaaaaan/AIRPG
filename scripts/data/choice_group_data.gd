class_name ChoiceGroupData
extends Resource
## A mandatory pick the player must make.
##
## Used by both classes (Fighting Style, Divine Order, Primal Order) and
## species (Elf lineage, Tiefling legacy, Goliath ancestry). Keeping one type
## means the creation UI only needs one choice widget.

@export var id: StringName = &""
## Localised question shown to the player, e.g. "Выберите боевой стиль".
@export var prompt: String = ""
## How many options the player picks. All PHB 2024 choices use 1.
@export_range(1, 10, 1) var count: int = 1
@export var options: Array[ChoiceOptionData] = []
