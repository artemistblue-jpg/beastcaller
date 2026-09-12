extends Control

## Draws a simple top-down dot map of the world: the player as a small
## facing arrow, plus color-coded blips for whatever's currently alive
## in a handful of gameplay groups. Reused as-is by both minimap.gd (a
## small always-on corner widget) and full_map_screen.gd (the big
## screen it opens into) — same drawing code at two different sizes,
## since this Control's own `size` is all _world_to_map() needs to
## scale into.
##
## Nothing here is cached — every blip is read straight from each
## node's global_position on every redraw — so a creature that dies (or
## respawns elsewhere) just stops/starts showing up on its own with
## zero extra wiring back to this file.

## Half the world's play-field size along one axis — the ground is
## 240x240 (see world.tscn), centered on the origin, so this is 120.
@export var world_half_size: float = 120.0
## How often to recompute and redraw. A map doesn't need to be pixel-
## perfect every frame, so this trades a little latency for not
## walking every tracked group's node list 60 times a second — cheap
## either way at this project's scale, but especially worth it for the
## always-on minimap widget on a phone.
@export var refresh_interval: float = 0.15

const BACKGROUND_COLOR: Color = Color(0.05, 0.08, 0.06, 0.85)
const BORDER_COLOR: Color = Color(0.6, 0.75, 0.6, 0.9)
const PLAYER_COLOR: Color = Color(1.0, 1.0, 1.0)
const BLIP_RADIUS: float = 3.0
const PLAYER_MARKER_SIZE: float = 7.0

## group name -> blip color. Anything currently in one of these groups
## shows up as a dot; a node in none of them (scenery, ground, UI,
## creature spawners themselves rather than what they spawn, etc.) just
## doesn't appear.
const GROUP_COLORS: Dictionary = {
	"hostile": Color(0.9, 0.25, 0.25),
	"wild_monster": Color(0.95, 0.55, 0.15),
	"shop_npc": Color(0.35, 0.55, 0.95),
	"gatherable": Color(0.4, 0.85, 0.45),
}

var _refresh_timer: float = 0.0
var _player: Node3D = null


func _ready() -> void:
	set_process(true)


func _process(delta: float) -> void:
	_refresh_timer -= delta
	if _refresh_timer <= 0.0:
		_refresh_timer = refresh_interval
		queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BACKGROUND_COLOR)
	draw_rect(Rect2(Vector2.ZERO, size), BORDER_COLOR, false, 2.0)

	for group_name in GROUP_COLORS.keys():
		_draw_group_blips(group_name, GROUP_COLORS[group_name])

	_draw_player_marker()


func _draw_group_blips(group_name: String, color: Color) -> void:
	for node in get_tree().get_nodes_in_group(group_name):
		if node is Node3D:
			draw_circle(_world_to_map(node.global_position), BLIP_RADIUS, color)


func _draw_player_marker() -> void:
	var player := _get_player()
	if player == null:
		return

	var pos: Vector2 = _world_to_map(player.global_position)
	var facing: float = 0.0
	if player.has_node("CharacterModel"):
		facing = (player.get_node("CharacterModel") as Node3D).rotation.y

	# Matches how player.gd computes this same angle for movement
	# (atan2(direction.x, direction.z)) — so "forward" here is
	# (sin(facing), cos(facing)) in that same (x, z) sense, kept
	# consistent with _world_to_map()'s x->x, z->y mapping.
	var forward := Vector2(sin(facing), cos(facing))
	var right := Vector2(forward.y, -forward.x)

	var tip: Vector2 = pos + forward * PLAYER_MARKER_SIZE
	var base_left: Vector2 = pos - forward * (PLAYER_MARKER_SIZE * 0.6) + right * (PLAYER_MARKER_SIZE * 0.6)
	var base_right: Vector2 = pos - forward * (PLAYER_MARKER_SIZE * 0.6) - right * (PLAYER_MARKER_SIZE * 0.6)

	draw_colored_polygon(PackedVector2Array([tip, base_left, base_right]), PLAYER_COLOR)


func _get_player() -> Node3D:
	if _player == null or not is_instance_valid(_player):
		var players := get_tree().get_nodes_in_group("player")
		if players.size() > 0:
			_player = players[0]
	return _player


func _world_to_map(world_pos: Vector3) -> Vector2:
	var normalized_x: float = clamp((world_pos.x + world_half_size) / (world_half_size * 2.0), 0.0, 1.0)
	var normalized_z: float = clamp((world_pos.z + world_half_size) / (world_half_size * 2.0), 0.0, 1.0)
	return Vector2(normalized_x * size.x, normalized_z * size.y)
