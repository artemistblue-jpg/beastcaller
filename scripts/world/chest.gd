extends StaticBody3D

## A lootable chest — replaces the old one-time hand-placed item
## pickups (see item_pickup.gd; that script/scene are left in the
## project unused for now rather than deleted, in case a future quest
## wants a genuine no-strings pickup). Walk up and press the interact
## key (E) or the on-screen TAME button (see player.gd's
## _try_interact()/_try_open_chest()) — opening ALWAYS requires
## watching a rewarded ad first (see AdManager). That's the whole point
## of this system: Tommy's chosen source of ad revenue, so there is
## deliberately no free "just open it" path.
##
## Not meant to be hand-placed directly in a map — see
## chest_spawner.gd, which scatters these across scattered points
## around the map and brings a fresh one back (at a randomized nearby
## spot, not the exact same one) after a cooldown once this one's
## been looted.

signal opened

@export var essence_min: int = 10
@export var essence_max: int = 25

## Every open also gives ONE randomly chosen bonus item from this pool
## (item_id -> relative weight) instead of a fixed guaranteed item, so
## chests don't feel like "the herb one" / "the sigil one" the way the
## old fixed-position pickups did.
const LOOT_TABLE: Dictionary = {
	"herb": 5,
	"ore": 5,
	"battery_cell": 2,
	"ancient_sigil": 1,
}

var _opened: bool = false
var _ad_in_progress: bool = false


func _ready() -> void:
	add_to_group("chest")


func can_open() -> bool:
	return not _opened and not _ad_in_progress


## Called by the player (see player.gd's _try_open_chest()). This only
## ever STARTS the ad — the loot is granted solely from _grant_loot(),
## which AdManager only calls once the ad is actually watched through.
## Never grant anything from here, or a skipped/failed ad would still
## pay out.
func request_open() -> void:
	if not can_open():
		return
	_ad_in_progress = true
	AdManager.show_rewarded_ad(_grant_loot)


func _grant_loot() -> void:
	if _opened:
		return
	_opened = true
	_ad_in_progress = false

	SkillManager.add_essence(randi_range(essence_min, essence_max))

	var item_id := _pick_loot_item()
	if item_id != "" and ItemDatabase.has_item(item_id):
		InventoryManager.add_item(item_id, 1)

	opened.emit()
	_notify_spawner_removed()
	queue_free()


func _pick_loot_item() -> String:
	var total_weight: int = 0
	for weight in LOOT_TABLE.values():
		total_weight += int(weight)
	if total_weight <= 0:
		return ""

	var roll: int = randi_range(1, total_weight)
	var running_total: int = 0
	for item_id in LOOT_TABLE.keys():
		running_total += int(LOOT_TABLE[item_id])
		if roll <= running_total:
			return item_id
	return ""


## Same spot-respawn hookup CreatureSpawner already uses for creatures
## (see creature_ai.gd/wild_monster.gd) — reused as-is here rather than
## renamed to something chest-specific, since renaming the base
## script's method would break every existing spawner's wiring.
func _notify_spawner_removed() -> void:
	var spawner := get_parent()
	if spawner and spawner.has_method("notify_creature_removed"):
		spawner.notify_creature_removed()
