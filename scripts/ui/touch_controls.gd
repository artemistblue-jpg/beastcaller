extends CanvasLayer

## On-screen mobile controls: a drag-stick for movement plus tap buttons
## for jump/attack/tame. Lives in the world scene as a sibling of the
## player and finds it lazily via the "player" group.

@onready var joystick: TouchJoystick = $JoystickBase
@onready var attack_button: Button = $ActionButtons/AttackButton
@onready var tame_button: Button = $ActionButtons/TameButton
@onready var jump_button: Button = $ActionButtons/JumpButton
@onready var bag_button: Button = $ActionButtons/BagButton
@onready var skill_button: Button = $ActionButtons/SkillButton
@onready var party_button: Button = $ActionButtons/PartyButton
@onready var quest_button: Button = $ActionButtons/QuestButton
@onready var release_button: Button = $ActionButtons/ReleaseButton

var _player: Node = null


func _ready() -> void:
	add_to_group("touch_controls")
	attack_button.pressed.connect(_on_attack_pressed)
	tame_button.pressed.connect(_on_tame_pressed)
	jump_button.pressed.connect(_on_jump_pressed)
	bag_button.pressed.connect(_on_bag_pressed)
	skill_button.pressed.connect(_on_skill_pressed)
	party_button.pressed.connect(_on_party_pressed)
	quest_button.pressed.connect(_on_quest_pressed)
	release_button.pressed.connect(_on_release_pressed)
	MonsterRoster.squad_mode_changed.connect(_refresh_release_button)
	# Also refresh if premium ever gets granted (e.g. a future "Buy
	# Premium" button) while this screen is already open, so the button
	# doesn't keep showing "PREMIUM" after the player's already bought it.
	PremiumManager.premium_changed.connect(func(_is_premium: bool) -> void: _refresh_release_button(MonsterRoster.squad_independent))
	_refresh_release_button(MonsterRoster.squad_independent)


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


func _on_bag_pressed() -> void:
	var inventory_screens := get_tree().get_nodes_in_group("inventory_screen")
	if inventory_screens.size() > 0 and inventory_screens[0].has_method("toggle"):
		inventory_screens[0].toggle()


func _on_skill_pressed() -> void:
	var skill_screens := get_tree().get_nodes_in_group("skill_screen")
	if skill_screens.size() > 0 and skill_screens[0].has_method("toggle"):
		skill_screens[0].toggle()


func _on_party_pressed() -> void:
	var party_screens := get_tree().get_nodes_in_group("party_screen")
	if party_screens.size() > 0 and party_screens[0].has_method("toggle"):
		party_screens[0].toggle()


func _on_quest_pressed() -> void:
	var quest_screens := get_tree().get_nodes_in_group("quest_screen")
	if quest_screens.size() > 0 and quest_screens[0].has_method("toggle"):
		quest_screens[0].toggle()


## Flips the whole squad between following the player and roaming/fighting
## on their own — see MonsterRoster.set_squad_independent(). Premium-gated
## (see premium_manager.gd) — currently unlocked for everyone by default
## since there's no real purchase flow yet, but the check is already in
## place so flipping PremiumManager.DEFAULT_IS_PREMIUM to false later is
## the only change needed to actually start gating it. The button label
## always reflects the CURRENT state (what pressing it will do is the
## opposite), same convention as a mute button showing a speaker icon
## when sound is on.
func _on_release_pressed() -> void:
	if not PremiumManager.is_premium:
		DialogueBox.say(["Releasing your squad to fight on their own is a premium feature."])
		return
	MonsterRoster.set_squad_independent(not MonsterRoster.squad_independent)


func _refresh_release_button(is_independent: bool) -> void:
	if not PremiumManager.is_premium:
		release_button.text = "PREMIUM"
		return
	release_button.text = "RECALL" if is_independent else "RELEASE"
