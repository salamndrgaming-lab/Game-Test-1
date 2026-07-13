extends PlayerSpawnManager
## Run manager: storm spawns at the map edge -> chase -> storm dissipates ->
## drive to extraction -> footage uploads -> RESULTS. Host drives the state
## machine; run_state/time_left sync to clients. Contract tier (garage board)
## caps the storm's F-rating and multiplies the payout.

enum RunState { CHASE, DISSIPATE, EXTRACT, DONE }

const PICKUP_SCENE := preload("res://scenes/props/camera_pickup.tscn")
const HAT_SCENE := preload("res://scenes/props/hat_prop.tscn")
const EXTRACT_RADIUS := 15.0

var run_state: int = RunState.CHASE  # synced
var time_left := 0.0  # synced

var _pickup_seq := 0
var _van_flew := false
var _deaths := 0

@onready var tornado: Node3D = $Tornado
@onready var extraction: Node3D = $Extraction
@onready var sun: DirectionalLight3D = $Sun
@onready var run_label: Label = $UI/RunLabel

func _ready() -> void:
	super._ready()
	add_to_group("run_manager")
	$Sun.rotation_degrees = Vector3(-55.0, -30.0, 0.0)
	if multiplayer.is_server():
		time_left = Game.balance.run_chase_seconds

func _spawn_pos(idx: int) -> Vector3:
	return Vector3(438.0 + 2.5 * idx, 0.2, 442.0)

func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	_update_run(delta)
	if not _van_flew:
		for v in get_tree().get_nodes_in_group("vans"):
			if v.global_position.y > 6.0:
				_van_flew = true

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not PauseMenu.is_open:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

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

## Called by player_health on the host when someone eats dirt.
func note_death() -> void:
	_deaths += 1

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
			"air": snappedf(p.air_time, 0.1),
		})
	var title := "The Time We Almost Made Money"
	if total < 50.0:
		title = "The Time Nobody Filmed Anything"
	if _deaths == 1:
		title = "The Time Somebody Ate Dirt"
	elif _deaths > 1:
		title = "The Time Everybody Kept Dying"
	if _van_flew:
		title = "The Time The Van Learned To Fly"
	var mult: float = Game.balance.contract_multipliers[clampi(Game.contract_tier - 1, 0, 3)]
	var views := int(total * Game.balance.views_per_point)
	var money := int(views / 100.0 * Game.balance.payout_per_100_views * mult)
	Game.set_run_results.rpc(results, views, money, title)
	Game.net_change_state.rpc(Game.State.RESULTS)

# --- Runtime prop spawns (camera pickups, blown-off hats) ----------------------

func spawn_pickup(pos: Vector3, amount: float) -> void:  # host
	_pickup_seq += 1
	_spawn_pickup.rpc("pickup_%d" % _pickup_seq, pos, amount)

func spawn_hat(pos: Vector3, id: int, vel: Vector3) -> void:  # host
	_pickup_seq += 1
	var hat_name := "hat_%d" % _pickup_seq
	_spawn_hat.rpc(hat_name, pos, id)
	# call_local ran synchronously above, so the host copy exists now.
	var hat: RigidBody3D = $Pickups.get_node(hat_name)
	hat.linear_velocity = vel

func despawn_pickup(node: Node) -> void:  # host; also used for hats
	_despawn_pickup.rpc(String(node.name))

@rpc("authority", "call_local", "reliable")
func _spawn_pickup(pickup_name: String, pos: Vector3, amount: float) -> void:
	var pk := PICKUP_SCENE.instantiate()
	pk.name = pickup_name
	pk.amount = amount
	pk.position = pos
	$Pickups.add_child(pk)

@rpc("authority", "call_local", "reliable")
func _spawn_hat(hat_name: String, pos: Vector3, id: int) -> void:
	var hat := HAT_SCENE.instantiate()
	hat.name = hat_name
	hat.hat_id = id
	hat.position = pos
	$Pickups.add_child(hat)

@rpc("authority", "call_local", "reliable")
func _despawn_pickup(pickup_name: String) -> void:
	if $Pickups.has_node(pickup_name):
		$Pickups.get_node(pickup_name).queue_free()
