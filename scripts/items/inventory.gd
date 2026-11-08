class_name Inventory
extends RefCounted
## Runtime inventory for one player during a match.
##
## Scope right now: a flat list of stacks built from the character's starting
## equipment (plus gold). The API already follows the usual contract —
## `add_item` returns the leftover that did not fit, stacks merge before new
## slots are used, and one `changed` signal is emitted per operation — so loot,
## pickups or trading can be layered on later.
##
## The contents are currently derived from `CharacterDraft.to_payload()` on
## every peer, so they survive reconnects and save/load automatically. Runtime
## changes (future pickups) would need to be replicated by the server.

signal changed

const MAX_SLOTS: int = 40

## Each slot: { id: StringName, display_name: String, quantity: int }.
var slots: Array[Dictionary] = []
var gold: int = 0


## Replaces the contents with the starting equipment from the spawn payload.
func setup(entries: Array, starting_gold: int) -> void:
	slots.clear()
	gold = maxi(0, starting_gold)
	for entry in entries:
		if not (entry is Dictionary):
			continue
		var item_id := StringName(str(entry.get("item_id", "")))
		if item_id == &"":
			continue
		_add_silent(item_id, str(entry.get("display_name", item_id)), int(entry.get("quantity", 1)))
	changed.emit()


## Adds up to `quantity`; returns how many did NOT fit.
func add_item(item_id: StringName, display_name: String, quantity: int) -> int:
	var leftover := _add_silent(item_id, display_name, quantity)
	if leftover < quantity:
		changed.emit()
	return leftover


## Removes up to `quantity`; returns how many were actually removed.
func remove_item(item_id: StringName, quantity: int) -> int:
	if quantity <= 0:
		return 0
	var removed := 0
	for index in range(slots.size() - 1, -1, -1):
		var slot := slots[index]
		if slot["id"] != item_id:
			continue
		var take := mini(quantity - removed, int(slot["quantity"]))
		slot["quantity"] = int(slot["quantity"]) - take
		removed += take
		if int(slot["quantity"]) <= 0:
			slots.remove_at(index)
		if removed >= quantity:
			break
	if removed > 0:
		changed.emit()
	return removed


func get_item_count(item_id: StringName) -> int:
	var total := 0
	for slot in slots:
		if slot["id"] == item_id:
			total += int(slot["quantity"])
	return total


func has_item(item_id: StringName, quantity: int = 1) -> bool:
	return get_item_count(item_id) >= quantity


func is_empty() -> bool:
	return slots.is_empty() and gold <= 0


func find_slot(item_id: StringName) -> int:
	for index in slots.size():
		if slots[index]["id"] == item_id:
			return index
	return -1


func get_display_name(item_id: StringName) -> String:
	var index := find_slot(item_id)
	return str(slots[index]["display_name"]) if index >= 0 else String(item_id)


## Plain-data snapshot for RPC and saves: strings and ints only.
func to_payload() -> Dictionary:
	var out_slots: Array = []
	for slot in slots:
		out_slots.append({
			"id": String(slot["id"]),
			"display_name": str(slot["display_name"]),
			"quantity": int(slot["quantity"]),
		})
	return {"slots": out_slots, "gold": gold}


## Replaces the contents from a to_payload() snapshot. Server payloads are
## trusted; no capacity checks are applied here.
func apply_payload(data: Dictionary) -> void:
	slots.clear()
	gold = maxi(0, int(data.get("gold", 0)))
	var raw: Variant = data.get("slots", [])
	if raw is Array:
		for entry in raw:
			if not (entry is Dictionary):
				continue
			var item_id := StringName(str(entry.get("id", "")))
			if item_id == &"":
				continue
			slots.append({
				"id": item_id,
				"display_name": str(entry.get("display_name", item_id)),
				"quantity": maxi(1, int(entry.get("quantity", 1))),
			})
	changed.emit()


## Adds without emitting; returns the leftover.
func _add_silent(item_id: StringName, display_name: String, quantity: int) -> int:
	if item_id == &"" or quantity <= 0:
		return quantity
	var remaining := quantity
	var max_stack := ItemCatalog.stack_size(item_id)

	# Fill existing stacks first.
	for slot in slots:
		if slot["id"] != item_id:
			continue
		var space := max_stack - int(slot["quantity"])
		if space <= 0:
			continue
		var take := mini(space, remaining)
		slot["quantity"] = int(slot["quantity"]) + take
		remaining -= take
		if remaining == 0:
			return 0

	# Then open new slots.
	while remaining > 0 and slots.size() < MAX_SLOTS:
		var take := mini(max_stack, remaining)
		slots.append({
			"id": item_id,
			"display_name": display_name,
			"quantity": take,
		})
		remaining -= take

	return remaining
