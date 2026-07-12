extends Node
## Host-side prop grabbing: deliberately floppy spring (HL2 gravity-gun-lite).
## Two players grabbing one prop apply independent springs and fight over it.
## Lives on its own node so player.gd stays under the size budget.

var grabbed: RigidBody3D = null

@onready var player: CharacterBody3D = get_parent()

func toggle() -> void:
	if grabbed != null:
		drop()
		return
	var best: RigidBody3D = null
	var best_d := 2.6
	for node in get_tree().get_nodes_in_group("grabbable"):
		if node is RigidBody3D:
			var d: float = node.global_position.distance_to(_hold_point())
			if d < best_d:
				best_d = d
				best = node
	grabbed = best

func drop() -> void:
	grabbed = null

func update(_delta: float) -> void:
	if grabbed == null:
		return
	if not is_instance_valid(grabbed) \
			or grabbed.global_position.distance_to(_hold_point()) > Game.balance.grab_break_distance:
		drop()
		return
	var to := _hold_point() - grabbed.global_position
	var force := to * Game.balance.grab_spring - grabbed.linear_velocity * Game.balance.grab_damping
	grabbed.apply_central_force(force * grabbed.mass)

func _hold_point() -> Vector3:
	return player.global_position + Basis(Vector3.UP, player.input_yaw) * Vector3(0.0, 1.2, -1.4)
