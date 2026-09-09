extends CanvasLayer

## Minimal always-on HUD: player HP, how many monsters you've tamed
## overall, and who's currently in your active squad.

@onready var health_label: Label = $Margin/VBox/HealthLabel
@onready var collection_label: Label = $Margin/VBox/CollectionLabel
@onready var squad_label: Label = $Margin/VBox/SquadLabel


func _ready() -> void:
	MonsterRoster.roster_changed.connect(_refresh_roster)
	_refresh_roster()
	call_deferred("_find_player")


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
