class_name InventoryPanel
extends CanvasLayer
## Two-column inventory screen.
##
## Left column is the external source: nearby ground items, or the contents of
## an open chest. Right column is always the local player's backpack. Clicking a
## row transfers/picks that stack; every mutation goes through the server.
##
## The panel does not pause the match. It only tells the game to ignore the
## attack key while open (the local player keeps moving).

signal toggled(open: bool)

const ACCENT := Color(0.72, 0.85, 1.0)
const MUTED := Color(0.62, 0.7, 0.82)
const GOOD := Color(0.6, 0.95, 0.7)

@onready var gold_label: Label = $Center/Panel/Margin/Content/Header/GoldLabel
@onready var close_button: Button = $Center/Panel/Margin/Content/Header/CloseButton
@onready var external_title: Label = $Center/Panel/Margin/Content/Columns/ExternalPanel/ExternalContent/ExternalTitle
@onready var external_list: VBoxContainer = $Center/Panel/Margin/Content/Columns/ExternalPanel/ExternalContent/ExternalScroll/ExternalList
@onready var equipped_label: Label = $Center/Panel/Margin/Content/Columns/PlayerPanel/PlayerContent/EquippedLabel
@onready var list: VBoxContainer = $Center/Panel/Margin/Content/Columns/PlayerPanel/PlayerContent/PlayerScroll/List

var _player: PlayerCharacter = null
var _container: LootChest = null
var _nearby: Array = []
var _nearby_ids: Array = []


func _ready() -> void:
	visible = false
	close_button.pressed.connect(close)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("inventory"):
		if visible:
			close()
		else:
			open_nearby()
		get_viewport().set_input_as_handled()


## Rebinds the panel to the local player when the arena spawns it.
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


## Opens the screen with the left column showing nearby ground items.
func open_nearby() -> void:
	_disconnect_container()
	if not visible:
		open()
	else:
		_refresh()


## Opens the screen with a chest on the left and the backpack on the right.
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


func _refresh() -> void:
	for child in list.get_children():
		list.remove_child(child)
		child.queue_free()
	for child in external_list.get_children():
		external_list.remove_child(child)
		child.queue_free()

	if _player == null:
		gold_label.text = ""
		equipped_label.text = "Нет локального игрока."
		external_title.text = "Предметы рядом"
		_add_paragraph(external_list, "Подождите, пока арена загрузит персонажа.")
		return

	gold_label.text = "Золото: %d" % _player.inventory.gold
	var weapon_name := str(_player.weapon.get("name", "Без оружия"))
	equipped_label.text = "В руках: %s  ·  %s" % [weapon_name, ItemCatalog.describe(_player.weapon_id)]

	if _container != null:
		external_title.text = "Сундук: %s" % _container.display_name
		_add_inventory(external_list, _container.inventory, true)
		if _container.inventory.slots.is_empty():
			_add_paragraph(external_list, "Сундук пуст.")
	else:
		external_title.text = "Предметы рядом"
		_add_nearby(external_list)
		if _nearby.is_empty():
			_add_paragraph(external_list, "Рядом ничего нет.")

	_add_inventory(list, _player.inventory, false)


func _add_inventory(parent: Control, inventory: Inventory, from_chest: bool) -> void:
	var groups := {}
	for slot in inventory.slots:
		var category := ItemCatalog.category(slot["id"])
		if not groups.has(category):
			groups[category] = []
		groups[category].append(slot)

	if groups.is_empty() and not from_chest:
		_add_paragraph(parent, "Инвентарь пуст.")
		return

	for category in ItemCatalog.CATEGORY_ORDER:
		if not groups.has(category):
			continue
		_add_section(parent, ItemCatalog.CATEGORY_NAMES_RU.get(category, "Снаряжение"))
		var stacks: Array = groups[category]
		stacks.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return str(a["display_name"]) < str(b["display_name"])
		)
		for slot in stacks:
			_add_inventory_row(parent, slot, category, from_chest)


func _add_nearby(parent: Control) -> void:
	for pickup in _nearby:
		if not is_instance_valid(pickup) or not pickup.is_available():
			continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)

		var name_label := Label.new()
		name_label.text = str(pickup.display_name)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if int(pickup.quantity) > 1:
			name_label.text += "  ×%d" % int(pickup.quantity)
		row.add_child(name_label)

		var take_button := Button.new()
		take_button.text = "Подобрать"
		take_button.custom_minimum_size = Vector2(120, 0)
		take_button.disabled = not _player.is_alive
		take_button.pressed.connect(_on_pickup_pressed.bind(pickup))
		row.add_child(take_button)

		parent.add_child(row)
		_add_paragraph(parent, ItemCatalog.describe(pickup.item_id))


func _add_inventory_row(parent: Control, slot: Dictionary, category: int, from_chest: bool) -> void:
	var item_id: StringName = slot["id"]
	var quantity := int(slot["quantity"])

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var name_label := Label.new()
	name_label.text = str(slot["display_name"])
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if quantity > 1:
		name_label.text += "  ×%d" % quantity
	row.add_child(name_label)

	if from_chest:
		var take_button := Button.new()
		take_button.text = "Забрать"
		take_button.custom_minimum_size = Vector2(110, 0)
		take_button.disabled = not _player.is_alive
		take_button.pressed.connect(_on_take_pressed.bind(item_id, quantity))
		row.add_child(take_button)
	else:
		if category == ItemCatalog.Category.WEAPON:
			var equip_button := Button.new()
			equip_button.custom_minimum_size = Vector2(120, 0)
			if item_id == _player.weapon_id:
				equip_button.text = "В руках"
				equip_button.disabled = true
				equip_button.add_theme_color_override("font_color", GOOD)
			else:
				equip_button.text = "Экипировать"
				equip_button.disabled = not _player.is_alive
				equip_button.pressed.connect(_on_equip_pressed.bind(item_id))
			row.add_child(equip_button)

		if _container != null:
			var put_button := Button.new()
			put_button.text = "В сундук"
			put_button.custom_minimum_size = Vector2(110, 0)
			put_button.disabled = not _player.is_alive
			put_button.pressed.connect(_on_put_pressed.bind(item_id, quantity))
			row.add_child(put_button)

	parent.add_child(row)
	_add_paragraph(parent, ItemCatalog.describe(item_id))


func _on_pickup_pressed(pickup: ItemPickup) -> void:
	pickup.request()


func _on_equip_pressed(item_id: StringName) -> void:
	if _player != null:
		_player.request_equip(item_id)


func _on_put_pressed(item_id: StringName, quantity: int) -> void:
	if _container != null:
		_container.request_put(item_id, quantity)


func _on_take_pressed(item_id: StringName, quantity: int) -> void:
	if _container != null:
		_container.request_take(item_id, quantity)


func _add_section(parent: Control, text: String) -> void:
	var label := Label.new()
	label.text = text.to_upper()
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", ACCENT)
	parent.add_child(label)


func _add_paragraph(parent: Control, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", MUTED)
	label.add_theme_font_size_override("font_size", 13)
	parent.add_child(label)
