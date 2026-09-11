extends StaticBody3D

## A fishing spot at the edge of the water — same "gatherable" group
## interface as ore/tree nodes (see gatherable_node.gd) so it plugs
## straight into player.gd's existing gather wiring (_try_gather()/
## _try_attack()), but the mechanic itself is different: instead of a
## guaranteed yield on a respawn timer, each cast has a chance to catch
## a Fish (boosted by the Fishing skill — see
## SkillManager.get_fishing_catch_chance()) and only a short cooldown
## between casts rather than a long respawn.

const BASE_CATCH_CHANCE: float = 0.4

@export var cast_cooldown: float = 2.0

var _cooldown_timer: float = 0.0


func _ready() -> void:
	add_to_group("gatherable")


func _process(delta: float) -> void:
	if _cooldown_timer > 0.0:
		_cooldown_timer -= delta


func can_gather() -> bool:
	return _cooldown_timer <= 0.0


## Doesn't check can_gather() itself — see gatherable_node.gd's gather()
## for why (callers already check via has_method("can_gather")). A miss
## still spends the cooldown, same as casting a line and coming up
## empty for real.
func gather() -> void:
	_cooldown_timer = cast_cooldown

	var chance: float = clamp(BASE_CATCH_CHANCE + SkillManager.get_fishing_catch_chance(), 0.0, 0.95)
	if randf() <= chance:
		InventoryManager.add_item("fish", 1)
