extends CanvasLayer
## Upgrades shop overlay. Built in code; opened via the shop bench station.
## Buy requests go to the host (crew wallet); rows refresh from synced state.

const ITEMS := [
	["van_engine", "Bigger Engine", "+35% torque. The van goes."],
	["van_rollcage", "Roll Cage", "Crashes deal half damage to the van."],
	["van_tires", "Storm Tires", "The tornado shoves the van half as hard."],
	["van_winch", "Winch", "E-grab the van or a downed friend to tow them."],
	["cam_lens", "Wide Lens", "+20 degrees of filming cone."],
	["cam_stabilizer", "Stabilizer", "No score penalty for filming on the move."],
	["cam_battery", "Big Battery", "Camcorder battery lasts twice as long."],
]

var is_open := false

var _money_label: Label
var _buttons := {}  # id -> Button

func _ready() -> void:
	layer = 50
	visible = false
	_build()

func open() -> void:
	is_open = true
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func close() -> void:
	is_open = false
	visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _process(_delta: float) -> void:
	if not is_open:
		return
	# Self-heal: closing the pause menu recaptures the mouse; if the shop is
	# still open underneath, free it again so the buttons stay clickable.
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not PauseMenu.is_open:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_money_label.text = "CREW MONEY: $%d" % Game.crew_money
	for item in ITEMS:
		var id: String = item[0]
		var btn: Button = _buttons[id]
		if Game.has_upgrade(id):
			btn.text = "OWNED"
			btn.disabled = true
		else:
			var price := int(Game.balance.upgrade_prices.get(id, 0))
			btn.text = "BUY  $%d" % price
			btn.disabled = Game.crew_money < price

func _buy_pressed(id: String) -> void:
	var garage := get_parent()
	if multiplayer.is_server():
		garage.buy(id)
	else:
		garage._request_buy.rpc_id(1, id)

func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var vb := VBoxContainer.new()
	vb.custom_minimum_size = Vector2(620, 0)
	vb.add_theme_constant_override("separation", 8)
	panel.add_child(vb)
	var title := Label.new()
	title.text = "UPGRADES"
	title.add_theme_font_size_override("font_size", 30)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)
	_money_label = Label.new()
	_money_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_money_label)
	vb.add_child(HSeparator.new())
	for item in ITEMS:
		var id: String = item[0]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		vb.add_child(row)
		var text := Label.new()
		text.text = "%s — %s" % [item[1], item[2]]
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(text)
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(120, 0)
		btn.pressed.connect(_buy_pressed.bind(id))
		row.add_child(btn)
		_buttons[id] = btn
	vb.add_child(HSeparator.new())
	var close_btn := Button.new()
	close_btn.text = "CLOSE"
	close_btn.pressed.connect(close)
	vb.add_child(close_btn)
