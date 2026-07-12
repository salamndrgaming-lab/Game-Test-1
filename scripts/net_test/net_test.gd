extends Node3D
## Phase 0/1 debug playground: players on a flat plane with grabbable props,
## synced through the active multiplayer peer (Steam or local ENet). The
## server spawns/despawns players; the MultiplayerSpawner replicates them.

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")

@onready var players: Node3D = $Players
@onready var status_label: Label = $UI/StatusLabel

func _ready() -> void:
	# Rotations set in code so the .tscn stays free of handwritten basis math.
	$Sun.rotation_degrees = Vector3(-55.0, -30.0, 0.0)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	if multiplayer.is_server():
		_spawn(1)
		for id in multiplayer.get_peers():
			_spawn(id)

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

func _on_peer_connected(id: int) -> void:
	if multiplayer.is_server():
		_spawn(id)

func _on_peer_disconnected(id: int) -> void:
	if multiplayer.is_server() and players.has_node(str(id)):
		players.get_node(str(id)).queue_free()

func _spawn(id: int) -> void:
	if players.has_node(str(id)):
		return
	var player := PLAYER_SCENE.instantiate()
	player.name = str(id)
	player.position = Vector3(2.0 * players.get_child_count() - 3.0, 0.2, 0.0)
	players.add_child(player)
