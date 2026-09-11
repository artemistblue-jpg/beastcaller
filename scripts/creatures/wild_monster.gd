extends CharacterBody3D

## A wandering wild creature. Weaken it below the tame threshold and try
## to tame it (E) — success chance depends on species toughness
## (base_capture_chance) and how badly hurt it is. Fail the roll and it
## turns hostile, fighting back harder for a while before calming down.

@export var species_name: String = "Sparkit"
@export var move_speed: float = 2.0
@export var acceleration: float = 6.0
@export var wander_radius: float = 6.0
@export var tame_health_fraction: float = 0.3

## Chance to succeed the instant it becomes tameable, before any bonus
## from further weakening it. Tougher species should use a lower value.
@export var base_capture_chance: float = 0.7

@export var detection_range: float = 14.0
@export var attack_range: float = 1.6
@export var attack_damage: float = 8.0
@export var attack_cooldown: float = 1.0

## How a failed tame attempt makes it "fight back harder" — temporarily,
## not a permanent buff, so repeated failures can't spiral out of control.
@export var enrage_duration: float = 15.0
@export var enrage_speed_multiplier: float = 1.4
@export var enrage_damage_multiplier: float = 1.6

## Gauntlet gate for taming this creature — see GauntletManager and
## player.gd's _try_tame().
@export var required_gauntlet_tier: int = 1
@export var capture_energy_cost: float = 15.0
## Capture chance used instead of the normal calculation when the
## player's gauntlet tier is below required_gauntlet_tier — the attempt
## is still allowed, just a long shot.
@export var underleveled_capture_chance: float = 0.05

## Optional item drop on a successful tame — see ItemDatabase.
@export var loot_item_id: String = ""
@export var loot_chance: float = 0.5
@export var loot_min: int = 1
@export var loot_max: int = 1

## Monster Essence (currency + skill-sphere fuel — see SkillManager)
## awarded on every successful tame, unlike the chance-based loot above.
@export var essence_min: int = 3
@export var essence_max: int = 8

@onready var health: HealthComponent = $HealthComponent
@onready var attack_area: Area3D = $AttackArea3D

var gravity: float = ProjectSettings.get_setting(
	"physics/3d/default_gravity"
)

var home_position: Vector3
var wander_target: Vector3
var wander_timer: float = 0.0
var is_tameable: bool = false

var is_enraged: bool = false
var enrage_timer: float = 0.0
var attack_timer: float = 0.0
var target: Node3D = null


func _ready() -> void:
	add_to_group("wild_monster")
	add_to_group("tameable")
	# Also join "hostile" — not because these are aggressive, but because
	# it's the group summoned pets search for targets in (see
	# creature_ai.gd's target_group). Without this, tamed pets could
	# never find/attack a wild_monster at all. The player's own punches
	# already special-cased around this gap by checking "hostile" OR
	# "wild_monster" directly; joining both groups here closes the gap
	# for pets too instead of needing every future combatant to know
	# about the split.
	add_to_group("hostile")
	home_position = global_position
	wander_target = global_position
	health.health_changed.connect(_on_health_changed)
	# HealthComponent emits "died" at 0 HP — without listening for it, a
	# wild_monster that gets killed outright (rather than tamed) just
	# sits there at 0 HP forever, since nothing ever called queue_free().
	health.died.connect(_on_died)


func _on_health_changed(current: float, max_health: float) -> void:
	if not is_tameable and current <= max_health * tame_health_fraction:
		is_tameable = true


func take_damage(amount: float) -> void:
	health.take_damage(amount)


## Called by the player, passing their gauntlet's current tier. Returns
## the capture data on success, or an empty Dictionary on failure (the
## monster handles its own reaction). gauntlet_tier defaults high so a
## caller that doesn't pass one gets the normal, non-penalized chance.
func attempt_tame(gauntlet_tier: int = 999) -> Dictionary:
	if not is_tameable:
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

	# Chance climbs from base_capture_chance (right at the threshold) up
	# toward a near-guaranteed catch the closer it is to fainting.
	var progress: float = 1.0 - clamp(health.current_health / threshold_health, 0.0, 1.0)
	return clamp(lerp(base_capture_chance, 0.97, progress), 0.0, 1.0)


func _capture() -> Dictionary:
	var data := {
		"species_name": species_name,
		"max_health": health.max_health,
	}
	_remove_and_reward()
	return data


## Killed outright rather than tamed — still worth the same loot/essence
## as a capture (matches how creature_ai.gd treats a hostile creature's
## death and capture identically), it just doesn't join your roster.
func _on_died() -> void:
	_remove_and_reward()


func _remove_and_reward() -> void:
	_drop_loot()
	SkillManager.add_essence(randi_range(essence_min, essence_max))
	_notify_spawner_removed()
	queue_free()


func _drop_loot() -> void:
	if loot_item_id == "" or not ItemDatabase.has_item(loot_item_id):
		return
	if randf() > loot_chance:
		return
	InventoryManager.add_item(loot_item_id, randi_range(loot_min, loot_max))


## If this monster was placed by a CreatureSpawner (see
## creature_spawner.gd), tell it we're gone so it starts its respawn
## cooldown. Wild monsters aren't currently spawned any other way, but
## the check keeps this safe if that ever changes.
func _notify_spawner_removed() -> void:
	var spawner := get_parent()
	if spawner and spawner.has_method("notify_creature_removed"):
		spawner.notify_creature_removed()


func _enrage() -> void:
	is_enraged = true
	enrage_timer = enrage_duration


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta

	if is_enraged:
		_process_enraged(delta)
	else:
		_process_wander(delta)

	move_and_slide()


func _process_enraged(delta: float) -> void:
	enrage_timer -= delta
	if enrage_timer <= 0.0:
		is_enraged = false
		target = null
		velocity.x = move_toward(velocity.x, 0.0, acceleration * delta)
		velocity.z = move_toward(velocity.z, 0.0, acceleration * delta)
		return

	attack_timer = max(attack_timer - delta, 0.0)

	if target == null or not is_instance_valid(target):
		var candidates := get_tree().get_nodes_in_group("player_side")
		if candidates.size() > 0:
			target = candidates[0]

	if target == null:
		velocity.x = move_toward(velocity.x, 0.0, acceleration * delta)
		velocity.z = move_toward(velocity.z, 0.0, acceleration * delta)
		return

	var to_target: Vector3 = target.global_position - global_position
	to_target.y = 0.0
	var distance: float = to_target.length()
	var speed: float = move_speed * enrage_speed_multiplier

	if distance <= attack_range:
		velocity.x = move_toward(velocity.x, 0.0, acceleration * delta)
		velocity.z = move_toward(velocity.z, 0.0, acceleration * delta)
		_face_direction(to_target.normalized(), delta)
		_try_attack()
	elif distance <= detection_range:
		var direction := to_target.normalized()
		velocity.x = move_toward(velocity.x, direction.x * speed, acceleration * delta)
		velocity.z = move_toward(velocity.z, direction.z * speed, acceleration * delta)
		_face_direction(direction, delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, acceleration * delta)
		velocity.z = move_toward(velocity.z, 0.0, acceleration * delta)


func _try_attack() -> void:
	if attack_timer > 0.0:
		return
	attack_timer = attack_cooldown

	for body in attack_area.get_overlapping_bodies():
		if body.is_in_group("player_side") and body.has_method("take_damage"):
			body.take_damage(attack_damage * enrage_damage_multiplier)


func _process_wander(delta: float) -> void:
	wander_timer -= delta
	if wander_timer <= 0.0:
		wander_timer = randf_range(2.0, 5.0)
		var offset := Vector3(
			randf_range(-wander_radius, wander_radius),
			0.0,
			randf_range(-wander_radius, wander_radius)
		)
		wander_target = home_position + offset

	var to_target: Vector3 = wander_target - global_position
	to_target.y = 0.0

	if to_target.length() > 0.5:
		var direction := to_target.normalized()
		velocity.x = move_toward(velocity.x, direction.x * move_speed, acceleration * delta)
		velocity.z = move_toward(velocity.z, direction.z * move_speed, acceleration * delta)
		_face_direction(direction, delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, acceleration * delta)
		velocity.z = move_toward(velocity.z, 0.0, acceleration * delta)


func _face_direction(direction: Vector3, delta: float) -> void:
	if direction.length() < 0.01:
		return
	var target_angle := atan2(direction.x, direction.z)
	rotation.y = lerp_angle(rotation.y, target_angle, 10.0 * delta)
