extends VehicleBody3D
## The van. Host-authoritative physics (clients freeze and receive synced
## transforms). Deliberately top-heavy via a raised custom center of mass:
## corners fine at low speed, threatens to roll at high speed.
##
## Seats: driver (WASD drive, SHIFT brake), passenger (radio R + glovebox G),
## two rear seats, and a roof slot. Any seat can honk (H) — the horn is
## non-positional on purpose: always audible everywhere, that's the joke.
## Doors are separate hinged bodies (siblings under the VanRig wrapper).

const SEAT_SLOTS := ["driver", "passenger", "rear_l", "rear_r", "roof"]
const EXIT_SIDE := {"driver": 1.7, "passenger": -1.7, "rear_l": 1.7, "rear_r": -1.7, "roof": 0.0}

# Synced (see Sync replication config).
var seats := {}  # slot -> peer id
var van_hp := 100.0
var radio_on := false
var glovebox_used := false

const PAINT_PALETTE := [
	Color(0.72, 0.74, 0.8),  # primer gray
	Color(0.75, 0.25, 0.2),  # barn red
	Color(0.2, 0.6, 0.6),  # motel teal
	Color(0.85, 0.75, 0.25),  # caution yellow
	Color(0.55, 0.35, 0.7),  # regret purple
]

var _prev_vel := Vector3.ZERO
var _base_color := Color(0.72, 0.74, 0.8)
var _body_mat := StandardMaterial3D.new()

@onready var engine_audio: AudioStreamPlayer3D = $EngineAudio
@onready var radio_audio: AudioStreamPlayer3D = $RadioAudio
@onready var horn_audio: AudioStreamPlayer = $HornAudio
@onready var smoke: GPUParticles3D = $Smoke

func _ready() -> void:
	add_to_group("vans")
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0.0, Game.balance.van_com_height, 0.0)
	_body_mat.albedo_color = _base_color
	$Body.material_override = _body_mat
	# WAV loops via replay-on-finished so we don't depend on import settings.
	engine_audio.finished.connect(engine_audio.play)
	radio_audio.finished.connect(func() -> void:
		if radio_on:
			radio_audio.play())
	engine_audio.play()
	if not multiplayer.is_server():
		freeze = true  # Never simulate physics on clients (design rule).

func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	_update_seats(delta)
	_apply_driver_input(delta)
	_update_damage()
	_bonk_pedestrians()

## Rigid contacts don't move CharacterBody3D, so a speeding van would just
## stop dead against a standing player. Instead: anyone standing too close to
## a fast van gets ragdolled with its velocity. Roof riders (well above the
## chassis origin) are exempt.
func _bonk_pedestrians() -> void:
	if linear_velocity.length() < 4.0:
		return
	for p in get_tree().get_nodes_in_group("players"):
		if p.state != p.PState.NORMAL:
			continue
		if p.global_position.y > global_position.y + 1.8:
			continue
		if p.global_position.distance_to(global_position) < 2.8:
			p._enter_ragdoll(linear_velocity * 1.1 + Vector3.UP * 2.5)

func _process(_delta: float) -> void:
	_update_visuals_and_audio()

# --- Seats ---------------------------------------------------------------------

## Host. Returns true if a seat was free.
func enter_player(p: Node) -> bool:
	for slot in SEAT_SLOTS:
		if not seats.has(slot):
			seats[slot] = p.peer_id()
			p.van = self
			p.state = p.PState.SEATED
			p.body_shape.set_deferred("disabled", true)
			p.velocity = Vector3.ZERO
			p.jump_queued = false
			return true
	return false

## Host. eject=true leaves the player where they are (caller ragdolls them).
func exit_player(p: Node, eject := false) -> void:
	var slot := ""
	for s in seats:
		if seats[s] == p.peer_id():
			slot = s
			break
	if slot != "":
		seats.erase(slot)
	p.van = null
	p.jump_queued = false
	p.body_shape.set_deferred("disabled", false)
	p.state = p.PState.NORMAL
	if eject:
		return
	var local_exit := Vector3(EXIT_SIDE.get(slot, 1.7), 0.5, _seat_marker(slot).position.z if slot != "" else 0.0)
	if slot == "roof":
		local_exit = Vector3(0.0, 2.6, 0.0)
	p.global_position = to_global(local_exit)
	p.velocity = linear_velocity
	# Bailing out at speed is a choice, and the choice is ragdoll.
	if linear_velocity.length() > Game.balance.van_exit_ragdoll_speed:
		p._enter_ragdoll(linear_velocity)

func _seat_marker(slot: String) -> Node3D:
	if slot != "" and $Seats.has_node(slot):
		return $Seats.get_node(slot) as Node3D
	return $Seats.get_node("driver") as Node3D

func _update_seats(delta: float) -> void:
	for slot in seats.keys():
		var p := _player_by_id(seats[slot])
		if p == null or p.van != self:
			seats.erase(slot)
			continue
		p.global_position = _seat_marker(slot).global_position
		p.velocity = Vector3.ZERO
		var fwd := -global_basis.z
		p.facing = atan2(fwd.x, fwd.z)
		p.ragdoll.follow_pose(p.facing)
		if global_position.y > 6.0:
			p.air_time += delta  # riding a flying van counts as airborne

func _player_by_id(pid: int) -> Node:
	for p in get_tree().get_nodes_in_group("players"):
		if str(p.name) == str(pid):
			return p
	return null

# --- Driving --------------------------------------------------------------------

func _apply_driver_input(delta: float) -> void:
	var bal: BalanceConfig = Game.balance
	var drv := _player_by_id(seats.get("driver", 0))
	var throttle := 0.0
	var steer_in := 0.0
	var braking := false
	if drv != null:
		throttle = -drv.input_move.y  # W = forward
		steer_in = -drv.input_move.x
		braking = drv.sprinting
	var torque := bal.van_engine_torque * (1.35 if Game.has_upgrade("van_engine") else 1.0)
	engine_force = throttle * torque if van_hp > 0.0 else 0.0
	steering = move_toward(steering, steer_in * bal.van_max_steer, bal.van_steer_speed * delta)
	if braking:
		brake = bal.van_brake_force
	elif drv == null:
		brake = bal.van_idle_brake  # parked van creeps to a stop
	else:
		brake = 0.0

# --- Damage -----------------------------------------------------------------------

func _update_damage() -> void:
	var decel := (_prev_vel - linear_velocity).length()
	_prev_vel = linear_velocity
	var bal: BalanceConfig = Game.balance
	if decel > bal.van_impact_min_decel:
		var dmg := (decel - bal.van_impact_min_decel) * bal.van_impact_damage_scale
		if Game.has_upgrade("van_rollcage"):
			dmg *= 0.5
		van_hp = maxf(van_hp - dmg, 0.0)

func _update_visuals_and_audio() -> void:
	_base_color = PAINT_PALETTE[Game.van_paint % PAINT_PALETTE.size()]
	var frac := van_hp / Game.balance.van_max_hp
	# Placeholder crumple: panels darken and the body sags as HP drops
	# (75/50/25% read as progressively worse). Real dent meshes come with art.
	_body_mat.albedo_color = _base_color.darkened((1.0 - frac) * 0.55)
	$Body.rotation_degrees.z = (1.0 - frac) * 4.0
	smoke.emitting = frac < 0.25
	if van_hp <= 0.0:
		if engine_audio.playing:
			engine_audio.stop()  # dead engine — run continues on foot
	else:
		var sputter := randf() * 0.35 if frac < 0.25 else 0.0
		engine_audio.pitch_scale = 0.8 + linear_velocity.length() * 0.04 - sputter
	if radio_on and not radio_audio.playing:
		radio_audio.play()
	elif not radio_on and radio_audio.playing:
		radio_audio.stop()

# --- Seat interactables: horn (any seat), radio + glovebox (front seats) ----------

@rpc("any_peer", "call_remote", "reliable")
func _request_horn() -> void:
	if multiplayer.is_server():
		horn_from(multiplayer.get_remote_sender_id())

func horn_from(pid: int) -> void:
	if seats.values().has(pid):
		_play_horn.rpc()

@rpc("authority", "call_local", "reliable")
func _play_horn() -> void:
	horn_audio.play()

@rpc("any_peer", "call_remote", "reliable")
func _request_radio() -> void:
	if multiplayer.is_server():
		radio_from(multiplayer.get_remote_sender_id())

func radio_from(pid: int) -> void:
	if pid == seats.get("passenger", -1) or pid == seats.get("driver", -1):
		radio_on = not radio_on

@rpc("any_peer", "call_remote", "reliable")
func _request_glovebox() -> void:
	if multiplayer.is_server():
		glovebox_from(multiplayer.get_remote_sender_id())

func glovebox_from(pid: int) -> void:
	if glovebox_used or pid != seats.get("passenger", -1):
		return
	glovebox_used = true
	var p := _player_by_id(pid)
	if p == null:
		return
	if pid == 1:
		p._refill_battery()
	else:
		p._refill_battery.rpc_id(pid)
