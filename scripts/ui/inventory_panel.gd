class_name InventoryPanel
extends CanvasLayer
## Two-column, slot-grid inventory screen.
##
## Left grid: nearby ground items or the contents of an open chest.
## Right side: equipment slots (weapon / armour / clothing / shield) plus the
## player's 5×8 backpack grid. Click a slot to select it; the details bar below
## offers the valid action (equip / take / pick up / put into chest).
##
## All mutations go through the server; the panel only renders synced state.

signal toggled(open: bool)

const COLUMNS: int = 5
const SLOT_SIZE := Vector2(64, 48)

const ACCENT := Color(0.72, 0.85, 1.0)
const MUTED := Color(0.62, 0.7, 0.82)
const GOOD := Color(0.6, 0.95, 0.7)

@onready var gold_label: Label = $Center/Panel/Margin/Content/Header/GoldLabel
@onready var close_button: Button = $Center/Panel/Margin/Content/Header/CloseButton
@onready var external_title: Label = $Center/Panel/Margin/Content/Columns/ExternalPanel/ExternalContent/ExternalTitle
@onready var external_grid: GridContainer = $Center/Panel/Margin/Content/Columns/ExternalPanel/ExternalContent/ExternalScroll/ExternalGrid
@onready var equipment_row: HBoxContainer = $Center/Panel/Margin/Content/Columns/PlayerPanel/PlayerContent/EquipmentRow
@onready var equipped_label: Label = $Center/Panel/Margin/Content/Columns/PlayerPanel/PlayerContent/EquippedLabel
@onready var player_grid: GridContainer = $Center/Panel/Margin/Content/Columns/PlayerPanel/PlayerContent/PlayerScroll/PlayerGrid
@onready var details_label: Label = $Center/Panel/Margin/Content/Details/DetailsLabel
@onready var primary_button: Button = $Center/Panel/Margin/Content/Details/PrimaryButton
@onready var secondary_button: Button = $Center/Panel/Margin/Content/Details/SecondaryButton
@onready var drop_button: Button = $Center/Panel/Margin/Content/Details/DropButton

var _player: PlayerCharacter = null
var _container: LootChest = null
var _nearby: Array = []
var _nearby_ids: Array = []
var _selection: Dictionary = {}


func _ready() -> void:
	visible = false
	close_button.pressed.connect(close)
	external_grid.columns = COLUMNS
	player_grid.columns = COLUMNS
	external_grid.set_drag_forwarding(_no_drag, _can_drop_external, _drop_external)
	player_grid.set_drag_forwarding(_no_drag, _can_drop_player_grid, _drop_player_grid)
	primary_button.pressed.connect(_on_primary_pressed)
	secondary_button.pressed.connect(_on_secondary_pressed)
	drop_button.pressed.connect(_on_drop_pressed)
	_clear_details()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("inventory"):
		if visible:
			close()
		else:
			open_nearby()
		get_viewport().set_input_as_handled()


func bind_player(hero: PlayerCharacter) -> void:
	if _player != null:
		if _player.equipment_changed.is_connected(_on_equipment_changed):
			_player.equipment_changed.disconnect(_on_equipment_changed)
		if _player.inventory.changed.is_connected(_on_inventory_changed):
			_player.inventory.changed.disconnect(_on_inventory_changed)
	_player = hero
	if _player == null:
		return
	_player.equipment_changed.connect(_on_equipment_changed)
	_player.inventory.changed.connect(_on_inventory_changed)
	if visible:
		_refresh()


## Game keeps this list fresh from the interactables in range.
func set_nearby(pickups: Array) -> void:
	var ids: Array = []
	for pickup in pickups:
		ids.append(pickup.get_instance_id())
	if ids == _nearby_ids:
		return
	_nearby_ids = ids
	_nearby = pickups.duplicate()
	if visible and _container == null:
		_refresh()


func open_nearby() -> void:
	_disconnect_container()
	if not visible:
		open()
	else:
		_refresh()


func open_container(chest: LootChest) -> void:
	if _container != chest:
		_disconnect_container()
		_container = chest
		if _container != null:
			_container.inventory.changed.connect(_on_container_changed)
	if not visible:
		open()
	else:
		_refresh()


func open() -> void:
	visible = true
	_refresh()
	toggled.emit(true)


func close() -> void:
	visible = false
	_disconnect_container()
	toggled.emit(false)


func _disconnect_container() -> void:
	if _container != null and _container.inventory.changed.is_connected(_on_container_changed):
		_container.inventory.changed.disconnect(_on_container_changed)
	_container = null


func _on_equipment_changed() -> void:
	if visible:
		_refresh()


func _on_inventory_changed() -> void:
	if visible:
		_refresh()


func _on_container_changed() -> void:
	if visible:
		_refresh()


# --- rendering --------------------------------------------------------------

func _refresh() -> void:
	_selection = {}
	_clear_grid(external_grid)
	_clear_grid(player_grid)
	_clear_children(equipment_row)

	if _player == null:
		gold_label.text = ""
		equipped_label.text = "Нет локального игрока."
		external_title.text = "Предметы рядом"
		_add_empty_grid(external_grid)
		_add_empty_grid(player_grid)
		_clear_details()
		return

	gold_label.text = "Золото: %d" % _player.inventory.gold
	var weapon_name := str(_player.weapon.get("name", "Без оружия"))
	equipped_label.text = "В руках: %s  ·  %s" % [weapon_name, ItemCatalog.describe(_player.weapon_id)]
	_build_equipment_row()

	if _container != null:
		external_title.text = "Сундук: %s" % _container.display_name
		_fill_inventory_grid(external_grid, _container.inventory, "chest")
	else:
		external_title.text = "Предметы рядом"
		_fill_nearby_grid(external_grid)

	_fill_inventory_grid(player_grid, _player.inventory, "player")
	_clear_details()


func _build_equipment_row() -> void:
	var slots := [
		[ItemCatalog.Slot.WEAPON, _player.weapon_id],
		[ItemCatalog.Slot.ARMOR, _player.armor_id],
		[ItemCatalog.Slot.CLOTHING, _player.clothing_id],
		[ItemCatalog.Slot.SHIELD, _player.shield_id],
	]
	for entry in slots:
		var slot: int = entry[0]
		var item_id: StringName = entry[1]
		var label := Button.new()
		label.focus_mode = Control.FOCUS_NONE
		label.clip_text = true
		label.custom_minimum_size = Vector2(0, 30)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.add_theme_font_size_override("font_size", 11)
		var item_name := "—"
		if item_id != &"" and item_id != &"unarmed":
			item_name = _player.inventory.get_display_name(item_id)
		elif item_id == &"unarmed":
			item_name = "Без оружия"
		label.text = "%s: %s" % [ItemCatalog.SLOT_NAMES_RU.get(slot, "Слот"), item_name]
		label.tooltip_text = "Перетащите подходящий предмет из рюкзака"
		if item_id != &"" and item_id != &"unarmed":
			label.tooltip_text = "%s\n%s\nПеретащите другой предмет, чтобы заменить" % [
				item_name, ItemCatalog.describe(item_id),
			]
		label.set_drag_forwarding(
			_no_drag,
			_can_drop_equipment.bind(slot),
			_drop_equipment.bind(slot)
		)
		equipment_row.add_child(label)


func _fill_inventory_grid(grid: GridContainer, inventory: Inventory, source: String) -> void:
	for index in inventory.slots.size():
		var slot: Dictionary = inventory.slots[index]
		grid.add_child(_make_slot(
			slot["id"], str(slot["display_name"]), int(slot["quantity"]), source
		))
	var empty := Inventory.MAX_SLOTS - inventory.slots.size()
	for _index in maxi(0, empty):
		grid.add_child(_make_empty_slot())


func _fill_nearby_grid(grid: GridContainer) -> void:
	var used := 0
	for pickup in _nearby:
		if not is_instance_valid(pickup) or not pickup.is_available():
			continue
		grid.add_child(_make_pickup_slot(pickup))
		used += 1
	for _index in maxi(0, Inventory.MAX_SLOTS - used):
		grid.add_child(_make_empty_slot())


func _make_slot(item_id: StringName, display_name: String, quantity: int, source: String, pickup: ItemPickup = null) -> Button:
	var button := Button.new()
	button.custom_minimum_size = SLOT_SIZE
	button.clip_text = true
	button.add_theme_font_size_override("font_size", 10)
	var text := display_name
	if quantity > 1:
		text += " ×%d" % quantity
	if _is_equipped(item_id):
		text = "• " + text
	button.text = text

	var description := ItemCatalog.describe(item_id)
	button.tooltip_text = "%s\n%s\nКоличество: %d" % [display_name, description, quantity]
	if _is_equipped(item_id):
		button.tooltip_text += "\nЭкипировано"
		button.add_theme_color_override("font_color", GOOD)
	button.pressed.connect(_on_slot_pressed.bind(source, item_id, display_name, quantity, pickup))
	var can_drop := _can_drop_player_grid if source == "player" else _can_drop_external
	var drop := _drop_player_grid if source == "player" else _drop_external
	button.set_drag_forwarding(
		_slot_drag_data.bind(button, source, item_id, display_name, quantity, pickup),
		can_drop,
		drop
	)
	return button


func _make_pickup_slot(pickup: ItemPickup) -> Button:
	var button := Button.new()
	button.custom_minimum_size = SLOT_SIZE
	button.clip_text = true
	button.add_theme_font_size_override("font_size", 10)
	button.text = str(pickup.display_name)
	if int(pickup.quantity) > 1:
		button.text += " ×%d" % int(pickup.quantity)
	button.tooltip_text = "%s\n%s\nКоличество: %d" % [
		pickup.display_name, ItemCatalog.describe(pickup.item_id), pickup.quantity,
	]
	button.pressed.connect(_on_slot_pressed.bind(
		"pickup", pickup.item_id, pickup.display_name, pickup.quantity, pickup
	))
	button.set_drag_forwarding(
		_slot_drag_data.bind(button, "pickup", pickup.item_id, pickup.display_name, pickup.quantity, pickup),
		_can_drop_external,
		_drop_external
	)
	return button


func _make_empty_slot() -> Button:
	var button := Button.new()
	button.custom_minimum_size = SLOT_SIZE
	button.disabled = true
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.modulate = Color(1, 1, 1, 0.4)
	return button


# --- selection / actions ----------------------------------------------------

func _on_slot_pressed(
	source: String,
	item_id: StringName,
	display_name: String,
	quantity: int,
	pickup: ItemPickup
) -> void:
	_selection = {
		"source": source,
		"item_id": item_id,
		"display_name": display_name,
		"quantity": quantity,
		"pickup": pickup,
	}
	_update_details()


func _update_details() -> void:
	if _selection.is_empty() or _player == null:
		_clear_details()
		return

	var item_id: StringName = _selection["item_id"]
	var name := str(_selection["display_name"])
	var quantity := int(_selection["quantity"])
	var source := str(_selection["source"])
	var lines := PackedStringArray()
	lines.append("%s%s" % [name, " ×%d" % quantity if quantity > 1 else ""])
	lines.append(ItemCatalog.describe(item_id))
	details_label.text = "\n".join(lines)

	primary_button.visible = false
	secondary_button.visible = false
	drop_button.visible = false

	match source:
		"player":
			var slot := ItemCatalog.equip_slot(item_id)
			if slot != ItemCatalog.Slot.NONE:
				primary_button.visible = true
				if _is_equipped(item_id):
					primary_button.text = "Уже надето"
					primary_button.disabled = true
				else:
					primary_button.text = "Экипировать"
					primary_button.disabled = not _player.is_alive
			if _container != null:
				secondary_button.visible = true
				secondary_button.text = "В сундук"
				secondary_button.disabled = not _player.is_alive
			drop_button.visible = true
			drop_button.text = "Выбросить"
			drop_button.disabled = not _player.is_alive
		"chest":
			primary_button.visible = true
			primary_button.text = "Забрать"
			primary_button.disabled = not _player.is_alive
		"pickup":
			primary_button.visible = true
			primary_button.text = "Подобрать"
			primary_button.disabled = not _player.is_alive


func _clear_details() -> void:
	details_label.text = "Выберите предмет, чтобы увидеть описание и действия."
	primary_button.visible = false
	primary_button.disabled = false
	secondary_button.visible = false
	secondary_button.disabled = false
	drop_button.visible = false
	drop_button.disabled = false


func _on_primary_pressed() -> void:
	if _selection.is_empty():
		return
	var source := str(_selection["source"])
	var item_id: StringName = _selection["item_id"]
	var quantity := int(_selection["quantity"])
	match source:
		"player":
			_player.request_equip(item_id)
		"chest":
			if _container != null:
				_container.request_take(item_id, quantity)
		"pickup":
			var pickup: ItemPickup = _selection.get("pickup")
			if is_instance_valid(pickup):
				pickup.request()


func _on_secondary_pressed() -> void:
	if _selection.is_empty() or _container == null:
		return
	var item_id: StringName = _selection["item_id"]
	var quantity := int(_selection["quantity"])
	_container.request_put(item_id, quantity)


func _on_drop_pressed() -> void:
	if _selection.is_empty() or _player == null:
		return
	if str(_selection.get("source", "")) != "player":
		return
	_player.request_drop(
		StringName(str(_selection.get("item_id", ""))),
		int(_selection.get("quantity", 1))
	)


# --- helpers ----------------------------------------------------------------

func _is_equipped(item_id: StringName) -> bool:
	return item_id != &"" and (
		item_id == _player.weapon_id
		or item_id == _player.armor_id
		or item_id == _player.clothing_id
		or item_id == _player.shield_id
	)


func _clear_grid(grid: GridContainer) -> void:
	_clear_children(grid)


func _clear_children(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()


func _add_empty_grid(grid: GridContainer) -> void:
	for _index in Inventory.MAX_SLOTS:
		grid.add_child(_make_empty_slot())


# --- drag and drop ----------------------------------------------------------

func _no_drag(_at_position: Vector2) -> Variant:
	return null


func _slot_drag_data(
	_at_position: Vector2,
	button: Button,
	source: String,
	item_id: StringName,
	display_name: String,
	quantity: int,
	pickup: ItemPickup
) -> Variant:
	if _player == null or not _player.is_alive:
		return null

	var preview := Label.new()
	preview.text = display_name
	if quantity > 1:
		preview.text += " ×%d" % quantity
	preview.add_theme_color_override("font_color", Color(1, 0.95, 0.7))
	preview.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	preview.add_theme_constant_override("shadow_offset_x", 2)
	preview.add_theme_constant_override("shadow_offset_y", 2)
	if button.get_viewport().gui_is_dragging():
		button.set_drag_preview(preview)

	return {
		"source": source,
		"item_id": String(item_id),
		"display_name": display_name,
		"quantity": quantity,
		"pickup": pickup,
	}


func _can_drop_external(_at_position: Vector2, data: Variant) -> bool:
	if not (data is Dictionary) or _container == null or _player == null:
		return false
	return str(data.get("source", "")) == "player" and _player.is_alive


func _drop_external(_at_position: Vector2, data: Variant) -> void:
	if not _can_drop_external(_at_position, data):
		return
	_container.request_put(
		StringName(str(data.get("item_id", ""))),
		int(data.get("quantity", 1))
	)


func _can_drop_player_grid(_at_position: Vector2, data: Variant) -> bool:
	if not (data is Dictionary) or _player == null or not _player.is_alive:
		return false
	var source := str(data.get("source", ""))
	if source == "chest":
		return _container != null
	if source == "pickup":
		var pickup: ItemPickup = data.get("pickup")
		return is_instance_valid(pickup) and pickup.is_available()
	return false


func _drop_player_grid(_at_position: Vector2, data: Variant) -> void:
	if not _can_drop_player_grid(_at_position, data):
		return
	var source := str(data.get("source", ""))
	if source == "chest":
		_container.request_take(
			StringName(str(data.get("item_id", ""))),
			int(data.get("quantity", 1))
		)
	elif source == "pickup":
		var pickup: ItemPickup = data.get("pickup")
		if is_instance_valid(pickup):
			pickup.request()


func _can_drop_equipment(_at_position: Vector2, data: Variant, slot: int) -> bool:
	if not (data is Dictionary) or _player == null or not _player.is_alive:
		return false
	if str(data.get("source", "")) != "player":
		return false
	var item_id := StringName(str(data.get("item_id", "")))
	return ItemCatalog.equip_slot(item_id) == slot


func _drop_equipment(_at_position: Vector2, data: Variant, slot: int) -> void:
	if not _can_drop_equipment(_at_position, data, slot):
		return
	_player.request_equip(StringName(str(data.get("item_id", ""))))
