extends Area3D

## A one-time item pickup placed directly in the world (see world.tscn's
## "Pickups" group, scattered alongside the trees/rocks). Walk into it as
## the player to collect it. Doesn't respawn — unlike CreatureSpawner,
## these are meant to feel like a one-off find (a stray potion, a relic),
## not a renewable resource.

@export var item_id: String = ""
@export var quantity: int = 1

@onready var mesh_instance: MeshInstance3D = $MeshInstance3D

var _collected: bool = false


func _ready() -> void:
	body_entered.connect(_on_body_entered)

	if ItemDatabase.has_item(item_id):
		var material := StandardMaterial3D.new()
		var color: Color = ItemDatabase.get_color(item_id)
		material.albedo_color = color
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 0.6
		mesh_instance.material_override = material
	else:
		push_warning("ItemPickup: unknown item_id '%s'" % item_id)


func _process(delta: float) -> void:
	rotate_y(1.5 * delta)


func _on_body_entered(body: Node3D) -> void:
	if _collected or not body.is_in_group("player"):
		return
	if item_id == "" or not ItemDatabase.has_item(item_id):
		return

	_collected = true
	InventoryManager.add_item(item_id, quantity)
	queue_free()
