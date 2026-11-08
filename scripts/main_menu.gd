extends Control
## Lobby UI: nickname entry, HOST / JOIN / START / EXIT and the live player list.

@onready var nickname_edit: LineEdit = $CenterContainer/Panel/Content/NicknameRow/NicknameEdit
@onready var address_edit: LineEdit = $CenterContainer/Panel/Content/AddressRow/AddressEdit
@onready var status_label: Label = $CenterContainer/Panel/Content/StatusLabel
@onready var host_button: Button = $CenterContainer/Panel/Content/Buttons/HostButton
@onready var join_button: Button = $CenterContainer/Panel/Content/Buttons/JoinButton
@onready var start_button: Button = $CenterContainer/Panel/Content/Buttons/StartButton
@onready var exit_button: Button = $CenterContainer/Panel/Content/Buttons/ExitButton
@onready var player_list: VBoxContainer = $CenterContainer/Panel/Content/PlayerScroll/PlayerList
@onready var player_count: Label = $CenterContainer/Panel/Content/PlayersHeader/PlayerCount
@onready var character_summary: Label = $CenterContainer/Panel/Content/CharacterRow/CharacterSummary
@onready var character_button: Button = $CenterContainer/Panel/Content/CharacterRow/CharacterButton

const CHARACTER_SCENE: String = "res://scenes/CharacterCreation.tscn"


func _ready() -> void:
	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)
	start_button.pressed.connect(_on_start_pressed)
	exit_button.pressed.connect(_on_exit_pressed)
	character_button.pressed.connect(_on_character_pressed)
	nickname_edit.text_submitted.connect(_on_nickname_submitted)

	NetworkManager.players_updated.connect(_refresh_players)
	NetworkManager.characters_updated.connect(_on_characters_updated)
	NetworkManager.lobby_joined.connect(_on_lobby_joined)
	NetworkManager.connection_failed.connect(_on_connection_failed)
	NetworkManager.disconnected.connect(_on_disconnected)

	_reset_buttons()
	_refresh_players(NetworkManager.players)
	_refresh_character()

	# Returning from character creation (or a resized menu) must not drop an
	# already open lobby: restore the joined state instead of resetting it.
	if NetworkManager.is_online():
		nickname_edit.text = NetworkManager.nickname
		_on_lobby_joined()
		# Return from character creation while connected: push the edited
		# character to the server so the lobby and the spawn payload are fresh.
		NetworkManager.sync_own_character()

	if not NetworkManager.last_message.is_empty():
		_set_status(NetworkManager.last_message, NetworkManager.last_message_is_error)
		NetworkManager.last_message = ""
	elif not NetworkManager.is_online():
		_set_status("Введите никнейм и нажмите HOST или JOIN.")

	nickname_edit.grab_focus()


func _on_nickname_submitted(_text: String) -> void:
	if NetworkManager.is_online():
		return
	_on_host_pressed()


func _on_host_pressed() -> void:
	if NetworkManager.is_host():
		return
	var nick := _read_nickname()
	if nick.is_empty():
		return
	var err := NetworkManager.host_game(nick)
	if err != OK:
		_set_status("Не удалось запустить сервер. Порт %d уже занят?" % NetworkManager.PORT, true)
		return
	_set_status("Сервер запущен. Ожидание игроков...")


func _on_join_pressed() -> void:
	if NetworkManager.is_online():
		return
	var nick := _read_nickname()
	if nick.is_empty():
		return
	var address := address_edit.text.strip_edges()
	if address.is_empty():
		address = "127.0.0.1"
	var err := NetworkManager.join_game(nick, address)
	if err != OK:
		_set_status("Не удалось начать подключение к %s." % address, true)
		return

	host_button.disabled = true
	join_button.disabled = true
	start_button.visible = false
	nickname_edit.editable = false
	address_edit.editable = false
	_set_status("Подключение к %s:%d..." % [address, NetworkManager.PORT])


func _on_start_pressed() -> void:
	if not NetworkManager.is_host():
		return
	if not PlayerProfile.has_character():
		_set_status("Сначала создайте персонажа: кнопка ПЕРСОНАЖ.", true)
		return
	var error := NetworkManager.start_game()
	if not error.is_empty():
		_set_status(error, true)


func _on_character_pressed() -> void:
	get_tree().change_scene_to_file(CHARACTER_SCENE)


func _refresh_character() -> void:
	character_summary.text = PlayerProfile.summary_line()
	if PlayerProfile.has_character():
		character_summary.add_theme_color_override("font_color", Color(0.7, 0.85, 0.75))
	else:
		character_summary.add_theme_color_override("font_color", Color(0.8, 0.6, 0.55))


func _on_exit_pressed() -> void:
	get_tree().quit()


func _on_lobby_joined() -> void:
	host_button.disabled = true
	join_button.disabled = true
	nickname_edit.editable = false
	address_edit.editable = false
	start_button.visible = NetworkManager.is_host()
	start_button.disabled = false

	if NetworkManager.is_host():
		_set_status("Сервер запущен. Ожидание игроков...")
	else:
		_set_status("Подключено к лобби. Ждём, пока хост начнёт игру...")
	_refresh_players(NetworkManager.players)


func _on_connection_failed() -> void:
	_reset_buttons()
	_refresh_players(NetworkManager.players)
	_set_status("Не удалось подключиться к серверу.", true)


func _on_disconnected() -> void:
	_reset_buttons()
	_refresh_players(NetworkManager.players)
	var message := NetworkManager.last_message
	if message.is_empty():
		message = "Соединение потеряно."
	_set_status(message, true)
	NetworkManager.last_message = ""


func _reset_buttons() -> void:
	host_button.disabled = false
	join_button.disabled = false
	start_button.visible = false
	start_button.disabled = false
	nickname_edit.editable = true
	address_edit.editable = true


func _read_nickname() -> String:
	var nick := nickname_edit.text.strip_edges()
	if nick.is_empty():
		_set_status("Сначала введите никнейм.", true)
		nickname_edit.grab_focus()
		return ""
	if nick.length() > 16:
		nick = nick.left(16)
		nickname_edit.text = nick
	return nick


func _set_status(message: String, is_error: bool = false) -> void:
	status_label.text = message
	if is_error:
		status_label.add_theme_color_override("font_color", Color(0.95, 0.45, 0.4))
	else:
		status_label.add_theme_color_override("font_color", Color(0.55, 0.85, 0.65))


func _refresh_players(players: Dictionary) -> void:
	for child in player_list.get_children():
		player_list.remove_child(child)
		child.queue_free()

	var ids: Array = players.keys()
	ids.sort()
	var my_id: int = multiplayer.get_unique_id() if NetworkManager.is_online() else -1
	var is_host := NetworkManager.is_host()

	for id in ids:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)

		var dot := Label.new()
		dot.text = "●"
		dot.add_theme_color_override("font_color", Color(0.4, 0.85, 0.55))
		row.add_child(dot)

		var name_label := Label.new()
		name_label.text = str(players[id])
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if int(id) == my_id:
			name_label.text += "  (вы)"
		row.add_child(name_label)

		var role := Label.new()
		role.text = "хост" if int(id) == 1 else "клиент"
		role.add_theme_color_override("font_color", Color(0.55, 0.65, 0.8))
		row.add_child(role)

		var payload: Dictionary = NetworkManager.characters.get(int(id), {})
		if payload.is_empty():
			var missing := Label.new()
			missing.text = "нет персонажа"
			missing.add_theme_color_override("font_color", Color(0.95, 0.68, 0.4))
			missing.add_theme_font_size_override("font_size", 12)
			row.add_child(missing)

		if is_host and int(id) != 1:
			var kick_button := Button.new()
			kick_button.text = "Кик"
			kick_button.tooltip_text = "Исключить игрока из лобби"
			kick_button.custom_minimum_size = Vector2(56, 0)
			kick_button.add_theme_font_size_override("font_size", 12)
			kick_button.pressed.connect(_on_kick_pressed.bind(int(id)))
			row.add_child(kick_button)

		player_list.add_child(row)

	player_count.text = str(players.size())


func _on_kick_pressed(peer_id: int) -> void:
	if not NetworkManager.is_host():
		return
	var nick := str(NetworkManager.players.get(peer_id, "Игрок"))
	NetworkManager.kick_player(peer_id)
	_set_status("Игрок «%s» исключён." % nick)


## Characters stream in after the nickname, so refresh the list when they do.
func _on_characters_updated(_characters: Dictionary) -> void:
	_refresh_players(NetworkManager.players)
