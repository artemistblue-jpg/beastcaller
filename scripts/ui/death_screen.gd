extends CanvasLayer

## Shown the instant the player dies (see player.gd's _on_died()) instead
## of the old free "wait a few seconds and you're back up" respawn.
## Dying now costs something — same philosophy as chests always
## requiring a rewarded ad (see chest.gd/AdManager): pay a cut of your
## Monster Essence to revive on the spot, or watch a rewarded ad and
## revive for free. Deliberately no third "just wait it out" option, and
## no close button — the only way out of this screen is one of the two
## buttons.
##
## Doesn't use signals: player.gd hands show_death() a Callable to run
## the instant either revive path actually pays off, mirroring how
## AdManager.show_rewarded_ad()/chest.gd already pass a reward callback
## around instead of wiring up a one-off signal for it.

## Fraction of current essence charged for an instant revive, rounded up
## so even a very low essence balance still costs at least 1 (unless
## it's exactly 0, in which case reviving is free anyway).
@export var essence_cost_fraction: float = 0.02

@onready var root: Control = $Root
@onready var cost_label: Label = $Root/Panel/VBox/CostLabel
@onready var pay_button: Button = $Root/Panel/VBox/ButtonRow/PayButton
@onready var ad_button: Button = $Root/Panel/VBox/ButtonRow/AdButton
@onready var ad_status_label: Label = $Root/Panel/VBox/AdStatusLabel

var _on_revived: Callable = Callable()
var _ad_in_progress: bool = false


func _ready() -> void:
	add_to_group("death_screen")
	root.visible = false
	pay_button.pressed.connect(_on_pay_pressed)
	ad_button.pressed.connect(_on_ad_pressed)
	SkillManager.essence_changed.connect(_refresh_cost_label)


## Called by player.gd the moment it dies. on_revived is invoked exactly
## once, however the player chooses to come back.
func show_death(on_revived: Callable) -> void:
	_on_revived = on_revived
	_ad_in_progress = false
	ad_status_label.text = ""
	pay_button.disabled = false
	ad_button.disabled = false
	_refresh_cost_label()
	root.visible = true


func get_essence_cost() -> int:
	return int(ceil(SkillManager.essence * essence_cost_fraction))


func _refresh_cost_label() -> void:
	var cost: int = get_essence_cost()
	if cost <= 0:
		cost_label.text = "You died. Revive for free, or watch an ad — your call."
	else:
		cost_label.text = "You died. Revive now for %d Essence, or watch an ad to revive for free." % cost
	pay_button.text = "Revive (%d Essence)" % cost


func _on_pay_pressed() -> void:
	if _ad_in_progress:
		return
	var cost: int = get_essence_cost()
	if cost > 0:
		SkillManager.spend_essence(cost)
	_finish_revive()


func _on_ad_pressed() -> void:
	if _ad_in_progress:
		return
	_ad_in_progress = true
	pay_button.disabled = true
	ad_button.disabled = true
	ad_status_label.text = "Watching ad..."
	AdManager.show_rewarded_ad(_finish_revive)


func _finish_revive() -> void:
	root.visible = false
	var callback := _on_revived
	_on_revived = Callable()
	if callback.is_valid():
		callback.call()
