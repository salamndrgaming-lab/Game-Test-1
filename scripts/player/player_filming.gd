extends Node
## Host-side footage scoring (Phase 3 — replaces the Phase 1 HUD stub).
## While the player films, points per second scale with tornado-in-frame ×
## proximity × intensity × subject bonuses, times a steadiness multiplier.
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

	var tor: Node3D = get_tree().get_first_node_in_group("tornado")
	if tor != null and tor.active:
		var to: Vector3 = tor.global_position + Vector3.UP * 20.0 - origin
		var dist := to.length()
		if dist < bal.film_max_range and aim.angle_to(to) < half_fov:
			# The best footage is filmed from inside the danger rings.
			var proximity := 1.0 + 3.0 * clampf(1.0 - dist / bal.tornado_outer_radius, 0.0, 1.0)
			pts += bal.footage_base_points_per_second * tor.intensity * proximity
			caption = "the tornado, WAY too close" if dist < bal.tornado_middle_radius else "the tornado"

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

func _aim_dir() -> Vector3:
	return Vector3(0, 0, -1).rotated(Vector3.RIGHT, player.input_pitch).rotated(Vector3.UP, player.input_yaw)
