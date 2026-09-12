extends Node

## Autoload singleton (registered as "ElementSystem" in project.godot) —
## no class_name here on purpose, for the exact reason item_database.gd
## gives: an autoloaded script's class_name would shadow the actual
## autoload instance everywhere and break every call into it.
##
## Shared elemental typing + combat-role system for every creature in the
## game — hostile wildlife, passive wild monsters, and the player's own
## tamed squad all read from this table. Each creature exports one
## Element and one Role (see creature_ai.gd / wild_monster.gd):
##   - Element decides who it hits hard/soft against in combat — see
##     get_damage_multiplier().
##   - Role decides its combat stat profile and gives it one small bit of
##     extra behavior — see ROLE_STAT_MULTIPLIERS and each creature
##     script's _apply_role_stats()/_try_heal_ally()/mage range boost.
##
## Both are stored as plain ints on the creature (via @export_enum, to
## keep the editor dropdown working without every script needing to
## reference this autoload's enum types directly) — the int values below
## are the source of truth for what those ints mean, and every export
## list elsewhere must stay in this exact order.

enum Element { NEUTRAL, FIRE, WATER, EARTH, WIND, DARK, LIGHT }
enum Role { ATTACKER, TANK, HEALER, MAGE }

const ELEMENT_NAMES: Dictionary = {
	Element.NEUTRAL: "Neutral",
	Element.FIRE: "Fire",
	Element.WATER: "Water",
	Element.EARTH: "Earth",
	Element.WIND: "Wind",
	Element.DARK: "Dark",
	Element.LIGHT: "Light",
}

## Used for the health-bar element dot and any other "at a glance" UI —
## not meant to be a precise design-doc color, just a quick visual tell.
const ELEMENT_COLORS: Dictionary = {
	Element.NEUTRAL: Color(0.75, 0.75, 0.75),
	Element.FIRE: Color(0.9, 0.35, 0.15),
	Element.WATER: Color(0.25, 0.55, 0.95),
	Element.EARTH: Color(0.55, 0.4, 0.2),
	Element.WIND: Color(0.55, 0.9, 0.6),
	Element.DARK: Color(0.4, 0.2, 0.55),
	Element.LIGHT: Color(0.95, 0.9, 0.5),
}

const ROLE_NAMES: Dictionary = {
	Role.ATTACKER: "Attacker",
	Role.TANK: "Tank",
	Role.HEALER: "Healer",
	Role.MAGE: "Mage",
}

## Each element is strong against exactly one other, and — symmetrically
## — weak against whichever element is strong against it. A four-way
## cycle for the physical elements (Fire scorches Earth, Earth grounds
## Wind, Wind wears down Water, Water douses Fire) plus a straight
## Light/Dark rivalry. Neutral sits outside the whole chart: see
## get_damage_multiplier() — it never gets a bonus and never gets
## resisted, in either direction.
const STRONG_AGAINST: Dictionary = {
	Element.FIRE: Element.EARTH,
	Element.EARTH: Element.WIND,
	Element.WIND: Element.WATER,
	Element.WATER: Element.FIRE,
	Element.LIGHT: Element.DARK,
	Element.DARK: Element.LIGHT,
}

const SUPER_EFFECTIVE_MULTIPLIER: float = 1.5
const RESISTED_MULTIPLIER: float = 0.65

## Per-role combat stat multipliers, applied on top of whatever base
## stats a creature's own .tscn already has tuned in — see each combat
## script's _apply_role_stats(). A role with no entry for a given stat
## (e.g. nothing overrides attack_range here) just leaves that stat at
## 1.0/unaffected by this table.
const ROLE_STAT_MULTIPLIERS: Dictionary = {
	Role.ATTACKER: {"max_health": 1.0, "attack_damage": 1.3, "move_speed": 1.0},
	Role.TANK: {"max_health": 1.6, "attack_damage": 0.75, "move_speed": 0.85},
	Role.HEALER: {"max_health": 0.85, "attack_damage": 0.6, "move_speed": 1.0},
	Role.MAGE: {"max_health": 0.75, "attack_damage": 1.15, "move_speed": 1.0},
}

## A Mage's effective attack range (both the AI's "stop and attack"
## distance and its actual AttackArea3D hit-sphere — see each combat
## script's mage range boost) gets multiplied by this so it visibly
## fights from further back instead of just hitting a little harder.
const MAGE_RANGE_MULTIPLIER: float = 2.2

## A Healer periodically mends the lowest-HP nearby ally (creature_ai.gd
## — covers hostile world creatures healing each other, and a player
## summon healing the player or a squadmate) or, for a solitary
## wild_monster with no allies around, itself.
const HEALER_HEAL_INTERVAL: float = 4.0
const HEALER_HEAL_AMOUNT: float = 12.0
const HEALER_HEAL_RADIUS: float = 8.0
const HEALER_SELF_HEAL_AMOUNT: float = 6.0

## MonsterRoster caps you at one of each species (see its
## add_to_collection()) — taming a duplicate doesn't add a second copy,
## it powers up the one you already have instead: +8% max HP and attack
## per repeat tame. Linear rather than compounding, always computed off
## the same stored base_max_health/base attack, so "power level 3" is
## always exactly +16%, not a moving target based on when it was last
## recalculated.
const POWER_BONUS_PER_LEVEL: float = 0.08


func get_power_multiplier(power_level: int) -> float:
	return 1.0 + float(max(power_level - 1, 0)) * POWER_BONUS_PER_LEVEL


## Combat damage multiplier for attacker_element hitting defender_element.
## Neutral is a hard exception on both sides — it's never in
## STRONG_AGAINST as a key or a value, but this checks explicitly anyway
## so the rule reads clearly here rather than relying on a table lookup
## quietly missing.
func get_damage_multiplier(attacker_element: Element, defender_element: Element) -> float:
	if attacker_element == Element.NEUTRAL or defender_element == Element.NEUTRAL:
		return 1.0
	if STRONG_AGAINST.get(attacker_element, -1) == defender_element:
		return SUPER_EFFECTIVE_MULTIPLIER
	if STRONG_AGAINST.get(defender_element, -1) == attacker_element:
		return RESISTED_MULTIPLIER
	return 1.0


func get_element_name(element: Element) -> String:
	return String(ELEMENT_NAMES.get(element, "Neutral"))


func get_element_color(element: Element) -> Color:
	return ELEMENT_COLORS.get(element, Color.WHITE)


func get_role_name(role: Role) -> String:
	return String(ROLE_NAMES.get(role, "Attacker"))


## What this element is strong against, for UI tooltips ("Strong vs
## Earth") — "" for Neutral, which has none.
func get_strong_against_name(element: Element) -> String:
	if not STRONG_AGAINST.has(element):
		return ""
	return get_element_name(STRONG_AGAINST[element])


## The reverse lookup — what's strong against this element ("Weak vs
## Water") — "" for Neutral.
func get_weak_against_name(element: Element) -> String:
	for attacker in STRONG_AGAINST:
		if STRONG_AGAINST[attacker] == element:
			return get_element_name(attacker)
	return ""
