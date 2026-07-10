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
		var sens: float = Game.balance.mouse_sensitivity
		yaw = wrapf(yaw - event.relative.x * sens, -PI, PI)
		pitch = clampf(pitch - event.relative.y * sens, deg_to_rad(-70.0), deg_to_rad(35.0))

func _process(delta: float) -> void:
	rotation = Vector3(0.0, yaw, 0.0)
	arm.rotation = Vector3(pitch, 0.0, 0.0)
	# Slight zoom while filming sells the camcorder.
	camera.fov = lerpf(camera.fov, 50.0 if player.filming else 75.0, 8.0 * delta)
