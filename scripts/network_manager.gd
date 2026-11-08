extends Node
## Autoload that owns the ENet connection and the lobby player registry.
##
## Server keeps an authoritative dictionary of `peer_id -> nickname` and
## replicates it to every peer. Clients only ever ask the server to register
## them; the server decides when the match starts.

signal players_updated(players: Dictionary)
signal characters_updated(characters: Dictionary)
signal lobby_joined
signal connection_failed
signal disconnected

const PORT: int = 7777
const MAX_CLIENTS: int = 8
const MENU_SCENE: String = "res://scenes/MainMenu.tscn"
const GAME_SCENE: String = "res://scenes/Game.tscn"

var nickname: String = ""
var players: Dictionary = {}
## peer_id -> character payload (see CharacterDraft.to_payload). Server-owned.
var characters: Dictionary = {}
var game_started: bool = false
## Message shown by the menu after a disconnect / kick.
var last_message: String = ""
## Whether `last_message` should be shown as an error (red) or as info (green).
var last_message_is_error: bool = true


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func is_online() -> bool:
	return multiplayer.multiplayer_peer is ENetMultiplayerPeer


func is_host() -> bool:
	return is_online() and multiplayer.is_server()


func host_game(nick: String) -> Error:
	_shutdown_network()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, MAX_CLIENTS)
	if err != OK:
		return err

	multiplayer.multiplayer_peer = peer
	nickname = nick
	game_started = false
	last_message = ""
	last_message_is_error = false
	players.clear()
	players[1] = nick
	characters.clear()
	var own := _validated_character_payload(PlayerProfile.to_payload())
	if not own.is_empty():
		characters[1] = own
	players_updated.emit(players)
	characters_updated.emit(characters)
	lobby_joined.emit()
	return OK


func join_game(nick: String, address: String) -> Error:
	_shutdown_network()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, PORT)
	if err != OK:
		return err

	multiplayer.multiplayer_peer = peer
	nickname = nick
	game_started = false
	last_message = ""
	last_message_is_error = false
	players.clear()
	characters.clear()
	return OK


## Starts the match. Returns an empty string on success, or a message for the
## host explaining why the match cannot start yet.
func start_game() -> String:
	if not is_host() or game_started:
		return ""

	# Every peer must have a character the server has already validated.
	for peer_id in players:
		var payload: Dictionary = characters.get(int(peer_id), {})
		if payload.is_empty():
			return "У игрока «%s» нет готового персонажа." % str(players[peer_id])

	game_started = true
	_load_game.rpc()
	return ""


## Re-sends the local character to the server. Call after editing the character
## while already connected; the server validates it again and broadcasts.
func sync_own_character() -> void:
	if not is_online():
		return
	if is_host():
		var payload := _validated_character_payload(PlayerProfile.to_payload())
		if payload.is_empty():
			characters.erase(1)
		else:
			characters[1] = payload
		_sync_characters.rpc(characters)
	else:
		register_character.rpc_id(1, PlayerProfile.to_payload())


func return_to_menu(message: String = "", is_error: bool = false) -> void:
	_shutdown_network()
	last_message = message
	last_message_is_error = is_error
	get_tree().paused = false
	get_tree().change_scene_to_file(MENU_SCENE)


## Closes the connection and exits the game process.
func quit_game() -> void:
	_shutdown_network()
	get_tree().quit()


## Server-only: disconnects `peer_id` and tells it why.
func kick_player(peer_id: int) -> void:
	if not is_host() or peer_id == 1:
		return
	if not players.has(peer_id):
		return
	# Broadcast the new roster while every peer is still connected: a peer that
	# has been queued for disconnect reports 0 channels and rejects packets.
	players.erase(peer_id)
	_sync_players.rpc(players)
	_kicked.rpc_id(peer_id, "Вас исключил хост.")
	_disconnect_after_flush(peer_id)


## Gives the reliable kick message a moment to reach the client, then drops the
## link if the client did not close it itself.
func _disconnect_after_flush(peer_id: int) -> void:
	await get_tree().create_timer(0.25).timeout
	var peer := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if peer == null or not multiplayer.get_peers().has(peer_id):
		return
	peer.disconnect_peer(peer_id, true)


func _shutdown_network() -> void:
	game_started = false
	players.clear()
	characters.clear()
	var peer := multiplayer.multiplayer_peer
	if peer is ENetMultiplayerPeer:
		peer.close()
	multiplayer.multiplayer_peer = null


# --- Client -> server -------------------------------------------------------

@rpc("any_peer", "reliable")
func register_player(nick: String) -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if game_started:
		_kicked.rpc_id(sender_id, "Игра уже началась, подключение отклонено.")
		return

	var clean := nick.strip_edges().left(16)
	if clean.is_empty():
		clean = "Игрок %d" % sender_id
	if _is_nick_taken(clean, sender_id):
		_kicked.rpc_id(sender_id, "Никнейм «%s» уже занят. Выберите другой." % clean)
		return
	players[sender_id] = clean
	_sync_players.rpc(players)


## Client -> server: the character chosen before joining. The payload is
## rebuilt and validated here, then stored in its server-computed form; the
## derived numbers a client sends are never trusted.
@rpc("any_peer", "reliable")
func register_character(payload: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if not players.has(sender_id):
		return

	# Joining without a character is allowed: the host simply cannot start.
	if payload.is_empty():
		characters.erase(sender_id)
		_sync_characters.rpc(characters)
		return

	var validated := _validated_character_payload(payload)
	if validated.is_empty():
		characters.erase(sender_id)
		_sync_characters.rpc(characters)
		_kicked.rpc_id(sender_id, "Сервер отклонил персонажа. Создайте его заново.")
		return

	characters[sender_id] = validated
	_sync_characters.rpc(characters)


## Rebuilds and validates a payload, returning the canonical server-side copy
## or an empty Dictionary when the build is incomplete/inconsistent.
func _validated_character_payload(payload: Dictionary) -> Dictionary:
	var draft := CharacterDraft.from_payload(payload)
	if draft == null or not draft.validate().is_empty():
		return {}
	return draft.to_payload()


## Returns true when another peer in the lobby already uses `nick` (case-insensitive).
func _is_nick_taken(nick: String, except_peer: int) -> bool:
	var needle := nick.to_lower()
	for peer_id in players:
		if int(peer_id) == except_peer:
			continue
		if str(players[peer_id]).to_lower() == needle:
			return true
	return false


# --- Server -> clients ------------------------------------------------------

@rpc("authority", "reliable", "call_local")
func _sync_players(new_players: Dictionary) -> void:
	players = new_players
	players_updated.emit(players)


@rpc("authority", "reliable", "call_local")
func _sync_characters(new_characters: Dictionary) -> void:
	characters = new_characters
	characters_updated.emit(characters)


@rpc("authority", "reliable", "call_local")
func _load_game() -> void:
	get_tree().change_scene_to_file(GAME_SCENE)


@rpc("authority", "reliable")
func _kicked(reason: String) -> void:
	last_message = reason
	last_message_is_error = true
	_shutdown_network()
	disconnected.emit()


# --- MultiplayerAPI callbacks ----------------------------------------------

func _on_peer_connected(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	# Send the current lobby immediately; the nickname arrives right after.
	_sync_players.rpc_id(peer_id, players)
	_sync_characters.rpc_id(peer_id, characters)


func _on_peer_disconnected(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	players.erase(peer_id)
	characters.erase(peer_id)
	_sync_players.rpc(players)
	_sync_characters.rpc(characters)


func _on_connected_to_server() -> void:
	register_player.rpc_id(1, nickname)
	register_character.rpc_id(1, PlayerProfile.to_payload())
	lobby_joined.emit()


func _on_connection_failed() -> void:
	multiplayer.multiplayer_peer = null
	connection_failed.emit()


func _on_server_disconnected() -> void:
	if last_message.is_empty():
		last_message = "Сервер закрыл соединение."
	last_message_is_error = true
	_shutdown_network()
	# Explicitly reset the client-side roster so every listener sees the lobby empty.
	players_updated.emit(players)
	disconnected.emit()
