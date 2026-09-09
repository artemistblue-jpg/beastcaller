extends Node3D

## A small floating health bar that always faces the camera. Drop this as
## a child of anything with a sibling "HealthComponent" node and it wires
## itself up automatically — no other script needs to know it exists.

@export var width: float = 1.0
@export var height: float = 0.12
@export var height_offset: float = 2.2

@export var low_health_fraction: float = 0.3
@export var normal_color: Color = Color(0.2, 0.85, 0.25, 1.0)
@export var low_color: Color = Color(0.9, 0.15, 0.15, 1.0)

@onready var back_sprite: Sprite3D = $Back
@onready var fill_sprite: Sprite3D = $Fill

var health: HealthComponent = null


func _ready() -> void:
	position.y = height_offset

	var pixel_image := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	pixel_image.fill(Color.WHITE)
	var texture := ImageTexture.create_from_image(pixel_image)

	_setup_sprite(back_sprite, texture, Color(0.08, 0.08, 0.08, 0.85))
	back_sprite.scale = Vector3(width, height, 1.0)

	_setup_sprite(fill_sprite, texture, normal_color)
	fill_sprite.scale = Vector3(width, height * 0.75, 1.0)
	fill_sprite.position.z = 0.001

	var owner_node := get_parent()
	if owner_node != null and owner_node.has_node("HealthComponent"):
		track(owner_node.get_node("HealthComponent"))


func _setup_sprite(sprite: Sprite3D, texture: Texture2D, color: Color) -> void:
	sprite.texture = texture
	sprite.pixel_size = 1.0
	sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	sprite.shaded = false
	sprite.no_depth_test = true
	sprite.modulate = color
	sprite.centered = true


func track(health_component: HealthComponent) -> void:
	health = health_component
	health.health_changed.connect(_on_health_changed)
	_on_health_changed(health.current_health, health.max_health)


func _on_health_changed(current: float, max_health: float) -> void:
	var fraction: float = 0.0
	if max_health > 0.0:
		fraction = clamp(current / max_health, 0.0, 1.0)

	var fill_width: float = max(width * fraction, 0.001)
	fill_sprite.scale.x = fill_width
	fill_sprite.position.x = -(width - fill_width) / 2.0
	fill_sprite.modulate = low_color if fraction <= low_health_fraction else normal_color

	visible = fraction > 0.0
