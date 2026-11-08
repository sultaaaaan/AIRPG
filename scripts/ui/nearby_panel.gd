class_name NearbyPanel
extends PanelContainer
## Compact left-side list of ground items in range.
##
## Appears automatically while the player is near pickups; each row has a
## "Взять" button that sends the same server request as the full inventory
## screen. Hidden while the full inventory/chest screen is open.

@onready var list: VBoxContainer = $Content/List

var _ids: Array = []


func _ready() -> void:
	visible = false


## Called by the game every frame with the available pickups in range.
func set_pickups(pickups: Array) -> void:
	var ids: Array = []
	for pickup in pickups:
		ids.append(pickup.get_instance_id())
	if ids == _ids:
		return
	_ids = ids
	_rebuild(pickups)


func _rebuild(pickups: Array) -> void:
	for child in list.get_children():
		list.remove_child(child)
		child.queue_free()

	if pickups.is_empty():
		visible = false
		return
	visible = true

	for pickup in pickups:
		if not is_instance_valid(pickup) or not pickup.is_available():
			continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)

		var name_label := Label.new()
		name_label.text = str(pickup.display_name)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if int(pickup.quantity) > 1:
			name_label.text += " ×%d" % int(pickup.quantity)
		row.add_child(name_label)

		var button := Button.new()
		button.text = "Взять"
		button.custom_minimum_size = Vector2(82, 0)
		button.add_theme_font_size_override("font_size", 13)
		button.pressed.connect(_on_take_pressed.bind(pickup))
		row.add_child(button)

		list.add_child(row)


func _on_take_pressed(pickup: ItemPickup) -> void:
	pickup.request()
