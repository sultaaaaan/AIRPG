extends Node
## Autoload holding the player's committed character.
##
## CharacterCreation edits a *copy* (begin_edit) so Cancel truly discards
## changes. The game scene can later read `draft` to build the actual stats.
##
## The committed character is persisted to `user://character.json` and restored
## on startup, so a hero survives relaunching the game.

signal changed

const SAVE_VERSION: int = 1
const SAVE_PATH: String = "user://character.json"

var draft: CharacterDraft = null

## Tests can point this at a temporary file, or disable disk writes entirely.
var persistence_enabled: bool = true
var save_path: String = SAVE_PATH


func _ready() -> void:
	load_from_disk()


## True only when a complete, valid character has been committed.
func has_character() -> bool:
	return draft != null and draft.validate().is_empty()


## A fresh draft pre-filled from the committed one, for the editor to mutate.
func begin_edit() -> CharacterDraft:
	var fresh := CharacterDraft.new()
	if draft != null:
		fresh.copy_from(draft)
	return fresh


func commit(new_draft: CharacterDraft, save: bool = true) -> void:
	draft = new_draft
	changed.emit()
	if save:
		save_to_disk()


## Writes the committed character. An incomplete draft is never saved.
func save_to_disk() -> Error:
	if not persistence_enabled:
		return OK
	if draft == null or not draft.validate().is_empty():
		return ERR_INVALID_DATA

	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify({
		"version": SAVE_VERSION,
		"character": draft.to_payload(),
	}, "\t"))
	file.close()
	return OK


## Replaces the in-memory character with the saved one, if it is still valid.
func load_from_disk() -> void:
	draft = null
	if not persistence_enabled:
		return
	if not FileAccess.file_exists(save_path):
		return

	var file := FileAccess.open(save_path, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not (parsed is Dictionary):
		push_warning("PlayerProfile: %s is not valid JSON; ignoring." % save_path)
		return

	var character_data: Variant = parsed.get("character", {})
	if not (character_data is Dictionary):
		return
	var loaded := CharacterDraft.from_payload(character_data)
	if loaded == null or not loaded.validate().is_empty():
		push_warning("PlayerProfile: saved character is invalid; ignoring.")
		return

	draft = loaded
	changed.emit()


## Removes the save file and the in-memory character.
func clear_character() -> void:
	draft = null
	if persistence_enabled and FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	changed.emit()


## One-line description for menus: "Дурган — Воин, дварф".
func summary_line() -> String:
	if draft == null:
		return "Персонаж не создан"
	var parts := PackedStringArray()
	if not draft.character_name.strip_edges().is_empty():
		parts.append(draft.character_name.strip_edges())
	if draft.class_data != null:
		parts.append(draft.class_data.display_name)
	if draft.subclass != null:
		parts.append(draft.subclass.display_name)
	if draft.species != null:
		parts.append(draft.species.display_name)
	if parts.is_empty():
		return "Персонаж не создан"
	var level_tag := "%d ур." % draft.level
	if parts.size() == 1:
		return "%s · %s" % [parts[0], level_tag]
	return "%s — %s · %s" % [parts[0], " · ".join(parts.slice(1)), level_tag]


## Payload for spawning the player on the server.
## Keep it plain data: Dictionaries and primitives survive RPCs.
func to_payload() -> Dictionary:
	return draft.to_payload() if draft != null else {}
