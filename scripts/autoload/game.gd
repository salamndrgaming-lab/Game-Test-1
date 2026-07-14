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

# Tomorrow's weather (host-generated each garage visit, synced):
# { "heavy": {x,z}, "cells": [{x,z,peak,t_start,duration}],
#   "deploys": [{x,z,danger,label}], "selected": int }
var forecast := {}

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
		sync_progress.rpc_id(id, crew_money, upgrades, van_paint)
		if not forecast.is_empty():
			sync_forecast.rpc_id(id, forecast)

# --- Networked state / progression --------------------------------------------

## Host-broadcast scene transitions (run start, results, back to garage).
@rpc("authority", "call_local", "reliable")
func net_change_state(next: int) -> void:
	change_state(next)

@rpc("authority", "call_local", "reliable")
func sync_progress(money: int, upg: Dictionary, paint: int) -> void:
	crew_money = money
	upgrades = upg
	van_paint = paint

## Host: push progression to everyone and persist it.
func broadcast_progress() -> void:
	sync_progress.rpc(crew_money, upgrades, van_paint)
	save_progress()

# --- Weather forecast ------------------------------------------------------------

## Deploy candidates around the map edge/midfield (HQ corner excluded).
const DEPLOY_CANDIDATES := [
	Vector2(-380, -380), Vector2(0, -400), Vector2(380, -380), Vector2(-400, 0),
	Vector2(-380, 300), Vector2(0, 300), Vector2(300, 100), Vector2(120, -150),
]

## Host: roll tomorrow's weather. Cells cluster stronger near a random
## "heavy area"; three deploy points spanning mild -> deathwish severity.
func generate_forecast() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var heavy := Vector2(rng.randf_range(-350, 350), rng.randf_range(-400, 200))
	var chase: float = balance.run_chase_seconds
	var cells: Array = []
	for i in rng.randi_range(3, 5):
		var pos := Vector2(rng.randf_range(-420, 380), rng.randf_range(-420, 300))
		var peak := clampf(4.3 - pos.distance_to(heavy) / 220.0 + rng.randf_range(-0.3, 0.3), 1.0, 4.0)
		var t_start := 0.0 if i == 0 else rng.randf_range(0.15, 0.55) * chase
		var duration := clampf(rng.randf_range(0.35, 0.6) * chase, 60.0, chase - t_start)
		cells.append({"x": pos.x, "z": pos.y, "peak": peak, "t_start": t_start, "duration": duration})
	var scored: Array = []
	for cand in DEPLOY_CANDIDATES:
		var danger := 0.0
		for c in cells:
			var d: float = cand.distance_to(Vector2(c.x, c.z))
			danger = maxf(danger, float(c.peak) * clampf(1.0 - d / 500.0, 0.15, 1.0))
		scored.append({"x": cand.x, "z": cand.y, "danger": danger})
	scored.sort_custom(func(a, b): return a.danger < b.danger)
	var picks: Array = [scored[0], scored[int(scored.size() / 2.0)], scored[scored.size() - 1]]
	for p in picks:
		var danger := float(p.danger)
		p["label"] = "MILD" if danger < 1.3 else ("SPICY" if danger < 2.6 else "DEATHWISH")
	forecast = {
		"heavy": {"x": heavy.x, "z": heavy.y},
		"cells": cells, "deploys": picks, "selected": 1,
	}
	sync_forecast.rpc(forecast)

@rpc("authority", "call_local", "reliable")
func sync_forecast(f: Dictionary) -> void:
	forecast = f

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
