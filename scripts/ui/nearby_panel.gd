class_name NearbyPanel
extends PanelContainer
## Compact left-side list of ground items in range.
##
## Appears automatically while the player is near pickups; each row has a
## "Взять" button that sends the same server request as the full inventory
## screen. Hidden while the full inventory/chest screen is open.

@onready var title: Label = $Content/Title
@onready var list: VBoxContainer = $Content/List

var _ids: Array = []


func _ready() -> void:
	visible = false
	reset_size()


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

	visible = true
	var shown := 0
	for pickup in pickups:
		if not is_instance_valid(pickup) or not pickup.is_available():
			continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)

		var name_label := Label.new()
		name_label.text = str(pickup.display_name)
		name_label.clip_text = true
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.add_theme_font_size_override("font_size", 12)
		if int(pickup.quantity) > 1:
			name_label.text += " ×%d" % int(pickup.quantity)
		row.add_child(name_label)

		var button := Button.new()
		button.text = "Взять"
		button.custom_minimum_size = Vector2(70, 0)
		button.add_theme_font_size_override("font_size", 12)
		button.pressed.connect(_on_take_pressed.bind(pickup))
		row.add_child(button)

		list.add_child(row)
		shown += 1

	if shown == 0:
		visible = false
		return

	title.text = "РЯДОМ · %d" % shown
	reset_size()
	call_deferred("reset_size")


func _on_take_pressed(pickup: ItemPickup) -> void:
	pickup.request()
