extends Node

## Autoload singleton: the player's item inventory. Holds a quantity per
## item id (see ItemDatabase for what each id means/does) and persists
## through SaveManager the same way MonsterRoster does — see
## to_save_data()/load_save_data() and world.gd.

signal inventory_changed

var items: Dictionary = {}  # item_id -> quantity


func add_item(item_id: String, amount: int = 1) -> void:
	if amount <= 0 or not ItemDatabase.has_item(item_id):
		return
	var stack_max: int = ItemDatabase.get_stack_max(item_id)
	var current: int = items.get(item_id, 0)
	items[item_id] = min(current + amount, stack_max)
	inventory_changed.emit()


## Returns false (and changes nothing) if there isn't enough of the item
## to remove — callers should check before assuming the removal happened.
func remove_item(item_id: String, amount: int = 1) -> bool:
	if amount <= 0:
		return false
	var current: int = items.get(item_id, 0)
	if current < amount:
		return false

	var remaining: int = current - amount
	if remaining <= 0:
		items.erase(item_id)
	else:
		items[item_id] = remaining
	inventory_changed.emit()
	return true


func get_quantity(item_id: String) -> int:
	return items.get(item_id, 0)


func has_item(item_id: String, amount: int = 1) -> bool:
	return get_quantity(item_id) >= amount


## Applies an item's effect and consumes one, for whichever "Use" button
## the inventory screen shows (Consumables heal the player, Gauntlet
## items recharge or upgrade the gauntlet). Key items and materials
## aren't used this way — key items just sit in the inventory until
## something later reads them, and materials are only spent by craft().
func use_item(item_id: String, player: Node) -> bool:
	if not has_item(item_id):
		return false

	var item_type: int = ItemDatabase.get_type(item_id)
	var definition: Dictionary = ItemDatabase.get_definition(item_id)

	if item_type == ItemDatabase.ItemType.CONSUMABLE:
		if definition.has("heal_amount") and player.has_node("HealthComponent"):
			var health: HealthComponent = player.get_node("HealthComponent")
			health.heal(float(definition["heal_amount"]))
		remove_item(item_id, 1)
		return true

	if item_type == ItemDatabase.ItemType.GAUNTLET:
		if definition.has("energy_amount"):
			GauntletManager.recharge(float(definition["energy_amount"]))
			remove_item(item_id, 1)
			return true
		if definition.has("sets_tier"):
			if GauntletManager.upgrade_to(int(definition["sets_tier"])):
				remove_item(item_id, 1)
				return true
			return false

	return false


func can_craft(item_id: String) -> bool:
	var recipe: Dictionary = ItemDatabase.get_recipe(item_id)
	if recipe.is_empty():
		return false

	var materials: Dictionary = recipe.get("materials", {})
	for material_id in materials.keys():
		if not has_item(material_id, int(materials[material_id])):
			return false
	return true


## Consumes the recipe's materials and adds the crafted item. Returns
## false (and changes nothing) if there aren't enough materials.
func craft(item_id: String) -> bool:
	if not can_craft(item_id):
		return false

	var recipe: Dictionary = ItemDatabase.get_recipe(item_id)
	var materials: Dictionary = recipe.get("materials", {})
	for material_id in materials.keys():
		remove_item(material_id, int(materials[material_id]))

	var result_qty: int = int(recipe.get("result_qty", 1)) + SkillManager.get_crafting_bonus_yield()
	add_item(item_id, result_qty)
	return true


## Used by SaveManager.restart_game() — see there for why.
func reset() -> void:
	items.clear()
	inventory_changed.emit()


func to_save_data() -> Dictionary:
	return items.duplicate()


func load_save_data(data: Dictionary) -> void:
	items = data.duplicate()
	inventory_changed.emit()
