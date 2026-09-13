extends CanvasLayer

## Reference screen for game mechanics — opened any time (HELP button on
## touch controls) rather than shown once like TutorialManager's
## contextual popups. Content is static and data-driven (see TOPICS)
## rather than reusing each tip's exact wording, since a player pulling
## this up wants the full picture in one place, not a replay of toasts
## they may or may not have actually seen yet.

@onready var root: Control = $Root
@onready var topics_list: VBoxContainer = $Root/Panel/VBox/TopicsScroll/TopicsList
@onready var close_button: Button = $Root/Panel/VBox/TitleRow/CloseButton

const TOPICS: Array[Dictionary] = [
	{
		"title": "Movement & Camera",
		"body": "Drag the joystick to move. Tap JUMP to get over obstacles. The camera stays fixed behind you.",
	},
	{
		"title": "Taming",
		"body": "Walk up to a wild monster and tap TAME to try to capture it with your gauntlet. Tougher monsters need a higher gauntlet tier, but you can still try at low odds if you're under-tiered. A failed attempt makes the monster more aggressive.",
	},
	{
		"title": "Combat & Gathering",
		"body": "Tap ATK to punch hostile creatures, or to gather from a nearby rock or tree. A chest or gatherable node in range always takes priority over a punch.",
	},
	{
		"title": "Your Squad",
		"body": "Tamed monsters join your squad and follow you automatically, helping you fight. Use PARTY to manage your squad, or RELEASE to send them off to roam and fight on their own (RECALL brings them back).",
	},
	{
		"title": "Inventory & Crafting",
		"body": "Tap BAG to see everything you're carrying. The Craft tab turns gathered materials (ore, herb, wood, fish, and more) into potions, gauntlet upgrades, tools, and other gear.",
	},
	{
		"title": "Chests",
		"body": "Chests scattered around the map need a short rewarded ad watched to open — that's how they stay free while still supporting the game.",
	},
	{
		"title": "The Shop",
		"body": "Find the merchant NPC and interact with them to spend Monster Essence directly on consumables and gauntlet upgrades — a faster alternative to gathering and crafting.",
	},
	{
		"title": "Essence & Skills",
		"body": "Defeating or taming monsters earns Monster Essence. Spend it on the skill sphere (SKILL) to permanently boost things like taming, crafting, mining, woodcutting, and fishing — or spend it at the shop instead.",
	},
	{
		"title": "Quests",
		"body": "Check QUEST for your current objectives. New quests unlock automatically into the log as you meet their requirements — no quest-giver to track down.",
	},
]


func _ready() -> void:
	add_to_group("help_screen")
	close_button.pressed.connect(close)
	_populate()


func toggle() -> void:
	if root.visible:
		close()
	else:
		open()


func open() -> void:
	root.visible = true


func close() -> void:
	root.visible = false


func _populate() -> void:
	for child in topics_list.get_children():
		child.queue_free()

	for topic in TOPICS:
		topics_list.add_child(_build_topic(topic))


func _build_topic(topic: Dictionary) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)

	var title_label := Label.new()
	title_label.text = String(topic.get("title", ""))
	title_label.add_theme_font_size_override("font_size", 18)
	title_label.add_theme_color_override("font_color", Color(1, 0.85, 0.2, 1))
	box.add_child(title_label)

	var body_label := Label.new()
	body_label.text = String(topic.get("body", ""))
	body_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	box.add_child(body_label)

	return box
