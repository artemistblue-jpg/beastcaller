extends Node

## Autoload singleton: owns the single save file for the whole game.
## Tracks the player's position/health, the tamed-monster roster, and
## which hand-placed world creatures have already been killed or
## captured — so progress survives a restart, a phone lock, or the app
## getting backgrounded.

const SAVE_PATH := "user://savegame.json"
const AUTOSAVE_INTERVAL := 30.0

## Names of Creatures-node children that no longer exist in the world
## (tamed or killed). Seeded from the save file on load, appended to as
## the game is played.
var removed_creatures: Array[String] = []

@onready var _autosave_timer: Timer = Timer.new()


func _ready() -> void:
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


## Called by a creature the instant it's tamed or killed, so a reload
## never brings back something the player already dealt with.
func mark_creature_removed(creature_name: String) -> void:
	if creature_name in removed_creatures:
		return
	removed_creatures.append(creature_name)
	save_game()


## Used only while applying a loaded save, before gameplay has had a
## chance to append anything of its own — fills the list without
## triggering a redundant save.
func seed_removed_creatures(names: Array) -> void:
	for raw_name in names:
		var creature_name := String(raw_name)
		if creature_name not in removed_creatures:
			removed_creatures.append(creature_name)


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
		"removed_creatures": removed_creatures,
	}

	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("SaveManager: failed to open save file for writing.")
		return
	file.store_string(JSON.stringify(save_data))
	file.close()


## Returns the parsed save Dictionary, or an empty Dictionary if there's
## no save yet or it couldn't be read.
func load_game() -> Dictionary:
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
