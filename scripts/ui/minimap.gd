extends CanvasLayer

## Small always-on map widget in the corner of the screen — tap/click it
## to open the big version (see full_map_screen.gd). The widget itself
## IS the button: a flat, textless Button wraps a MapView (see
## map_view.gd, mouse_filter set to IGNORE in the scene so clicks pass
## through it to the Button underneath) so the whole square is
## clickable rather than needing a separate overlay control.

@onready var map_button: Button = $Root/MapButton


func _ready() -> void:
	add_to_group("minimap")
	map_button.pressed.connect(_on_map_button_pressed)


func _on_map_button_pressed() -> void:
	var full_map_screens := get_tree().get_nodes_in_group("full_map_screen")
	if full_map_screens.size() > 0 and full_map_screens[0].has_method("open"):
		full_map_screens[0].open()
