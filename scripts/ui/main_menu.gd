extends Control
## Main menu. Ugly is fine, functional is required (Phase 0 spec).

@onready var status_label: Label = %StatusLabel
@onready var steam_label: Label = %SteamLabel
@onready var lobby_id_edit: LineEdit = %LobbyIdEdit
@onready var ip_edit: LineEdit = %IpEdit

func _ready() -> void:
	%HostSteamButton.pressed.connect(_on_host_steam)
	%JoinSteamButton.pressed.connect(_on_join_steam)
	%HostLocalButton.pressed.connect(_on_host_local)
	%JoinLocalButton.pressed.connect(_on_join_local)
	%SettingsButton.pressed.connect(_on_settings)
	%QuitButton.pressed.connect(func() -> void: get_tree().quit())
	SteamManager.steam_status_changed.connect(_on_steam_status_changed)
	SteamManager.session_started.connect(_on_session_started)
	SteamManager.session_failed.connect(_on_session_failed)
	_refresh_steam_label()

func _refresh_steam_label() -> void:
	if SteamManager.steam_ok:
		steam_label.text = "Steam: %s" % SteamManager.steam_username
	else:
		steam_label.text = "Steam offline — install GodotSteam & run Steam for lobbies.\nLocal Test below works without it."

func _on_steam_status_changed(_ok: bool, _message: String) -> void:
	_refresh_steam_label()

func _on_host_steam() -> void:
	status_label.text = "Creating Steam lobby..."
	SteamManager.host_steam()

func _on_join_steam() -> void:
	var raw := lobby_id_edit.text.strip_edges()
	if not raw.is_valid_int():
		status_label.text = "Enter a numeric Steam lobby ID (the host presses F1 in-lobby to copy theirs)."
		return
	status_label.text = "Joining lobby %s..." % raw
	SteamManager.join_steam(raw.to_int())

func _on_host_local() -> void:
	status_label.text = "Hosting local server on port %d..." % SteamManager.LOCAL_PORT
	SteamManager.host_local()

func _on_join_local() -> void:
	var address := ip_edit.text.strip_edges()
	if address.is_empty():
		address = "127.0.0.1"
	status_label.text = "Joining %s..." % address
	SteamManager.join_local(address)

func _on_settings() -> void:
	status_label.text = "Settings arrive in Phase 5."

func _on_session_started(_as_host: bool) -> void:
	Game.change_state(Game.State.LOBBY)

func _on_session_failed(reason: String) -> void:
	status_label.text = reason
