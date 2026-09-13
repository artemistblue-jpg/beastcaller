extends Node

## Autoload singleton (registered as "ItemDatabase" in project.godot) —
## no class_name here on purpose: giving an autoloaded script a
## class_name of the same name makes Godot treat that name as the
## global class/type everywhere, which shadows the actual autoload
## instance and breaks every call into its instance methods (and
## collides with Node's own get_name()). The autoload registration
## alone already makes "ItemDatabase" globally accessible from any
## script, enums and consts included — no class_name needed for that.
##
## The master list of every item that exists in the
## game, plus the crafting recipes that turn raw materials into finished
## goods. Items are plain data here (id -> definition dictionary) rather
## than individual .tres resources, so adding a new one is a one-line
## edit to ITEMS instead of creating a resource file in the editor.
## InventoryManager and the inventory UI look everything up by id
## through this table — nothing else should read ITEMS/RECIPES directly.

enum ItemType { CONSUMABLE, GAUNTLET, KEY, MATERIAL, TOOL, PLACEABLE }

const ITEMS: Dictionary = {
	"health_potion": {
		"name": "Health Potion",
		"description": "Restores 30 HP when used. Crafted only — doesn't turn up in the world.",
		"type": ItemType.CONSUMABLE,
		"stack_max": 20,
		"color": Color(0.3, 0.85, 0.35),
		"heal_amount": 30.0,
	},
	"battery_cell": {
		"name": "Battery Cell",
		"description": "Recharges 40 energy into your capture gauntlet when used.",
		"type": ItemType.GAUNTLET,
		"stack_max": 20,
		"color": Color(0.3, 0.55, 0.95),
		"energy_amount": 40.0,
	},
	"gauntlet_core_ii": {
		"name": "Gauntlet Core II",
		"description": "Installs into your gauntlet, upgrading it to Tier II — higher max energy and lets you capture tougher creatures.",
		"type": ItemType.GAUNTLET,
		"stack_max": 1,
		"color": Color(0.55, 0.35, 0.85),
		"sets_tier": 2,
	},
	"ancient_sigil": {
		"name": "Ancient Sigil",
		"description": "A strange, humming relic. Feels important — probably tied to something later.",
		"type": ItemType.KEY,
		"stack_max": 1,
		"color": Color(0.85, 0.7, 0.2),
	},
	"herb": {
		"name": "Herb",
		"description": "A common wild plant. Used in crafting.",
		"type": ItemType.MATERIAL,
		"stack_max": 50,
		"color": Color(0.45, 0.7, 0.35),
	},
	"ore": {
		"name": "Ore",
		"description": "Raw ore, mined out of a rock vein. Used in crafting.",
		"type": ItemType.MATERIAL,
		"stack_max": 50,
		"color": Color(0.55, 0.55, 0.6),
	},
	"wood": {
		"name": "Wood",
		"description": "A sturdy log, chopped from a tree. Used in crafting.",
		"type": ItemType.MATERIAL,
		"stack_max": 50,
		"color": Color(0.5, 0.35, 0.2),
	},
	"fish": {
		"name": "Fish",
		"description": "Caught at a fishing spot. Used in crafting.",
		"type": ItemType.MATERIAL,
		"stack_max": 50,
		"color": Color(0.4, 0.6, 0.75),
	},
	"fish_stew": {
		"name": "Fish Stew",
		"description": "Restores 50 HP when used. Crafted from Fish and Herb.",
		"type": ItemType.CONSUMABLE,
		"stack_max": 20,
		"color": Color(0.85, 0.6, 0.3),
		"heal_amount": 50.0,
	},
	"beast_fang": {
		"name": "Beast Fang",
		"description": "Torn from a Feral Stalker. Too tough for ordinary crafting — used in its own recipes.",
		"type": ItemType.MATERIAL,
		"stack_max": 50,
		"color": Color(0.75, 0.2, 0.2),
	},
	"spark_shard": {
		"name": "Spark Shard",
		"description": "A crackling fragment left behind by a Sparkit. Used in its own recipes.",
		"type": ItemType.MATERIAL,
		"stack_max": 50,
		"color": Color(0.9, 0.85, 0.25),
	},
	"beast_tonic": {
		"name": "Beast Tonic",
		"description": "A potent brew steeped with a Beast Fang. Restores 70 HP when used — Crafted only.",
		"type": ItemType.CONSUMABLE,
		"stack_max": 20,
		"color": Color(0.8, 0.3, 0.25),
		"heal_amount": 70.0,
	},
	"charged_cell": {
		"name": "Charged Cell",
		"description": "A Battery Cell rebuilt around a Spark Shard's crackle. Recharges 70 energy into your capture gauntlet when used — Crafted only.",
		"type": ItemType.GAUNTLET,
		"stack_max": 20,
		"color": Color(0.9, 0.75, 0.2),
		"energy_amount": 70.0,
	},
	"pickaxe": {
		"name": "Pickaxe",
		"description": "Once crafted, breaks rocks in far fewer swings than bare hands. A permanent upgrade — use it once to equip it for good.",
		"type": ItemType.TOOL,
		"stack_max": 1,
		"color": Color(0.6, 0.6, 0.65),
		"unlocks_tool": "pickaxe",
	},
	"axe": {
		"name": "Axe",
		"description": "Once crafted, fells trees in far fewer swings than bare hands. A permanent upgrade — use it once to equip it for good.",
		"type": ItemType.TOOL,
		"stack_max": 1,
		"color": Color(0.6, 0.45, 0.25),
		"unlocks_tool": "axe",
	},
	"stone_path": {
		"name": "Stone Path",
		"description": "A crafted paving stone. Use it to lay one down on the ground right where you're standing, facing the way you're facing.",
		"type": ItemType.PLACEABLE,
		"stack_max": 50,
		"color": Color(0.65, 0.65, 0.68),
		# Read by InventoryManager.use_item() to know what to instance
		# into the world — see world.gd's add_placed_decoration().
		"scene_path": "res://scenes/world/rock_path_piece.tscn",
	},
}

## item_id -> {"result_qty": int, "materials": {material_id: qty, ...}}
const RECIPES: Dictionary = {
	"health_potion": {"result_qty": 1, "materials": {"herb": 2}},
	"battery_cell": {"result_qty": 1, "materials": {"ore": 2}},
	"gauntlet_core_ii": {"result_qty": 1, "materials": {"ore": 5, "herb": 3}},
	"fish_stew": {"result_qty": 1, "materials": {"fish": 2, "herb": 1}},
	"beast_tonic": {"result_qty": 1, "materials": {"beast_fang": 1, "herb": 2}},
	"charged_cell": {"result_qty": 1, "materials": {"spark_shard": 1, "ore": 2}},
	"pickaxe": {"result_qty": 1, "materials": {"ore": 5, "wood": 3}},
	"axe": {"result_qty": 1, "materials": {"wood": 5, "ore": 3}},
	"stone_path": {"result_qty": 2, "materials": {"ore": 1}},
}

## item_id -> Monster Essence cost for buying one unit from the NPC
## shop (see shop_npc.gd/shop_screen.gd) — a second essence sink
## alongside the skill sphere, for players who'd rather spend essence
## than gather materials to craft. Only consumables/gauntlet items are
## sold; raw materials are gather-only and key items aren't for sale.
const SHOP: Dictionary = {
	"health_potion": 15,
	"battery_cell": 20,
	"gauntlet_core_ii": 150,
}


func has_item(item_id: String) -> bool:
	return ITEMS.has(item_id)


func get_definition(item_id: String) -> Dictionary:
	return ITEMS.get(item_id, {})


## Named get_display_name() rather than get_name() — Node already has a
## get_name() (returns the node's own scene-tree name, a StringName)
## and this project treats GDScript's "overriding a native method with
## an incompatible signature" warning as a hard compile error, so
## reusing that name here breaks the build the moment anything extends
## Node and defines it.
func get_display_name(item_id: String) -> String:
	return String(get_definition(item_id).get("name", item_id))


func get_type(item_id: String) -> ItemType:
	return get_definition(item_id).get("type", ItemType.CONSUMABLE)


func get_stack_max(item_id: String) -> int:
	return int(get_definition(item_id).get("stack_max", 99))


func get_color(item_id: String) -> Color:
	return get_definition(item_id).get("color", Color.WHITE)


func get_recipe(item_id: String) -> Dictionary:
	return RECIPES.get(item_id, {})


func is_craftable(item_id: String) -> bool:
	return RECIPES.has(item_id)


func is_purchasable(item_id: String) -> bool:
	return SHOP.has(item_id)


func get_shop_cost(item_id: String) -> int:
	return int(SHOP.get(item_id, 0))
