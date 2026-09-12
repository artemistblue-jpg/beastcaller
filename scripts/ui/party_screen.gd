extends CanvasLayer

## Full-screen party/roster UI: shows every monster in your active
## squad, whether it's fainted, and lets you spend Monster Essence to
## revive a fainted one (cost scales with how tough it is — see
## MonsterRoster.get_revive_cost()). Its own screen for the same reason
## the skill sphere got one — this is a whole system, not an inventory
## tab. Toggled by the "toggle_party" key or the on-screen PARTY button
## (see touch_controls.gd), and refreshes live off MonsterRoster's and
## SkillManager's signals (essence changes affect which revives you can
## currently afford).

@onready var root: Control = $Root
@onready var essence_label: Label = $Root/Panel/VBox/EssenceLabel
@onready var squad_list: VBoxContainer = $Root/Panel/VBox/SquadScroll/SquadList
@onready var close_button: Button = $Root/Panel/VBox/TitleRow/CloseButton


func _ready() -> void:
	add_to_group("party_screen")

	close_button.pressed.connect(close)
	MonsterRoster.roster_changed.connect(_refresh)
	SkillManager.essence_changed.connect(_refresh)
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_party"):
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

	for child in squad_list.get_children():
		child.queue_free()

	if MonsterRoster.active_squad.is_empty():
		var empty_label := Label.new()
		empty_label.text = "(no tamed monsters yet)"
		empty_label.modulate = Color(1.0, 1.0, 1.0, 0.6)
		squad_list.add_child(empty_label)
		return

	for i in MonsterRoster.active_squad.size():
		squad_list.add_child(_build_squad_row(i))


func _build_squad_row(index: int) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

	var monster_data: Dictionary = MonsterRoster.active_squad[index]
	var is_fainted: bool = monster_data.get("is_fainted", false)

	var swatch := ColorRect.new()
	swatch.custom_minimum_size = Vector2(28, 28)
	swatch.color = Color(0.45, 0.45, 0.45) if is_fainted else Color(0.35, 0.75, 0.5)
	row.add_child(swatch)

	var element_name: String = ElementSystem.get_element_name(monster_data.get("element", 0))
	var role_name: String = ElementSystem.get_role_name(monster_data.get("role", 0))

	var label := Label.new()
	var status_text: String = "Fainted" if is_fainted else "Active"
	label.text = "%s (%s / %s) — %s (%d HP)" % [
		String(monster_data.get("species_name", "Monster")),
		element_name,
		role_name,
		status_text,
		int(monster_data.get("max_health", 0)),
	]
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)

	if is_fainted:
		var cost: int = MonsterRoster.get_revive_cost(monster_data)
		var revive_button := Button.new()
		revive_button.text = "Revive (%d)" % cost
		revive_button.disabled = not MonsterRoster.can_revive(index)
		revive_button.pressed.connect(_on_revive_pressed.bind(index))
		row.add_child(revive_button)

	return row


func _on_revive_pressed(index: int) -> void:
	MonsterRoster.revive(index)
