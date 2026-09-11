extends CanvasLayer

## Global dialogue box: the "voice in your head", NPC conversations, and
## quest text all go through this one reusable system instead of each
## needing their own UI. Autoloaded (see project.godot) so any script,
## anywhere, can call DialogueBox.say([...]) without needing a scene
## reference.
##
## Lines show one at a time; tap/click the box (or press E/Space on
## desktop) to advance. Gameplay code should check is_active() to freeze
## movement/actions while a conversation is playing — see player.gd's
## _physics_process/_try_attack/_try_tame for how that's wired up.

signal dialogue_started
signal dialogue_finished

@onready var root: Control = $Root
@onready var panel_button: Button = $Root/DialoguePanel
@onready var speaker_label: Label = $Root/DialoguePanel/VBox/SpeakerLabel
@onready var text_label: Label = $Root/DialoguePanel/VBox/TextLabel

var _lines: Array = []
var _index: int = -1
var _on_finished: Callable = Callable()


func _ready() -> void:
	panel_button.pressed.connect(_advance)


func _unhandled_input(event: InputEvent) -> void:
	if not root.visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_E or event.physical_keycode == KEY_SPACE:
			_advance()
			get_viewport().set_input_as_handled()


## lines: Array of either plain Strings (shown with no speaker name) or
## Dictionaries shaped {"speaker": String, "text": String}.
## on_finished (optional): called once the player has advanced past the
## last line — use it to resume gameplay, start a quest, etc.
func say(lines: Array, on_finished: Callable = Callable()) -> void:
	if lines.is_empty():
		return
	_lines = lines
	_index = -1
	_on_finished = on_finished
	root.visible = true
	dialogue_started.emit()
	_advance()


func is_active() -> bool:
	return root.visible


func _advance() -> void:
	_index += 1
	if _index >= _lines.size():
		_close()
		return
	_show_line(_lines[_index])


func _show_line(line: Variant) -> void:
	if line is String:
		speaker_label.text = ""
		speaker_label.visible = false
		text_label.text = line
	else:
		var line_dict: Dictionary = line
		var speaker: String = String(line_dict.get("speaker", ""))
		speaker_label.text = speaker
		speaker_label.visible = speaker != ""
		text_label.text = String(line_dict.get("text", ""))


func _close() -> void:
	root.visible = false
	_lines = []
	_index = -1
	var callback := _on_finished
	_on_finished = Callable()
	dialogue_finished.emit()
	if callback.is_valid():
		callback.call()
