extends Node3D
## Third-person camera rig, purely local for the owning player. Pitch stays
## client-side; yaw is read by player.gd and streamed to the host as part of
## the input packet (movement basis + facing + grab aim).

var yaw := 0.0
var pitch := deg_to_rad(-15.0)

@onready var player: CharacterBody3D = get_parent()
@onready var arm: SpringArm3D = $SpringArm
@onready var camera: Camera3D = $SpringArm/Camera

func _ready() -> void:
	if not player.is_local():
		set_process(false)
		set_process_input(false)
		return
	camera.make_current()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sens: float = Game.balance.mouse_sensitivity * float(Game.settings.get("sensitivity", 1.0))
		yaw = wrapf(yaw - event.relative.x * sens, -PI, PI)
		pitch = clampf(pitch - event.relative.y * sens, deg_to_rad(-70.0), deg_to_rad(35.0))

func _process(delta: float) -> void:
	rotation = Vector3(0.0, yaw, 0.0)
	arm.rotation = Vector3(pitch, 0.0, 0.0)
	# Slight zoom while filming sells the camcorder.
	camera.fov = lerpf(camera.fov, 50.0 if player.filming else 75.0, 8.0 * delta)
	# Seated: rise above the van roof for an exterior chase cam (the arm
	# ignores the vehicle layer, so without this you'd stare at roof interior).
	var seated: bool = player.state == player.PState.SEATED
	arm.position.y = lerpf(arm.position.y, 3.0 if seated else 1.6, 6.0 * delta)
	arm.spring_length = lerpf(arm.spring_length, 6.5 if seated else 4.0, 6.0 * delta)
