extends CanvasLayer
## In-game Esc menu: resume, return to the lobby (disconnect) or quit the game.
##
## The layer runs with PROCESS_MODE_ALWAYS so it keeps receiving input while
## the rest of the scene tree is paused.

@onready var resume_button: Button = $Center/Panel/Content/ResumeButton
@onready var lobby_button: Button = $Center/Panel/Content/LobbyButton
@onready var quit_button: Button = $Center/Panel/Content/QuitButton


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	resume_button.pressed.connect(close)
	lobby_button.pressed.connect(_on_lobby_pressed)
	quit_button.pressed.connect(_on_quit_pressed)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if visible:
			close()
		else:
			open()
		get_viewport().set_input_as_handled()


func open() -> void:
	visible = true
	get_tree().paused = true
	resume_button.grab_focus()


func close() -> void:
	visible = false
	get_tree().paused = false


func _on_lobby_pressed() -> void:
	close()
	NetworkManager.return_to_menu("Вы вышли в лобби.", false)


func _on_quit_pressed() -> void:
	NetworkManager.quit_game()
