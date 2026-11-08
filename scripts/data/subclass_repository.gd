class_name SubclassRepository
extends RefCounted
## Loads every SubclassData under res://data/subclasses/.

const DIR := "res://data/subclasses"

static var _cache: Array[SubclassData] = []


static func load_all() -> Array[SubclassData]:
	if not _cache.is_empty():
		return _cache

	var dir := DirAccess.open(DIR)
	if dir == null:
		push_error("SubclassRepository: cannot open %s" % DIR)
		return _cache

	var files := dir.get_files()
	files.sort()
	for file_name in files:
		if not file_name.ends_with(".tres"):
			continue
		var resource: Resource = load("%s/%s" % [DIR, file_name])
		if resource is SubclassData:
			_cache.append(resource)
		else:
			push_error("SubclassRepository: %s is not a SubclassData" % file_name)
	return _cache


static func find(subclass_id: StringName) -> SubclassData:
	for data in load_all():
		if data.id == subclass_id:
			return data
	return null


## Every subclass of one class, in file order.
static func for_class(class_id: StringName) -> Array[SubclassData]:
	var out: Array[SubclassData] = []
	for data in load_all():
		if data.class_id == class_id:
			out.append(data)
	return out


static func clear_cache() -> void:
	_cache.clear()
