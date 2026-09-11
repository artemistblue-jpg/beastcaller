extends "res://scripts/creatures/creature_ai.gd"

## The dying god's death scene, made real: the one-time boss whose defeat
## triggers the "voice goes silent" story beat that world.gd's intro
## dialogue TODO left dangling. Reuses creature_ai.gd's stats/combat
## wholesale (self_group "hostile", can_be_tamed false, much higher
## numbers set on the .tscn) and only adds the one-shot story trigger on
## death. Meant to be hand-placed ONCE directly in world.tscn — not
## spawned via a CreatureSpawner — so it never respawns after this scene.

const STORY_FLAG := "god_voice_silenced"


func _on_died() -> void:
	if not SaveManager.has_story_flag(STORY_FLAG):
		SaveManager.set_story_flag(STORY_FLAG)
		DialogueBox.say([
			"The creature falls still. For a moment, the world itself seems to hold its breath.",
			{"speaker": "???", "text": "...I felt that. The last thread just snapped."},
			{"speaker": "???", "text": "That's the end of what I can give you. My voice won't reach you again after this."},
			{"speaker": "???", "text": "Everything left standing between the Demon Lord and this world now... is you."},
		])
	super._on_died()
