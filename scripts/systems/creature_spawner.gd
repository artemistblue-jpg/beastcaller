extends Node3D

## Owns one fixed location in the world. Keeps a creature alive there,
## and — once it's tamed or killed — brings a fresh one back after a
## cooldown instead of leaving that spot empty forever.
##
## The respawn cooldown is persisted through SaveManager as an absolute
## timestamp, so it keeps counting down (or finishes outright) even
## across a full game restart — check back on the game later and the
## world has repopulated while you were away.

@export var creature_scene: PackedScene
@export var respawn_delay: float = 45.0

var _respawn_remaining: float = 0.0
var _waiting_to_respawn: bool = false


func _ready() -> void:
	var saved_state := SaveManager.get_spawner_state(name)
	if saved_state.has("respawn_ready_at"):
		var remaining: float = float(saved_state["respawn_ready_at"]) - Time.get_unix_time_from_system()
		if remaining > 0.0:
			_begin_respawn_wait(remaining, false)
			return
	_spawn_creature()


func _process(delta: float) -> void:
	if not _waiting_to_respawn:
		return
	_respawn_remaining -= delta
	if _respawn_remaining <= 0.0:
		_waiting_to_respawn = false
		SaveManager.clear_spawner_state(name)
		_spawn_creature()


## Called by the spawned creature itself (see creature_ai.gd and
## wild_monster.gd) the instant it's tamed or killed.
func notify_creature_removed() -> void:
	_begin_respawn_wait(respawn_delay, true)


func _spawn_creature() -> void:
	if creature_scene == null:
		return
	var instance := creature_scene.instantiate()
	add_child(instance)


func _begin_respawn_wait(seconds: float, persist: bool) -> void:
	_waiting_to_respawn = true
	_respawn_remaining = seconds
	if persist:
		var ready_at: float = Time.get_unix_time_from_system() + seconds
		SaveManager.set_spawner_state(name, {"respawn_ready_at": ready_at})
