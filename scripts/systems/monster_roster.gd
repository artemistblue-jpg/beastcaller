extends Node

## Autoload singleton: tracks every monster the player has tamed, which
## ones are in the active squad (max 4), and spawns/despawns their
## in-world summon instances next to the player.
##
## A squad member that dies in the field doesn't vanish for good — it
## "faints" (see notify_fainted(), called by creature_ai.gd) and sits
## out of the fight until the player pays Monster Essence to revive it
## (see revive()). The cost scales with how tough the monster is (its
## max_health) rather than being a flat number, so losing a beefy tank
## stings more than losing a fragile early capture — mirrors how tougher
## creatures are already harder to tame in the first place.

signal roster_changed
## Fired whenever the whole squad flips between "Follow" and
## "Independent" — see set_squad_independent(). Separate from
## roster_changed so UI that only cares about this one flag (the
## release/recall button) doesn't have to re-filter every roster event.
signal squad_mode_changed(is_independent: bool)

const SQUAD_LIMIT := 4
const SUMMON_SCENE := preload("res://scenes/creatures/summon_monster.tscn")

## Revive cost = max(REVIVE_MIN_COST, ceil(max_health * REVIVE_ESSENCE_PER_HEALTH)).
const REVIVE_ESSENCE_PER_HEALTH: float = 0.5
const REVIVE_MIN_COST: int = 5

var collection: Array[Dictionary] = []
var active_squad: Array[Dictionary] = []
## Parallel to active_squad by index — null where that slot has no live
## in-world instance right now (fainted, or the squad hasn't been
## spawned into a world yet).
var spawned_summons: Array[Node3D] = []

## Whole-squad toggle (see the on-screen RELEASE/RECALL button in
## touch_controls.gd) — true once the player has sent their squad off to
## fight on their own instead of following. Applied to every summon as
## it spawns (see _spawn_one()), and pushed live to whatever's already
## spawned when the player flips it (see set_squad_independent()).
## Persisted in the save file (see save_manager.gd/world.gd) so it
## survives a reload instead of silently resetting to "Follow".
var squad_independent: bool = false

## Whoever spawn_squad() was last called for — remembered so revive()
## can drop the revived monster straight back into the world instead of
## only taking effect the next time the whole squad respawns.
var _player_ref: Node3D = null


## Used by SaveManager.restart_game() — see there for why. Despawns any
## live summons first, since the reload that follows this call frees
## the world scene anyway but this autoload's own arrays would
## otherwise be left pointing at now-invalid instances.
func reset() -> void:
	_despawn_squad()
	collection.clear()
	active_squad.clear()
	squad_independent = false
	_player_ref = null
	roster_changed.emit()


## Flips the whole squad between following the player and fighting off
## on their own, and immediately applies it to whatever's currently
## spawned (a fainted/unspawned slot just picks it up next time it
## spawns — see _spawn_one()). Returns the new state, so a caller like
## touch_controls.gd can update its button label off the return value
## instead of re-reading squad_independent itself.
func set_squad_independent(value: bool) -> bool:
	squad_independent = value
	for summon in spawned_summons:
		if is_instance_valid(summon) and summon.has_method("set_independent"):
			summon.set_independent(value)
	squad_mode_changed.emit(value)
	return value


## Only one of each species is ever kept — taming a species already in
## your collection doesn't add a second copy (and can't sneak a
## duplicate into active_squad either). Instead it powers up the one you
## have: see _power_up(). A genuinely new species is added as normal and
## auto-joins the active squad if there's room, same as before.
func add_to_collection(monster_data: Dictionary) -> void:
	var species: String = String(monster_data.get("species_name", ""))
	var existing_index: int = _find_species_index(collection, species)

	if existing_index >= 0:
		_power_up(collection[existing_index])
		# collection and active_squad hold separate Dictionary instances
		# once a save has round-tripped through JSON, so the squad copy
		# (if this species is currently fielded) needs its own update.
		var squad_index: int = _find_species_index(active_squad, species)
		if squad_index >= 0:
			_power_up(active_squad[squad_index])
		roster_changed.emit()
		return

	monster_data["power_level"] = 1
	monster_data["base_max_health"] = monster_data.get("max_health", 20.0)
	collection.append(monster_data)
	if active_squad.size() < SQUAD_LIMIT:
		active_squad.append(monster_data)
	roster_changed.emit()
	TutorialManager.show_tip(
		"squad",
		"Tamed monsters join your squad and follow you! Check PARTY to manage them, or RELEASE to send them off to fight on their own."
	)


func _find_species_index(list: Array[Dictionary], species: String) -> int:
	for i in list.size():
		if String(list[i].get("species_name", "")) == species:
			return i
	return -1


## +1 power level, and max_health recomputed from base_max_health so the
## bonus is always ElementSystem.get_power_multiplier(power_level) exactly
## — never compounded on top of an already-boosted number. See
## creature_ai.gd's configure()/_apply_role_stats() for where the matching
## attack-damage bonus gets applied (max_health travels with the saved
## data directly; attack_damage is derived fresh each spawn, so it reads
## power_level itself instead).
func _power_up(monster_data: Dictionary) -> void:
	var power_level: int = int(monster_data.get("power_level", 1)) + 1
	var base_health: float = float(monster_data.get("base_max_health", monster_data.get("max_health", 20.0)))
	monster_data["power_level"] = power_level
	monster_data["base_max_health"] = base_health
	monster_data["max_health"] = base_health * ElementSystem.get_power_multiplier(power_level)


## One-time cleanup for a save made before duplicate species were merged
## into power levels — folds any existing duplicate entries for the same
## species into a single one (summing their power levels) instead of
## leaving old saves showing two "Sparkit" rows side by side forever.
## Called once right after a save's roster data loads (see world.gd's
## _apply_roster_data()); a no-op on a save that's already deduped, or a
## brand-new one with nothing loaded yet.
func dedupe_and_power_existing() -> void:
	collection = _dedupe_list(collection)
	active_squad = _dedupe_list(active_squad)
	if active_squad.size() > SQUAD_LIMIT:
		active_squad = active_squad.slice(0, SQUAD_LIMIT)


func _dedupe_list(list: Array[Dictionary]) -> Array[Dictionary]:
	var merged: Array[Dictionary] = []
	for entry in list:
		var species: String = String(entry.get("species_name", ""))
		var existing_index: int = _find_species_index(merged, species)
		if existing_index >= 0:
			var target: Dictionary = merged[existing_index]
			var combined_power: int = int(target.get("power_level", 1)) + int(entry.get("power_level", 1))
			var base_health: float = float(target.get("base_max_health", target.get("max_health", 20.0)))
			target["power_level"] = combined_power
			target["base_max_health"] = base_health
			target["max_health"] = base_health * ElementSystem.get_power_multiplier(combined_power)
		else:
			if not entry.has("power_level"):
				entry["power_level"] = 1
			if not entry.has("base_max_health"):
				entry["base_max_health"] = entry.get("max_health", 20.0)
			merged.append(entry)
	return merged


func spawn_squad(around: Node3D) -> void:
	_despawn_squad()
	_player_ref = around

	var parent := around.get_parent()
	if parent == null:
		return

	spawned_summons.resize(active_squad.size())

	for i in active_squad.size():
		var monster_data: Dictionary = active_squad[i]
		if monster_data.get("is_fainted", false):
			spawned_summons[i] = null
		else:
			spawned_summons[i] = _spawn_one(i, around, parent)


## Called by the spawned creature itself (see creature_ai.gd) the
## instant one of the player's own squad members hits 0 HP. Marks that
## squad slot "fainted" rather than removing it from the roster outright.
func notify_fainted(index: int) -> void:
	if index < 0 or index >= active_squad.size():
		return
	active_squad[index]["is_fainted"] = true
	if index < spawned_summons.size():
		spawned_summons[index] = null
	roster_changed.emit()


## Essence cost to revive a fainted squad member — scales with how tough
## it is (max_health) instead of being flat.
func get_revive_cost(monster_data: Dictionary) -> int:
	var toughness: float = float(monster_data.get("max_health", 20.0))
	return max(REVIVE_MIN_COST, int(ceil(toughness * REVIVE_ESSENCE_PER_HEALTH)))


func can_revive(index: int) -> bool:
	if index < 0 or index >= active_squad.size():
		return false
	var monster_data: Dictionary = active_squad[index]
	if not monster_data.get("is_fainted", false):
		return false
	return SkillManager.essence >= get_revive_cost(monster_data)


## Spends the essence and, if the player is currently out in the world,
## drops the monster right back in next to them. If there's no live
## player reference yet (shouldn't normally happen — a monster can only
## faint after already being spawned once), it just clears the fainted
## flag and the next spawn_squad() call (e.g. on world load) brings it
## back instead.
func revive(index: int) -> bool:
	if not can_revive(index):
		return false

	var monster_data: Dictionary = active_squad[index]
	if not SkillManager.spend_essence(get_revive_cost(monster_data)):
		return false

	monster_data["is_fainted"] = false
	roster_changed.emit()

	if _player_ref != null and is_instance_valid(_player_ref):
		var parent := _player_ref.get_parent()
		if parent != null:
			while spawned_summons.size() <= index:
				spawned_summons.append(null)
			spawned_summons[index] = _spawn_one(index, _player_ref, parent)

	return true


func _spawn_one(index: int, around: Node3D, parent: Node) -> Node3D:
	var monster_data: Dictionary = active_squad[index]
	var summon := SUMMON_SCENE.instantiate()
	parent.add_child(summon)

	var squad_count: int = max(active_squad.size(), 1)
	var angle: float = (TAU / float(squad_count)) * index
	var offset := Vector3(cos(angle), 0.0, sin(angle)) * 2.0
	summon.global_position = around.global_position + offset

	if summon.has_method("configure"):
		summon.configure(monster_data, around, index)
	if squad_independent and summon.has_method("set_independent"):
		summon.set_independent(true)

	return summon


func _despawn_squad() -> void:
	for summon in spawned_summons:
		if is_instance_valid(summon):
			summon.queue_free()
	spawned_summons.clear()
