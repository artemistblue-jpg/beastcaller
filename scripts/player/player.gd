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

## Bone NAMES (not full paths) a punch is allowed to override. Everything
## NOT listed here (hips, legs, feet) keeps following the locomotion
## animation underneath, which is what lets the character punch and keep
## walking/running at the same time instead of freezing mid-stride.
##
## Full filter paths are built at runtime in _setup_animation_tree() by
## finding the Skeleton3D and computing its path relative to whatever
## node the animations were actually baked against (animation_player's
## own root_node) — two guesses at a hardcoded "Skeleton3D:..." /
## "Armature/Skeleton3D:..." prefix both failed to actually move the
## character, so this derives it instead of assuming it.
const _UPPER_BODY_BONE_NAMES: Array[String] = [
	"spine_01",
	"spine_02",
	"spine_03",
	"neck_01",
	"Head",
	"clavicle_l",
	"upperarm_l",
	"lowerarm_l",
	"hand_l",
	"clavicle_r",
	"upperarm_r",
	"lowerarm_r",
	"hand_r",
]

const _LOCOMOTION_BLEND_TIME: float = 0.15

var animation_tree: AnimationTree
var _punch_clip_node: AnimationNodeAnimation
var _locomotion_blend: float = 0.0
var _locomotion_target: float = 0.0


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	add_to_group("player")
	add_to_group("player_side")

	# Fixed third-person camera angle.
	camera_pivot.rotation_degrees = Vector3.ZERO
	spring_arm.rotation_degrees = Vector3(-8.0, 0.0, 0.0)

	# Prevent the camera from colliding with the player body.
	spring_arm.add_excluded_object(get_rid())

	_setup_animation_tree()

	# Respawn point: use a "player_spawn" marker if the level has one,
	# otherwise fall back to wherever we started.
	respawn_position = global_position
	var spawn_points := get_tree().get_nodes_in_group("player_spawn")
	if spawn_points.size() > 0 and spawn_points[0] is Node3D:
		respawn_position = (spawn_points[0] as Node3D).global_position

	health.died.connect(_on_died)


## Builds a small AnimationTree in code (rather than hand-editing the
## scene file) so a punch can play as a one-shot overlay on just the
## upper-body bones while the Idle/Jog_Fwd loop keeps driving the legs
## underneath it. Layout:
##   Idle ─┐
##         ├─ Locomotion (Blend2, driven by _locomotion_blend) ─┐
##   Move ─┘                                                    ├─ PunchShot (OneShot, filtered) ─ output
##                                                   PunchClip ─┘
func _setup_animation_tree() -> void:
	var blend_tree := AnimationNodeBlendTree.new()

	# Ground truth, printed directly from animation_player's own imported
	# library at runtime: the real clip names are plain "Idle" and
	# "Jog_Fwd" — no "_Loop" suffix at all. An earlier guess based on
	# parsing the raw glTF JSON by hand got this wrong, which meant the
	# whole locomotion layer resolved to nothing and only ever showed a
	# T-pose, regardless of what else got fixed around it (the punch
	# overlay itself was firing fine the whole time — has_animation()/
	# tree_active were already true).
	var idle_node := AnimationNodeAnimation.new()
	idle_node.animation = "Idle"
	blend_tree.add_node("Idle", idle_node)

	var move_node := AnimationNodeAnimation.new()
	move_node.animation = "Jog_Fwd"
	blend_tree.add_node("Move", move_node)

	# A plain 0..1 blend rather than AnimationNodeTransition — driven by
	# hand in _physics_process (see _locomotion_blend) so it crossfades
	# smoothly without relying on that node's own state-switching API.
	var locomotion := AnimationNodeBlend2.new()
	blend_tree.add_node("Locomotion", locomotion)
	blend_tree.connect_node("Locomotion", 0, "Idle")
	blend_tree.connect_node("Locomotion", 1, "Move")

	_punch_clip_node = AnimationNodeAnimation.new()
	_punch_clip_node.animation = "Punch_Jab"
	blend_tree.add_node("PunchClip", _punch_clip_node)

	var punch_shot := AnimationNodeOneShot.new()
	punch_shot.filter_enabled = true
	blend_tree.add_node("PunchShot", punch_shot)
	blend_tree.connect_node("PunchShot", 0, "Locomotion")
	blend_tree.connect_node("PunchShot", 1, "PunchClip")

	blend_tree.connect_node("output", 0, "PunchShot")

	animation_tree = AnimationTree.new()
	add_child(animation_tree)
	animation_tree.tree_root = blend_tree
	animation_tree.anim_player = animation_tree.get_path_to(animation_player)

	# Confirmed via debug output: setting anim_player above makes the tree
	# report a library named "" of its own, but it's an empty placeholder,
	# NOT actually populated from animation_player — has_animation() on
	# the tree returned false despite the player having the real clips.
	# A "skip if it already exists" guard here previously left that empty
	# placeholder in place instead of replacing it. Force-replacing it
	# with the real library (removing any existing one of the same name
	# first) is what actually gets the clips onto the tree.
	for lib_name in animation_player.get_animation_library_list():
		if animation_tree.has_animation_library(lib_name):
			animation_tree.remove_animation_library(lib_name)
		animation_tree.add_animation_library(lib_name, animation_player.get_animation_library(lib_name))

	# AnimationTree (via its AnimationMixer base) resolves every track and
	# filter NodePath relative to its OWN root_node. Two earlier attempts
	# hardcoded a guess here (first the default "..", then CharacterModel)
	# and neither actually moved the skeleton — has_animation()/tree.active
	# all reported success, but nothing visibly played, which meant paths
	# still weren't resolving. Rather than guess a third time, derive it:
	# animation_player.root_node is whatever the glTF importer ALREADY
	# configured correctly for its own tracks to resolve against, so
	# pointing our tree at that exact same node (reached via our own
	# position instead) guarantees a match.
	var baked_root: Node = animation_player.get_node(animation_player.root_node)
	animation_tree.root_node = animation_tree.get_path_to(baked_root)

	var skeleton := _find_skeleton()
	if skeleton != null:
		var skeleton_path: NodePath = baked_root.get_path_to(skeleton)
		for bone_name in _UPPER_BODY_BONE_NAMES:
			var bone_path := NodePath("%s:%s" % [skeleton_path, bone_name])
			punch_shot.set_filter_path(bone_path, true)
	else:
		push_warning("Player: no Skeleton3D found under CharacterModel — punch overlay filter left empty.")

	animation_tree.active = true


func _find_skeleton() -> Skeleton3D:
	var skeletons := character_model.find_children("*", "Skeleton3D", true, false)
	if skeletons.is_empty():
		return null
	return skeletons[0]


func take_damage(amount: float) -> void:
	if is_dead or invulnerable_timer > 0.0:
		return
	health.take_damage(amount)


func _on_died() -> void:
	is_dead = true
	# The AnimationTree owns playback while it's active, so it has to
	# step aside for this one full-body animation the tree doesn't know
	# about, then hand control back on respawn.
	animation_tree.active = false
	animation_player.play("Death01")
	print("Player died.")
	_show_death_screen()


## Dying now has a real cost instead of a free timed respawn — see
## death_screen.gd for the actual pay-essence-or-watch-an-ad choice.
## _respawn is handed over as the callback it runs the instant either
## path pays off, so this file doesn't need to know which one the
## player picked.
func _show_death_screen() -> void:
	var death_screens := get_tree().get_nodes_in_group("death_screen")
	if death_screens.size() > 0 and death_screens[0].has_method("show_death"):
		death_screens[0].show_death(_respawn)
		return

	# No death screen present in this scene (shouldn't normally happen)
	# — fall back to the old free timed respawn rather than leaving the
	# player stuck forever with no way back in.
	await get_tree().create_timer(respawn_delay).timeout
	_respawn()


func _respawn() -> void:
	global_position = respawn_position
	velocity = Vector3.ZERO
	health.reset()
	is_dead = false
	invulnerable_timer = respawn_invulnerability
	_locomotion_blend = 0.0
	_locomotion_target = 0.0
	animation_tree["parameters/Locomotion/blend_amount"] = 0.0
	animation_tree.active = true
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
			_try_interact()


func _try_attack() -> void:
	if is_dead or attack_timer > 0.0 or DialogueBox.is_active():
		return

	# A chest in range takes priority over punching — ATK is the button
	# players reach for by habit, so it should open a chest the same way
	# the E key/TAME button does (see _try_interact()), rather than only
	# throwing a punch at it. Doesn't spend the attack cooldown, since
	# opening a chest isn't an attack.
	if _try_open_chest():
		return

	attack_timer = attack_cooldown

	# No dedicated jump-kick animation is available in the character's
	# animation set, so an airborne attack reuses the heavier cross punch
	# to at least read as a distinct, weightier hit from the grounded jab.
	_fire_punch("Punch_Cross" if not is_on_floor() else "Punch_Jab")

	# A rock/tree in range takes priority over the combat sweep below,
	# same reasoning as the chest check above — this swing goes toward
	# breaking it (see gatherable_node.gd) rather than also being wasted
	# on a fight-target check when there's nothing to punch there.
	if _try_gather():
		return

	for body in attack_area.get_overlapping_bodies():
		if not body.has_method("take_damage"):
			continue
		if body.is_in_group("hostile") or body.is_in_group("wild_monster"):
			body.take_damage(attack_damage)


## Swaps which clip the PunchClip node points at, then fires it as a
## one-shot overlay — see _setup_animation_tree() for how the filter
## keeps this confined to the upper body.
func _fire_punch(clip_name: String) -> void:
	_punch_clip_node.animation = clip_name
	animation_tree.set(
		"parameters/PunchShot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE
	)


## Single "interact" entry point for both the E key and the on-screen
## TAME button (see request_tame() below) — checks for an open-able
## chest in range first, since that's a quick, no-inventory-required
## action, and only falls back to a tame attempt if there's no chest
## nearby. Keeps one button/key covering both instead of needing a
## whole extra "interact" button crowding the touch controls.
func _try_interact() -> void:
	if is_dead or DialogueBox.is_active():
		return
	if _try_open_chest():
		return
	if _try_gather():
		return
	if _try_open_shop():
		return
	_try_tame()


## Looks for the nearest open-able chest within tame_range and starts
## its watch-an-ad-to-open flow (see chest.gd/AdManager). Returns true
## the moment a chest is found and told to open — regardless of
## whether the player actually finishes watching the ad — so
## _try_interact() knows not to also attempt a tame on this press.
func _try_open_chest() -> bool:
	var nearest: Node3D = null
	var nearest_distance: float = tame_range

	for candidate in get_tree().get_nodes_in_group("chest"):
		if not (candidate is Node3D) or not candidate.has_method("request_open"):
			continue
		if candidate.has_method("can_open") and not candidate.can_open():
			continue
		var distance: float = global_position.distance_to(candidate.global_position)
		if distance <= nearest_distance:
			nearest = candidate
			nearest_distance = distance

	if nearest == null:
		return false
	nearest.request_open()
	return true


## Same idea as _try_open_chest() but for an ore/tree node (group
## "gatherable") — mirrors its structure exactly. Used by both ATK
## (_try_attack()) and the E key/TAME button (_try_interact()).
func _try_gather() -> bool:
	var nearest: Node3D = null
	var nearest_distance: float = tame_range

	for candidate in get_tree().get_nodes_in_group("gatherable"):
		if not (candidate is Node3D) or not candidate.has_method("gather"):
			continue
		if candidate.has_method("can_gather") and not candidate.can_gather():
			continue
		var distance: float = global_position.distance_to(candidate.global_position)
		if distance <= nearest_distance:
			nearest = candidate
			nearest_distance = distance

	if nearest == null:
		return false
	nearest.gather()
	return true


## Same idea again but for a shop NPC (group "shop_npc") — opens the
## shop screen instead of granting anything directly. Deliberately not
## also wired into _try_attack(): punching the shopkeeper to open their
## shop would be a strange way to browse wares, so this only fires from
## _try_interact() (E key/TAME button).
func _try_open_shop() -> bool:
	var nearest: Node3D = null
	var nearest_distance: float = tame_range

	for candidate in get_tree().get_nodes_in_group("shop_npc"):
		if not (candidate is Node3D) or not candidate.has_method("interact"):
			continue
		var distance: float = global_position.distance_to(candidate.global_position)
		if distance <= nearest_distance:
			nearest = candidate
			nearest_distance = distance

	if nearest == null:
		return false
	nearest.interact()
	return true


func _try_tame() -> void:
	if is_dead or DialogueBox.is_active():
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

			# Gauntlet-gated instead of an ammo item: a candidate can export
			# required_gauntlet_tier/capture_energy_cost (creature_ai.gd,
			# wild_monster.gd) — default to the base tier/cost if it doesn't.
			var required_tier: int = 1
			if "required_gauntlet_tier" in candidate:
				required_tier = candidate.required_gauntlet_tier
			var energy_cost: float = 25.0
			if "capture_energy_cost" in candidate:
				energy_cost = candidate.capture_energy_cost

			if GauntletManager.energy < energy_cost:
				print("Gauntlet out of energy!")
				return

			# Being under-tiered no longer blocks the attempt outright — it
			# just makes it a long shot (see each creature's
			# underleveled_capture_chance). Passing our tier through lets
			# attempt_tame() apply that penalty itself.
			if GauntletManager.tier < required_tier:
				print("Your gauntlet isn't strong enough for a clean catch here — this is a long shot...")

			# Spent on the attempt itself, win or lose — same logic as the
			# old Capture Ball, just drawn from a rechargeable pool instead.
			GauntletManager.spend_energy(energy_cost)

			var data: Dictionary = candidate.attempt_tame(GauntletManager.tier)
			if data.is_empty():
				print("Taming failed — it's fighting back!")
				var species: String = "It"
				if "species_name" in candidate:
					species = String(candidate.species_name)
				# HUD is looked up by group rather than cached — a failed
				# tame is rare enough that this costs nothing, and it keeps
				# player.gd from needing a standing reference to a UI node.
				var hud := get_tree().get_first_node_in_group("hud")
				if hud and hud.has_method("show_notification"):
					hud.show_notification(
						"%s got more aggressive!" % species, Color(0.95, 0.3, 0.2)
					)
			else:
				MonsterRoster.add_to_collection(data)
				MonsterRoster.spawn_squad(self)
				SaveManager.save_game()
			return


## Public entry points for the on-screen touch buttons — mirror the
## keyboard/mouse actions above.
func request_attack() -> void:
	_try_attack()


## Named for taming (matches the on-screen "TAME" button/E key it's
## always been bound to), but now doubles as the general interact
## button — see _try_interact(), which checks for a chest first.
func request_tame() -> void:
	_try_interact()


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


## Sets which way the Locomotion blend should be heading (0 = Idle,
## 1 = Move). The actual crossfade happens gradually in _physics_process
## via _locomotion_blend, so this can be called every physics frame with
## no cost when the state hasn't changed.
func _set_locomotion(moving: bool) -> void:
	_locomotion_target = 1.0 if moving else 0.0


func _physics_process(delta: float) -> void:
	attack_timer = max(attack_timer - delta, 0.0)
	invulnerable_timer = max(invulnerable_timer - delta, 0.0)

	# Gradually crossfade Idle <-> Jog_Fwd toward whatever _set_locomotion
	# last requested, rather than snapping instantly — see _setup_animation_tree().
	_locomotion_blend = move_toward(_locomotion_blend, _locomotion_target, delta / _LOCOMOTION_BLEND_TIME)
	animation_tree["parameters/Locomotion/blend_amount"] = _locomotion_blend

	if is_dead:
		velocity.x = move_toward(velocity.x, 0.0, deceleration * delta)
		velocity.z = move_toward(velocity.z, 0.0, deceleration * delta)
		if not is_on_floor():
			velocity.y -= gravity * delta
		move_and_slide()
		return

	# Frozen during a dialogue line (see dialogue_box.gd) so the player
	# can't wander off, attack, or tame mid-conversation.
	if DialogueBox.is_active():
		jump_requested = false
		velocity.x = move_toward(velocity.x, 0.0, deceleration * delta)
		velocity.z = move_toward(velocity.z, 0.0, deceleration * delta)
		if not is_on_floor():
			velocity.y -= gravity * delta
		_set_locomotion(false)
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

		_set_locomotion(true)

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

		_set_locomotion(false)

	move_and_slide()
