extends Node3D
## An interactable garage station (contracts board, shop bench, paint booth,
## hat rack, garage door). Player E-interact resolves on the host, which
## calls use(); the garage manager does the actual work.

@export var station_id := ""

func use(player: Node) -> void:  # host-side
	var mgr := get_tree().get_first_node_in_group("garage_manager")
	if mgr != null:
		mgr.station_used(station_id, player)
