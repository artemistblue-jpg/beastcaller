extends CanvasLayer

## Minimal always-on HUD: player HP, how many monsters you've tamed
## overall, who's currently in your active squad, and a manual Restart
## button for testing — wipes all progress and jumps straight back to
## a brand-new game (intro dialogue included) without needing to
## uninstall the app or clear its data by hand. See
## SaveManager.restart_game().

@onready var health_label: Label = $Margin/VBox/HealthLabel
@onready var gauntlet_label: Label = $Margin/VBox/GauntletLabel
@onready var essence_label: Label = $Margin/VBox/EssenceLabel
@onready var collection_label: Label = $Margin/VBox/CollectionLabel
@onready var squad_label: Label = $Margin/VBox/SquadLabel
@onready var restart_button: Button = $RestartButton
@onready var restart_confirm: ConfirmationDialog = $RestartConfirm


func _ready() -> void:
	MonsterRoster.roster_changed.connect(_refresh_roster)
	_refresh_roster()

	GauntletManager.gauntlet_changed.connect(_refresh_gauntlet)
	_refresh_gauntlet()

	SkillManager.essence_changed.connect(_refresh_essence)
	_refresh_essence()

	restart_button.pressed.connect(_on_restart_pressed)
	restart_confirm.confirmed.connect(_on_restart_confirmed)

	call_deferred("_find_player")


## Confirm-then-restart rather than acting on the first tap — this
## wipes ALL progress with no undo, and it's a one-thumb button that's
## easy to fat-finger on a phone.
func _on_restart_pressed() -> void:
	restart_confirm.popup_centered()


func _on_restart_confirmed() -> void:
	SaveManager.restart_game()


func _find_player() -> void:
	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return

	var player: Node = players[0]
	if not player.has_node("HealthComponent"):
		return

	var health: HealthComponent = player.get_node("HealthComponent")
	health.health_changed.connect(_on_player_health_changed)
	_on_player_health_changed(health.current_health, health.max_health)


func _on_player_health_changed(current: float, max_health: float) -> void:
	health_label.text = "HP: %d / %d" % [round(current), round(max_health)]


func _refresh_gauntlet() -> void:
	gauntlet_label.text = "Gauntlet: %d / %d (%s)" % [
		round(GauntletManager.energy),
		round(GauntletManager.get_max_energy()),
		GauntletManager.get_tier_name(),
	]


func _refresh_essence() -> void:
	essence_label.text = "Essence: %d" % SkillManager.essence


func _refresh_roster() -> void:
	collection_label.text = "Collected: %d" % MonsterRoster.collection.size()

	if MonsterRoster.active_squad.is_empty():
		squad_label.text = "Squad: (empty)"
		return

	var text := "Squad: "
	for i in MonsterRoster.active_squad.size():
		if i > 0:
			text += ", "
		text += String(MonsterRoster.active_squad[i].get("species_name", "Monster"))

	squad_label.text = text
