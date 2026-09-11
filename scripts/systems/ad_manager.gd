extends Node

## Autoload singleton: the ONE place a rewarded-ad request goes through.
## Right now this is a placeholder/simulated ad (a short delay, then it
## always succeeds) — there's no real ad network wired up yet. Every
## caller (chest.gd, and anything else that gates a reward behind an ad
## later) should only ever go through show_rewarded_ad() and never
## assume anything about HOW the ad is shown, so swapping this file out
## for a real ad plugin later doesn't require touching chest.gd or
## anything else that calls it.
##
## HOW TO WIRE UP A REAL AD NETWORK (e.g. AdMob) LATER — none of this
## can be done through file edits alone, it needs the Godot editor UI,
## an AdMob (or other network) account, and a real device to test on:
##   1. Create an AdMob account, register the app, and create a
##      "Rewarded" ad unit — this gives you an App ID and an Ad Unit ID.
##   2. Install a Godot Android ads plugin (the Poing Studios AdMob
##      plugin is the most common one) via the AssetLib in the Godot
##      editor, or by dropping its release files into res://addons/.
##   3. In the Android export preset: enable "Use Gradle Build" +
##      "Custom Build", add the plugin under "Gradle Build > Plugins",
##      and put your AdMob App ID in the manifest section the plugin's
##      own README asks for (exact steps vary by plugin/Godot version —
##      follow that plugin's setup guide, not this comment).
##   4. Back in THIS file: replace _run_simulated_ad() below with a
##      real call into the plugin (e.g. its load_rewarded_ad() /
##      show_rewarded_ad()-equivalent autoload), and make is_ad_ready()
##      reflect whether the plugin actually has an ad loaded. Critically:
##      only ever call reward_callback.call() from inside the plugin's
##      "user earned reward" signal — never from a plain "ad closed" or
##      "ad shown" signal, or a player could skip the ad and still get
##      paid.
##   5. CI note: the GitHub Actions build (see .github/workflows) will
##      need the plugin's files present in the repo and the export
##      preset changes committed — a plugin that's only installed
##      locally in the editor won't make it into the CI-built APK.

signal rewarded_ad_started
signal rewarded_ad_finished(succeeded: bool)

## How long the simulated "ad" takes, so the flow feels (and can be
## tested) like a real rewarded ad rather than an instant freebie.
const SIMULATED_AD_SECONDS: float = 2.0

## True as long as this is the simulated stand-in rather than a real ad
## network. Not used for any gameplay logic — just here so UI can
## optionally show a "(test ad)" hint while this is still a placeholder.
var is_simulated: bool = true


## A real integration should make this reflect whether the ad network
## actually has a rewarded ad loaded right now, so callers (chest.gd)
## can grey out the "open" prompt instead of starting a show request
## that's just going to fail. The simulated stand-in is always "ready".
func is_ad_ready() -> bool:
	return true


## Shows the rewarded ad. reward_callback is invoked if and only if the
## player watches it through to completion — callers must not grant
## anything until this callback actually fires.
func show_rewarded_ad(reward_callback: Callable) -> void:
	rewarded_ad_started.emit()
	await _run_simulated_ad()
	rewarded_ad_finished.emit(true)
	if reward_callback.is_valid():
		reward_callback.call()


func _run_simulated_ad() -> void:
	await get_tree().create_timer(SIMULATED_AD_SECONDS).timeout
