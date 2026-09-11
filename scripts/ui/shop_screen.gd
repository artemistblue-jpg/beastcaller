extends CanvasLayer

## Full-screen NPC shop UI: spend Monster Essence directly on
## consumables/gauntlet items (see ItemDatabase.SHOP) instead of
## gathering materials to craft them — a second, faster essence sink
## alongside the skill sphere (skill_screen.gd). Opened only by walking
## up to a shop NPC and interacting (see shop_npc.gd and player.gd's
## _try_open_shop()) rather than a persistent hotkey/touch button like
## the other screens, since it's meant to feel like an actual shop you
## have to visit rather than a menu always in your pocket.

@onready var root: Control = $Root
@onready var essence_label: Label = $Root/Panel/VBox/EssenceLabel
@onready var items_list: VBoxContainer = $Root/Panel/VBox/ItemsScroll/ItemsList
@onready var close_button: Button = $Root/Panel/VBox/TitleRow/CloseButton


func _ready() -> void:
	add_to_group("shop_screen")

	close_button.pressed.connect(close)
	SkillManager.essence_changed.connect(_refresh)
	InventoryManager.inventory_changed.connect(_refresh)
	_refresh()


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


func _refresh() -> void:
	essence_label.text = "Monster Essence: %d" % SkillManager.essence

	for child in items_list.get_children():
		child.queue_free()

	var item_ids: Array = ItemDatabase.SHOP.keys()
	if item_ids.is_empty():
		var empty_label := Label.new()
		empty_label.text = "(nothing for sale yet)"
		items_list.add_child(empty_label)
		return

	for item_id in item_ids:
		items_list.add_child(_build_row(item_id))


func _build_row(item_id: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

	var swatch := ColorRect.new()
	swatch.custom_minimum_size = Vector2(28, 28)
	swatch.color = ItemDatabase.get_color(item_id)
	row.add_child(swatch)

	var cost: int = ItemDatabase.get_shop_cost(item_id)
	var owned: int = InventoryManager.get_quantity(item_id)
	var stack_max: int = ItemDatabase.get_stack_max(item_id)

	var label := Label.new()
	label.text = "%s  x%d owned — %d essence" % [
		ItemDatabase.get_display_name(item_id),
		owned,
		cost,
	]
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.tooltip_text = String(ItemDatabase.get_definition(item_id).get("description", ""))
	row.add_child(label)

	var buy_button := Button.new()
	buy_button.text = "Buy"
	buy_button.disabled = SkillManager.essence < cost or owned >= stack_max
	buy_button.pressed.connect(_on_buy_pressed.bind(item_id))
	row.add_child(buy_button)

	return row


func _on_buy_pressed(item_id: String) -> void:
	var cost: int = ItemDatabase.get_shop_cost(item_id)
	if not SkillManager.spend_essence(cost):
		return
	InventoryManager.add_item(item_id, 1)
