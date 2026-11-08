class_name EquipmentEntry
extends Resource
## One stack of starting gear. Item definitions do not exist yet, so the
## display name is stored alongside the id; swap it for an ItemData reference
## once the item catalogue lands.

@export var item_id: StringName = &""
@export var display_name: String = ""
@export_range(1, 999, 1) var quantity: int = 1
