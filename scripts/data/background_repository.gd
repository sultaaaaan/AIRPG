class_name BackgroundRepository
extends RefCounted
## Loads every BackgroundData under res://data/backgrounds/.

const DIR := "res://data/backgrounds"

static var _cache: Array[BackgroundData] = []


static func load_all() -> Array[BackgroundData]:
	if not _cache.is_empty():
		return _cache

	var dir := DirAccess.open(DIR)
	if dir == null:
		push_error("BackgroundRepository: cannot open %s" % DIR)
		return _cache

	var files := dir.get_files()
	files.sort()
	for file_name in files:
		if not file_name.ends_with(".tres"):
			continue
		var resource: Resource = load("%s/%s" % [DIR, file_name])
		if resource is BackgroundData:
			_cache.append(resource)
		else:
			push_error("BackgroundRepository: %s is not a BackgroundData" % file_name)
	return _cache


static func find(background_id: StringName) -> BackgroundData:
	for data in load_all():
		if data.id == background_id:
			return data
	return null


static func clear_cache() -> void:
	_cache.clear()
