extends Node

## Autoload singleton: the player's item inventory. Holds a quantity per
## item id (see ItemDatabase for what each id means/does) and persists
## through SaveManager the same way MonsterRoster does — see
## to_save_data()/load_save_data() and world.gd.

signal inventory_changed
## Fired whenever an item is actually added — gathering, loot drops,
## crafting output, shop purchases — so UI (see hud.gd) can pop up a
## quick "+N Item" notice without needing to diff inventory state itself.
## Carries the amount actually gained, which can be less than what was
## requested if the stack was already near stack_max.
signal item_obtained(item_id: String, amount: int)

var items: Dictionary = {}  # item_id -> quantity


func add_item(item_id: String, amount: int = 1) -> void:
	if amount <= 0 or not ItemDatabase.has_item(item_id):
		return
	var stack_max: int = ItemDatabase.get_stack_max(item_id)
	var current: int = items.get(item_id, 0)
	var new_amount: int = min(current + amount, stack_max)
	items[item_id] = new_amount
	inventory_changed.emit()
	var gained: int = new_amount - current
	if gained > 0:
		item_obtained.emit(item_id, gained)
		TutorialManager.show_tip(
			"inventory", "Items you pick up go straight to your Inventory — tap BAG to see what you're holding."
		)
		if ItemDatabase.get_type(item_id) == ItemDatabase.ItemType.MATERIAL:
			TutorialManager.show_tip(
				"crafting", "Materials like this are used to craft gear — check the Craft tab in your Inventory."
			)


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

	if item_type == ItemDatabase.ItemType.TOOL:
		if definition.has("unlocks_tool"):
			ToolManager.unlock_tool(String(definition["unlocks_tool"]))
			remove_item(item_id, 1)
			return true
		return false

	if item_type == ItemDatabase.ItemType.PLACEABLE:
		return _place_in_world(item_id, definition, player)

	return false


## Instances a PLACEABLE item's scene into the live world a short
## distance in front of wherever "player" is currently facing (e.g. a
## crafted Stone Path piece), rather than requiring its own dedicated
## placement/aiming UI — good enough for a "use to drop one down" item.
## Delegates the actual instancing to world.gd (found via
## get_tree().current_scene, since this project only ever has the one
## world scene loaded) so PlacedDecorations stays a single source of
## truth for both live placement and save/load — see
## world.gd's add_placed_decoration()/get_placed_decorations_data().
func _place_in_world(item_id: String, definition: Dictionary, player: Node) -> bool:
	if not definition.has("scene_path") or not (player is Node3D):
		return false

	var world := player.get_tree().current_scene
	if world == null or not world.has_method("add_placed_decoration"):
		return false

	var player_3d: Node3D = player
	var forward: Vector3 = -player_3d.global_transform.basis.z
	var place_position: Vector3 = player_3d.global_position + forward * 1.5
	var instance: Node3D = world.add_placed_decoration(
		String(definition["scene_path"]), place_position, player_3d.rotation.y
	)
	if instance == null:
		return false

	remove_item(item_id, 1)
	return true


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
