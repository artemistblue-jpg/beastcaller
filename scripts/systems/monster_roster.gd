extends Node

## Autoload singleton: tracks every monster the player has tamed, which
## ones are in the active squad (max 4), and spawns/despawns their
## in-world summon instances next to the player.

signal roster_changed

const SQUAD_LIMIT := 4
const SUMMON_SCENE := preload("res://scenes/creatures/summon_monster.tscn")

var collection: Array[Dictionary] = []
var active_squad: Array[Dictionary] = []
var spawned_summons: Array[Node3D] = []


func add_to_collection(monster_data: Dictionary) -> void:
	collection.append(monster_data)
	if active_squad.size() < SQUAD_LIMIT:
		active_squad.append(monster_data)
	roster_changed.emit()


func spawn_squad(around: Node3D) -> void:
	_despawn_squad()

	var parent := around.get_parent()
	if parent == null:
		return

	for i in active_squad.size():
		var monster_data: Dictionary = active_squad[i]
		var summon := SUMMON_SCENE.instantiate()
		parent.add_child(summon)


		var squad_count: int = max(active_squad.size(), 1)
		var angle: float = (TAU / float(squad_count)) * i
		var offset := Vector3(cos(angle), 0.0, sin(angle)) * 2.0
		summon.global_position = around.global_position + offset

		if summon.has_method("configure"):
			summon.configure(monster_data, around)

		spawned_summons.append(summon)


func _despawn_squad() -> void:
	for summon in spawned_summons:
		if is_instance_valid(summon):
			summon.queue_free()
	spawned_summons.clear()
