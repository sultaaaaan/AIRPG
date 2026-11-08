extends SceneTree
## Headless round-trip of PlayerProfile's disk persistence.
##
##   godot --headless --path . --script res://tools/profile_io_smoke.gd
##
## Uses a temporary file in user:// so the player's real save is untouched.

const TEMP_PATH := "user://profile_smoke.json"


func _initialize() -> void:
	await process_frame
	var profile: Node = root.get_node("PlayerProfile")
	var old_path: String = profile.save_path
	var old_enabled: bool = profile.persistence_enabled

	profile.persistence_enabled = true
	profile.save_path = TEMP_PATH
	_remove_temp()

	var draft := _make_draft()
	profile.commit(draft)
	if not FileAccess.file_exists(TEMP_PATH):
		_fail("save file was not created")
		return
	if profile.save_to_disk() != OK:
		_fail("save_to_disk returned an error")
		return

	profile.draft = null
	profile.load_from_disk()
	if not profile.has_character():
		_fail("loaded character is missing or invalid")
		return
	if profile.draft.character_name != "Сохранённый":
		_fail("loaded name is '%s'" % profile.draft.character_name)
		return
	if profile.draft.max_hit_points() != draft.max_hit_points():
		_fail("HP changed across save/load: %d vs %d" % [profile.draft.max_hit_points(), draft.max_hit_points()])
		return
	if profile.draft.armor_class() != draft.armor_class():
		_fail("AC changed across save/load")
		return

	_remove_temp()
	profile.save_path = old_path
	profile.persistence_enabled = old_enabled
	profile.draft = null
	print("Profile IO smoke OK — name, HP and AC survived save/load")
	quit(0)


func _make_draft() -> CharacterDraft:
	var draft := CharacterDraft.new()
	draft.character_name = "Сохранённый"
	draft.class_data = ClassRepository.find(&"fighter")
	draft.background = BackgroundRepository.find(&"soldier")
	draft.species = SpeciesRepository.find(&"dwarf")
	draft.apply_standard_array({
		&"strength": 15, &"dexterity": 12, &"constitution": 14,
		&"intelligence": 8, &"wisdom": 10, &"charisma": 13,
	})
	var targets: Array[StringName] = [&"strength", &"dexterity", &"constitution"]
	draft.background_targets = targets
	var skills: Array[StringName] = [&"athletics", &"perception"]
	draft.skill_choices = skills
	draft.select_option(&"fighting_style", &"dueling")
	return draft


func _remove_temp() -> void:
	if FileAccess.file_exists(TEMP_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_PATH))


func _fail(message: String) -> void:
	printerr("Profile IO smoke FAILED: %s" % message)
	_remove_temp()
	quit(1)
