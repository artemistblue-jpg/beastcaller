extends Node

## Autoload singleton: one-time contextual tutorial tips for new players.
## Every tip has a unique string id; show_tip() is safe to call
## repeatedly (every physics frame, even — see player.gd's
## _update_tutorial_triggers()) since it only actually fires the first
## time a given id is shown. After that, shown_tips remembers it forever
## (persisted via SaveManager, same pattern as every other system — see
## to_save_data()/load_save_data() and world.gd), so a tip never repeats
## once seen, including across app restarts on the same save.
##
## Doesn't touch the HUD directly — it just announces tip_ready and lets
## hud.gd own the actual on-screen banner/queue, matching how the rest of
## the project keeps autoloads decoupled from any specific scene (see
## InventoryManager.item_obtained -> hud.gd for the same pattern).

signal tip_ready(text: String)

var shown_tips: Array[String] = []


func show_tip(tip_id: String, text: String) -> void:
	if shown_tips.has(tip_id):
		return
	shown_tips.append(tip_id)
	tip_ready.emit(text)


func has_shown(tip_id: String) -> bool:
	return shown_tips.has(tip_id)


## Marks a tip as already-seen with no popup and no signal — the
## migration case below, where the tip genuinely doesn't need showing at
## all, unlike show_tip() which always announces the first time.
func _mark_shown(tip_id: String) -> void:
	if not shown_tips.has(tip_id):
		shown_tips.append(tip_id)


## Called once from world.gd for a save with no "tutorial" entry at all
## (i.e. one made before this system existed) — backfills the tips an
## already-playing save's owner obviously doesn't need anymore, so
## returning players aren't suddenly flooded with beginner popups.
## Deliberately leaves "chests" and "shop" un-backfilled: those two are
## brief and low-friction enough that seeing one again isn't a real
## nuisance, and there's no single reliable "already knows this" signal
## for either the way there is for the others below.
func migrate_existing_progress() -> void:
	_mark_shown("movement")

	if not MonsterRoster.collection.is_empty():
		_mark_shown("taming")
		_mark_shown("squad")

	if not InventoryManager.items.is_empty():
		_mark_shown("gathering")
		_mark_shown("inventory")
		_mark_shown("crafting")

	if SkillManager.essence > 0:
		_mark_shown("essence")


## Used by SaveManager.restart_game() — a fresh game should see every tip
## again from scratch, same as any other brand-new save.
func reset() -> void:
	shown_tips.clear()


func to_save_data() -> Dictionary:
	return {"shown": shown_tips}


func load_save_data(data: Dictionary) -> void:
	shown_tips.clear()
	for entry in data.get("shown", []):
		if entry is String:
			shown_tips.append(entry)
