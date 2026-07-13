class_name PlayerSpawnManager
extends Node3D
## Shared player spawning for every scene players inhabit (garage, storm run,
## net test). Explicit RPC spawning with a ready-handshake: MultiplayerSpawner
## pushes existing nodes to a peer the moment it CONNECTS, but our clients
## connect while still in the previous scene, so those packets would be
## dropped. Here the client announces readiness from _ready() and the server
## sends the roster + broadcasts the newcomer.
##
## Subclasses must have a "Players" Node3D child, override _spawn_pos(), and
## call super._ready() from their own _ready().

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")

@onready var players: Node3D = $Players

func _ready() -> void:
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	if multiplayer.is_server():
		_spawn_local(1, _spawn_pos(0))
	else:
		_notify_ready.rpc_id(1)

func _spawn_pos(_idx: int) -> Vector3:
	return Vector3(0, 0.2, 0)  # override per scene

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

func _on_peer_disconnected(id: int) -> void:
	if multiplayer.is_server():
		_despawn_remote.rpc(id)

@rpc("authority", "call_local", "reliable")
func _despawn_remote(pid: int) -> void:
	if players.has_node(str(pid)):
		players.get_node(str(pid)).queue_free()
