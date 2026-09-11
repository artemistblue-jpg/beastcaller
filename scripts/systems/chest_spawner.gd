extends "res://scripts/systems/creature_spawner.gd"

## A CreatureSpawner variant for chests: same fixed-point,
## respawn-after-cooldown behavior as the base class (see
## creature_spawner.gd — its "creature_scene" export and
## notify_creature_removed() naming are reused as-is here rather than
## renamed to something chest-specific, since renaming the base
## class's exported property would silently break every existing
## spawner node's saved override in world.tscn), but scatters each
## fresh chest to a random nearby spot instead of always the exact
## same position, so "random locations" means something across
## respawns too, not just "this fixed point happens to be off-center".

@export var placement_radius: float = 8.0


func _spawn_creature() -> void:
	if creature_scene == null:
		return
	var instance := creature_scene.instantiate()
	add_child(instance)
	if instance is Node3D:
		var angle: float = randf() * TAU
		var distance: float = randf() * placement_radius
		(instance as Node3D).position = Vector3(cos(angle) * distance, 0.0, sin(angle) * distance)
