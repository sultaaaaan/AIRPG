class_name InventoryPanel
extends CanvasLayer
## In-game inventory panel (I key).
##
## List-based on purpose: the character starts with a fixed kit and there is no
## loot yet. Weapon rows can be equipped; the server validates the request and
## broadcasts the change, so every peer sees the same weapon in combat.
##
## The panel does not pause the match. It only tells the game to ignore the
## attack key while open (the local player keeps moving).

signal toggled(open: bool)

const ACCENT := Color(0.72, 0.85, 1.0)
const MUTED := Color(0.62, 0.7, 0.82)
const GOOD := Color(0.6, 0.95, 0.7)

@onready var gold_label: Label = $Center/Panel/Margin/Content/Header/GoldLabel
@onready var equipped_label: Label = $Center/Panel/Margin/Content/EquippedLabel
@onready var list: VBoxContainer = $Center/Panel/Margin/Content/Scroll/List
@onready var close_button: Button = $Center/Panel/Margin/Content/Header/CloseButton

var _player: PlayerCharacter = null


func _ready() -> void:
	visible = false
	close_button.pressed.connect(close)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("inventory"):
		if visible:
			close()
		else:
			open()
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


func open() -> void:
	visible = true
	_refresh()
	toggled.emit(true)


func close() -> void:
	visible = false
	toggled.emit(false)


func _on_equipment_changed() -> void:
	if visible:
		_refresh()


func _on_inventory_changed() -> void:
	if visible:
		_refresh()


func _refresh() -> void:
	for child in list.get_children():
		list.remove_child(child)
		child.queue_free()

	if _player == null:
		gold_label.text = ""
		equipped_label.text = "Нет локального игрока."
		_add_paragraph(list, "Подождите, пока арена загрузит персонажа.")
		return

	gold_label.text = "Золото: %d" % _player.inventory.gold
	var weapon_name := str(_player.weapon.get("name", "Без оружия"))
	equipped_label.text = "В руках: %s  ·  %s" % [weapon_name, ItemCatalog.describe(_player.weapon_id)]

	var groups := {}
	for slot in _player.inventory.slots:
		var category := ItemCatalog.category(slot["id"])
		if not groups.has(category):
			groups[category] = []
		groups[category].append(slot)

	if groups.is_empty():
		_add_paragraph(list, "Инвентарь пуст.")
		return

	for category in ItemCatalog.CATEGORY_ORDER:
		if not groups.has(category):
			continue
		_add_section(list, ItemCatalog.CATEGORY_NAMES_RU.get(category, "Снаряжение"))
		var stacks: Array = groups[category]
		stacks.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return str(a["display_name"]) < str(b["display_name"])
		)
		for slot in stacks:
			_add_row(slot, category)


func _add_row(slot: Dictionary, category: int) -> void:
	var item_id: StringName = slot["id"]

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var name_label := Label.new()
	name_label.text = str(slot["display_name"])
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if int(slot["quantity"]) > 1:
		name_label.text += "  ×%d" % int(slot["quantity"])
	row.add_child(name_label)

	if category == ItemCatalog.Category.WEAPON:
		var button := Button.new()
		button.custom_minimum_size = Vector2(120, 0)
		if item_id == _player.weapon_id:
			button.text = "В руках"
			button.disabled = true
			button.add_theme_color_override("font_color", GOOD)
		else:
			button.text = "Экипировать"
			button.disabled = not _player.is_alive
			button.pressed.connect(_on_equip_pressed.bind(item_id))
		row.add_child(button)

	list.add_child(row)
	_add_paragraph(list, ItemCatalog.describe(item_id))


func _on_equip_pressed(item_id: StringName) -> void:
	if _player != null:
		_player.request_equip(item_id)


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
