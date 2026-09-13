extends Node

## Autoload singleton: which gathering tools the player has crafted.
##
## A tool (Pickaxe, Axe — see ItemDatabase's "unlocks_tool" items) is a
## one-time craft that's consumed the moment it's used (see
## InventoryManager.use_item()'s ItemType.TOOL branch) to permanently
## register here instead of sitting in the inventory as a repeatable
## item. Once owned, it makes that tool's matching gatherable node type
## (see gatherable_node.gd's tool_item_id/tool_required_hits) take far
## fewer hits to break — bare hands still work on any node, a tool just
## makes it faster.

signal tool_unlocked(tool_id: String)

var owned_tools: Dictionary = {}  # tool_id -> true (used as a set)


func has_tool(tool_id: String) -> bool:
	return owned_tools.has(tool_id)


## Idempotent — using a second copy of a tool you already own (shouldn't
## normally happen, since stack_max is 1, but a stray extra shouldn't be
## able to do anything weird) is a no-op rather than emitting twice.
func unlock_tool(tool_id: String) -> void:
	if owned_tools.has(tool_id):
		return
	owned_tools[tool_id] = true
	tool_unlocked.emit(tool_id)


## Used by SaveManager.restart_game() — see there for why.
func reset() -> void:
	owned_tools.clear()


func to_save_data() -> Dictionary:
	return owned_tools.duplicate()


func load_save_data(data: Dictionary) -> void:
	owned_tools = (data as Dictionary).duplicate()
