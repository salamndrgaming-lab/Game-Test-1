extends Node3D
## Phase 0/1/2 debug playground: players on a flat plane with props and the
## van, synced through the active multiplayer peer (Steam or local ENet).
##
## Spawning is explicit RPC with a ready-handshake instead of a
## MultiplayerSpawner: the spawner pushes existing nodes to a peer the moment
## it CONNECTS, but our clients connect while still in the menu (the scene
## loads after), so those packets would arrive before the client scene exists
## and get dropped. Here the client announces readiness from _ready() and the
## server sends the roster + broadcasts the newcomer.

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")

@onready var players: Node3D = $Players
@onready var status_label: Label = $UI/StatusLabel

func _ready() -> void:
	# Rotations set in code so the .tscn stays free of handwritten basis math.
	$Sun.rotation_degrees = Vector3(-55.0, -30.0, 0.0)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	if multiplayer.is_server():
		_spawn_local(1, _spawn_pos(0))
	else:
		_notify_ready.rpc_id(1)

func _process(_delta: float) -> void:
	status_label.text = _status_text()

func _status_text() -> String:
	var lines: PackedStringArray = []
	if SteamManager.is_local_fallback:
		lines.append("LOCAL TEST (ENet) — %s" % ("hosting port %d" % SteamManager.LOCAL_PORT if multiplayer.is_server() else "client"))
	elif SteamManager.lobby_id != 0:
		lines.append("STEAM LOBBY %d — %s" % [SteamManager.lobby_id, "host" if multiplayer.is_server() else "client"])
		lines.append("[F1] copy lobby ID    [F2] invite friends (overlay)")
	else:
		lines.append("OFFLINE (scene opened directly, no session)")
	lines.append("Players connected: %d" % (multiplayer.get_peers().size() + 1))
	lines.append("WASD move  SHIFT sprint  SPACE jump  E grab/enter van  hold C film")
	lines.append("X flop  hold Q emotes  ESC free mouse / leave")
	lines.append("Van: WASD drive  SHIFT brake  H horn  R radio  G glovebox  E exit")
	return "\n".join(lines)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		# First ESC frees the mouse, second ESC leaves the session
		# (Game returns everyone to the menu via SteamManager.session_ended).
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			SteamManager.leave_session()
		return
	if event is InputEventMouseButton and event.pressed \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_F1:
				DisplayServer.clipboard_set(str(SteamManager.lobby_id))
			KEY_F2:
				SteamManager.invite_overlay()

# --- Spawning -------------------------------------------------------------------

## Client -> server: my scene is loaded; send me the roster and spawn me.
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
	return Vector3(2.0 * idx - 3.0, 0.2, 0.0)

func _on_peer_disconnected(id: int) -> void:
	if multiplayer.is_server():
		_despawn_remote.rpc(id)

@rpc("authority", "call_local", "reliable")
func _despawn_remote(pid: int) -> void:
	if players.has_node(str(pid)):
		players.get_node(str(pid)).queue_free()
