class_name SpeciesRepository
extends RefCounted
## Loads every SpeciesData under res://data/species/.

const DIR := "res://data/species"

static var _cache: Array[SpeciesData] = []


static func load_all() -> Array[SpeciesData]:
	if not _cache.is_empty():
		return _cache

	var dir := DirAccess.open(DIR)
	if dir == null:
		push_error("SpeciesRepository: cannot open %s" % DIR)
		return _cache

	var files := dir.get_files()
	files.sort()
	for file_name in files:
		if not file_name.ends_with(".tres"):
			continue
		var resource: Resource = load("%s/%s" % [DIR, file_name])
		if resource is SpeciesData:
			_cache.append(resource)
		else:
			push_error("SpeciesRepository: %s is not a SpeciesData" % file_name)
	return _cache


static func find(species_id: StringName) -> SpeciesData:
	for data in load_all():
		if data.id == species_id:
			return data
	return null


static func clear_cache() -> void:
	_cache.clear()
