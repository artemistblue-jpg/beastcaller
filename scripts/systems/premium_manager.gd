extends Node

## Autoload singleton: the ONE place anything checks whether the player
## owns premium. Same "simulated placeholder, real thing wired in later"
## shape as ad_manager.gd — there's no real store/purchase flow yet, so
## is_premium just starts at DEFAULT_IS_PREMIUM below rather than coming
## from an actual purchase record.
##
## First (and so far only) feature gated behind this: the squad
## RELEASE/RECALL button (see touch_controls.gd) — sending your tamed
## squad off to fight independently is meant to be a premium perk.
## Future premium features should check is_premium the same way rather
## than growing their own flag.
##
## HOW TO WIRE UP A REAL PURCHASE FLOW LATER — like ad_manager.gd, none
## of this can be done through file edits alone, it needs the Godot
## editor UI, a Play/App Store developer account, and a real device:
##   1. Create a one-time, non-consumable "premium" in-app product in
##      Google Play Console (and Apple's equivalent if this ever ships
##      on iOS).
##   2. Install a Godot billing plugin (e.g. the Poing Studios Google
##      Play Billing plugin) the same way ad_manager.gd's real-AdMob
##      steps describe — AssetLib or res://addons/, then enable it under
##      the Android export preset's Gradle Build > Plugins.
##   3. Back in THIS file: replace purchase_premium() with a real call
##      into the plugin's purchase flow, and set is_premium from the
##      plugin's "owned purchases" query on startup (and again whenever
##      a purchase completes) instead of DEFAULT_IS_PREMIUM below.
##   4. Persist the result in SaveManager (same pattern as
##      MonsterRoster.squad_independent) so a player who bought premium
##      still has it after closing the app, even before the store
##      re-confirms the purchase on next launch.
##   5. CI note: same as ad_manager.gd — the plugin's files and export
##      preset changes need to be committed, not just installed locally.

signal premium_changed(is_premium: bool)

## True for now so development/testing isn't gated by a paywall that has
## no real purchase flow behind it yet. Flip this to false once premium
## actually needs to mean something for real players.
const DEFAULT_IS_PREMIUM: bool = true

var is_premium: bool = DEFAULT_IS_PREMIUM


## Simulated purchase — grants premium instantly, no real payment
## involved. See the file-level comment for what replaces this once a
## real store purchase flow is wired up.
func purchase_premium() -> void:
	if is_premium:
		return
	is_premium = true
	premium_changed.emit(true)
