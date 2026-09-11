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
	_player_ref = null
	roster_changed.emit()


func add_to_collection(monster_data: Dictionary) -> void:
	collection.append(monster_data)
	if active_squad.size() < SQUAD_LIMIT:
		active_squad.append(monster_data)
	roster_changed.emit()


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

	return summon


func _despawn_squad() -> void:
	for summon in spawned_summons:
		if is_instance_valid(summon):
			summon.queue_free()
	spawned_summons.clear()
