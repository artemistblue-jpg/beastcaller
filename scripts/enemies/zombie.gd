extends CharacterBody3D

@export var move_speed: float = 2.5
@export var acceleration: float = 8.0
@export var detection_range: float = 12.0
@export var attack_range: float = 1.6
@export var attack_damage: float = 10.0
@export var attack_cooldown: float = 1.2

@onready var health: HealthComponent = $HealthComponent
@onready var attack_area: Area3D = $AttackArea3D

var gravity: float = ProjectSettings.get_setting(
	"physics/3d/default_gravity"
)

var player: Node3D = null
var attack_timer: float = 0.0


func _ready() -> void:
	add_to_group("zombie")
	health.died.connect(_on_died)
	# Found by group instead of a hard node path, so this scene works
	# no matter where it ends up in the level tree (train, raid area, etc.)
	call_deferred("_find_player")


func _find_player() -> void:
	var players := get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		player = players[0]


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta

	attack_timer = max(attack_timer - delta, 0.0)

	if player == null:
		velocity.x = move_toward(velocity.x, 0.0, acceleration * delta)
		velocity.z = move_toward(velocity.z, 0.0, acceleration * delta)
		move_and_slide()
		return

	var to_player: Vector3 = player.global_position - global_position
	to_player.y = 0.0
	var distance: float = to_player.length()

	if distance <= detection_range and distance > attack_range:
		var direction := to_player.normalized()
		velocity.x = move_toward(velocity.x, direction.x * move_speed, acceleration * delta)
		velocity.z = move_toward(velocity.z, direction.z * move_speed, acceleration * delta)
		_face_direction(direction, delta)

	elif distance <= attack_range:
		velocity.x = move_toward(velocity.x, 0.0, acceleration * delta)
		velocity.z = move_toward(velocity.z, 0.0, acceleration * delta)
		_face_direction(to_player.normalized(), delta)
		_try_attack()

	else:
		velocity.x = move_toward(velocity.x, 0.0, acceleration * delta)
		velocity.z = move_toward(velocity.z, 0.0, acceleration * delta)

	move_and_slide()


func _face_direction(direction: Vector3, delta: float) -> void:
	if direction.length() < 0.01:
		return
	var target_angle := atan2(direction.x, direction.z)
	rotation.y = lerp_angle(rotation.y, target_angle, 10.0 * delta)


func _try_attack() -> void:
	if attack_timer > 0.0:
		return
	attack_timer = attack_cooldown

	for body in attack_area.get_overlapping_bodies():
		if body.is_in_group("player") and body.has_method("take_damage"):
			body.take_damage(attack_damage)


func take_damage(amount: float) -> void:
	health.take_damage(amount)


func _on_died() -> void:
	queue_free()
