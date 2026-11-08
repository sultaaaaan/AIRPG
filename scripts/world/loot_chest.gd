class_name LootChest
extends StaticBody3D
## A shared storage chest. One inventory per chest, owned by the server.
##
## All peers have the node (it is part of the arena scene), but only the server
## fills and mutates it. Opening broadcasts the contents; transferring items is
## validated against distance and ownership before both inventories are synced.

@export var chest_id: StringName = &""
@export var display_name: String = "Сундук"

const REACH: float = 3.5

## chest_id -> Array of [item_id, display_name, quantity].
const CHEST_LOOT := {
	&"armory": [
		[&"longsword", "Длинный меч", 1],
		[&"greataxe", "Секира", 1],
		[&"longbow", "Длинный лук", 1],
		[&"arrow", "Стрела", 40],
		[&"chain_shirt", "Кольчужная рубаха", 1],
	],
	&"supplies": [
		[&"healers_kit", "Набор целителя", 1],
		[&"rope", "Верёвка", 1],
		[&"oil", "Масло", 2],
		[&"dagger", "Кинжал", 1],
		[&"javelin", "Метательное копьё", 4],
		[&"leather_armor", "Кожаный доспех", 1],
	],
}

@onready var label: Label3D = $Label

var inventory: Inventory = Inventory.new()


func _ready() -> void:
	add_to_group("interactables")
	label.text = display_name
	if _is_server_context():
		_fill_loot()


func is_available() -> bool:
	return true


func prompt_text() -> String:
	return "E — открыть «%s»" % display_name


# --- client -> server -------------------------------------------------------

func request_open() -> void:
	if not multiplayer.has_multiplayer_peer() or multiplayer.is_server():
		_request_open()
	else:
		_request_open.rpc_id(1)


func request_take(item_id: StringName, quantity: int = 1) -> void:
	if not multiplayer.has_multiplayer_peer() or multiplayer.is_server():
		_request_take(item_id, quantity)
	else:
		_request_take.rpc_id(1, item_id, quantity)


func request_put(item_id: StringName, quantity: int = 1) -> void:
	if not multiplayer.has_multiplayer_peer() or multiplayer.is_server():
		_request_put(item_id, quantity)
	else:
		_request_put.rpc_id(1, item_id, quantity)


@rpc("any_peer", "reliable")
func _request_open() -> void:
	if not multiplayer.is_server():
		return
	var player := _requesting_player()
	if player == null or not _in_reach(player):
		return
	_sync_contents.rpc(inventory.to_payload())


@rpc("any_peer", "reliable")
func _request_take(item_id: StringName, quantity: int) -> void:
	if not multiplayer.is_server():
		return
	var player := _requesting_player()
	if player == null or not _in_reach(player):
		return

	var available := inventory.get_item_count(item_id)
	var take := mini(maxi(1, quantity), available)
	if take <= 0:
		return

	var item_name := inventory.get_display_name(item_id)
	var removed := inventory.remove_item(item_id, take)
	var leftover := player.server_add_item(item_id, item_name, removed)
	if leftover > 0:
		inventory.add_item(item_id, item_name, leftover)
	_broadcast()


@rpc("any_peer", "reliable")
func _request_put(item_id: StringName, quantity: int) -> void:
	if not multiplayer.is_server():
		return
	var player := _requesting_player()
	if player == null or not _in_reach(player):
		return

	var available := player.inventory.get_item_count(item_id)
	var take := mini(maxi(1, quantity), available)
	if take <= 0:
		return

	var item_name := player.inventory.get_display_name(item_id)
	var removed := player.server_remove_item(item_id, take)
	var leftover := inventory.add_item(item_id, item_name, removed)
	if leftover > 0:
		player.server_add_item(item_id, item_name, leftover)
	_broadcast()


# --- server -> clients ------------------------------------------------------

@rpc("authority", "call_local", "reliable")
func _sync_contents(data: Dictionary) -> void:
	inventory.apply_payload(data)


func _broadcast() -> void:
	if multiplayer.has_multiplayer_peer():
		_sync_contents.rpc(inventory.to_payload())


# --- setup / helpers --------------------------------------------------------

func _fill_loot() -> void:
	var entries: Array = CHEST_LOOT.get(chest_id, [])
	for entry in entries:
		inventory.add_item(StringName(entry[0]), str(entry[1]), int(entry[2]))


func _is_server_context() -> bool:
	if not multiplayer.has_multiplayer_peer():
		return true
	return multiplayer.is_server()


func _in_reach(player: PlayerCharacter) -> bool:
	return player.is_alive and player.global_position.distance_to(global_position) <= REACH


func _requesting_player() -> PlayerCharacter:
	var peer_id := multiplayer.get_remote_sender_id()
	if peer_id == 0:
		peer_id = multiplayer.get_unique_id()
	var players := _players_root()
	if players == null:
		return null
	return players.get_node_or_null(str(peer_id)) as PlayerCharacter


func _players_root() -> Node:
	var scene := get_tree().current_scene
	if scene != null:
		var node := scene.get_node_or_null("Players")
		if node != null:
			return node
	return get_parent().get_node_or_null("Players")
