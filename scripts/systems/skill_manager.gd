extends Node

## Autoload singleton: Monster Essence (the shared currency dropped by
## creatures on capture/death) and the "skill sphere" — an uncapped set
## of skills leveled up by spending essence, Dark Souls-souls style: the
## same essence the NPC shop (see shop_screen.gd) spends on goods also
## pays for these, so leveling a skill is a real trade-off against
## buying something else.
##
## Every skill has a live effect now (see get_taming_bonus()/
## get_crafting_bonus_yield()/get_mining_bonus_yield()/
## get_woodcutting_bonus_yield()/get_foraging_bonus_yield()/
## get_fishing_catch_chance()) — mining, woodcutting, and foraging all
## pay out at their respective gatherable nodes (rocks, trees, herb
## patches), fishing at fishing spots (see gatherable_node.gd/
## fishing_spot.gd).

signal essence_changed
signal skill_changed(skill_id: String)

const SKILLS: Dictionary = {
	"taming": {
		"name": "Taming",
		"description": "+1% capture chance per level on every tame attempt.",
	},
	"crafting": {
		"name": "Crafting",
		"description": "Every 10 levels, crafting a recipe yields one extra item.",
	},
	"mining": {
		"name": "Mining",
		"description": "+1 bonus ore per 10 levels when gathering from an ore node.",
	},
	"woodcutting": {
		"name": "Woodcutting",
		"description": "+1 bonus wood per 10 levels when gathering from a tree node.",
	},
	"foraging": {
		"name": "Foraging",
		"description": "+1 bonus herb per 10 levels when gathering from a wild herb patch.",
	},
	"fishing": {
		"name": "Fishing",
		"description": "+1% catch chance per level when casting at a fishing spot.",
	},
}

## Essence cost to go from level N to N+1 is BASE_LEVEL_COST *
## LEVEL_COST_GROWTH^N — an ever-climbing but uncapped curve, since
## there's no fixed number of levels (an "infinite sphere"). 25% growth
## per level keeps this a real grind: 10, 13, 16, 20, 24, 31, 38...
const BASE_LEVEL_COST := 10
const LEVEL_COST_GROWTH := 1.25

var essence: int = 0
var skill_levels: Dictionary = {}  # skill_id -> level (int, absent = 0)


func add_essence(amount: int) -> void:
	if amount <= 0:
		return
	essence += amount
	essence_changed.emit()


func get_skill_level(skill_id: String) -> int:
	return int(skill_levels.get(skill_id, 0))


func cost_for_next_level(skill_id: String) -> int:
	var level: int = get_skill_level(skill_id)
	return int(round(BASE_LEVEL_COST * pow(LEVEL_COST_GROWTH, level)))


func can_level_up(skill_id: String) -> bool:
	return SKILLS.has(skill_id) and essence >= cost_for_next_level(skill_id)


func level_up(skill_id: String) -> bool:
	if not can_level_up(skill_id):
		return false

	if not spend_essence(cost_for_next_level(skill_id)):
		return false
	skill_levels[skill_id] = get_skill_level(skill_id) + 1
	skill_changed.emit(skill_id)
	return true


## Shared essence-deduction path — also used by MonsterRoster.revive() to
## pay for reviving a fainted squad member. Returns false (and spends
## nothing) if the balance is too low, so callers can just check the
## return value instead of comparing essence themselves first.
func spend_essence(amount: int) -> bool:
	if amount <= 0 or essence < amount:
		return false
	essence -= amount
	essence_changed.emit()
	return true


## Flat additive bonus applied on top of whatever capture chance a tame
## attempt already computed — see creature_ai.gd/wild_monster.gd.
func get_taming_bonus() -> float:
	return get_skill_level("taming") * 0.01


## Extra items produced per successful craft — see InventoryManager.craft().
func get_crafting_bonus_yield() -> int:
	return get_skill_level("crafting") / 10


## Extra ore per gather — see gatherable_node.gd.
func get_mining_bonus_yield() -> int:
	return get_skill_level("mining") / 10


## Extra wood per gather — see gatherable_node.gd.
func get_woodcutting_bonus_yield() -> int:
	return get_skill_level("woodcutting") / 10


## Extra herb per gather — see gatherable_node.gd.
func get_foraging_bonus_yield() -> int:
	return get_skill_level("foraging") / 10


## Flat additive bonus applied on top of a fishing spot's base catch
## chance per cast — see fishing_spot.gd.
func get_fishing_catch_chance() -> float:
	return get_skill_level("fishing") * 0.01


## Used by SaveManager.restart_game() — see there for why.
func reset() -> void:
	essence = 0
	skill_levels.clear()
	essence_changed.emit()


func to_save_data() -> Dictionary:
	return {"essence": essence, "skill_levels": skill_levels.duplicate()}


func load_save_data(data: Dictionary) -> void:
	essence = int(data.get("essence", 0))
	skill_levels = (data.get("skill_levels", {}) as Dictionary).duplicate()
	essence_changed.emit()
