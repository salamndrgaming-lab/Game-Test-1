extends PlayerSpawnManager
## Run manager. The forecast (rolled in the garage) drives everything:
## storm cells spawn at their forecast positions and activate on their own
## timers, the crew deploys at the chosen deploy point with the van, and
## when the last cell blows out everyone drives HOME — footage uploads over
## the HQ garage wifi while you sit in the driveway. No beams.

enum RunState { CHASE, HEAD_HOME, DONE }

const TORNADO_SCENE := preload("res://scenes/tornado/tornado.tscn")
const PICKUP_SCENE := preload("res://scenes/props/camera_pickup.tscn")
const HAT_SCENE := preload("res://scenes/props/hat_prop.tscn")

var run_state: int = RunState.CHASE  # synced
var time_left := 0.0  # synced
var called_cell := -1  # synced; the navigator's current storm call
var called_by := 0  # host-side: who made the call (gets the spotter cut)

var _elapsed := 0.0
var _chase_end := 0.0
var _call_expires := 0.0
var _pickup_seq := 0
var _van_flew := false
var _deaths := 0

@onready var home: Node3D = $Home
@onready var sun: DirectionalLight3D = $Sun
@onready var run_label: Label = $UI/RunLabel

func _ready() -> void:
	add_to_group("run_manager")
	$Sun.rotation_degrees = Vector3(-55.0, -30.0, 0.0)
	if multiplayer.is_server() and Game.forecast.is_empty():
		Game.generate_forecast()  # dev fallback; the garage normally rolls it
	_spawn_cells()
	var dep := _deploy()
	$Van.position = Vector3(dep.x, 0.1, dep.y - 8.0)
	if multiplayer.is_server():
		for c in Game.forecast.get("cells", []):
			_chase_end = maxf(_chase_end, float(c.t_start) + float(c.duration))
		time_left = _chase_end
	super._ready()

func _spawn_cells() -> void:
	# Deterministic on every peer from the synced forecast — no spawn RPCs.
	var cells: Array = Game.forecast.get("cells", [])
	for i in cells.size():
		var c: Dictionary = cells[i]
		var tor := TORNADO_SCENE.instantiate()
		tor.name = "Cell%d" % i
		tor.cell_index = i
		tor.cell_center = Vector2(float(c.x), float(c.z))
		tor.peak = float(c.peak)
		tor.t_start = float(c.t_start)
		tor.duration = float(c.duration)
		tor.position = Vector3(float(c.x), 0.0, float(c.z))
		$Cells.add_child(tor)

func _deploy() -> Vector2:
	var deploys: Array = Game.forecast.get("deploys", [])
	if deploys.is_empty():
		return Vector2(438.0, 442.0)
	var d: Dictionary = deploys[clampi(int(Game.forecast.get("selected", 0)), 0, deploys.size() - 1)]
	return Vector2(float(d.x), float(d.z))

func _spawn_pos(idx: int) -> Vector3:
	var dep := _deploy()
	return Vector3(dep.x + 2.5 * idx, 0.2, dep.y + 3.0)

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
	var strongest := 0.0
	var live := 0
	for tor in get_tree().get_nodes_in_group("tornado"):
		if tor.active:
			live += 1
			strongest = maxf(strongest, tor.intensity)
	# Sky darkens with the strongest live cell.
	sun.light_energy = lerpf(1.2, 0.3, strongest / 4.0)
	run_label.text = _run_text(live, strongest)

func _run_text(live: int, strongest: float) -> String:
	match run_state:
		RunState.CHASE:
			var line := "%d:%02d" % [int(time_left / 60.0), int(time_left) % 60]
			if live == 0:
				return "STORM WATCH — quiet for now, check the radar (%s)" % line
			return "STORM WATCH: %d cell(s) live — strongest F%d — %s — hold C to film" \
					% [live, clampi(int(strongest), 1, 4), line]
		RunState.HEAD_HOME:
			return "Storms are done — head home, footage uploads in the HQ driveway (%ds)" % int(time_left)
		_:
			return "Upload complete."

# --- Host run state ---------------------------------------------------------

func _update_run(delta: float) -> void:
	_elapsed += delta
	if called_cell != -1 and _elapsed > _call_expires:
		called_cell = -1
	match run_state:
		RunState.CHASE:
			time_left = maxf(_chase_end - _elapsed, 0.0)
			if time_left <= 0.0:
				run_state = RunState.HEAD_HOME
				time_left = Game.balance.run_extract_seconds
		RunState.HEAD_HOME:
			time_left = maxf(time_left - delta, 0.0)
			_upload_players(delta)
			if time_left <= 0.0 or _everyone_uploaded():
				_finish_run()
		RunState.DONE:
			pass

## Footage transfers over the garage wifi while you're in the driveway.
func _upload_players(delta: float) -> void:
	for p in get_tree().get_nodes_in_group("players"):
		if p.dead or p.footage <= 0.0:
			continue
		if p.global_position.distance_to(home.global_position) < Game.balance.home_radius:
			var amount: float = minf(Game.balance.upload_rate * delta, p.footage)
			p.footage -= amount
			p.banked += amount

func _everyone_uploaded() -> bool:
	for p in get_tree().get_nodes_in_group("players"):
		if p.dead:
			continue
		if p.footage > 0.0 \
				or p.global_position.distance_to(home.global_position) > Game.balance.home_radius:
			return false
	return true

## Called by player_health on the host when someone eats dirt.
func note_death() -> void:
	_deaths += 1

# --- The navigator's storm call (passenger seat role) --------------------------

@rpc("any_peer", "call_remote", "reliable")
func _request_mark() -> void:
	if multiplayer.is_server():
		mark_from(multiplayer.get_remote_sender_id())

func mark_from(pid: int) -> void:  # host
	var is_navigator := false
	for v in get_tree().get_nodes_in_group("vans"):
		if int(v.seats.get("passenger", -1)) == pid:
			is_navigator = true
	if not is_navigator:
		return
	var best: Node = null
	for tor in get_tree().get_nodes_in_group("tornado"):
		if tor.active and (best == null or tor.intensity > best.intensity):
			best = tor
	if best == null:
		return
	called_cell = best.cell_index
	called_by = pid
	_call_expires = _elapsed + Game.balance.mark_duration

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
	var views := int(total * Game.balance.views_per_point)
	var money := int(views / 100.0 * Game.balance.payout_per_100_views)
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
