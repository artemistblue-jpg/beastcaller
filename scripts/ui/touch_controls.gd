extends CanvasLayer

## On-screen mobile controls: a drag-stick for movement plus tap buttons
## for jump/attack/tame. Lives in the world scene as a sibling of the
## player and finds it lazily via the "player" group.

@onready var joystick: TouchJoystick = $JoystickBase
@onready var attack_button: Button = $ActionButtons/AttackButton
@onready var tame_button: Button = $ActionButtons/TameButton
@onready var jump_button: Button = $ActionButtons/JumpButton

var _player: Node = null


func _ready() -> void:
	add_to_group("touch_controls")
	attack_button.pressed.connect(_on_attack_pressed)
	tame_button.pressed.connect(_on_tame_pressed)
	jump_button.pressed.connect(_on_jump_pressed)


func get_movement_input() -> Vector2:
	return joystick.output


func _get_player() -> Node:
	if _player == null or not is_instance_valid(_player):
		var players := get_tree().get_nodes_in_group("player")
		if players.size() > 0:
			_player = players[0]
	return _player


func _on_attack_pressed() -> void:
	var player := _get_player()
	if player and player.has_method("request_attack"):
		player.request_attack()


func _on_tame_pressed() -> void:
	var player := _get_player()
	if player and player.has_method("request_tame"):
		player.request_tame()


func _on_jump_pressed() -> void:
	var player := _get_player()
	if player and player.has_method("request_jump"):
		player.request_jump()
