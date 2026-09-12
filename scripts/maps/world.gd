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

	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return
	var player: Node3D = players[0]

	if data.is_empty():
		_seed_starting_inventory()
		_play_intro_dialogue()
		return

	_apply_player_data(player, data.get("player", {}))
	_apply_roster_data(data.get("roster", {}), player)
	_apply_inventory_data(data.get("inventory", {}))
	_apply_gauntlet_data(data.get("gauntlet", {}))
	_apply_skill_data(data.get("skills", {}))
	_apply_quest_data(data.get("quests", {}))


## A brand-new save (or an old save from before the inventory system
## existed) starts with a few materials rather than nothing, so there's
## something to test crafting/the gauntlet with right away.
func _seed_starting_inventory() -> void:
	InventoryManager.add_item("herb", 4)
	InventoryManager.add_item("scrap_metal", 4)
	InventoryManager.add_item("battery_cell", 1)


## Opening lines for a brand-new save — the "voice in your head" is a
## dying god, defeated by the Demon Lord, spending its last strength to
## summon champions (you and others) and hand out fragments of its own
## power (the gauntlet) since it can no longer hold back the creatures
## it used to keep in check. Both the god and the Demon Lord stay
## unnamed for now — easy to name later once tone/lore firms up.
##
## TODO: the voice is meant to actually go silent partway through the
## game as a real story beat once the god finally dies — not just
## flavor text. That needs a real trigger (a boss fight, a quest
## milestone) to hang off of, which doesn't exist yet — wire it up once
## the main questline/boss system is built rather than faking it here.
func _play_intro_dialogue() -> void:
	DialogueBox.say([
		"Your eyes open. Trees. Sky. Silence. You don't know this place — and worse, you don't know yourself.",
		{"speaker": "???", "text": "You're awake. Good. There isn't much time — I'm fading, and I won't be able to hold on much longer."},
		{"speaker": "???", "text": "I was a god, once. The Demon Lord saw to the \"was.\""},
		{"speaker": "???", "text": "You've been summoned here with the last of what I have left. And you are not the only one."},
		{"speaker": "???", "text": "The creatures tearing this world apart were mine to hold back. Without me, they run wild — and worse things are stirring behind them."},
	])


func _apply_inventory_data(inventory_data: Dictionary) -> void:
	if inventory_data.is_empty():
		_seed_starting_inventory()
		return
	InventoryManager.load_save_data(inventory_data)


## The gauntlet's own defaults (tier 1, full energy) already cover a
## brand-new save, so this only needs to act when there's real saved
## state to restore.
func _apply_gauntlet_data(gauntlet_data: Dictionary) -> void:
	if gauntlet_data.is_empty():
		return
	GauntletManager.load_save_data(gauntlet_data)


## Same reasoning as the gauntlet above — SkillManager's own defaults
## (0 essence, every skill at level 0) already cover a brand-new save.
func _apply_skill_data(skill_data: Dictionary) -> void:
	if skill_data.is_empty():
		return
	SkillManager.load_save_data(skill_data)


## Same reasoning again — QuestManager already seeds a brand-new save's
## starter quests itself (see quest_manager.gd's _ready()), so this only
## needs to act when there's real saved quest progress to restore.
func _apply_quest_data(quest_data: Dictionary) -> void:
	if quest_data.is_empty():
		return
	QuestManager.load_save_data(quest_data)


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
	# So the RELEASE/RECALL state (see touch_controls.gd) survives a
	# reload instead of silently resetting to "Follow" every time.
	MonsterRoster.squad_independent = bool(roster_data.get("squad_independent", false))

	# Migrates any save made before duplicate species were merged into
	# power levels — a no-op for a save that's already deduped.
	MonsterRoster.dedupe_and_power_existing()

	MonsterRoster.roster_changed.emit()

	if MonsterRoster.active_squad.size() > 0:
		MonsterRoster.spawn_squad(player)


func _to_dict_array(raw: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry in raw:
		if entry is Dictionary:
			result.append(entry)
	return result
