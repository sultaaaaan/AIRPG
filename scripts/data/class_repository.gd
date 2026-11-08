class_name ClassRepository
extends RefCounted
## Loads every ClassData under res://data/classes/.
##
## Call `load_all()` once and cache the result for the session; the resources
## are read-only and shared. If this ever ships to a platform where DirAccess
## cannot list packed .tres files, replace the scan with an explicit path list.

const CLASS_DIR := "res://data/classes"

static var _cache: Array[ClassData] = []


## All classes, sorted by id. Cached after the first call.
static func load_all() -> Array[ClassData]:
	if not _cache.is_empty():
		return _cache

	var dir := DirAccess.open(CLASS_DIR)
	if dir == null:
		push_error("ClassRepository: cannot open %s" % CLASS_DIR)
		return _cache

	var files := dir.get_files()
	files.sort()
	for file_name in files:
		if not file_name.ends_with(".tres"):
			continue
		var resource: Resource = load("%s/%s" % [CLASS_DIR, file_name])
		if resource is ClassData:
			_cache.append(resource)
		else:
			push_error("ClassRepository: %s is not a ClassData" % file_name)
	return _cache


## Fetch one class by id, or null when unknown.
static func find(class_id: StringName) -> ClassData:
	for class_data in load_all():
		if class_data.id == class_id:
			return class_data
	return null


## Drop the cache, e.g. after regenerating the .tres files in the editor.
static func clear_cache() -> void:
	_cache.clear()
