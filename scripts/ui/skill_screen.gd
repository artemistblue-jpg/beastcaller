extends CanvasLayer

## Full-screen skill sphere UI: spend Monster Essence to level up any of
## SkillManager's uncapped skills (see skill_manager.gd). Its own
## separate screen rather than an inventory tab, since the skill sphere
## is its own system, not an item category. Toggled by the
## "toggle_skills" key or the on-screen SKILL button (see
## touch_controls.gd), and refreshes live off SkillManager's signals.

@onready var root: Control = $Root
@onready var essence_label: Label = $Root/Panel/VBox/EssenceLabel
@onready var skills_list: VBoxContainer = $Root/Panel/VBox/SkillsScroll/SkillsList
@onready var close_button: Button = $Root/Panel/VBox/TitleRow/CloseButton


func _ready() -> void:
	add_to_group("skill_screen")

	close_button.pressed.connect(close)
	SkillManager.essence_changed.connect(_refresh)
	SkillManager.skill_changed.connect(func(_skill_id): _refresh())
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_skills"):
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
	essence_label.text = "Monster Essence: %d" % SkillManager.essence

	for child in skills_list.get_children():
		child.queue_free()

	for skill_id in SkillManager.SKILLS.keys():
		skills_list.add_child(_build_skill_row(skill_id))


func _build_skill_row(skill_id: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

	var skill_def: Dictionary = SkillManager.SKILLS.get(skill_id, {})
	var level: int = SkillManager.get_skill_level(skill_id)
	var next_cost: int = SkillManager.cost_for_next_level(skill_id)

	var swatch := ColorRect.new()
	swatch.custom_minimum_size = Vector2(28, 28)
	swatch.color = Color(0.75, 0.55, 0.85)
	row.add_child(swatch)

	var label := Label.new()
	label.text = "%s — Lv %d  (next: %d essence)" % [
		String(skill_def.get("name", skill_id)),
		level,
		next_cost,
	]
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.tooltip_text = String(skill_def.get("description", ""))
	row.add_child(label)

	var level_button := Button.new()
	level_button.text = "Level Up"
	level_button.disabled = not SkillManager.can_level_up(skill_id)
	level_button.pressed.connect(_on_level_up_pressed.bind(skill_id))
	row.add_child(level_button)

	return row


func _on_level_up_pressed(skill_id: String) -> void:
	SkillManager.level_up(skill_id)
