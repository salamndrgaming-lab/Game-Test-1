extends Node
## Autoload: SteamManager
##
## Owns Steam init, lobby lifecycle, and the active MultiplayerPeer.
## All Steam access goes through Engine.get_singleton("Steam") so the project
## still loads and runs (in Local Test mode) when the GodotSteam GDExtension
## isn't installed yet. See addons/godotsteam/INSTALL.md.
##
## Networking rule (design doc): host simulates everything, clients send
## inputs. This node only manages the transport; authority lives in gameplay
## scripts.

signal steam_status_changed(ok: bool, message: String)
signal session_started(as_host: bool)
signal session_failed(reason: String)
signal session_ended

const APP_ID := 480  # Spacewar, Valve's public test appid. Swap for the real appid in Phase 6.
const LOBBY_MAX_MEMBERS := 4
const LOBBY_TYPE_FRIENDS_ONLY := 1  # Steam ELobbyType
const VIRTUAL_PORT := 0  # SteamMultiplayerPeer virtual port
const LOCAL_PORT := 7777  # ENet dev-only local test port

var steam: Object = null
var steam_ok := false
var steam_username := ""
var lobby_id := 0
var is_host := false
var is_local_fallback := false

func _ready() -> void:
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	_init_steam()

func _process(_delta: float) -> void:
	if steam_ok:
		steam.run_callbacks()

# --- Steam init -------------------------------------------------------------

func _init_steam() -> void:
	if not Engine.has_singleton("Steam"):
		push_warning("SteamManager: GodotSteam extension not found; Steam features disabled. Local Test mode still works. See addons/godotsteam/INSTALL.md")
		steam_status_changed.emit(false, "GodotSteam not installed")
		return
	steam = Engine.get_singleton("Steam")
	var ok := false
	var message := ""
	if steam.has_method("steamInitEx"):
		# GodotSteam 4.x: returns { status: int, verbal: String }, status 0 == OK.
		var res: Dictionary = steam.steamInitEx(APP_ID, false)
		ok = int(res.get("status", 1)) == 0
		message = str(res.get("verbal", ""))
	elif steam.has_method("steamInit"):
		# Legacy GodotSteam: status 1 == OK.
		var res: Dictionary = steam.steamInit()
		ok = int(res.get("status", 0)) == 1
		message = str(res.get("verbal", ""))
	if not ok:
		push_warning("SteamManager: Steam init failed (%s). Is Steam running and logged in?" % message)
		steam_status_changed.emit(false, "Steam init failed: %s" % message)
		return
	steam_ok = true
	steam_username = str(steam.getPersonaName())
	steam.connect("lobby_created", _on_lobby_created)
	steam.connect("lobby_joined", _on_lobby_joined)
	steam.connect("join_requested", _on_join_requested)
	steam_status_changed.emit(true, "Steam OK: %s" % steam_username)

# --- Public API: Steam sessions ----------------------------------------------

func host_steam() -> void:
	if not steam_ok:
		session_failed.emit("Steam not available — use Local Test, or install GodotSteam and run Steam.")
		return
	is_host = true
	is_local_fallback = false
	steam.createLobby(LOBBY_TYPE_FRIENDS_ONLY, LOBBY_MAX_MEMBERS)

func join_steam(target_lobby_id: int) -> void:
	if not steam_ok:
		session_failed.emit("Steam not available — use Local Test, or install GodotSteam and run Steam.")
		return
	is_host = false
	is_local_fallback = false
	steam.joinLobby(target_lobby_id)

func invite_overlay() -> void:
	if steam_ok and lobby_id != 0:
		steam.activateGameOverlayInviteDialog(lobby_id)

# --- Public API: local ENet fallback (dev testing only, never ships) ---------

func host_local() -> void:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(LOCAL_PORT, LOBBY_MAX_MEMBERS - 1)
	if err != OK:
		session_failed.emit("Could not open local port %d (err %d). Already hosting in another window?" % [LOCAL_PORT, err])
		return
	is_host = true
	is_local_fallback = true
	multiplayer.multiplayer_peer = peer
	session_started.emit(true)

func join_local(address: String = "127.0.0.1") -> void:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, LOCAL_PORT)
	if err != OK:
		session_failed.emit("Could not start local client (err %d)." % err)
		return
	is_host = false
	is_local_fallback = true
	multiplayer.multiplayer_peer = peer
	# session_started fires from connected_to_server.

# --- Teardown ----------------------------------------------------------------

func leave_session() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	if steam_ok and lobby_id != 0:
		steam.leaveLobby(lobby_id)
	lobby_id = 0
	is_host = false
	is_local_fallback = false
	session_ended.emit()

# --- Steam callbacks ----------------------------------------------------------

func _on_lobby_created(connect_status: int, this_lobby_id: int) -> void:
	if connect_status != 1:  # k_EResultOK
		is_host = false
		session_failed.emit("Failed to create Steam lobby (EResult %d)." % connect_status)
		return
	lobby_id = this_lobby_id
	steam.setLobbyData(lobby_id, "name", "%s's storm crew" % steam_username)
	steam.setLobbyData(lobby_id, "game", "twister_chasers")
	_create_steam_peer(true)

func _on_lobby_joined(this_lobby_id: int, _permissions: int, _locked: bool, response: int) -> void:
	if is_host:
		return  # The host also receives lobby_joined for its own lobby.
	if response != 1:  # k_EChatRoomEnterResponseSuccess
		session_failed.emit("Could not join lobby (response %d)." % response)
		return
	lobby_id = this_lobby_id
	_create_steam_peer(false)

func _on_join_requested(this_lobby_id: int, _friend_id: int) -> void:
	# Player accepted an invite / clicked "join game" in the Steam overlay.
	join_steam(this_lobby_id)

# --- Peer setup ----------------------------------------------------------------

func _create_steam_peer(as_host: bool) -> void:
	if not ClassDB.class_exists("SteamMultiplayerPeer"):
		session_failed.emit("SteamMultiplayerPeer extension missing — see addons/godotsteam/INSTALL.md")
		return
	var peer: MultiplayerPeer = ClassDB.instantiate("SteamMultiplayerPeer")
	var err: int = ERR_UNAVAILABLE
	if as_host and peer.has_method("create_host"):
		err = peer.create_host(VIRTUAL_PORT)
	elif not as_host and peer.has_method("create_client"):
		err = peer.create_client(steam.getLobbyOwner(lobby_id), VIRTUAL_PORT)
	if err != OK:
		session_failed.emit("SteamMultiplayerPeer setup failed (err %d). Check the extension version — see INSTALL.md." % err)
		return
	multiplayer.multiplayer_peer = peer
	if as_host:
		session_started.emit(true)
	# Clients emit session_started from connected_to_server.

# --- SceneMultiplayer callbacks -------------------------------------------------

func _on_connected_to_server() -> void:
	session_started.emit(false)

func _on_connection_failed() -> void:
	multiplayer.multiplayer_peer = null
	session_failed.emit("Connection failed.")

func _on_server_disconnected() -> void:
	leave_session()
