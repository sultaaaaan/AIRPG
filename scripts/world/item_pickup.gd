class_name ItemPickup
extends Node3D
## A ground item the player can pick up with E.
##
## The node exists on every peer (it is part of the arena scene); the server
## owns the `taken` flag and the player's inventory. Clients only send intent.

@export var item_id: StringName = &""
@export var display_name: String = ""
@export var quantity: int = 1

@onready var label: Label3D = $Label

var taken: bool = false


func _ready() -> void:
	add_to_group("interactables")
	if display_name.is_empty():
		display_name = String(item_id)
	if quantity < 1:
		quantity = 1
	_update_label()


func is_available() -> bool:
	return not taken


func prompt_text() -> String:
	if quantity > 1:
		return "E — подобрать «%s» ×%d" % [display_name, quantity]
	return "E — подобрать «%s»" % display_name


func request() -> void:
	if not multiplayer.has_multiplayer_peer() or multiplayer.is_server():
		_request_pickup()
	else:
		_request_pickup.rpc_id(1)


@rpc("any_peer", "reliable")
func _request_pickup() -> void:
	if not multiplayer.is_server() or taken:
		return
	var player := _requesting_player()
	if player == null or not player.is_alive:
		return
	if player.global_position.distance_to(global_position) > 3.0:
		return

	var leftover := player.server_add_item(item_id, display_name, quantity)
	if leftover == 0:
		_set_taken.rpc(true)
	elif leftover < quantity:
		# Roll back the part that fitted; the item stays on the ground.
		player.server_remove_item(item_id, quantity - leftover)


@rpc("authority", "call_local", "reliable")
func _set_taken(value: bool) -> void:
	taken = value
	visible = not value


func _update_label() -> void:
	if not is_instance_valid(label):
		return
	label.text = display_name if quantity <= 1 else "%s ×%d" % [display_name, quantity]


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
	var current: Node = get_parent()
	while current != null:
		var node := current.get_node_or_null("Players")
		if node != null:
			return node
		current = current.get_parent()
	return null
