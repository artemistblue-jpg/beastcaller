extends Node

## Autoload singleton: the quest log. Every quest is static content
## defined below in QUESTS; progress is just which ids are active vs.
## completed, tracked here and persisted through SaveManager like every
## other system (see to_save_data()/load_save_data() and world.gd).
##
## Objectives are evaluated against the OTHER autoloads' live state
## (InventoryManager, MonsterRoster, GauntletManager, SkillManager)
## rather than needing separate hooks wired into gameplay scripts — a
## "gather 6 scrap metal" objective is just "currently holding >= 6",
## turn-in style. That keeps every other system decoupled: nothing
## outside this file needs to know quests exist.
##
## Quests aren't handed out by an NPC — there's no quest-giver dialogue
## system yet — they unlock straight into the log the moment their
## "requires" are met (see _auto_accept_available()), so the log always
## reflects what's actually worth doing next without the player needing
## to find the right person to talk to first.

signal quest_accepted(quest_id: String)
signal quest_completed(quest_id: String)
signal quests_changed

## quest_id -> definition.
##   "requires": quest ids that must already be completed before this
##     one unlocks into the log. Empty means available from the start.
##   "objectives": Array of Dictionaries, each checked by
##     _is_objective_met() below — a quest completes once every one of
##     its objectives is met.
##   "rewards": applied once, the instant the quest completes.
const QUESTS: Dictionary = {
	"first_catch": {
		"title": "First Catch",
		"description": "The gauntlet on your arm is the last gift of a dying god. Prove it works — tame your first monster.",
		"requires": [],
		"objectives": [
			{"type": "tamed_count", "count": 1, "label": "Tame a monster"},
		],
		"rewards": {"essence": 20},
	},
	"stock_the_shelves": {
		"title": "Stock the Shelves",
		"description": "With no one left to gather them, materials are just sitting out in the open fields. Bring back some scrap metal and herbs.",
		"requires": [],
		"objectives": [
			{"type": "have_item", "item_id": "scrap_metal", "count": 6, "label": "Scrap Metal"},
			{"type": "have_item", "item_id": "herb", "count": 6, "label": "Herb"},
		],
		"rewards": {"essence": 15, "items": {"battery_cell": 1}},
	},
	"gone_fishing": {
		"title": "Gone Fishing",
		"description": "The pond's been sitting still for who knows how long. See what's still biting.",
		"requires": [],
		"objectives": [
			{"type": "have_item", "item_id": "fish", "count": 3, "label": "Fish"},
		],
		"rewards": {"essence": 15, "items": {"fish_stew": 2}},
	},
	"gauntlet_upgrade": {
		"title": "A Stronger Grip",
		"description": "Tier I won't cut it for long. Craft or buy a Gauntlet Core and push past it.",
		"requires": ["stock_the_shelves"],
		"objectives": [
			{"type": "gauntlet_tier", "tier": 2, "label": "Reach Gauntlet Tier II"},
		],
		"rewards": {"essence": 25},
	},
	"growing_stronger": {
		"title": "Growing Stronger",
		"description": "Every monster you tame teaches you something. Sink some essence into the Taming skill and put it to use.",
		"requires": ["first_catch"],
		"objectives": [
			{"type": "skill_level", "skill_id": "taming", "level": 3, "label": "Reach Taming Lv 3"},
		],
		"rewards": {"essence": 20},
	},
}

## Quest ids currently in the log (unlocked, not yet completed).
var active_quests: Array[String] = []
## Quest ids already turned in — also what "requires" checks against.
var completed_quests: Array[String] = []


func _ready() -> void:
	InventoryManager.inventory_changed.connect(_check_active_quests)
	MonsterRoster.roster_changed.connect(_check_active_quests)
	GauntletManager.gauntlet_changed.connect(_check_active_quests)
	SkillManager.skill_changed.connect(func(_skill_id): _check_active_quests())

	# Nothing to load yet at this point (SaveManager applies real save
	# data later, through load_save_data()) — this just seeds the log
	# for a brand-new game so it isn't empty before that happens.
	_auto_accept_available()


func is_active(quest_id: String) -> bool:
	return active_quests.has(quest_id)


func is_completed(quest_id: String) -> bool:
	return completed_quests.has(quest_id)


## True once every "requires" entry is completed and it isn't already
## active or done.
func is_available(quest_id: String) -> bool:
	if is_active(quest_id) or is_completed(quest_id):
		return false
	var definition: Dictionary = QUESTS.get(quest_id, {})
	for required_id in definition.get("requires", []):
		if not is_completed(required_id):
			return false
	return true


## Current progress/target for one objective, for the quest log UI —
## e.g. (4, 6) for "have 6 scrap metal, currently holding 4".
func get_objective_progress(objective: Dictionary) -> Vector2i:
	var type: String = objective.get("type", "")
	match type:
		"tamed_count":
			return Vector2i(MonsterRoster.collection.size(), int(objective.get("count", 1)))
		"have_item":
			var item_id: String = objective.get("item_id", "")
			return Vector2i(InventoryManager.get_quantity(item_id), int(objective.get("count", 1)))
		"gauntlet_tier":
			return Vector2i(GauntletManager.tier, int(objective.get("tier", 1)))
		"skill_level":
			var skill_id: String = objective.get("skill_id", "")
			return Vector2i(SkillManager.get_skill_level(skill_id), int(objective.get("level", 1)))
	return Vector2i(0, 1)


func _is_objective_met(objective: Dictionary) -> bool:
	var progress: Vector2i = get_objective_progress(objective)
	return progress.x >= progress.y


func _is_quest_met(quest_id: String) -> bool:
	var definition: Dictionary = QUESTS.get(quest_id, {})
	for objective in definition.get("objectives", []):
		if not _is_objective_met(objective):
			return false
	return true


func _check_active_quests() -> void:
	# Iterate a copy — _complete_quest() mutates active_quests.
	for quest_id in active_quests.duplicate():
		if _is_quest_met(quest_id):
			_complete_quest(quest_id)
	_auto_accept_available()


func _complete_quest(quest_id: String) -> void:
	active_quests.erase(quest_id)
	completed_quests.append(quest_id)

	var rewards: Dictionary = QUESTS.get(quest_id, {}).get("rewards", {})
	if rewards.has("essence"):
		SkillManager.add_essence(int(rewards["essence"]))
	var reward_items: Dictionary = rewards.get("items", {})
	for item_id in reward_items.keys():
		InventoryManager.add_item(item_id, int(reward_items[item_id]))

	quest_completed.emit(quest_id)
	quests_changed.emit()
	SaveManager.save_game()


## Anything newly unlocked (at boot, or by a completion just above) that
## has no "requires" gate left gets added to the log automatically —
## this is a log of what to do, not something missable by not finding
## the right person to hand it out.
func _auto_accept_available() -> void:
	var accepted_any := false
	for quest_id in QUESTS.keys():
		if is_available(quest_id):
			active_quests.append(quest_id)
			quest_accepted.emit(quest_id)
			accepted_any = true
	if accepted_any:
		quests_changed.emit()


## Used by SaveManager.restart_game().
func reset() -> void:
	active_quests.clear()
	completed_quests.clear()
	_auto_accept_available()
	quests_changed.emit()


func to_save_data() -> Dictionary:
	return {"active": active_quests, "completed": completed_quests}


func load_save_data(data: Dictionary) -> void:
	active_quests = _to_string_array(data.get("active", []))
	completed_quests = _to_string_array(data.get("completed", []))
	_check_active_quests()
	quests_changed.emit()


func _to_string_array(raw: Array) -> Array[String]:
	var result: Array[String] = []
	for entry in raw:
		if entry is String:
			result.append(entry)
	return result
