extends PlayerSpawnManager
## The garage: hub between runs. Walk around, spend crew money, pick a
## contract, put on a stupid hat, then hit the garage door to roll out.
## Doubles as the lobby — this is the only place players can join.

const CONTRACT_NAMES := {
	1: "F1 — DUST DEVIL DAYCARE",
	2: "F2 — BABY'S FIRST WALL CLOUD",
	3: "F3 — COUNTY FAIR CANCELLED",
	4: "F4 — THE FINGER OF GOD",
}

@onready var contract_label: Label3D = $Stations/Contracts/Info
@onready var money_label: Label3D = $MoneySign
@onready var shop_ui: CanvasLayer = $ShopUI

func _ready() -> void:
	super._ready()
	add_to_group("garage_manager")
	$Sun.rotation_degrees = Vector3(-50.0, 20.0, 0.0)

func _process(_delta: float) -> void:
	var mult: float = Game.balance.contract_multipliers[clampi(Game.contract_tier - 1, 0, 3)]
	contract_label.text = "%s\npayout x%.1f — E to change" % [CONTRACT_NAMES[Game.contract_tier], mult]
	money_label.text = "CREW MONEY: $%d" % Game.crew_money

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED \
			and not PauseMenu.is_open and not shop_ui.is_open:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _spawn_pos(idx: int) -> Vector3:
	return Vector3(-11.0 + 2.2 * idx, 0.2, 6.5)

# --- Stations (host-side) -------------------------------------------------------

func station_used(id: String, player: Node) -> void:
	match id:
		"contracts":
			Game.contract_tier = Game.contract_tier % 4 + 1
			Game.broadcast_progress()
		"paint":
			Game.van_paint = (Game.van_paint + 1) % 5
			Game.broadcast_progress()
		"hats":
			player.hat_id = (player.hat_id + 1) % 4
		"shop":
			if player.peer_id() == 1:
				_open_shop()
			else:
				_open_shop.rpc_id(player.peer_id())
		"door":
			# Host starts the run; the label says so.
			if player.peer_id() == 1:
				Game.net_change_state.rpc(Game.State.STORM_RUN)

@rpc("authority", "call_remote", "reliable")
func _open_shop() -> void:
	shop_ui.open()

# --- Purchases (crew wallet, host validates) ---------------------------------------

@rpc("any_peer", "call_remote", "reliable")
func _request_buy(id: String) -> void:
	if multiplayer.is_server():
		buy(id)

func buy(id: String) -> void:  # host
	var price := int(Game.balance.upgrade_prices.get(id, -1))
	if price < 0 or Game.has_upgrade(id) or Game.crew_money < price:
		return
	Game.crew_money -= price
	Game.upgrades[id] = true
	Game.broadcast_progress()
