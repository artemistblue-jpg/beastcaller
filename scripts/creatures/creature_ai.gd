extends CharacterBody3D

## Generic real-time combatant AI, shared by hostile wildlife and the
## player's summoned monsters. Which one it is depends purely on the
## exported groups below — same script, opposite allegiances.

@export var move_speed: float = 2.5
@export var acceleration: float = 8.0
@export var detection_range: float = 12.0
@export var attack_range: float = 1.6
@export var attack_damage: float = 10.0
@export var attack_cooldown: float = 1.2
@export var species_name: String = "Monster"

## Elemental type + combat role — see element_system.gd (the "ElementSystem"
## autoload) for what each one actually does. Stored as plain ints rather
## than ElementSystem's own enum types so this export dropdown doesn't
## need to reference another autoload's script at parse time; the string
## lists below must stay in the exact same order as ElementSystem's
## Element/Role enums.
@export_enum("Neutral", "Fire", "Water", "Earth", "Wind", "Dark", "Light") var element: int = 0
@export_enum("Attacker", "Tank", "Healer", "Mage") var role: int = 0

## Group this creature belongs to (who it counts as, for others targeting it).
@export var self_group: StringName = &"hostile"
## Group this creature looks for targets in.
@export var target_group: StringName = &"player_side"
## Summoned monsters follow their owner when they have no target; hostile
## wildlife just stands its ground instead.
@export var follow_owner_when_idle: bool = false

## Aggressive creatures can also be tamed, but it's a riskier catch than a
## passive wild_monster: they never stop attacking while you weaken them,
## and their base capture chance should be set noticeably lower.
@export var can_be_tamed: bool = false
@export var tame_health_fraction: float = 0.25
@export var base_capture_chance: float = 0.3
@export var enrage_duration: float = 10.0
@export var enrage_speed_multiplier: float = 1.3
@export var enrage_damage_multiplier: float = 1.5

## Gauntlet gate for taming this creature — see GauntletManager and
## player.gd's _try_tame(). A creature tougher than the default should
## raise required_gauntlet_tier so a Mk I gauntlet can't even attempt it.
@export var required_gauntlet_tier: int = 1
@export var capture_energy_cost: float = 25.0
## Capture chance used instead of the normal calculation when the
## player's gauntlet tier is below required_gauntlet_tier — the attempt
## is still allowed, just a long shot.
@export var underleveled_capture_chance: float = 0.05

## Optional item drop on capture/death (see ItemDatabase). Only applies
## to world creatures (self_group "hostile"), not the player's own
## summons — see _drop_loot_if_world_creature().
@export var loot_item_id: String = ""
@export var loot_chance: float = 0.5
@export var loot_min: int = 1
@export var loot_max: int = 1

## Monster Essence (currency + skill-sphere fuel — see SkillManager)
## awarded every capture/death, unlike the chance-based loot_item_id
## above. Only applies to world creatures, same restriction as loot.
@export var essence_min: int = 8
@export var essence_max: int = 15

@onready var health: HealthComponent = $HealthComponent
@onready var attack_area: Area3D = $AttackArea3D

var gravity: float = ProjectSettings.get_setting(
	"physics/3d/default_gravity"
)

var owner_to_follow: Node3D = null
var target: Node3D = null
var attack_timer: float = 0.0
var retarget_timer: float = 0.0

## Which MonsterRoster.active_squad slot this instance is, for
## player-side summons only (see configure() and
## _notify_roster_if_player_summon()) — set at spawn time rather than
## assumed, so a squad member fainting always marks the right slot even
## if other members have already fainted/been revived around it.
var squad_index: int = -1

var is_tameable: bool = false
var is_enraged: bool = false
var enrage_timer: float = 0.0

## The scene's own tuned numbers, captured before any role multiplier is
## applied, so _apply_role_stats() always scales from the same starting
## point instead of compounding if it's called more than once (see
## configure(), which re-applies it once element/role arrive from
## captured save data).
var _base_max_health: float = 0.0
var _base_attack_damage: float = 0.0
var _base_move_speed: float = 0.0
var _base_attack_range: float = 0.0
var _mage_range_applied: bool = false

## Healer role only — see _try_heal_ally().
var _heal_timer: float = 0.0

## Every tamed species' summon uses this same generic scene
## (summon_monster.tscn) rather than its own species .tscn, so it has no
## built-in CreatureModel of its own — without this, a tamed monster's
## squad instance shows a plain placeholder instead of its real mesh
## (the wild/hostile version of the same species already has its own
## real model baked into its own .tscn; this table exists only to give
## the *summon* version the same look). Keep this in sync with each
## species .tscn's own CreatureModel ext_resource path.
const SPECIES_MODEL_PATHS: Dictionary = {
	"Ember Fang": "res://characters/monsters/dino.glb",
	"Duskwyrm": "res://characters/monsters/dragon_evolved.glb",
	"Tidewisp": "res://characters/monsters/glub.glb",
	"Glowmoth": "res://characters/monsters/ghost.glb",
	"Feral Stalker": "res://characters/monsters/goleling.glb",
	"Sparkit": "res://characters/monsters/pigeon.glb",
}

## How many times this exact species has been tamed — see
## MonsterRoster.add_to_collection()/_power_up(). Only ever arrives via
## configure() (a hand-placed wild/hostile creature stays at the default
## of 1, so ElementSystem.get_power_multiplier() is a no-op for it); see
## _apply_role_stats() for where it actually affects stats.
var power_level: int = 1

## Set by MonsterRoster.set_squad_independent() (the RELEASE/RECALL
## button — see touch_controls.gd) for player-side summons only. Once
## true, this summon stops following its owner entirely and wanders on
## its own instead — see set_independent() and _wander(). Combat itself
## doesn't change either way: an independent summon still fights
## whatever wanders into its own detection_range, same as always.
var is_independent: bool = false
var _wander_origin: Vector3 = Vector3.ZERO
var _wander_target: Vector3 = Vector3.ZERO
var _wander_timer: float = 0.0
const INDEPENDENT_WANDER_RADIUS: float = 10.0


func _ready() -> void:
	_base_max_health = health.max_health
	_base_attack_damage = attack_damage
	_base_move_speed = move_speed
	_base_attack_range = attack_range
	_apply_role_stats(true)
	_apply_mage_range_boost()

	add_to_group(self_group)
	health.died.connect(_on_died)
	if can_be_tamed:
		add_to_group("tameable")
		health.health_changed.connect(_on_health_changed)


## Recomputes move_speed/attack_damage/attack_range from the cached base
## stats plus the current role's multipliers (see
## ElementSystem.ROLE_STAT_MULTIPLIERS). max_health is only rescaled from
## the base when scale_health is true — configure() passes false because
## a tamed monster's captured max_health has already had its role
## multiplier baked in back when it was still a wild/hostile creature,
## so re-scaling it here again would double-apply it.
func _apply_role_stats(scale_health: bool) -> void:
	var mult: Dictionary = ElementSystem.ROLE_STAT_MULTIPLIERS.get(role, {})
	var power_mult: float = ElementSystem.get_power_multiplier(power_level)
	move_speed = _base_move_speed * float(mult.get("move_speed", 1.0))
	attack_damage = _base_attack_damage * float(mult.get("attack_damage", 1.0)) * power_mult
	attack_range = _base_attack_range
	if role == ElementSystem.Role.MAGE:
		attack_range *= ElementSystem.MAGE_RANGE_MULTIPLIER

	if scale_health and health:
		var new_max: float = _base_max_health * float(mult.get("max_health", 1.0)) * power_mult
		health.max_health = new_max
		health.current_health = new_max
		health.health_changed.emit(health.current_health, health.max_health)


## A Mage's bigger attack_range (see _apply_role_stats()) only changes
## when the AI decides to stop chasing and swing — the actual hit
## detection is a separate physical AttackArea3D collision shape, which
## needs its own radius grown to match or a mage would stop at range and
## then whiff every attack. Sub-resources in a .tscn are shared across
## every instance of that scene, so this duplicates the shape before
## mutating it rather than resizing the shared original. Guarded by
## _mage_range_applied so calling this again later (configure() calls it
## once more after a tamed monster's real role arrives) never
## double-boosts an already-boosted shape.
func _apply_mage_range_boost() -> void:
	if role != ElementSystem.Role.MAGE or _mage_range_applied:
		return
	var shape_node: CollisionShape3D = attack_area.get_node_or_null("CollisionShape3D")
	if shape_node == null or shape_node.shape == null:
		return
	var boosted_shape: Shape3D = shape_node.shape.duplicate()
	if boosted_shape is SphereShape3D:
		(boosted_shape as SphereShape3D).radius *= ElementSystem.MAGE_RANGE_MULTIPLIER
	shape_node.shape = boosted_shape
	_mage_range_applied = true


func get_element() -> int:
	return element


func get_role() -> int:
	return role


## Called by MonsterRoster (set_squad_independent(), and _spawn_one() for
## anything that spawns while the squad is already set to independent).
## Turning it on takes a fresh wander origin from wherever this summon
## currently is, so it starts roaming from where it was released rather
## than snapping back toward some stale earlier position; turning it back
## off needs no cleanup — _idle_movement() just goes back to checking
## follow_owner_when_idle again.
func set_independent(value: bool) -> void:
	is_independent = value
	if value:
		_wander_origin = global_position
		_wander_target = global_position
		_wander_timer = 0.0


func configure(data: Dictionary, new_owner: Node3D = null, index: int = -1) -> void:
	owner_to_follow = new_owner
	squad_index = index
	if data.has("species_name"):
		species_name = data["species_name"]
	if data.has("element"):
		element = data["element"]
	if data.has("role"):
		role = data["role"]
	if data.has("power_level"):
		power_level = data["power_level"]
	_apply_role_stats(false)
	_apply_mage_range_boost()
	_apply_species_model()
	if health and data.has("max_health"):
		health.max_health = data["max_health"]
		health.current_health = health.max_health


## Swaps in the real per-species mesh for a summoned squad member — see
## SPECIES_MODEL_PATHS. Only ever relevant for the generic summon scene
## (self_group "player_side"); a hand-placed wild/hostile creature comes
## with its own real CreatureModel already in its own .tscn, so this
## leaves those completely alone rather than risking swapping a model
## that's already correct. Safe to call more than once (e.g. re-tamed
## after fainting/reviving) — clears out whatever model is already there
## first instead of stacking a second one on top.
func _apply_species_model() -> void:
	if self_group != &"player_side" or not SPECIES_MODEL_PATHS.has(species_name):
		return

	var old_model := get_node_or_null("CreatureModel")
	if old_model != null:
		old_model.queue_free()

	var model_scene: PackedScene = load(SPECIES_MODEL_PATHS[species_name])
	if model_scene == null:
		return
	var model := model_scene.instantiate()
	model.name = "CreatureModel"
	add_child(model)


func take_damage(amount: float) -> void:
	health.take_damage(amount)


func _on_health_changed(current: float, max_health_value: float) -> void:
	if can_be_tamed and not is_tameable and current <= max_health_value * tame_health_fraction:
		is_tameable = true


## Called by the player, passing their gauntlet's current tier. Returns
## the capture data on success, or an empty Dictionary on failure (a
## failed attempt makes it fight back harder for a while, same as a
## wild_monster's enrage). gauntlet_tier defaults high so a caller that
## doesn't pass one gets the normal, non-penalized chance.
func attempt_tame(gauntlet_tier: int = 999) -> Dictionary:
	if not can_be_tamed or not is_tameable:
		return {}

	var chance: float = _current_capture_chance()
	if gauntlet_tier < required_gauntlet_tier:
		chance = underleveled_capture_chance
	chance = clamp(chance + SkillManager.get_taming_bonus(), 0.0, 1.0)

	if randf() <= chance:
		return _capture()

	_enrage()
	return {}


func _current_capture_chance() -> float:
	var threshold_health: float = health.max_health * tame_health_fraction
	if threshold_health <= 0.0:
		return base_capture_chance

	var progress: float = 1.0 - clamp(health.current_health / threshold_health, 0.0, 1.0)
	return clamp(lerp(base_capture_chance, 0.9, progress), 0.0, 1.0)


func _capture() -> Dictionary:
	var data := {
		"species_name": species_name,
		"max_health": health.max_health,
		"element": element,
		"role": role,
	}
	_drop_loot_if_world_creature()
	_award_essence_if_world_creature()
	_notify_spawner_if_world_creature()
	queue_free()
	return data


func _enrage() -> void:
	is_enraged = true
	enrage_timer = enrage_duration


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta

	attack_timer = max(attack_timer - delta, 0.0)
	retarget_timer = max(retarget_timer - delta, 0.0)

	if role == ElementSystem.Role.HEALER:
		_heal_timer -= delta
		if _heal_timer <= 0.0:
			_heal_timer = ElementSystem.HEALER_HEAL_INTERVAL
			_try_heal_ally()

	if is_enraged:
		enrage_timer -= delta
		if enrage_timer <= 0.0:
			is_enraged = false

	if retarget_timer <= 0.0:
		_find_target()
		retarget_timer = 0.5

	var current_speed: float = move_speed
	if is_enraged:
		current_speed *= enrage_speed_multiplier

	if target != null and is_instance_valid(target):
		var to_target: Vector3 = target.global_position - global_position
		to_target.y = 0.0
		var distance: float = to_target.length()

		if distance <= attack_range:
			velocity.x = move_toward(velocity.x, 0.0, acceleration * delta)
			velocity.z = move_toward(velocity.z, 0.0, acceleration * delta)
			_face_direction(to_target.normalized(), delta)
			_try_attack()
		else:
			var direction := to_target.normalized()
			velocity.x = move_toward(velocity.x, direction.x * current_speed, acceleration * delta)
			velocity.z = move_toward(velocity.z, direction.z * current_speed, acceleration * delta)
			_face_direction(direction, delta)
	else:
		_idle_movement(delta)

	move_and_slide()


func _idle_movement(delta: float) -> void:
	if is_independent:
		_wander(delta)
		return

	if follow_owner_when_idle and owner_to_follow != null and is_instance_valid(owner_to_follow):
		var to_owner: Vector3 = owner_to_follow.global_position - global_position
		to_owner.y = 0.0
		if to_owner.length() > 2.5:
			var direction := to_owner.normalized()
			velocity.x = move_toward(velocity.x, direction.x * move_speed, acceleration * delta)
			velocity.z = move_toward(velocity.z, direction.z * move_speed, acceleration * delta)
			_face_direction(direction, delta)
			return

	velocity.x = move_toward(velocity.x, 0.0, acceleration * delta)
	velocity.z = move_toward(velocity.z, 0.0, acceleration * delta)


## Independent-mode idle behavior — same shape as wild_monster.gd's own
## _process_wander(): pick a random point within INDEPENDENT_WANDER_RADIUS
## of wherever this summon was when it was released, drift toward it,
## then pick a new one after a random pause. It'll still break off to
## fight (see _physics_process()'s target check, which runs before this
## is ever called) the moment something shows up in detection_range.
func _wander(delta: float) -> void:
	_wander_timer -= delta
	if _wander_timer <= 0.0:
		_wander_timer = randf_range(2.0, 5.0)
		var offset := Vector3(
			randf_range(-INDEPENDENT_WANDER_RADIUS, INDEPENDENT_WANDER_RADIUS),
			0.0,
			randf_range(-INDEPENDENT_WANDER_RADIUS, INDEPENDENT_WANDER_RADIUS)
		)
		_wander_target = _wander_origin + offset

	var to_target: Vector3 = _wander_target - global_position
	to_target.y = 0.0
	if to_target.length() > 0.5:
		var direction := to_target.normalized()
		velocity.x = move_toward(velocity.x, direction.x * move_speed, acceleration * delta)
		velocity.z = move_toward(velocity.z, direction.z * move_speed, acceleration * delta)
		_face_direction(direction, delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, acceleration * delta)
		velocity.z = move_toward(velocity.z, 0.0, acceleration * delta)


func _find_target() -> void:
	var candidates := get_tree().get_nodes_in_group(target_group)
	var closest: Node3D = null
	var closest_distance := detection_range

	for candidate in candidates:
		if not (candidate is Node3D):
			continue
		var distance: float = global_position.distance_to(candidate.global_position)
		if distance <= closest_distance:
			closest = candidate
			closest_distance = distance

	target = closest


func _face_direction(direction: Vector3, delta: float) -> void:
	if direction.length() < 0.01:
		return
	var target_angle := atan2(direction.x, direction.z)
	rotation.y = lerp_angle(rotation.y, target_angle, 10.0 * delta)


func _try_attack() -> void:
	if attack_timer > 0.0:
		return
	attack_timer = attack_cooldown

	var damage: float = attack_damage
	if is_enraged:
		damage *= enrage_damage_multiplier

	for body in attack_area.get_overlapping_bodies():
		if body.is_in_group(target_group) and body.has_method("take_damage"):
			var defender_element: int = ElementSystem.Element.NEUTRAL
			if body.has_method("get_element"):
				defender_element = body.get_element()
			var multiplier: float = ElementSystem.get_damage_multiplier(element, defender_element)
			body.take_damage(damage * multiplier)


## Healer role only, ticked from _physics_process(). Mends whichever
## wounded member of self_group is closest to death, within
## HEALER_HEAL_RADIUS — this naturally covers a hostile healer supporting
## other hostile creatures/wild monsters (all in group "hostile"), and a
## player-side healer supporting the player or a squadmate (all in group
## "player_side", the player included — see player.gd's _ready()). Heals
## itself if it's the most wounded ally-shaped thing around, but only
## because it's a member of its own group like anyone else, not as a
## special case.
func _try_heal_ally() -> void:
	var best: Node = null
	var best_fraction: float = 1.0

	for candidate in get_tree().get_nodes_in_group(self_group):
		if not is_instance_valid(candidate) or not ("health" in candidate):
			continue
		var hc: HealthComponent = candidate.health
		if hc == null or hc.is_dead():
			continue
		var fraction: float = 1.0
		if hc.max_health > 0.0:
			fraction = hc.current_health / hc.max_health
		if fraction >= 1.0:
			continue
		if global_position.distance_to(candidate.global_position) > ElementSystem.HEALER_HEAL_RADIUS:
			continue
		if best == null or fraction < best_fraction:
			best = candidate
			best_fraction = fraction

	if best != null:
		best.health.heal(ElementSystem.HEALER_HEAL_AMOUNT)


func _on_died() -> void:
	_drop_loot_if_world_creature()
	_award_essence_if_world_creature()
	_notify_spawner_if_world_creature()
	_notify_roster_if_player_summon()
	queue_free()


## This script is shared by hand-placed hostile creatures (self_group
## "hostile") and the player's own summoned monsters (self_group
## "player_side"). Only the former are placed by a CreatureSpawner that
## needs to know to start its respawn cooldown — a summon despawning is
## expected every time its owner logs back in and has no spawner to
## notify.
func _notify_spawner_if_world_creature() -> void:
	if self_group != &"hostile":
		return
	var spawner := get_parent()
	if spawner and spawner.has_method("notify_creature_removed"):
		spawner.notify_creature_removed()


## Same "only world creatures, not player summons" restriction as
## _notify_spawner_if_world_creature() — a summoned monster despawning
## shouldn't hand the player free loot from their own team.
func _drop_loot_if_world_creature() -> void:
	if self_group != &"hostile":
		return
	if loot_item_id == "" or not ItemDatabase.has_item(loot_item_id):
		return
	if randf() > loot_chance:
		return
	InventoryManager.add_item(loot_item_id, randi_range(loot_min, loot_max))


## Same "only world creatures, not player summons" restriction — see
## _drop_loot_if_world_creature(). Unlike loot, essence always drops
## (no chance roll), since it's meant to be a reliable currency trickle.
func _award_essence_if_world_creature() -> void:
	if self_group != &"hostile":
		return
	SkillManager.add_essence(randi_range(essence_min, essence_max))


## The player-summon counterpart to _notify_spawner_if_world_creature():
## a summoned monster dying has no spawner to tell, it has a squad slot
## in MonsterRoster to mark "fainted" instead. See monster_roster.gd's
## notify_fainted()/revive() for how it gets back in the fight.
func _notify_roster_if_player_summon() -> void:
	if self_group != &"player_side" or squad_index < 0:
		return
	MonsterRoster.notify_fainted(squad_index)
