extends Node3D
## Run manager: storm spawns at the map edge -> ~10 min chase -> storm
## dissipates -> drive to extraction -> footage uploads -> RESULTS.
## Host drives the state machine; run_state/time_left sync to clients.
## Player spawning uses the same ready-handshake as NetTest (see that file
## for why MultiplayerSpawner can't be trusted with our scene-change timing).

enum RunState { CHASE, DISSIPATE, EXTRACT, DONE }

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const PICKUP_SCENE := preload("res://scenes/props/camera_pickup.tscn")
const EXTRACT_RADIUS := 15.0

var run_state: int = RunState.CHASE  # synced
var time_left := 0.0  # synced

var _pickup_seq := 0

@onready var players: Node3D = $Players
@onready var tornado: Node3D = $Tornado
@onready var extraction: Node3D = $Extraction
@onready var sun: DirectionalLight3D = $Sun
@onready var run_label: Label = $UI/RunLabel

func _ready() -> void:
	add_to_group("run_manager")
	$Sun.rotation_degrees = Vector3(-55.0, -30.0, 0.0)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	if multiplayer.is_server():
		time_left = Game.balance.run_chase_seconds
		_spawn_local(1, _spawn_pos(0))
	else:
		_notify_ready.rpc_id(1)

func _physics_process(delta: float) -> void:
	if multiplayer.is_server():
		_update_run(delta)

func _process(_delta: float) -> void:
	var inten: float = tornado.intensity if tornado.active else 0.0
	# Sky darkens as the storm intensifies (telegraphs the F-rating).
	sun.light_energy = lerpf(1.2, 0.3, inten / 4.0)
	run_label.text = _run_text(inten)

func _run_text(inten: float) -> String:
	match run_state:
		RunState.CHASE:
			return "STORM: F%d    %d:%02d    hold C to film it" \
					% [clampi(int(inten), 1, 4), int(time_left / 60.0), int(time_left) % 60]
		RunState.DISSIPATE:
			return "The storm is collapsing..."
		RunState.EXTRACT:
			return "GET TO EXTRACTION — the beacon (%ds)" % int(time_left)
		_:
			return "Uploading..."

# --- Host run state ---------------------------------------------------------

func _update_run(delta: float) -> void:
	time_left = maxf(time_left - delta, 0.0)
	match run_state:
		RunState.CHASE:
			if time_left <= 0.0:
				run_state = RunState.DISSIPATE
				time_left = 20.0
				tornado.dissipating = true
		RunState.DISSIPATE:
			if time_left <= 0.0:
				run_state = RunState.EXTRACT
				time_left = Game.balance.run_extract_seconds
		RunState.EXTRACT:
			_bank_players_in_zone()
			if time_left <= 0.0 or _all_alive_at_extraction():
				_finish_run()
		RunState.DONE:
			pass

func _bank_players_in_zone() -> void:
	for p in get_tree().get_nodes_in_group("players"):
		if p.dead or p.footage <= 0.0:
			continue
		if p.global_position.distance_to(extraction.global_position) < EXTRACT_RADIUS:
			p.banked += p.footage
			p.footage = 0.0

func _all_alive_at_extraction() -> bool:
	for p in get_tree().get_nodes_in_group("players"):
		if p.dead:
			continue
		if p.global_position.distance_to(extraction.global_position) > EXTRACT_RADIUS:
			return false
	return true

func _finish_run() -> void:
	run_state = RunState.DONE
	var results: Array = []
	var total := 0.0
	for p in get_tree().get_nodes_in_group("players"):
		total += p.banked
		var filming: Node = p.get_node("Filming")
		results.append({
			"pid": p.peer_id(),
			"footage": int(p.banked),
			"best": int(filming.best_second),
			"caption": String(filming.best_caption),
		})
	var views := int(total * Game.balance.views_per_point)
	var money := int(views / 100.0 * Game.balance.payout_per_100_views)
	Game.set_run_results.rpc(results, views, money)
	Game.net_change_state.rpc(Game.State.RESULTS)

# --- Camera pickups (death drops) --------------------------------------------

func spawn_pickup(pos: Vector3, amount: float) -> void:  # host
	_pickup_seq += 1
	_spawn_pickup.rpc("pickup_%d" % _pickup_seq, pos, amount)

func despawn_pickup(node: Node) -> void:  # host
	_despawn_pickup.rpc(String(node.name))

@rpc("authority", "call_local", "reliable")
func _spawn_pickup(pickup_name: String, pos: Vector3, amount: float) -> void:
	var pk := PICKUP_SCENE.instantiate()
	pk.name = pickup_name
	pk.amount = amount
	pk.position = pos
	$Pickups.add_child(pk)

@rpc("authority", "call_local", "reliable")
func _despawn_pickup(pickup_name: String) -> void:
	if $Pickups.has_node(pickup_name):
		$Pickups.get_node(pickup_name).queue_free()

# --- Player spawning (ready-handshake, same rationale as net_test.gd) ---------

@rpc("any_peer", "call_remote", "reliable")
func _notify_ready() -> void:
	if not multiplayer.is_server():
		return
	var pid := multiplayer.get_remote_sender_id()
	for existing in players.get_children():
		_spawn_remote.rpc_id(pid, int(str(existing.name)), existing.position)
	_spawn_remote.rpc(pid, _spawn_pos(players.get_child_count()))

@rpc("authority", "call_local", "reliable")
func _spawn_remote(pid: int, pos: Vector3) -> void:
	_spawn_local(pid, pos)

func _spawn_local(pid: int, pos: Vector3) -> void:
	if players.has_node(str(pid)):
		return
	var player := PLAYER_SCENE.instantiate()
	player.name = str(pid)
	player.position = pos
	players.add_child(player)

func _spawn_pos(idx: int) -> Vector3:
	return Vector3(438.0 + 2.5 * idx, 0.2, 442.0)

func _on_peer_disconnected(id: int) -> void:
	if multiplayer.is_server():
		_despawn_remote.rpc(id)

@rpc("authority", "call_local", "reliable")
func _despawn_remote(pid: int) -> void:
	if players.has_node(str(pid)):
		players.get_node(str(pid)).queue_free()
