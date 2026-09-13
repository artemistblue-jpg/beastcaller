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
@onready var notification_label: Label = $NotificationLabel
@onready var notification_timer: Timer = $NotificationTimer


func _ready() -> void:
	MonsterRoster.roster_changed.connect(_refresh_roster)
	_refresh_roster()

	GauntletManager.gauntlet_changed.connect(_refresh_gauntlet)
	_refresh_gauntlet()

	SkillManager.essence_changed.connect(_refresh_essence)
	_refresh_essence()

	restart_button.pressed.connect(_on_restart_pressed)
	restart_confirm.confirmed.connect(_on_restart_confirmed)

	InventoryManager.item_obtained.connect(_on_item_obtained)
	notification_timer.timeout.connect(_on_notification_timeout)

	call_deferred("_find_player")


## Quick "+N Item Name" pop, tinted with the item's own inventory color,
## every time something is actually added to the inventory (gathering,
## loot drops, crafting output, shop buys — see
## InventoryManager.item_obtained).
func _on_item_obtained(item_id: String, amount: int) -> void:
	show_notification("+%d %s" % [amount, ItemDatabase.get_display_name(item_id)], ItemDatabase.get_color(item_id))


## Generic one-line on-screen pop — used for item pickups above and for
## a failed tame attempt (see player.gd's _try_tame(), which looks this
## HUD up via the "hud" group and calls this directly rather than
## needing its own dedicated notification UI). A pop that arrives while
## another is still showing just restarts the same timer/label instead
## of queuing, so the newer one simply keeps the notice on screen a bit
## longer rather than stacking multiple lines.
func show_notification(text: String, color: Color = Color(1, 1, 1, 1), duration: float = 1.2) -> void:
	notification_label.text = text
	notification_label.modulate = color
	notification_label.visible = true
	notification_timer.start(duration)


func _on_notification_timeout() -> void:
	notification_label.visible = false


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
