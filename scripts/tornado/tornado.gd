extends Node3D
## One storm cell from the forecast. The run manager instantiates one of
## these per forecast cell; it activates at t_start, ramps up to its peak
## F-rating, holds, ramps out, and dies — several can be live at once.
## Host-simulated: noise-driven wander leashed to the cell center, plus the
## three-ring suction model:
##   outer  (200m): loose props slide toward the funnel, wind ramps
##   middle  (80m): players shoved, light props airborne, van pushed, hats gone
##   inner   (25m): players ragdoll and orbit up the funnel, van can fly
## Clients only run visuals/audio from the synced position + intensity.

# Cell parameters, set by the run manager before add_child (from Game.forecast).
var cell_index := 0
var cell_center := Vector2.ZERO
var peak := 2.0
var t_start := 0.0
var duration := 240.0

var intensity := 0.0  # synced
var active := false  # synced

var _elapsed := 0.0
var _noise := FastNoiseLite.new()

@onready var funnel: Node3D = $Funnel
@onready var dust: GPUParticles3D = $Dust
@onready var debris: GPUParticles3D = $Debris
@onready var wind: AudioStreamPlayer = $Wind

func _ready() -> void:
	add_to_group("tornado")
	_noise.seed = 7 + cell_index
	wind.finished.connect(wind.play)
	wind.play()

func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	_elapsed += delta
	var t := _elapsed - t_start
	if t < 0.0 or t > duration:
		if active:
			active = false
			intensity = 0.0
		return
	active = true
	intensity = maxf(peak * _envelope(t / duration), 0.15)
	_wander(delta)
	_apply_suction(delta)

## Ramp in over the first quarter, hold, ramp out over the last quarter.
func _envelope(u: float) -> float:
	return clampf(minf(u / 0.25, (1.0 - u) / 0.25), 0.0, 1.0)

func _process(delta: float) -> void:
	# Visuals/audio on every peer from synced state.
	visible = active
	dust.emitting = active
	debris.emitting = active
	funnel.rotation.y += delta * (2.0 + intensity)
	var s := 0.5 + intensity * 0.28
	funnel.scale = funnel.scale.lerp(Vector3(s, 1.0, s), 2.0 * delta)
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	if not active:
		wind.volume_db = maxf(wind.volume_db - 20.0 * delta, -60.0)
		return
	var d := cam.global_position.distance_to(global_position)
	var closeness := clampf(1.0 - d / (Game.balance.tornado_outer_radius * 1.5), 0.0, 1.0)
	wind.volume_db = lerpf(-38.0, 6.0, closeness) + (intensity - 1.0) * 2.0

# --- Host simulation ---------------------------------------------------------

func _wander(delta: float) -> void:
	var ang := _noise.get_noise_1d(_elapsed * 3.0) * TAU
	var dir := Vector3(sin(ang), 0.0, cos(ang))
	var from_center := Vector3(global_position.x - cell_center.x, 0.0, global_position.z - cell_center.y)
	if from_center.length() > Game.balance.tornado_leash_radius:
		# Steer back toward the cell's home turf.
		dir = (dir - from_center.normalized() * 1.3).normalized()
	global_position += dir * Game.balance.tornado_wander_speed * delta * (0.7 + intensity * 0.15)
	global_position.y = 0.0

func _apply_suction(_delta: float) -> void:
	var bal: BalanceConfig = Game.balance
	var inten_f := intensity / 4.0
	for prop in get_tree().get_nodes_in_group("grabbable"):
		if not prop is RigidBody3D or prop.freeze:
			continue
		_pull_prop(prop, bal, inten_f)
	for p in get_tree().get_nodes_in_group("players"):
		_pull_player(p, bal, inten_f)
	for v in get_tree().get_nodes_in_group("vans"):
		_pull_van(v, bal, inten_f)

func _flat_offset(from: Vector3) -> Vector3:
	var off := global_position - from
	off.y = 0.0
	return off

func _pull_prop(prop: RigidBody3D, bal: BalanceConfig, inten_f: float) -> void:
	var off := _flat_offset(prop.global_position)
	var d := off.length()
	if d > bal.tornado_outer_radius or d < 0.5:
		return
	var inward := off / d
	var tang := inward.cross(Vector3.UP)
	var f: Vector3
	if d < bal.tornado_inner_radius:
		f = (inward * 0.4 + tang) * bal.tornado_pull_inner + Vector3.UP * bal.tornado_inner_lift * 0.6
	elif d < bal.tornado_middle_radius:
		f = (inward * 0.8 + tang * 0.5) * bal.tornado_pull_middle
		if prop.mass < 4.0:
			f += Vector3.UP * bal.tornado_pull_middle * 0.6
	else:
		f = inward * bal.tornado_pull_outer
	prop.apply_central_force(f * prop.mass * inten_f * 2.0)

func _pull_player(p: Node, bal: BalanceConfig, inten_f: float) -> void:
	var off := _flat_offset(p.global_position)
	var d := off.length()
	if d > bal.tornado_middle_radius or d < 0.1:
		return
	var inward := off / d
	# Hats must physics-detach in the wind and be chaseable (design doc).
	if p.hat_id != 0:
		var mgr := get_tree().get_first_node_in_group("run_manager")
		if mgr != null:
			var fling := Vector3.UP * 6.0 + inward.cross(Vector3.UP) * 8.0
			mgr.spawn_hat(p.global_position + Vector3.UP * 2.0, p.hat_id, fling)
			p.hat_id = 0
	if p.state == p.PState.NORMAL:
		if d < bal.tornado_inner_radius:
			p._enter_ragdoll(Vector3.UP * 6.0)
		else:
			p.velocity += inward * bal.tornado_middle_push * inten_f * get_physics_process_delta_time()
	elif p.state == p.PState.RAGDOLL:
		var torso: RigidBody3D = p.ragdoll.torso
		var height := torso.global_position.y - global_position.y
		var lift := clampf(1.0 - height / 55.0, 0.0, 1.0)  # lift fades near the top -> flung out
		var tang := inward.cross(Vector3.UP)
		var f := (inward * 0.5 + tang) * bal.tornado_pull_inner \
				+ Vector3.UP * bal.tornado_inner_lift * lift
		torso.apply_central_force(f * inten_f * torso.mass)

func _pull_van(v: Node, bal: BalanceConfig, inten_f: float) -> void:
	var off := _flat_offset(v.global_position)
	var d := off.length()
	if d > bal.tornado_middle_radius:
		return
	var inward := off / maxf(d, 1.0)
	var push := bal.tornado_van_push * (0.5 if Game.has_upgrade("van_tires") else 1.0)
	v.apply_central_force(inward * push * inten_f)
	if d < bal.tornado_inner_radius and intensity >= bal.tornado_van_lift_intensity:
		v.apply_central_force(Vector3.UP * bal.tornado_van_lift)
		v.apply_torque(Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 3000.0)
