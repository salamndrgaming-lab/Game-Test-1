extends PlayerSpawnManager
## Dev sandbox (was the Phase 0-2 lobby; the garage is the real hub now).
## Flat plane, props, the van — reachable via Game.State.LOBBY for debugging.

@onready var status_label: Label = $UI/StatusLabel

func _ready() -> void:
	super._ready()
	# Rotations set in code so the .tscn stays free of handwritten basis math.
	$Sun.rotation_degrees = Vector3(-55.0, -30.0, 0.0)

func _spawn_pos(idx: int) -> Vector3:
	return Vector3(2.0 * idx - 3.0, 0.2, 0.0)

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
	lines.append("WASD move  SHIFT sprint  SPACE jump  E interact  hold C film")
	lines.append("X flop  hold Q emotes  ESC pause menu")
	if multiplayer.is_server():
		lines.append("ENTER: start a storm run")
	return "\n".join(lines)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not PauseMenu.is_open:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_F1:
				DisplayServer.clipboard_set(str(SteamManager.lobby_id))
			KEY_F2:
				SteamManager.invite_overlay()
			KEY_ENTER:
				if multiplayer.is_server():
					Game.net_change_state.rpc(Game.State.STORM_RUN)
