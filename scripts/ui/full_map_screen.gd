extends CanvasLayer

## The big map you get by tapping the minimap widget (see minimap.gd) —
## same MapView drawing code as the corner widget, just larger, plus a
## color legend since blips alone don't say what they are. Also
## toggleable with the "toggle_map" key for quick desktop testing,
## mirroring every other full-screen UI in this project
## (skill_screen.gd, quest_screen.gd, shop_screen.gd, ...).

## group id -> friendly legend text. Kept separate from MapView's own
## GROUP_COLORS (which is about drawing, not wording) so this screen
## can label things without MapView needing to know it's being labeled.
const LEGEND_LABELS: Dictionary = {
	"hostile": "Hostile Creature",
	"wild_monster": "Wild Monster",
	"shop_npc": "Shop",
	"gatherable": "Resource Node",
}

@onready var root: Control = $Root
@onready var map_view: Control = $Root/Panel/VBox/MapView
@onready var legend_row: Control = $Root/Panel/VBox/LegendRow
@onready var close_button: Button = $Root/Panel/VBox/TitleRow/CloseButton


func _ready() -> void:
	add_to_group("full_map_screen")
	close_button.pressed.connect(close)
	_build_legend()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_map"):
		toggle()
		get_viewport().set_input_as_handled()


func toggle() -> void:
	if root.visible:
		close()
	else:
		open()


func open() -> void:
	root.visible = true
	map_view.queue_redraw()


func close() -> void:
	root.visible = false


func _build_legend() -> void:
	legend_row.add_child(_build_legend_entry(Color(1.0, 1.0, 1.0), "You"))
	for group_name in LEGEND_LABELS.keys():
		var color: Color = map_view.GROUP_COLORS.get(group_name, Color.WHITE)
		legend_row.add_child(_build_legend_entry(color, String(LEGEND_LABELS[group_name])))


func _build_legend_entry(color: Color, label_text: String) -> Control:
	var entry := HBoxContainer.new()
	entry.add_theme_constant_override("separation", 4)

	var swatch := ColorRect.new()
	swatch.custom_minimum_size = Vector2(10, 10)
	swatch.color = color
	entry.add_child(swatch)

	var label := Label.new()
	label.text = label_text
	label.add_theme_font_size_override("font_size", 12)
	entry.add_child(label)

	return entry
