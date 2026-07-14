extends PlayerSpawnManager
## The garage: hub between runs. Walk around, spend crew money, review the
## weather radar and pick a deploy spot, put on a stupid hat, then hit the
## garage door to roll out. Doubles as the lobby — the only place to join.

@onready var radar_label: Label3D = $Stations/Radar/Info
@onready var money_label: Label3D = $MoneySign
@onready var shop_ui: CanvasLayer = $ShopUI
@onready var radar_ui: CanvasLayer = $RadarUI

func _ready() -> void:
	super._ready()
	add_to_group("garage_manager")
	$Sun.rotation_degrees = Vector3(-50.0, 20.0, 0.0)
	if multiplayer.is_server():
		Game.generate_forecast()  # fresh weather every garage visit

func _process(_delta: float) -> void:
	radar_label.text = _forecast_summary()
	money_label.text = "CREW MONEY: $%d" % Game.crew_money

func _forecast_summary() -> String:
	var f: Dictionary = Game.forecast
	if f.is_empty():
		return "radar warming up..."
	var worst := 0.0
	for c in f.get("cells", []):
		worst = maxf(worst, float(c.peak))
	var deploys: Array = f.get("deploys", [])
	var sel := clampi(int(f.get("selected", 0)), 0, maxi(deploys.size() - 1, 0))
	var label: String = String(deploys[sel].label) if not deploys.is_empty() else "?"
	return "%d cells inbound, worst F%d\nDeploy: %s — E to review" \
			% [f.get("cells", []).size(), int(round(worst)), label]

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED \
			and not PauseMenu.is_open and not shop_ui.is_open and not radar_ui.is_open:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _spawn_pos(idx: int) -> Vector3:
	return Vector3(-11.0 + 2.2 * idx, 0.2, 6.5)

# --- Stations (host-side) -------------------------------------------------------

func station_used(id: String, player: Node) -> void:
	match id:
		"radar":
			if player.peer_id() == 1:
				_open_radar()
			else:
				_open_radar.rpc_id(player.peer_id())
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

@rpc("authority", "call_remote", "reliable")
func _open_radar() -> void:
	radar_ui.open()

@rpc("any_peer", "call_remote", "reliable")
func _request_deploy(idx: int) -> void:
	if multiplayer.is_server():
		select_deploy(idx)

func select_deploy(idx: int) -> void:  # host
	var deploys: Array = Game.forecast.get("deploys", [])
	if deploys.is_empty():
		return
	Game.forecast["selected"] = clampi(idx, 0, deploys.size() - 1)
	Game.sync_forecast.rpc(Game.forecast)

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
