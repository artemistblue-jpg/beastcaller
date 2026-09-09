extends Node3D

## Restores whatever was saved the moment the world loads: the player's
## position/health and the tamed-monster roster (respawning the active
## squad next to them). Each CreatureSpawner restores its own respawn
## cooldown independently — see creature_spawner.gd.


func _ready() -> void:
	# Deferred so every child (Player, spawners, etc.) has already run
	# its own _ready() — in particular so the player has registered
	# itself in the "player" group before we go looking for it.
	call_deferred("_apply_save_data")


func _apply_save_data() -> void:
	var data := SaveManager.loaded_save
	if data.is_empty():
		return

	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return
	var player: Node3D = players[0]

	_apply_player_data(player, data.get("player", {}))
	_apply_roster_data(data.get("roster", {}), player)


func _apply_player_data(player: Node3D, player_data: Dictionary) -> void:
	if player_data.has("position"):
		var pos: Array = player_data["position"]
		if pos.size() == 3:
			var restored_position := Vector3(pos[0], pos[1], pos[2])
			player.global_position = restored_position
			# Keep the fall-back respawn point in sync so dying right
			# after a load doesn't teleport back to the map's spawn.
			if "respawn_position" in player:
				player.respawn_position = restored_position

	if player_data.has("health") and player.has_node("HealthComponent"):
		var health: HealthComponent = player.get_node("HealthComponent")
		health.current_health = clamp(float(player_data["health"]), 0.0, health.max_health)
		health.health_changed.emit(health.current_health, health.max_health)


func _apply_roster_data(roster_data: Dictionary, player: Node3D) -> void:
	if roster_data.has("collection"):
		MonsterRoster.collection = _to_dict_array(roster_data["collection"])
	if roster_data.has("active_squad"):
		MonsterRoster.active_squad = _to_dict_array(roster_data["active_squad"])

	MonsterRoster.roster_changed.emit()

	if MonsterRoster.active_squad.size() > 0:
		MonsterRoster.spawn_squad(player)


func _to_dict_array(raw: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry in raw:
		if entry is Dictionary:
			result.append(entry)
	return result
