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

@onready var health: HealthComponent = $HealthComponent
@onready var attack_area: Area3D = $AttackArea3D

var gravity: float = ProjectSettings.get_setting(
	"physics/3d/default_gravity"
)

var owner_to_follow: Node3D = null
var target: Node3D = null
var attack_timer: float = 0.0
var retarget_timer: float = 0.0

var is_tameable: bool = false
var is_enraged: bool = false
var enrage_timer: float = 0.0


func _ready() -> void:
	add_to_group(self_group)
	health.died.connect(_on_died)
	if can_be_tamed:
		add_to_group("tameable")
		health.health_changed.connect(_on_health_changed)


func configure(data: Dictionary, new_owner: Node3D = null) -> void:
	owner_to_follow = new_owner
	if data.has("species_name"):
		species_name = data["species_name"]
	if health and data.has("max_health"):
		health.max_health = data["max_health"]
		health.current_health = health.max_health


func take_damage(amount: float) -> void:
	health.take_damage(amount)


func _on_health_changed(current: float, max_health_value: float) -> void:
	if can_be_tamed and not is_tameable and current <= max_health_value * tame_health_fraction:
		is_tameable = true


## Called by the player. Returns the capture data on success, or an empty
## Dictionary on failure (a failed attempt makes it fight back harder for
## a while, same as a wild_monster's enrage).
func attempt_tame() -> Dictionary:
	if not can_be_tamed or not is_tameable:
		return {}

	if randf() <= _current_capture_chance():
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
	}
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
			body.take_damage(damage)


func _on_died() -> void:
	queue_free()
