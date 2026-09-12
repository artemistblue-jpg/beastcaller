extends CanvasLayer

## Full-screen quest log: every currently active quest, its description,
## and live objective progress — refreshed off both QuestManager's own
## signals and whatever those objectives actually track (inventory,
## roster, gauntlet, skills), so numbers move the instant they change
## rather than only when a quest completes. Toggled by the
## "toggle_quests" key or the on-screen QUEST button (see
## touch_controls.gd) — same pattern as skill_screen.gd/shop_screen.gd.

@onready var root: Control = $Root
@onready var summary_label: Label = $Root/Panel/VBox/SummaryLabel
@onready var quests_list: VBoxContainer = $Root/Panel/VBox/QuestsScroll/QuestsList
@onready var close_button: Button = $Root/Panel/VBox/TitleRow/CloseButton


func _ready() -> void:
	add_to_group("quest_screen")

	close_button.pressed.connect(close)
	QuestManager.quests_changed.connect(_refresh)
	InventoryManager.inventory_changed.connect(_refresh)
	MonsterRoster.roster_changed.connect(_refresh)
	GauntletManager.gauntlet_changed.connect(_refresh)
	SkillManager.skill_changed.connect(func(_skill_id): _refresh())
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_quests"):
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


func _refresh() -> void:
	summary_label.text = "%d active - %d completed" % [
		QuestManager.active_quests.size(),
		QuestManager.completed_quests.size(),
	]

	for child in quests_list.get_children():
		child.queue_free()

	if QuestManager.active_quests.is_empty():
		var empty_label := Label.new()
		empty_label.text = "No active quests right now — check back after your next adventure."
		empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD
		quests_list.add_child(empty_label)
		return

	for quest_id in QuestManager.active_quests:
		quests_list.add_child(_build_quest_block(quest_id))


func _build_quest_block(quest_id: String) -> Control:
	var definition: Dictionary = QuestManager.QUESTS.get(quest_id, {})

	var block := VBoxContainer.new()
	block.add_theme_constant_override("separation", 2)

	var title_label := Label.new()
	title_label.text = String(definition.get("title", quest_id))
	title_label.add_theme_font_size_override("font_size", 18)
	block.add_child(title_label)

	var description_label := Label.new()
	description_label.text = String(definition.get("description", ""))
	description_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	description_label.modulate = Color(1.0, 1.0, 1.0, 0.7)
	block.add_child(description_label)

	for objective in definition.get("objectives", []):
		var progress: Vector2i = QuestManager.get_objective_progress(objective)
		var done: bool = progress.x >= progress.y
		var objective_label := Label.new()
		objective_label.text = "  - %s (%d/%d)%s" % [
			String(objective.get("label", "")),
			min(progress.x, progress.y),
			progress.y,
			"  [done]" if done else "",
		]
		if done:
			objective_label.modulate = Color(0.55, 0.9, 0.55)
		block.add_child(objective_label)

	var reward_label := Label.new()
	reward_label.text = "Reward: %s" % _describe_rewards(definition.get("rewards", {}))
	reward_label.modulate = Color(0.85, 0.75, 0.4)
	block.add_child(reward_label)

	block.add_child(HSeparator.new())

	return block


func _describe_rewards(rewards: Dictionary) -> String:
	var parts: Array[String] = []
	if rewards.has("essence"):
		parts.append("%d Essence" % int(rewards["essence"]))
	var reward_items: Dictionary = rewards.get("items", {})
	for item_id in reward_items.keys():
		parts.append("%dx %s" % [int(reward_items[item_id]), ItemDatabase.get_display_name(item_id)])
	if parts.is_empty():
		return "-"
	return ", ".join(parts)
