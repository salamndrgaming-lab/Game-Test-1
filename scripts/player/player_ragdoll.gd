extends Node3D
## The character's visible body IS this ragdoll: six pin-jointed rigid bodies.
## In NORMAL state the host pose-locks the frozen parts to the CharacterBody3D
## each tick; on ragdoll the host unfreezes them and physics takes over.
## Clients never simulate (design rule) — their parts stay frozen and receive
## transforms from the RagdollSync node at a reduced rate. Resulting jitter
## reads as comedy, which is the point.

const PARTS := ["Torso", "Head", "ArmL", "ArmR", "LegL", "LegR"]

var active := false
var _rest: Dictionary = {}

@onready var torso: RigidBody3D = $Torso

func _ready() -> void:
	for part_name in PARTS:
		var p: RigidBody3D = get_node(part_name)
		_rest[part_name] = p.transform
		p.freeze = true
		_set_collide(p, false)

func set_hat(id: int) -> void:
	var hat: MeshInstance3D = $Head/Hat
	hat.visible = id != 0
	if id != 0:
		hat.mesh = HatProp.build_mesh(id)

func tint(color: Color) -> void:
	for part_name in PARTS:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color.lightened(0.45) if part_name == "Head" else color
		get_node(part_name).get_node("Mesh").material_override = mat

## Host, NORMAL state: keep frozen parts glued to the capsule, rotated to face
## the move direction (the root never yaws — the camera hangs off it).
func follow_pose(facing: float) -> void:
	if active:
		return
	var base := Transform3D(Basis(Vector3.UP, facing), Vector3.ZERO)
	for part_name in PARTS:
		get_node(part_name).transform = base * _rest[part_name]

func activate(initial_velocity: Vector3) -> void:
	active = true
	for part_name in PARTS:
		var p: RigidBody3D = get_node(part_name)
		p.freeze = false
		_set_collide(p, true)
		p.linear_velocity = initial_velocity
		p.angular_velocity = Vector3(randf_range(-3, 3), randf_range(-3, 3), randf_range(-3, 3))

func deactivate() -> void:
	active = false
	for part_name in PARTS:
		var p: RigidBody3D = get_node(part_name)
		p.freeze = true
		_set_collide(p, false)
		p.linear_velocity = Vector3.ZERO
		p.angular_velocity = Vector3.ZERO
		p.transform = _rest[part_name]

## Host, RAGDOLL state: glue the player root to the torso WITHOUT dragging
## the doll along. The parts are children of the root, and moving the parent
## of an active RigidBody3D teleports it by the same delta — a feedback loop
## that flings the doll to infinity. Save/restore part globals around the move.
func hold_root_to_torso(root: Node3D) -> void:
	var saved := {}
	for part_name in PARTS:
		saved[part_name] = (get_node(part_name) as RigidBody3D).global_transform
	root.global_position = torso.global_position
	for part_name in PARTS:
		(get_node(part_name) as RigidBody3D).global_transform = saved[part_name]

func torso_position() -> Vector3:
	return torso.global_position

func torso_velocity() -> Vector3:
	return torso.linear_velocity

func torso_speed() -> float:
	return torso.linear_velocity.length()

func is_settled() -> bool:
	return torso.linear_velocity.length() < 0.8

func _set_collide(p: RigidBody3D, on: bool) -> void:
	# Layers: 1 world, 2 players, 4 props, 8 vehicles. Frozen pose-locked
	# parts must not collide with anything or they'd act as moving walls.
	p.collision_layer = 2 if on else 0
	p.collision_mask = 15 if on else 0
