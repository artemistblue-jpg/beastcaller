extends StaticBody3D

## A rock, tree, or herb patch that can be mined/chopped/foraged for a
## material, then goes on cooldown and reappears — the mining/
## woodcutting/foraging counterpart to chest.gd, but paid out
## immediately (no ad) since these are meant to be a repeatable trickle
## rather than the chest's jackpot moment.
##
## Breaking one takes base_required_hits punches/gathers bare-handed —
## see gather() — cut down to tool_required_hits once the player owns
## the matching tool (Pickaxe for rocks, Axe for trees — see
## ToolManager). Every regular punch (player.gd's _try_attack()) counts
## as a hit here too, not just the E-key/TAME-button interact, so
## rocks and trees are breakable just by walking up and swinging.
##
## Depleted/respawn state is deliberately NOT persisted via SaveManager
## (unlike CreatureSpawner) — reloading the scene (e.g. via the Restart
## button) just resets every node back to available. Acceptable for now;
## revisit if players start save-scumming gathering nodes for farming.

@export var skill_id: String = "mining"
@export var item_id: String = "ore"
@export var yield_min: int = 1
@export var yield_max: int = 2
@export var respawn_delay: float = 30.0

## How many gather() calls (punches, or E-key gathers — see player.gd's
## _try_attack()/_try_gather()) it takes to break this node bare-handed.
## A herb patch leaves this at 1 (picking a plant by hand is already
## easy) — rocks and trees set it higher so breaking them by punching
## alone is a real, felt effort.
@export var base_required_hits: int = 1
## Tool item id (see ItemDatabase's "unlocks_tool" items/ToolManager)
## that, once owned, drops the hits required down to
## tool_required_hits — "" if this node type has no matching tool
## (e.g. a herb patch, which stays bare-hands-only forever).
@export var tool_item_id: String = ""
@export var tool_required_hits: int = 1

@onready var collision_shape: CollisionShape3D = $CollisionShape3D

var _depleted: bool = false
var _respawn_timer: float = 0.0
## Hits landed since the last time this node fully broke (or since it
## last respawned) — reset to 0 either way, so a node that respawns
## mid-way through being punched down doesn't remember partial progress
## from its previous life.
var _hits_taken: int = 0


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


## One hit toward breaking this node — called once per punch (see
## player.gd's _try_attack()) or E-key/TAME-button press (see
## _try_gather()). Only once enough hits land (see _get_required_hits())
## does it actually award item_id (base yield plus the matching skill's
## bonus) and start the respawn countdown; every hit before that is
## silent progress with nothing to show for it yet other than the node
## still standing. Doesn't check can_gather() itself — callers already
## do via has_method("can_gather") before calling this.
func gather() -> void:
	_hits_taken += 1
	if _hits_taken < _get_required_hits():
		return

	var amount: int = randi_range(yield_min, yield_max) + _get_skill_bonus()
	InventoryManager.add_item(item_id, amount)

	_hits_taken = 0
	_depleted = true
	_respawn_timer = respawn_delay
	visible = false
	collision_shape.disabled = true


## Bare-handed by default (base_required_hits) — cut down to
## tool_required_hits once the player owns this node's matching tool
## (see ToolManager). A node with no tool_item_id set (e.g. a herb
## patch) just always uses base_required_hits, since it has nothing to
## check ToolManager for.
func _get_required_hits() -> int:
	if tool_item_id != "" and ToolManager.has_tool(tool_item_id):
		return max(tool_required_hits, 1)
	return max(base_required_hits, 1)


func _get_skill_bonus() -> int:
	match skill_id:
		"mining":
			return SkillManager.get_mining_bonus_yield()
		"woodcutting":
			return SkillManager.get_woodcutting_bonus_yield()
		"foraging":
			return SkillManager.get_foraging_bonus_yield()
		_:
			return 0
