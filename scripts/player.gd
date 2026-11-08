class_name PlayerCharacter
extends CharacterBody3D
## Networked top-down controller.
##
## The owning peer reads input and moves the body. Remote peers receive a
## low-frequency authoritative state RPC and interpolate towards it.
## Movement is aligned to the fixed Hades-style camera, so the camera never
## rotates with the player; the body turns towards the movement direction.
##
## Character stats (HP, AC, skills, speed) arrive in the spawn payload from
## CharacterDraft.to_payload() and are exposed for the HUD and future combat.

signal health_changed(current: int, maximum: int)
signal combat_message(text: String, hit: bool)

@export var move_speed: float = 6.0
@export var ground_acceleration: float = 60.0
@export var air_acceleration: float = 18.0
@export var jump_velocity: float = 5.5
@export var turn_speed: float = 14.0
@export var sync_rate: float = 20.0
## How quickly a remote copy converges on the predicted position (per second).
@export var remote_smoothing: float = 12.0
## How far ahead (seconds) a remote copy may extrapolate after the last snapshot.
@export var max_extrapolation: float = 0.25
## Weight of each new snapshot when estimating remote velocity (0..1).
@export var velocity_smoothing: float = 0.35

## Golden-ratio hue step. Deriving the hue from the peer id gives every peer a
## distinct colour, unlike hashing the nickname (hashes can collide).
const HUE_STEP: float = 0.618033988749895

## Set by the spawn function before the node enters the tree.
var nickname: String = "Игрок"
var slot: int = 0
## Character payload from CharacterDraft.to_payload(); empty in a bare test.
var character: Dictionary = {}

## Derived character stats, filled from `character.derived`.
var hero_class: String = ""
var level: int = 1
var max_hp: int = 1
var current_hp: int = 1
var armor_class: int = 10
var passive_perception: int = 10
var speed_ft: int = 30
var skills: Dictionary = {}
var saves: Dictionary = {}
var ability_scores: Dictionary = {}
var proficiency_bonus_value: int = 2
var armor_training: Array = []
var weapon_training: Array = []

## Combat state. The server owns damage and death; the owner only sends input.
const ATTACK_COOLDOWN_MS: int = 600
const RESPAWN_DELAY: float = 3.0

var weapon_id: StringName = &"unarmed"
var weapon: Dictionary = WeaponTable.get_weapon(&"unarmed")
var is_alive: bool = true

var _last_attack_ms: int = -ATTACK_COOLDOWN_MS
var _rng := RandomNumberGenerator.new()

@onready var name_label: Label3D = $NameLabel
@onready var health_label: Label3D = $HealthLabel
@onready var body: MeshInstance3D = $Body
@onready var visor: MeshInstance3D = $Visor

var _gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
var _sync_timer: float = 0.0
var _remote_position: Vector3 = Vector3.ZERO
var _remote_velocity: Vector3 = Vector3.ZERO
var _remote_yaw: float = 0.0
var _has_remote_target: bool = false
var _last_sync_time: float = 0.0
var _time_since_sync: float = 0.0


func _ready() -> void:
	_rng.randomize()
	_apply_character()
	name_label.text = nickname
	global_position = _slot_position(slot)
	_apply_body_color()
	_update_health_label()


## Reads the validated character payload. The lobby nickname is a fallback for
## a bare character-less spawn (headless scene tests, join without a hero).
func _apply_character() -> void:
	var hero_name := str(character.get("name", "")).strip_edges()
	if not hero_name.is_empty():
		nickname = hero_name

	var derived: Variant = character.get("derived", {})
	if not (derived is Dictionary) or derived.is_empty():
		return

	hero_class = str(character.get("class_name", ""))
	level = maxi(1, int(character.get("level", 1)))
	max_hp = maxi(1, int(derived.get("hp", 1)))
	current_hp = max_hp
	armor_class = int(derived.get("ac", 10))
	passive_perception = int(derived.get("passive_perception", 10))
	speed_ft = int(derived.get("speed_ft", 30))
	move_speed = float(speed_ft) * 0.2
	proficiency_bonus_value = int(derived.get("proficiency", 2))

	var skill_value: Variant = derived.get("skills", {})
	if skill_value is Dictionary:
		skills = skill_value
	var save_value: Variant = derived.get("saves", {})
	if save_value is Dictionary:
		saves = save_value
	var scores_value: Variant = derived.get("scores", {})
	if scores_value is Dictionary:
		ability_scores = scores_value
	var armor_value: Variant = derived.get("armor_training", [])
	if armor_value is Array:
		armor_training = armor_value
	var weapons_value: Variant = derived.get("weapon_training", [])
	if weapons_value is Array:
		weapon_training = weapons_value

	_choose_weapon(derived)


## Picks the strongest weapon found in the starting equipment. Unknown items
## are skipped, so a caster with only a staff/dagger still gets a sensible arm.
func _choose_weapon(derived: Dictionary) -> void:
	var equipment: Variant = derived.get("equipment", [])
	var best_score := -1.0
	if equipment is Array:
		for entry in equipment:
			if not (entry is Dictionary):
				continue
			var item_id := StringName(str(entry.get("item_id", "")))
			if not WeaponTable.has_weapon(item_id):
				continue
			var candidate := WeaponTable.get_weapon(item_id)
			var score := float(candidate.get("count", 1)) * (float(candidate.get("faces", 1)) + 1.0) * 0.5
			if score > best_score:
				best_score = score
				weapon_id = item_id
	weapon = WeaponTable.get_weapon(weapon_id)


func _physics_process(delta: float) -> void:
	if not _is_authority():
		return
	if not is_alive:
		velocity = Vector3.ZERO
		return

	if not is_on_floor():
		velocity.y -= _gravity * delta

	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity

	# Fixed camera: W always moves up the screen (-Z), A/D across the screen.
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := Vector3(input_dir.x, 0.0, input_dir.y)
	var target := direction * move_speed
	var acceleration := ground_acceleration if is_on_floor() else air_acceleration

	velocity.x = move_toward(velocity.x, target.x, acceleration * delta)
	velocity.z = move_toward(velocity.z, target.z, acceleration * delta)

	# The body faces where it walks; a child node could hold a model instead.
	if direction.length_squared() > 0.0001:
		var target_yaw := atan2(-direction.x, -direction.z)
		rotation.y = lerp_angle(rotation.y, target_yaw, minf(1.0, turn_speed * delta))

	move_and_slide()

	_sync_timer += delta
	if _sync_timer >= 1.0 / sync_rate:
		_sync_timer = 0.0
		_sync_state.rpc(global_position, rotation.y)


func _process(delta: float) -> void:
	# Only remote copies interpolate; the authority is driven by physics.
	if _is_authority() or not _has_remote_target:
		return
	_time_since_sync += delta

	# Predict a little ahead of the last snapshot so a dropped packet does not
	# make the remote body freeze. Vertical motion is not extrapolated: without
	# the jump curve it would float or dig into the ground.
	var ahead := minf(_time_since_sync, max_extrapolation)
	var predicted := _remote_position
	predicted.x += _remote_velocity.x * ahead
	predicted.z += _remote_velocity.z * ahead

	var weight := minf(1.0, remote_smoothing * delta)
	global_position = global_position.lerp(predicted, weight)
	rotation.y = lerp_angle(rotation.y, _remote_yaw, weight)


func _is_authority() -> bool:
	return multiplayer.has_multiplayer_peer() and is_multiplayer_authority()


func _unhandled_input(event: InputEvent) -> void:
	if not _is_authority() or not is_alive:
		return
	if event.is_action_pressed("attack"):
		request_attack.rpc_id(1)
		get_viewport().set_input_as_handled()


# --- combat -----------------------------------------------------------------

## Client -> server. The server resolves the attack, so reach, cooldown, AC and
## damage are authoritative; the owner only sends the intent.
@rpc("any_peer", "reliable")
func request_attack() -> void:
	if not multiplayer.is_server() or not is_alive:
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != get_multiplayer_authority():
		return
	var now := Time.get_ticks_msec()
	if now - _last_attack_ms < ATTACK_COOLDOWN_MS:
		return
	_last_attack_ms = now

	play_swing.rpc()
	var target := _find_target()
	if target == null:
		_notify_attacker("В радиусе атаки никого нет.", false)
		return

	var natural := _rng.randi_range(1, 20)
	var total := natural + attack_bonus()
	var hit := natural != 1 and (natural == 20 or total >= target.armor_class)

	if not hit:
		_notify_attacker("Промах по «%s»: %d против КД %d." % [target.nickname, total, target.armor_class], false)
		return

	var critical := natural == 20
	var damage := roll_damage(critical)
	target.receive_damage.rpc(damage)
	_notify_attacker("%s «%s»: %d урона." % [
		"Критическое попадание по" if critical else "Попадание по",
		target.nickname,
		damage,
	], true)


func _notify_attacker(text: String, hit: bool) -> void:
	var owner_id := get_multiplayer_authority()
	if owner_id == multiplayer.get_unique_id():
		# The host's own node: call directly, an RPC to yourself is rejected.
		combat_result(text, hit)
	else:
		combat_result.rpc_id(owner_id, text, hit)


@rpc("any_peer", "reliable")
func combat_result(text: String, hit: bool) -> void:
	if not _rpc_from_server():
		return
	combat_message.emit(text, hit)


@rpc("any_peer", "call_local", "unreliable")
func play_swing() -> void:
	if not _rpc_from_server() or not is_alive:
		return
	var tween := create_tween()
	tween.tween_property(body, "rotation:x", -0.5, 0.08)
	tween.tween_property(body, "rotation:x", 0.0, 0.16)


## Server -> everyone. Applies damage on every peer; the server also schedules
## the respawn after the death timer.
@rpc("any_peer", "call_local", "reliable")
func receive_damage(amount: int) -> void:
	if not _rpc_from_server() or amount <= 0:
		return
	_set_hp_local(current_hp - amount)
	if current_hp == 0 and multiplayer.is_server():
		_respawn_after_delay()


@rpc("any_peer", "call_local", "reliable")
func respawn_at(position: Vector3, hp: int) -> void:
	if not _rpc_from_server():
		return
	global_position = position
	_set_hp_local(maxi(1, hp))
	_set_alive(true)


func _respawn_after_delay() -> void:
	await get_tree().create_timer(RESPAWN_DELAY).timeout
	if not is_inside_tree():
		return
	respawn_at.rpc(_slot_position(slot), max_hp)


func _find_target() -> PlayerCharacter:
	var best: PlayerCharacter = null
	var best_distance := INF
	var attack_range := float(weapon.get("range", 2.2))
	for node in get_parent().get_children():
		if node == self or not (node is PlayerCharacter):
			continue
		var other := node as PlayerCharacter
		if not other.is_alive:
			continue
		var distance := Vector2(global_position.x, global_position.z).distance_to(
			Vector2(other.global_position.x, other.global_position.z)
		)
		if distance <= attack_range and distance < best_distance:
			best = other
			best_distance = distance
	return best


func ability_modifier_for(ability: StringName) -> int:
	return floori(float(int(ability_scores.get(String(ability), 10)) - 10) / 2.0)


func attack_ability() -> StringName:
	if bool(weapon.get("ranged", false)):
		return &"dexterity"
	if bool(weapon.get("finesse", false)):
		var dexterity := ability_modifier_for(&"dexterity")
		var strength := ability_modifier_for(&"strength")
		return &"dexterity" if dexterity > strength else &"strength"
	return StringName(weapon.get("ability", "strength"))


func attack_bonus() -> int:
	var bonus := ability_modifier_for(attack_ability())
	if WeaponTable.is_proficient(weapon, weapon_training):
		bonus += proficiency_bonus_value
	return bonus


func damage_modifier() -> int:
	return ability_modifier_for(attack_ability())


## Rolls the weapon dice. A critical doubles the dice, not the ability modifier.
func roll_damage(critical: bool = false) -> int:
	var count := int(weapon.get("count", 1)) * (2 if critical else 1)
	var total := damage_modifier()
	for _index in count:
		total += _rng.randi_range(1, int(weapon.get("faces", 1)))
	return maxi(1, total)


## True when the RPC came from the server (or was called locally on the host).
func _rpc_from_server() -> bool:
	if not multiplayer.has_multiplayer_peer():
		return true
	var sender := multiplayer.get_remote_sender_id()
	if multiplayer.is_server():
		# Local calls can report either 0 or the server's own id, depending on
		# whether the RPC was invoked with call_local. Remote clients are never
		# allowed to drive damage/respawns/swings on the server.
		return sender == 0 or sender == multiplayer.get_unique_id()
	return sender == 1


## Character-sheet API for scripts/tests; only this peer may change its HP.
func set_hp(value: int) -> void:
	if not _is_authority():
		return
	_set_hp_local(value)


func _set_hp_local(value: int) -> void:
	current_hp = clampi(value, 0, max_hp)
	health_changed.emit(current_hp, max_hp)
	_update_health_label()
	if current_hp == 0:
		_set_alive(false)


func apply_damage(amount: int) -> void:
	if amount > 0:
		set_hp(current_hp - amount)


func heal(amount: int) -> void:
	if amount > 0:
		set_hp(current_hp + amount)


func _set_alive(value: bool) -> void:
	if is_alive == value:
		return
	is_alive = value
	body.visible = value
	visor.visible = value
	velocity = Vector3.ZERO
	_update_health_label()
	if not _is_authority():
		return
	if value:
		combat_message.emit("Вы возрождены.", true)
	else:
		combat_message.emit("Вы погибли. Возрождение через %.0f с." % RESPAWN_DELAY, false)


func _update_health_label() -> void:
	if not is_instance_valid(health_label):
		return
	if is_alive:
		health_label.text = "HP %d / %d" % [current_hp, max_hp]
	else:
		health_label.text = "погиб"


@rpc("authority", "call_local", "unreliable_ordered", 1)
func _sync_state(new_position: Vector3, yaw: float) -> void:
	if _is_authority():
		return
	var now := Time.get_ticks_msec() / 1000.0

	if _has_remote_target:
		var sample_delta := now - _last_sync_time
		# Ignore samples after long stalls (pause, lag spike): the derived
		# velocity would be meaningless and could launch the copy away.
		if sample_delta > 0.001 and sample_delta < 0.25:
			var measured := (new_position - _remote_position) / sample_delta
			measured.y = 0.0
			var max_speed := move_speed * 2.0
			if measured.length() > max_speed:
				measured = measured.limit_length(max_speed)
			_remote_velocity = _remote_velocity.lerp(measured, velocity_smoothing)

	_remote_position = new_position
	_remote_yaw = yaw
	_last_sync_time = now
	_time_since_sync = 0.0
	_has_remote_target = true


func _slot_position(slot_index: int) -> Vector3:
	var angle := float(slot_index) * TAU / float(NetworkManager.MAX_CLIENTS)
	return Vector3(cos(angle) * 4.0, 0.05, sin(angle) * 4.0)


func _apply_body_color() -> void:
	var hue := fposmod(float(get_multiplayer_authority()) * HUE_STEP, 1.0)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color.from_hsv(hue, 0.62, 0.95)
	material.roughness = 0.6
	body.material_override = material
