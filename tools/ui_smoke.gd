extends Node
## Headless end-to-end check of the character creation screen.
##
## Run as a main scene, because it needs the PlayerProfile autoload:
##   godot --headless --path . res://tools/UiSmoke.tscn
##
## It drives the same handlers the widgets call, so it catches broken signal
## wiring, missing repositories and validation regressions without a display.

func _ready() -> void:
	# Never touch the player's real save from an automated smoke test.
	PlayerProfile.persistence_enabled = false
	PlayerProfile.draft = null
	var packed: PackedScene = load("res://scenes/CharacterCreation.tscn")
	if packed == null:
		_fail("cannot load CharacterCreation.tscn")
		return

	var ui := packed.instantiate()
	add_child(ui)
	await get_tree().process_frame

	if ui.draft == null:
		_fail("draft was not created")
		return
	if ui._pages.size() != 6:
		_fail("expected 6 pages, got %d" % ui._pages.size())

	var classes := ClassRepository.load_all()
	ui._on_class_selected(_index_of(classes, &"fighter"))
	await get_tree().process_frame

	var backgrounds := BackgroundRepository.load_all()
	ui._on_background_selected(_index_of(backgrounds, &"soldier"))
	await get_tree().process_frame

	var species := SpeciesRepository.load_all()
	ui._on_species_selected(_index_of(species, &"dwarf"))
	await get_tree().process_frame

	ui._on_name_changed("Дурган")
	ui._on_skill_toggled(true, &"athletics")
	ui._on_skill_toggled(true, &"perception")

	var group: ChoiceGroupData = ui.draft.class_data.choices[0]
	ui._on_choice_selected(_option_item_index(group, &"dueling"), group)
	await get_tree().process_frame

	var problems: PackedStringArray = ui.draft.validate()
	for problem in problems:
		_fail("draft: %s" % problem)

	if ui._accept.disabled:
		_fail("accept button must be enabled once the draft is valid")
	if ui._sheet.text.length() < 100:
		_fail("sheet looks empty")
	if not ui.draft.has_equipment(&"chain_mail"):
		_fail("fighter pack should include chain mail")
	if ui.draft.armor_class() != 16:
		_fail("expected AC 16, got %d" % ui.draft.armor_class())

	# Commit through the same path the "Готово" button uses.
	PlayerProfile.commit(ui.draft)
	if not PlayerProfile.has_character():
		_fail("committed profile should report a valid character")
	if PlayerProfile.begin_edit().character_name != "Дурган":
		_fail("editing copy did not inherit the committed name")

	print("UI smoke OK — %s, HP %d, AC %d" % [
		PlayerProfile.summary_line(),
		ui.draft.max_hit_points(),
		ui.draft.armor_class(),
	])
	get_tree().quit(0)


func _index_of(entries: Array, id: StringName) -> int:
	for index in entries.size():
		if entries[index].id == id:
			return index
	return -1


func _option_item_index(group: ChoiceGroupData, id: StringName) -> int:
	for index in group.options.size():
		if group.options[index].id == id:
			return index + 1
	return 0


func _fail(message: String) -> void:
	printerr("UI smoke FAILED: %s" % message)
	get_tree().quit(1)
