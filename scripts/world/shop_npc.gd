extends StaticBody3D

## A stationary NPC that opens the shop screen (see shop_screen.gd) when
## the player interacts with it — same nearest-in-range pattern as
## chests and gatherable nodes (see player.gd's _try_open_shop()), just
## opening a UI instead of handing over loot directly.

func _ready() -> void:
	add_to_group("shop_npc")


func interact() -> void:
	var shop_screens := get_tree().get_nodes_in_group("shop_screen")
	if shop_screens.size() > 0 and shop_screens[0].has_method("open"):
		shop_screens[0].open()
