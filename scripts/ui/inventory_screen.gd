extends CanvasLayer

## Full-screen inventory UI: one tab per item category (see
## ItemDatabase.ItemType) and a Craft tab for turning gathered materials
## into consumables/gauntlet items (see ItemDatabase.RECIPES). Toggled
## by the "toggle_inventory" key or the on-screen BAG button (see
## touch_controls.gd), and refreshes live off InventoryManager's and
## GauntletManager's signals.
##
## The skill sphere (spending Monster Essence — see SkillManager) has
## its own separate screen, skill_screen.gd, rather than living here.

@onready var root: Control = $Root
@onready var tabs: TabContainer = $Root/Panel/VBox/Tabs
@onready var consumables_list: VBoxContainer = $Root/Panel/VBox/Tabs/Consumables/ConsumablesList
@onready var gauntlet_list: VBoxContainer = $Root/Panel/VBox/Tabs/Gauntlet/GauntletList
@onready var materials_list: VBoxContainer = $Root/Panel/VBox/Tabs/Materials/MaterialsList
@onready var key_items_list: VBoxContainer = $Root/Panel/VBox/Tabs/KeyItems/KeyItemsList
@onready var craft_list: VBoxContainer = $Root/Panel/VBox/Tabs/Craft/CraftList
@onready var close_button: Button = $Root/Panel/VBox/TitleRow/CloseButton

var _player: Node = null


func _ready() -> void:
	add_to_group("inventory_screen")

	# Node names can't have spaces, so the nicer display names are set
	# here rather than baked into the scene tree.
	tabs.set_tab_title(0, "Consumables")
	tabs.set_tab_title(1, "Gauntlet")
	tabs.set_tab_title(2, "Materials")
	tabs.set_tab_title(3, "Key Items")
	tabs.set_tab_title(4, "Craft")

	close_button.pressed.connect(close)
	InventoryManager.inventory_changed.connect(_refresh)
	GauntletManager.gauntlet_changed.connect(_refresh)
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_inventory"):
		toggle()
		get_viewport().set_input_as_handled()


func toggle() -> void:
	if root.visible:
		close()
	else:
		open()


func open() -> void:
	root.visible = true
	_refresh()


func close() -> void:
	root.visible = false


func _get_player() -> Node:
	if _player == null or not is_instance_valid(_player):
		var players := get_tree().get_nodes_in_group("player")
		if players.size() > 0:
			_player = players[0]
	return _player


func _refresh() -> void:
	_populate_list(consumables_list, ItemDatabase.ItemType.CONSUMABLE, true)
	_populate_list(gauntlet_list, ItemDatabase.ItemType.GAUNTLET, true)
	_populate_list(materials_list, ItemDatabase.ItemType.MATERIAL, false)
	_populate_list(key_items_list, ItemDatabase.ItemType.KEY, false)
	_populate_craft_list()


func _populate_list(list: VBoxContainer, item_type: int, usable: bool) -> void:
	for child in list.get_children():
		child.queue_free()

	var owned_ids: Array = []
	for item_id in InventoryManager.items.keys():
		if ItemDatabase.get_type(item_id) == item_type:
			owned_ids.append(item_id)

	if owned_ids.is_empty():
		var empty_label := Label.new()
		empty_label.text = "(nothing yet)"
		empty_label.modulate = Color(1.0, 1.0, 1.0, 0.6)
		list.add_child(empty_label)
		return

	for item_id in owned_ids:
		list.add_child(_build_row(item_id, usable))


func _build_row(item_id: String, usable: bool) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

	var swatch := ColorRect.new()
	swatch.custom_minimum_size = Vector2(28, 28)
	swatch.color = ItemDatabase.get_color(item_id)
	row.add_child(swatch)

	var label := Label.new()
	label.text = "%s  x%d" % [ItemDatabase.get_display_name(item_id), InventoryManager.get_quantity(item_id)]
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.tooltip_text = String(ItemDatabase.get_definition(item_id).get("description", ""))
	row.add_child(label)

	if usable:
		var use_button := Button.new()
		use_button.text = "Use"
		use_button.pressed.connect(_on_use_pressed.bind(item_id))
		row.add_child(use_button)

	return row


func _populate_craft_list() -> void:
	for child in craft_list.get_children():
		child.queue_free()

	var recipe_ids: Array = ItemDatabase.RECIPES.keys()
	if recipe_ids.is_empty():
		var empty_label := Label.new()
		empty_label.text = "(no recipes yet)"
		craft_list.add_child(empty_label)
		return

	for item_id in recipe_ids:
		craft_list.add_child(_build_craft_row(item_id))


func _build_craft_row(item_id: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

	var swatch := ColorRect.new()
	swatch.custom_minimum_size = Vector2(28, 28)
	swatch.color = ItemDatabase.get_color(item_id)
	row.add_child(swatch)

	var recipe: Dictionary = ItemDatabase.get_recipe(item_id)
	var materials: Dictionary = recipe.get("materials", {})

	var cost_text := ""
	for material_id in materials.keys():
		if cost_text != "":
			cost_text += ", "
		cost_text += "%s x%d (have %d)" % [
			ItemDatabase.get_display_name(material_id),
			int(materials[material_id]),
			InventoryManager.get_quantity(material_id),
		]

	var label := Label.new()
	label.text = "%s — needs %s" % [ItemDatabase.get_display_name(item_id), cost_text]
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)

	var craft_button := Button.new()
	craft_button.text = "Craft"
	craft_button.disabled = not InventoryManager.can_craft(item_id)
	craft_button.pressed.connect(_on_craft_pressed.bind(item_id))
	row.add_child(craft_button)

	return row


func _on_use_pressed(item_id: String) -> void:
	var player := _get_player()
	if player == null:
		return
	InventoryManager.use_item(item_id, player)


func _on_craft_pressed(item_id: String) -> void:
	InventoryManager.craft(item_id)
