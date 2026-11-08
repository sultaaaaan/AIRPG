extends Node3D
## 3D arena. The server owns spawning; MultiplayerSpawner replicates players.
## A single fixed top-down camera follows the local player (Hades-style).

const PLAYER_SCENE: PackedScene = preload("res://scenes/Player.tscn")
## Height 14 and 9 units behind produce a ~58 degree downward view.
const CAMERA_OFFSET := Vector3(0.0, 14.0, 9.0)
const CAMERA_FOLLOW_SPEED := 8.0

@onready var spawner: MultiplayerSpawner = $MultiplayerSpawner
@onready var players_root: Node3D = $Players
@onready var arena_camera: Camera3D = $ArenaCamera
@onready var stats_title: Label = $HUD/StatsPanel/Margin/Stats/Title
@onready var stats_vitals: Label = $HUD/StatsPanel/Margin/Stats/Vitals
@onready var stats_skills: Label = $HUD/StatsPanel/Margin/Stats/Skills
@onready var combat_log: Label = $HUD/CombatLog
@onready var interact_hint: Label = $HUD/InteractHint
@onready var nearby_panel: NearbyPanel = $HUD/NearbyPanel
@onready var inventory_panel: InventoryPanel = $InventoryPanel

var _next_slot: int = 0
var _ready_peers: Dictionary = {}
var _local_player: PlayerCharacter = null
var _stats_player: PlayerCharacter = null
var _nearest_interactable: Node = null


func _ready() -> void:
	get_tree().paused = false
	spawner.spawn_function = _spawn_player_node
	# Fixed Hades-style angle: ~58 degrees down, no yaw.
	arena_camera.rotation_degrees = Vector3(-58.0, 0.0, 0.0)
	NetworkManager.players_updated.connect(_on_players_updated)
	NetworkManager.disconnected.connect(_on_network_disconnected)
	inventory_panel.toggled.connect(_on_inventory_toggled)

	if NetworkManager.is_online() and not NetworkManager.is_host():
		# Client: tell the server this scene (and its spawner) exists.
		notify_game_ready.rpc_id(1)
	else:
		# Server, or a standalone headless run with no ENet peer.
		_ready_peers[1] = true
		_try_spawn_all()


func _process(delta: float) -> void:
	if not is_instance_valid(_local_player):
		_local_player = _find_local_player()
	if _local_player == null:
		_nearest_interactable = null
		interact_hint.text = ""
		nearby_panel.set_pickups([])
		return
	if _local_player != _stats_player:
		_bind_stats(_local_player)
	_update_interaction_prompt()

	# Follow only horizontally so jumps do not bounce the camera.
	var target := Vector3(
		_local_player.global_position.x + CAMERA_OFFSET.x,
		CAMERA_OFFSET.y,
		_local_player.global_position.z + CAMERA_OFFSET.z
	)
	arena_camera.global_position = arena_camera.global_position.lerp(
		target, minf(1.0, CAMERA_FOLLOW_SPEED * delta)
	)


func _find_local_player() -> PlayerCharacter:
	for child in players_root.get_children():
		if child is PlayerCharacter and child.is_multiplayer_authority():
			return child
	return null


# --- stats HUD ---------------------------------------------------------------

func _bind_stats(hero: PlayerCharacter) -> void:
	if _stats_player == hero:
		return
	if is_instance_valid(_stats_player):
		if _stats_player.health_changed.is_connected(_on_health_changed):
			_stats_player.health_changed.disconnect(_on_health_changed)
		if _stats_player.combat_message.is_connected(_on_combat_message):
			_stats_player.combat_message.disconnect(_on_combat_message)
		if _stats_player.equipment_changed.is_connected(_on_equipment_changed):
			_stats_player.equipment_changed.disconnect(_on_equipment_changed)
	_stats_player = hero
	if not hero.health_changed.is_connected(_on_health_changed):
		hero.health_changed.connect(_on_health_changed)
	if not hero.combat_message.is_connected(_on_combat_message):
		hero.combat_message.connect(_on_combat_message)
	if not hero.equipment_changed.is_connected(_on_equipment_changed):
		hero.equipment_changed.connect(_on_equipment_changed)
	inventory_panel.bind_player(hero)
	combat_log.text = ""
	_refresh_stats()


func _on_health_changed(_current: int, _maximum: int) -> void:
	_refresh_vitals()


func _on_equipment_changed() -> void:
	_refresh_vitals()


func _on_inventory_toggled(open: bool) -> void:
	if is_instance_valid(_local_player):
		_local_player.inventory_open = open


func _update_interaction_prompt() -> void:
	var pickups: Array = []
	var best: Node = null
	var best_distance := INF
	for node in get_tree().get_nodes_in_group("interactables"):
		if not node.has_method("is_available") or not node.is_available():
			continue
		var distance: float = _local_player.global_position.distance_to(node.global_position)
		if node is LootChest:
			if distance > LootChest.REACH:
				continue
		else:
			if distance > 3.0:
				continue
			pickups.append(node)
		if distance < best_distance:
			best = node
			best_distance = distance

	inventory_panel.set_nearby(pickups)
	nearby_panel.set_pickups([] if inventory_panel.visible else pickups)
	_nearest_interactable = best

	if inventory_panel.visible or best == null:
		interact_hint.text = ""
	elif best is LootChest:
		interact_hint.text = str(best.prompt_text())
	else:
		interact_hint.text = "E — предметы рядом (%d)" % pickups.size()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("interact"):
		return
	if inventory_panel.visible:
		inventory_panel.close()
		get_viewport().set_input_as_handled()
		return
	if _nearest_interactable == null:
		return

	if _nearest_interactable is LootChest:
		var chest := _nearest_interactable as LootChest
		chest.request_open()
		inventory_panel.open_container(chest)
	else:
		# Near ground items: open the two-column screen, left side lists them.
		inventory_panel.open_nearby()
	get_viewport().set_input_as_handled()


func _on_combat_message(text: String, hit: bool) -> void:
	combat_log.text = text
	combat_log.add_theme_color_override(
		"font_color",
		Color(0.6, 0.95, 0.7) if hit else Color(0.95, 0.72, 0.55)
	)


func _refresh_stats() -> void:
	if not is_instance_valid(_stats_player):
		return
	var title := _stats_player.nickname
	if not _stats_player.hero_class.is_empty():
		title += " · %s, %d ур." % [_stats_player.hero_class, _stats_player.level]
	stats_title.text = title
	_refresh_vitals()
	_refresh_skills()


func _refresh_vitals() -> void:
	if not is_instance_valid(_stats_player):
		return
	stats_vitals.text = "HP %d / %d    КД %d\nСкорость %d фт · Пасс. восприятие %d\nОружие: %s" % [
		_stats_player.current_hp,
		_stats_player.max_hp,
		_stats_player.armor_class,
		_stats_player.speed_ft,
		_stats_player.passive_perception,
		str(_stats_player.weapon.get("name", "Без оружия")),
	]


func _refresh_skills() -> void:
	if not is_instance_valid(_stats_player):
		return
	var trained: Array = _stats_player.skills.keys()
	trained.sort()
	var parts := PackedStringArray()
	for key in trained:
		parts.append("%s %+d" % [
			String(CharacterText.SKILL_NAMES_RU.get(StringName(str(key)), key)),
			int(_stats_player.skills[key]),
		])
	stats_skills.text = "Навыки: %s" % (", ".join(parts) if not parts.is_empty() else "—")


func _spawn_player_node(data: Dictionary) -> Node:
	var player := PLAYER_SCENE.instantiate()
	player.name = str(int(data.get("id", 1)))
	player.set_multiplayer_authority(int(data.get("id", 1)))
	player.nickname = str(data.get("nickname", "Игрок"))
	player.slot = int(data.get("slot", 0))
	player.character = data.get("character", {})
	if int(data.get("id", 1)) == multiplayer.get_unique_id():
		_local_player = player as PlayerCharacter
	return player


@rpc("any_peer", "reliable")
func notify_game_ready() -> void:
	if not NetworkManager.is_host():
		return
	_ready_peers[multiplayer.get_remote_sender_id()] = true
	_try_spawn_all()


func _try_spawn_all() -> void:
	for peer_id in NetworkManager.players:
		if not _ready_peers.has(int(peer_id)):
			return
	_on_players_updated(NetworkManager.players)


func _spawn_peer(peer_id: int) -> void:
	if players_root.get_node_or_null(str(peer_id)) != null:
		return
	spawner.spawn({
		"id": peer_id,
		"nickname": str(NetworkManager.players.get(peer_id, "Игрок")),
		"slot": _next_slot,
		"character": NetworkManager.characters.get(peer_id, {}),
	})
	_next_slot += 1


func _on_players_updated(players: Dictionary) -> void:
	if NetworkManager.is_online() and not NetworkManager.is_host():
		return

	# Despawn peers that left (MultiplayerSpawner mirrors this on clients).
	for child in players_root.get_children():
		if not players.has(int(str(child.name))):
			child.queue_free()

	for peer_id in players:
		if players_root.get_node_or_null(str(int(peer_id))) == null:
			_spawn_peer(int(peer_id))


func _on_network_disconnected() -> void:
	if NetworkManager.last_message.is_empty():
		NetworkManager.last_message = "Соединение с сервером потеряно."
	NetworkManager.last_message_is_error = true
	get_tree().paused = false
	get_tree().change_scene_to_file(NetworkManager.MENU_SCENE)
