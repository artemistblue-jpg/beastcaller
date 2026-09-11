extends Node

## Autoload singleton: the player's capture gauntlet. Not a consumable
## like the old Capture Balls — a single owned tool with a tier (which
## creatures it's even allowed to attempt) and an energy pool that a
## tame attempt spends and Battery Cells refill. See ItemDatabase for
## battery/gauntlet-upgrade items and player.gd's _try_tame() for how
## this gates a capture attempt.

signal gauntlet_changed

const TIERS: Dictionary = {
	1: {"name": "Gauntlet I", "max_energy": 100.0},
	2: {"name": "Gauntlet II", "max_energy": 160.0},
	3: {"name": "Gauntlet III", "max_energy": 240.0},
}

var tier: int = 1
var energy: float = 100.0


func get_max_energy() -> float:
	return float(TIERS.get(tier, TIERS[1]).get("max_energy", 100.0))


func get_tier_name() -> String:
	return String(TIERS.get(tier, TIERS[1]).get("name", "Gauntlet"))


func can_capture(required_tier: int, energy_cost: float) -> bool:
	return tier >= required_tier and energy >= energy_cost


func spend_energy(amount: float) -> void:
	energy = max(energy - amount, 0.0)
	gauntlet_changed.emit()


func recharge(amount: float) -> void:
	energy = min(energy + amount, get_max_energy())
	gauntlet_changed.emit()


## Only ever moves to a higher tier, and tops off energy on the upgrade
## (a new gauntlet coming online fully charged reads better than an
## upgrade that leaves you unable to use it right away).
func upgrade_to(new_tier: int) -> bool:
	if not TIERS.has(new_tier) or new_tier <= tier:
		return false
	tier = new_tier
	energy = get_max_energy()
	gauntlet_changed.emit()
	return true


## Used by SaveManager.restart_game() — see there for why.
func reset() -> void:
	tier = 1
	energy = get_max_energy()
	gauntlet_changed.emit()


func to_save_data() -> Dictionary:
	return {"tier": tier, "energy": energy}


func load_save_data(data: Dictionary) -> void:
	tier = int(data.get("tier", 1))
	energy = float(data.get("energy", get_max_energy()))
	gauntlet_changed.emit()
