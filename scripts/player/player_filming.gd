extends Node
## Host-side footage scoring. Points/sec scale with the best in-frame storm
## cell × proximity × intensity, plus subject bonuses (friend flung, van
## airborne), times a steadiness multiplier.
##
## Role economy (everyone contributes):
##  - Filming the navigator's CALLED cell pays a bonus, and the navigator
##    earns a cut of it (they found the shot).
##  - Filming from a moving van pays the driver a cut (they made the shot
##    possible).
## The best single second and its caption feed the results screen.

var best_second := 0.0
var best_caption := "a whole lot of nothing"

var _bucket := 0.0
var _bucket_caption := "the tornado"
var _bucket_t := 0.0

@onready var player: CharacterBody3D = get_parent()

func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	if not player.filming or player.dead or player.state == player.PState.RAGDOLL:
		# Reset the best-second bucket so a partial old second can't pad the
		# next filming session's first second.
		_bucket = 0.0
		_bucket_t = 0.0
		return
	var bal: BalanceConfig = Game.balance
	var aim := _aim_dir()
	var origin: Vector3 = player.global_position + Vector3.UP * 1.5
	var fov := bal.film_fov_degrees + (20.0 if Game.has_upgrade("cam_lens") else 0.0)
	var half_fov := deg_to_rad(fov * 0.5)
	var pts := 0.0
	var caption := ""

	# Best in-frame storm cell (several can be live at once).
	var best_tor: Node = null
	var best_tor_pts := 0.0
	for tor in get_tree().get_nodes_in_group("tornado"):
		if not tor.active:
			continue
		var to: Vector3 = tor.global_position + Vector3.UP * 20.0 - origin
		var dist := to.length()
		if dist >= bal.film_max_range or aim.angle_to(to) >= half_fov:
			continue
		# The best footage is filmed from inside the danger rings.
		var proximity := 1.0 + 3.0 * clampf(1.0 - dist / bal.tornado_outer_radius, 0.0, 1.0)
		var cell_pts: float = bal.footage_base_points_per_second * tor.intensity * proximity
		if cell_pts > best_tor_pts:
			best_tor_pts = cell_pts
			best_tor = tor
			caption = "the tornado, WAY too close" if dist < bal.tornado_middle_radius else "the tornado"
	pts += best_tor_pts

	for p in get_tree().get_nodes_in_group("players"):
		if p == player:
			continue
		if p.state == p.PState.RAGDOLL and p.ragdoll.torso_speed() > 8.0:
			var to_p: Vector3 = p.global_position - origin
			if to_p.length() < 150.0 and aim.angle_to(to_p) < half_fov:
				pts += bal.film_bonus_fling
				caption = "P%s getting yeeted" % p.name

	for v in get_tree().get_nodes_in_group("vans"):
		if v.linear_velocity.y > 4.0 or v.global_position.y > 4.0:
			var to_v: Vector3 = v.global_position - origin
			if to_v.length() < 250.0 and aim.angle_to(to_v) < half_fov:
				pts += bal.film_bonus_van_air
				caption = "THE VAN IS AIRBORNE"

	if pts <= 0.0:
		return
	var speed := Vector3(player.velocity.x, 0.0, player.velocity.z).length()
	var steadiness := 1.5 if speed < 0.5 else (0.5 if speed > bal.player_move_speed else 1.0)
	if Game.has_upgrade("cam_stabilizer"):
		steadiness = maxf(steadiness, 1.0)  # no penalty on the move
	pts *= steadiness

	# Navigator's call: bonus for shooting the called cell, cut for the caller.
	var mgr := get_tree().get_first_node_in_group("run_manager")
	if best_tor != null and mgr != null and mgr.called_cell == best_tor.cell_index:
		pts *= bal.called_bonus
		var spotter := _player_by_id(mgr.called_by)
		if spotter != null and spotter != player:
			spotter.footage += pts * bal.spotter_cut * delta
	# Wheelman's cut: shots taken from someone's van pay the driver.
	if player.state == player.PState.SEATED and player.van != null:
		var drv := _player_by_id(int(player.van.seats.get("driver", 0)))
		if drv != null and drv != player:
			drv.footage += pts * bal.driver_cut * delta

	player.footage += pts * delta
	_bucket += pts * delta
	_bucket_t += delta
	if caption != "":
		_bucket_caption = caption
	if _bucket_t >= 1.0:
		if _bucket > best_second:
			best_second = _bucket
			best_caption = _bucket_caption
		_bucket = 0.0
		_bucket_t = 0.0

func _player_by_id(pid: int) -> Node:
	for p in get_tree().get_nodes_in_group("players"):
		if str(p.name) == str(pid):
			return p
	return null

func _aim_dir() -> Vector3:
	return Vector3(0, 0, -1).rotated(Vector3.RIGHT, player.input_pitch).rotated(Vector3.UP, player.input_yaw)
