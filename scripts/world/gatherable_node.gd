extends StaticBody3D

## An ore vein or tree that can be chopped/mined for a material, then
## goes on cooldown and reappears — the mining/woodcutting counterpart
## to chest.gd, but paid out immediately (no ad) since these are meant
## to be a repeatable trickle rather than the chest's jackpot moment.
##
## Depleted/respawn state is deliberately NOT persisted via SaveManager
## (unlike CreatureSpawner) — reloading the scene (e.g. via the Restart
## button) just resets every node back to available. Acceptable for now;
## revisit if players start save-scumming gathering nodes for farming.

@export var skill_id: String = "mining"
@export var item_id: String = "scrap_metal"
@export var yield_min: int = 1
@export var yield_max: int = 2
@export var respawn_delay: float = 30.0

@onready var collision_shape: CollisionShape3D = $CollisionShape3D

var _depleted: bool = false
var _respawn_timer: float = 0.0


func _ready() -> void:
	add_to_group("gatherable")


func _process(delta: float) -> void:
	if not _depleted:
		return
	_respawn_timer -= delta
	if _respawn_timer <= 0.0:
		_depleted = false
		visible = true
		collision_shape.disabled = false


func can_gather() -> bool:
	return not _depleted


## Awards item_id (base yield plus the matching skill's bonus) to the
## player's inventory, then hides/disables self and starts the respawn
## countdown. Doesn't check can_gather() itself — callers (player.gd)
## already do via has_method("can_gather") before calling this.
func gather() -> void:
	var amount: int = randi_range(yield_min, yield_max) + _get_skill_bonus()
	InventoryManager.add_item(item_id, amount)

	_depleted = true
	_respawn_timer = respawn_delay
	visible = false
	collision_shape.disabled = true


func _get_skill_bonus() -> int:
	match skill_id:
		"mining":
			return SkillManager.get_mining_bonus_yield()
		"woodcutting":
			return SkillManager.get_woodcutting_bonus_yield()
		_:
			return 0
