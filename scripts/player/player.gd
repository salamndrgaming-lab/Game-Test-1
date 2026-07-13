class_name Player
extends CharacterBody3D
## Phase 1/2 character. Host-authoritative: the owning client streams input to
## the server, the server simulates movement / ragdoll / grabbing / seating,
## and MultiplayerSynchronizers send transforms + state back to everyone.
## The node's name IS the owning peer id (set at spawn by the level script).
## Grabbing lives in the Grabber child node (player_grab.gd).

enum PState { NORMAL, RAGDOLL, SEATED }

const EMOTE_POINT := 0
const EMOTE_THUMBS := 1
const EMOTE_SCREAM := 2
const EMOTE_FAINT := 3
const EMOTE_TEXT := {
	EMOTE_POINT: "OVER THERE!",
	EMOTE_THUMBS: "THUMBS UP",
	EMOTE_SCREAM: "AAAAAAAA!",
	EMOTE_FAINT: "*faints*",
}

# Synced (see Sync node replication config).
var state: int = PState.NORMAL
var filming := false

# Host-side simulation inputs.
var input_move := Vector2.ZERO
var input_yaw := 0.0
var sprinting := false
var jump_queued := false
var facing := 0.0
var van: Node = null  # host-side: the van we're seated in

var _recover_timer := 0.0
var _prev_state: int = PState.NORMAL
var _emote_token := 0

@onready var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
@onready var ragdoll: Node3D = $Ragdoll
@onready var body_shape: CollisionShape3D = $Shape
@onready var emote_tag: Label3D = $EmoteTag
@onready var film_tag: Label3D = $FilmTag

func peer_id() -> int:
	return int(str(name))

func is_local() -> bool:
	return peer_id() == multiplayer.get_unique_id()

func _ready() -> void:
	add_to_group("players")
	$NameTag.text = "P%s" % name
	var hue := float(hash(str(name)) % 256) / 256.0
	ragdoll.tint(Color.from_hsv(hue, 0.6, 0.95))
	emote_tag.text = ""
	film_tag.visible = false

func _physics_process(delta: float) -> void:
	if is_local() and state != PState.RAGDOLL:
		_gather_input()
	if multiplayer.is_server():
		_host_update(delta)

func _process(_delta: float) -> void:
	film_tag.visible = filming and state != PState.RAGDOLL
	if state != _prev_state:
		if state == PState.RAGDOLL:
			$BonkAudio.play()
		_prev_state = state

# --- Local input --------------------------------------------------------------

func _gather_input() -> void:
	var move := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var jump := Input.is_action_just_pressed("jump")
	var sprint := Input.is_action_pressed("sprint")
	var yaw: float = $CameraRig.yaw
	if multiplayer.is_server():
		input_move = move
		input_yaw = yaw
		sprinting = sprint
		if jump and state == PState.NORMAL:
			jump_queued = true
	else:
		# Every tick, unreliable: lost packets are corrected next tick.
		_submit_input.rpc_id(1, move, yaw, sprint, jump)
	if Input.is_action_just_pressed("flop"):
		if multiplayer.is_server():
			_flop()
		else:
			_request_flop.rpc_id(1)
	if Input.is_action_just_pressed("interact"):
		if multiplayer.is_server():
			_do_interact()
		else:
			_request_interact.rpc_id(1)
	if state == PState.SEATED:
		_gather_van_input()

func _gather_van_input() -> void:
	var v := _my_van()
	if v == null:
		return
	if Input.is_action_just_pressed("horn"):
		if multiplayer.is_server():
			v.horn_from(peer_id())
		else:
			v._request_horn.rpc_id(1)
	if Input.is_action_just_pressed("radio"):
		if multiplayer.is_server():
			v.radio_from(peer_id())
		else:
			v._request_radio.rpc_id(1)
	if Input.is_action_just_pressed("glovebox"):
		if multiplayer.is_server():
			v.glovebox_from(peer_id())
		else:
			v._request_glovebox.rpc_id(1)

## On the host `van` is authoritative; clients find their van via the synced
## seats dictionary.
func _my_van() -> Node:
	if multiplayer.is_server():
		return van
	for v in get_tree().get_nodes_in_group("vans"):
		if v.seats.values().has(peer_id()):
			return v
	return null

## Called by the local HUD only.
func set_filming(active: bool) -> void:
	if multiplayer.is_server():
		filming = active
	else:
		_request_film.rpc_id(1, active)

## Called by the local HUD only.
func send_emote(id: int) -> void:
	if multiplayer.is_server():
		_handle_emote(id)
	else:
		_request_emote.rpc_id(1, id)

# --- RPCs (client -> host) ------------------------------------------------------

func _sender_ok() -> bool:
	return multiplayer.is_server() and multiplayer.get_remote_sender_id() == peer_id()

@rpc("any_peer", "call_remote", "unreliable_ordered")
func _submit_input(move: Vector2, yaw: float, sprint: bool, jump: bool) -> void:
	if not _sender_ok():
		return
	input_move = move.limit_length(1.0)
	input_yaw = yaw
	sprinting = sprint
	if jump and state == PState.NORMAL:
		jump_queued = true

@rpc("any_peer", "call_remote", "reliable")
func _request_flop() -> void:
	if _sender_ok():
		_flop()

@rpc("any_peer", "call_remote", "reliable")
func _request_interact() -> void:
	if _sender_ok():
		_do_interact()

@rpc("any_peer", "call_remote", "reliable")
func _request_film(active: bool) -> void:
	if _sender_ok():
		filming = active

@rpc("any_peer", "call_remote", "reliable")
func _request_emote(id: int) -> void:
	if _sender_ok():
		_handle_emote(id)

## Host -> the passenger who opened the glovebox: fresh camcorder battery.
@rpc("authority", "call_remote", "reliable")
func _refill_battery() -> void:
	$HUD.battery = 1.0

# --- Host-side actions --------------------------------------------------------------

func _flop() -> void:
	# Keep momentum plus a little hop; flopping in a moving van ejects you at
	# speed (the van's velocity is added inside _enter_ragdoll).
	_enter_ragdoll(velocity + Vector3.UP * 2.0)

func _do_interact() -> void:
	if state == PState.SEATED and van != null:
		van.exit_player(self)
		return
	if state != PState.NORMAL:
		return
	var v := _nearest_van(4.0)
	if v != null and v.enter_player(self):
		$Grabber.drop()
		return
	$Grabber.toggle()

func _nearest_van(max_d: float) -> Node:
	var best: Node = null
	var best_d := max_d
	for v in get_tree().get_nodes_in_group("vans"):
		var d: float = v.global_position.distance_to(global_position)
		if d < best_d:
			best_d = d
			best = v
	return best

# --- Emotes (host validates, broadcasts to all) ----------------------------------

func _handle_emote(id: int) -> void:
	if not EMOTE_TEXT.has(id):
		return
	_show_emote.rpc(id)

@rpc("authority", "call_local", "reliable")
func _show_emote(id: int) -> void:
	emote_tag.text = EMOTE_TEXT[id]
	if id == EMOTE_SCREAM:
		$ScreamAudio.play()
	_emote_token += 1
	var token := _emote_token
	get_tree().create_timer(2.0).timeout.connect(func() -> void:
		if _emote_token == token:
			emote_tag.text = "")
	if multiplayer.is_server() and id == EMOTE_FAINT:
		_enter_ragdoll()

# --- Host simulation --------------------------------------------------------------

func _host_update(delta: float) -> void:
	match state:
		PState.NORMAL:
			_simulate_move(delta)
			$Grabber.update(delta)
		PState.RAGDOLL:
			_ragdoll_follow(delta)
		PState.SEATED:
			pass  # The van positions us (van.gd _update_seats).

func _simulate_move(delta: float) -> void:
	var bal: BalanceConfig = Game.balance
	if not is_on_floor():
		velocity.y -= gravity * delta
	elif jump_queued:
		velocity.y = bal.player_jump_velocity
	jump_queued = false
	var speed := bal.player_move_speed * (bal.player_sprint_multiplier if sprinting else 1.0)
	var dir := Basis(Vector3.UP, input_yaw) * Vector3(input_move.x, 0.0, input_move.y)
	velocity.x = move_toward(velocity.x, dir.x * speed, bal.player_accel * delta)
	velocity.z = move_toward(velocity.z, dir.z * speed, bal.player_accel * delta)
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	if flat.length() > 0.5:
		facing = lerp_angle(facing, atan2(flat.x, flat.z), 10.0 * delta)
	var pre_vel := velocity
	move_and_slide()
	ragdoll.follow_pose(facing)
	# Shoving players and kicking props: CharacterBody3D applies no forces on
	# contact by itself, so both are done by hand here.
	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		var other := col.get_collider()
		if other is Player and other.state == PState.NORMAL:
			other.velocity += -col.get_normal() * bal.player_push_force * delta
		elif other is RigidBody3D and not other.freeze:
			other.apply_central_impulse(-col.get_normal() * bal.player_kick_impulse * delta * 60.0)
	# Big sudden deceleration (wall sprint, hard landing) -> comedy ragdoll.
	if (velocity - pre_vel).length() > bal.ragdoll_impact_speed:
		_enter_ragdoll(pre_vel)

func _enter_ragdoll(initial_velocity: Vector3 = Vector3.ZERO) -> void:
	if state == PState.RAGDOLL:
		return
	var extra := Vector3.ZERO
	if state == PState.SEATED and van != null:
		extra = van.linear_velocity
		van.exit_player(self, true)
	state = PState.RAGDOLL
	_recover_timer = 0.0
	$Grabber.drop()
	var vel := initial_velocity + extra
	if vel == Vector3.ZERO:
		vel = velocity
	velocity = Vector3.ZERO
	body_shape.set_deferred("disabled", true)
	ragdoll.activate(vel)

func _ragdoll_follow(delta: float) -> void:
	ragdoll.hold_root_to_torso(self)
	# A fast-flying body knocks over anyone it hits. Content.
	if ragdoll.torso_speed() > 5.0:
		for p in get_tree().get_nodes_in_group("players"):
			if p != self and p.state == PState.NORMAL \
					and p.global_position.distance_to(global_position) < 0.9:
				p._enter_ragdoll(ragdoll.torso_velocity() * 0.8)
	if ragdoll.is_settled():
		_recover_timer += delta
		if _recover_timer >= Game.balance.player_ragdoll_recover_seconds:
			_exit_ragdoll()
	else:
		_recover_timer = 0.0

func _exit_ragdoll() -> void:
	global_position = ragdoll.torso_position() + Vector3.UP * 0.2
	ragdoll.deactivate()
	body_shape.set_deferred("disabled", false)
	velocity = Vector3.ZERO
	state = PState.NORMAL
