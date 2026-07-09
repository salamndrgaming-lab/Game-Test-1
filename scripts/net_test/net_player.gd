extends CharacterBody3D
## NetTest capsule. Host-authoritative per the design doc: the owning client
## sends raw input to the server every physics tick, the server simulates,
## and the MultiplayerSynchronizer sends transforms back to everyone.
## No client prediction in Phase 0 — clients see their own capsule with a
## small delay; revisit in Phase 1 if it feels bad.
##
## The node's name IS the owning peer id (set by net_test.gd at spawn).

var input_dir := Vector2.ZERO
var jump_queued := false

@onready var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

func _ready() -> void:
	$NameTag.text = "P%s" % name
	# Deterministic per-peer color so both windows agree who is who.
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color.from_hsv(float(hash(str(name)) % 256) / 256.0, 0.65, 0.95)
	$Mesh.material_override = mat
	$CameraPivot.rotation_degrees.x = -20.0
	if _peer_id() == multiplayer.get_unique_id():
		$CameraPivot/Camera3D.make_current()

func _peer_id() -> int:
	return int(str(name))

func _physics_process(delta: float) -> void:
	if _peer_id() == multiplayer.get_unique_id():
		_gather_input()
	if multiplayer.is_server():
		_simulate(delta)

func _gather_input() -> void:
	var dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var jump := Input.is_action_just_pressed("jump")
	if multiplayer.is_server():
		input_dir = dir
		if jump:
			jump_queued = true
	else:
		# Sent every tick, unreliable: a lost packet is corrected next tick,
		# and a lost "stopped moving" packet can't wedge the capsule.
		_submit_input.rpc_id(1, dir, jump)

@rpc("any_peer", "call_remote", "unreliable_ordered")
func _submit_input(dir: Vector2, jump: bool) -> void:
	if multiplayer.get_remote_sender_id() != _peer_id():
		return  # Only the owning client may drive this capsule.
	input_dir = dir.limit_length(1.0)
	if jump:
		jump_queued = true

func _simulate(delta: float) -> void:
	var bal: BalanceConfig = Game.balance
	if not is_on_floor():
		velocity.y -= gravity * delta
	elif jump_queued:
		velocity.y = bal.player_jump_velocity
	jump_queued = false  # No jump buffering in the test scene.
	var target := Vector3(input_dir.x, 0.0, input_dir.y) * bal.player_move_speed
	velocity.x = move_toward(velocity.x, target.x, bal.player_accel * delta)
	velocity.z = move_toward(velocity.z, target.z, bal.player_accel * delta)
	move_and_slide()
