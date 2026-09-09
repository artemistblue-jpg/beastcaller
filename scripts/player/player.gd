extends CharacterBody3D

@export var move_speed: float = 6.0
@export var acceleration: float = 20.0
@export var deceleration: float = 24.0
@export var jump_velocity: float = 6.0
@export var rotation_speed: float = 10.0

@export var zoom_speed: float = 1.0
@export var minimum_zoom: float = 4.0
@export var maximum_zoom: float = 10.0

@export var attack_damage: float = 25.0
@export var attack_cooldown: float = 0.5
@export var tame_range: float = 2.5
@export var respawn_delay: float = 3.0
@export var respawn_invulnerability: float = 2.0

@onready var camera_pivot: Node3D = $CameraPivot
@onready var spring_arm: SpringArm3D = $CameraPivot/SpringArm3D
@onready var character_model: Node3D = $CharacterModel
@onready var animation_player: AnimationPlayer = $CharacterModel/AnimationPlayer
@onready var health: HealthComponent = $HealthComponent
@onready var attack_area: Area3D = $AttackArea3D

var gravity: float = ProjectSettings.get_setting(
	"physics/3d/default_gravity"
)

var attack_timer: float = 0.0
var is_dead: bool = false
var respawn_position: Vector3 = Vector3.ZERO
var jump_requested: bool = false
var touch_controls: Node = null
var invulnerable_timer: float = 0.0
var _current_animation: String = ""


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	add_to_group("player")
	add_to_group("player_side")

	# Fixed third-person camera angle.
	camera_pivot.rotation_degrees = Vector3.ZERO
	spring_arm.rotation_degrees = Vector3(-8.0, 0.0, 0.0)

	# Prevent the camera from colliding with the player body.
	spring_arm.add_excluded_object(get_rid())

	# Start the character's idle animation.
	_play_animation("Idle")

	# Respawn point: use a "player_spawn" marker if the level has one,
	# otherwise fall back to wherever we started.
	respawn_position = global_position
	var spawn_points := get_tree().get_nodes_in_group("player_spawn")
	if spawn_points.size() > 0 and spawn_points[0] is Node3D:
		respawn_position = (spawn_points[0] as Node3D).global_position

	health.died.connect(_on_died)


func take_damage(amount: float) -> void:
	if is_dead or invulnerable_timer > 0.0:
		return
	health.take_damage(amount)


func _on_died() -> void:
	is_dead = true
	_play_animation("Death01")
	# TODO: swap this for a real game-over screen once we build one —
	# for now, just respawn after a short delay so you're never stuck.
	print("Player died. Respawning in %.1fs..." % respawn_delay)
	await get_tree().create_timer(respawn_delay).timeout
	_respawn()


func _respawn() -> void:
	global_position = respawn_position
	velocity = Vector3.ZERO
	health.reset()
	is_dead = false
	invulnerable_timer = respawn_invulnerability
	SaveManager.save_game()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			spring_arm.spring_length = clamp(
				spring_arm.spring_length - zoom_speed,
				minimum_zoom,
				maximum_zoom
			)

		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			spring_arm.spring_length = clamp(
				spring_arm.spring_length + zoom_speed,
				minimum_zoom,
				maximum_zoom
			)

		elif event.button_index == MOUSE_BUTTON_LEFT:
			_try_attack()

	elif event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_E:
			_try_tame()


func _try_attack() -> void:
	if is_dead or attack_timer > 0.0:
		return
	attack_timer = attack_cooldown

	for body in attack_area.get_overlapping_bodies():
		if not body.has_method("take_damage"):
			continue
		if body.is_in_group("hostile") or body.is_in_group("wild_monster"):
			body.take_damage(attack_damage)


func _try_tame() -> void:
	if is_dead:
		return

	var candidates := get_tree().get_nodes_in_group("tameable")
	for candidate in candidates:
		if not (candidate is Node3D):
			continue
		if global_position.distance_to(candidate.global_position) > tame_range:
			continue
		if "is_tameable" in candidate and candidate.is_tameable:
			if not candidate.has_method("attempt_tame"):
				continue
			var data: Dictionary = candidate.attempt_tame()
			if data.is_empty():
				print("Taming failed — it's fighting back!")
			else:
				MonsterRoster.add_to_collection(data)
				MonsterRoster.spawn_squad(self)
				SaveManager.save_game()
			return


## Public entry points for the on-screen touch buttons — mirror the
## keyboard/mouse actions above.
func request_attack() -> void:
	_try_attack()


func request_tame() -> void:
	_try_tame()


func request_jump() -> void:
	jump_requested = true


## Looked up lazily (rather than cached once in _ready) because
## TouchControls can add itself to the group after this node's _ready
## runs, depending on sibling order in the scene tree.
func _get_touch_controls() -> Node:
	if touch_controls == null or not is_instance_valid(touch_controls):
		var touch_nodes := get_tree().get_nodes_in_group("touch_controls")
		if touch_nodes.size() > 0:
			touch_controls = touch_nodes[0]
	return touch_controls


## Switches to a clip only when it isn't already playing, so a call every
## physics frame doesn't keep restarting the animation from frame 0.
func _play_animation(clip_name: String) -> void:
	if clip_name == _current_animation:
		return
	var qualified_name := _resolve_animation_name(clip_name)
	if qualified_name.is_empty():
		push_warning("Player: no animation found for '%s'" % clip_name)
		return
	animation_player.play(qualified_name)
	_current_animation = clip_name


## The character's glTF file might have its animations under a named
## AnimationLibrary rather than the default one — check both so a bare
## clip name like "Idle" still resolves wherever the importer put it.
func _resolve_animation_name(clip_name: String) -> String:
	if animation_player.has_animation(clip_name):
		return clip_name
	for library_name in animation_player.get_animation_library_list():
		var qualified_name: String = "%s/%s" % [library_name, clip_name]
		if animation_player.has_animation(qualified_name):
			return qualified_name
	return ""


func _physics_process(delta: float) -> void:
	attack_timer = max(attack_timer - delta, 0.0)
	invulnerable_timer = max(invulnerable_timer - delta, 0.0)

	if is_dead:
		velocity.x = move_toward(velocity.x, 0.0, deceleration * delta)
		velocity.z = move_toward(velocity.z, 0.0, deceleration * delta)
		if not is_on_floor():
			velocity.y -= gravity * delta
		move_and_slide()
		return

	if not is_on_floor():
		velocity.y -= gravity * delta

	if (Input.is_action_just_pressed("jump") or jump_requested) and is_on_floor():
		velocity.y = jump_velocity
	jump_requested = false

	var input_direction := Input.get_vector(
		"move_left",
		"move_right",
		"move_forward",
		"move_back"
	)

	var touch := _get_touch_controls()
	if touch != null:
		var touch_direction: Vector2 = touch.get_movement_input()
		if touch_direction.length() > input_direction.length():
			input_direction = touch_direction

	var movement_direction := Vector3(
		input_direction.x,
		0.0,
		input_direction.y
	).normalized()

	if movement_direction != Vector3.ZERO:
		velocity.x = move_toward(
			velocity.x,
			movement_direction.x * move_speed,
			acceleration * delta
		)

		velocity.z = move_toward(
			velocity.z,
			movement_direction.z * move_speed,
			acceleration * delta
		)

		var target_angle := atan2(
			movement_direction.x,
			movement_direction.z
		)

		character_model.rotation.y = lerp_angle(
			character_model.rotation.y,
			target_angle,
			rotation_speed * delta
		)

		_play_animation("Jog_Fwd")

	else:
		velocity.x = move_toward(
			velocity.x,
			0.0,
			deceleration * delta
		)

		velocity.z = move_toward(
			velocity.z,
			0.0,
			deceleration * delta
		)

		_play_animation("Idle")

	move_and_slide()
