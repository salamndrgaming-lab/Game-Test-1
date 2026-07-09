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
	State.STORM_RUN: "",  # Phase 3
	State.RESULTS: "",  # Phase 3
}

## All tunable gameplay values live in this one resource (design rule).
var balance: BalanceConfig = preload("res://config/balance.tres")

var state: State = State.MENU

func _ready() -> void:
	SteamManager.session_ended.connect(_on_session_ended)

func change_state(next: State) -> void:
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
