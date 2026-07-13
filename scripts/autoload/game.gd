extends Node
## Autoload: Game — global state machine, crew progression, local settings.
## MENU -> GARAGE (hub/lobby) -> STORM_RUN -> RESULTS -> GARAGE ...
## Progression is crew-wide and host-authoritative (design rule: one wallet,
## no griefing economics); the host's save file owns it, clients get synced.

enum State { MENU, LOBBY, GARAGE, STORM_RUN, RESULTS }

const STATE_SCENES := {
	State.MENU: "res://scenes/ui/main_menu.tscn",
	State.LOBBY: "res://scenes/net_test/net_test.tscn",  # dev sandbox
	State.GARAGE: "res://scenes/garage/garage.tscn",
	State.STORM_RUN: "res://scenes/storm_run/storm_run.tscn",
	State.RESULTS: "res://scenes/ui/results.tscn",
}
const SAVE_PATH := "user://twister_save.json"
const SETTINGS_PATH := "user://settings.json"

## All tunable gameplay values live in this one resource (design rule).
var balance: BalanceConfig = preload("res://config/balance.tres")

var state: int = State.MENU

# Crew progression (synced from host, saved by host).
var crew_money := 0
var upgrades := {}  # id -> true
var van_paint := 0
var contract_tier := 1

# Local-only settings.
var settings := {"volume": 1.0, "sensitivity": 1.0, "push_to_talk": false}

# Last run data for the results screen.
var last_run_results: Array = []
var last_run_views := 0
var last_run_money := 0
var last_run_title := ""

func _ready() -> void:
	load_progress()
	load_settings()
	SteamManager.session_ended.connect(_on_session_ended)
	multiplayer.peer_connected.connect(_on_peer_connected)

func has_upgrade(id: String) -> bool:
	return upgrades.get(id, false)

func change_state(next: int) -> void:
	if next == state:
		return
	var path: String = STATE_SCENES[next]
	if path.is_empty():
		push_warning("Game: no scene wired for state %s yet." % State.keys()[next])
		return
	state = next
	if multiplayer.is_server():
		# Late joins are lobby/garage-only (design rule).
		SteamManager.set_session_joinable(next == State.LOBBY or next == State.GARAGE)
	# Deferred so we never swap scenes mid-signal.
	get_tree().change_scene_to_file.call_deferred(path)

func _on_session_ended() -> void:
	if state != State.MENU:
		change_state(State.MENU)

func _on_peer_connected(id: int) -> void:
	if multiplayer.is_server():
		sync_progress.rpc_id(id, crew_money, upgrades, van_paint, contract_tier)

# --- Networked state / progression --------------------------------------------

## Host-broadcast scene transitions (run start, results, back to garage).
@rpc("authority", "call_local", "reliable")
func net_change_state(next: int) -> void:
	change_state(next)

@rpc("authority", "call_local", "reliable")
func sync_progress(money: int, upg: Dictionary, paint: int, tier: int) -> void:
	crew_money = money
	upgrades = upg
	van_paint = paint
	contract_tier = tier

## Host: push progression to everyone and persist it.
func broadcast_progress() -> void:
	sync_progress.rpc(crew_money, upgrades, van_paint, contract_tier)
	save_progress()

@rpc("authority", "call_local", "reliable")
func set_run_results(results: Array, views: int, money: int, title: String) -> void:
	last_run_results = results
	last_run_views = views
	last_run_money = money
	last_run_title = title
	crew_money += money
	if multiplayer.is_server():
		save_progress()

# --- Persistence ----------------------------------------------------------------

func save_progress() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({
			"money": crew_money, "upgrades": upgrades, "paint": van_paint,
		}))

func load_progress() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if data is Dictionary:
		crew_money = int(data.get("money", 0))
		var upg: Variant = data.get("upgrades", {})
		if upg is Dictionary:
			upgrades = upg
		van_paint = int(data.get("paint", 0))

# --- Local settings ----------------------------------------------------------------

func set_volume(v: float) -> void:
	settings["volume"] = clampf(v, 0.0, 1.0)
	_apply_volume()
	save_settings()

func set_sensitivity(v: float) -> void:
	settings["sensitivity"] = clampf(v, 0.2, 3.0)
	save_settings()

func _apply_volume() -> void:
	var v := float(settings.get("volume", 1.0))
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(v, 0.0001)))

func save_settings() -> void:
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(settings))

func load_settings() -> void:
	if FileAccess.file_exists(SETTINGS_PATH):
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(SETTINGS_PATH))
		if data is Dictionary:
			for key in settings.keys():
				if data.has(key):
					settings[key] = data[key]
	_apply_volume()
