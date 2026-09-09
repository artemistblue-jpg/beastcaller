extends Node

## Autoload singleton: owns the single save file for the whole game.
## Tracks the player's position/health, the tamed-monster roster, and
## every creature spawner's respawn cooldown — so progress survives a
## restart, a phone lock, or the app getting backgrounded.

const SAVE_PATH := "user://savegame.json"
const AUTOSAVE_INTERVAL := 30.0

## The save file as it was found at boot — read once here so every
## other script (player, spawners, world) can pull its own slice of it
## without each re-reading the file itself. As an autoload, this node's
## _ready() runs before any scene-tree node's, so it's always populated
## in time.
var loaded_save: Dictionary = {}

## Spawner node name -> {"respawn_ready_at": unix_time}. Only holds
## entries for spawners currently on cooldown; a spawner with no entry
## here is assumed to have a live creature.
var spawner_states: Dictionary = {}

@onready var _autosave_timer: Timer = Timer.new()


func _ready() -> void:
	loaded_save = _read_save_file()
	spawner_states = (loaded_save.get("spawners", {}) as Dictionary).duplicate(true)

	add_child(_autosave_timer)
	_autosave_timer.wait_time = AUTOSAVE_INTERVAL
	_autosave_timer.autostart = true
	_autosave_timer.timeout.connect(save_game)


## Catches the desktop window close button and, more importantly on
## mobile, the app being sent to the background (home button / app
## switch) — the most common way a phone player "quits" without a
## clean shutdown.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED:
		save_game()


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


## The spawner's saved state, or an empty Dictionary if it has none
## (meaning it should just spawn its creature normally).
func get_spawner_state(spawner_name: String) -> Dictionary:
	return (loaded_save.get("spawners", {}) as Dictionary).get(spawner_name, {})


func set_spawner_state(spawner_name: String, state: Dictionary) -> void:
	spawner_states[spawner_name] = state
	save_game()


func clear_spawner_state(spawner_name: String) -> void:
	if spawner_states.has(spawner_name):
		spawner_states.erase(spawner_name)
		save_game()


func save_game() -> void:
	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return
	var player: Node = players[0]

	var player_data: Dictionary = {
		"position": [
			player.global_position.x,
			player.global_position.y,
			player.global_position.z,
		],
	}
	if player.has_node("HealthComponent"):
		var health: HealthComponent = player.get_node("HealthComponent")
		player_data["health"] = health.current_health

	var save_data: Dictionary = {
		"player": player_data,
		"roster": {
			"collection": MonsterRoster.collection,
			"active_squad": MonsterRoster.active_squad,
		},
		"spawners": spawner_states,
	}

	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("SaveManager: failed to open save file for writing.")
		return
	file.store_string(JSON.stringify(save_data))
	file.close()


func _read_save_file() -> Dictionary:
	if not has_save():
		return {}

	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return {}
	var text := file.get_as_text()
	file.close()

	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed
