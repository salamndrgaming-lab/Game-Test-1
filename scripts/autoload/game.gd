extends Node
## Autoload: Game — global state machine.
## MENU -> LOBBY -> GARAGE -> STORM_RUN -> RESULTS
## Phase 0 only wires MENU and LOBBY (the NetTest debug scene stands in for
## the lobby until the garage exists in Phase 5).

enum State { MENU, LOBBY, GARAGE, STORM_RUN, RESULTS }

const STATE_SCENES := {
	State.MENU: "res://scenes/ui/main_menu.tscn",
	State.LOBBY: "res://scenes/net_test/net_test.tscn",
	State.GARAGE: "",  # Phase 5
	State.STORM_RUN: "res://scenes/storm_run/storm_run.tscn",
	State.RESULTS: "res://scenes/ui/results.tscn",
}

## All tunable gameplay values live in this one resource (design rule).
var balance: BalanceConfig = preload("res://config/balance.tres")

var state: State = State.MENU

# Run-to-run session data (real persistence is Phase 5).
var crew_money := 0
var last_run_results: Array = []
var last_run_views := 0
var last_run_money := 0

func _ready() -> void:
	SteamManager.session_ended.connect(_on_session_ended)

func change_state(next: int) -> void:
	if next == state:
		return
	var path: String = STATE_SCENES[next]
	if path.is_empty():
		push_warning("Game: no scene wired for state %s yet." % State.keys()[next])
		return
	state = next
	# Deferred so we never swap scenes mid-signal.
	get_tree().change_scene_to_file.call_deferred(path)

func _on_session_ended() -> void:
	if state != State.MENU:
		change_state(State.MENU)

## Host-broadcast scene transitions (run start, results, back to lobby).
## Autoloads share a NodePath on every peer, so RPCs here reach everyone.
@rpc("authority", "call_local", "reliable")
func net_change_state(next: int) -> void:
	change_state(next)

@rpc("authority", "call_local", "reliable")
func set_run_results(results: Array, views: int, money: int) -> void:
	last_run_results = results
	last_run_views = views
	last_run_money = money
	crew_money += money
