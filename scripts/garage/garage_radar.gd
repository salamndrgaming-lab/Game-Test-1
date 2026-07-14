extends CanvasLayer
## The county weather radar overlay (replaces the old contracts board).
## Shows tomorrow's randomly generated forecast — cells colored by peak
## F-rating, clustered stronger near the heavy area — and the three deploy
## points. Anyone can pick the deploy spot; the host applies it.

var is_open := false

var _radar: RadarView
var _deploy_buttons: Array = []

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
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not PauseMenu.is_open:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var deploys: Array = Game.forecast.get("deploys", [])
	var selected := int(Game.forecast.get("selected", 0))
	for i in _deploy_buttons.size():
		var btn: Button = _deploy_buttons[i]
		if i < deploys.size():
			var d: Dictionary = deploys[i]
			btn.text = "%sDEPLOY %d — %s" % ["> " if i == selected else "", i + 1, String(d.label)]
			btn.disabled = false
		else:
			btn.text = "—"
			btn.disabled = true

func _select(idx: int) -> void:
	var garage := get_parent()
	if multiplayer.is_server():
		garage.select_deploy(idx)
	else:
		garage._request_deploy.rpc_id(1, idx)

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
	vb.add_theme_constant_override("separation", 8)
	panel.add_child(vb)
	var title := Label.new()
	title.text = "COUNTY WEATHER RADAR — TOMORROW'S OUTLOOK"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)
	_radar = RadarView.new()
	vb.add_child(_radar)
	var hint := Label.new()
	hint.text = "Red blobs pay better. Pick where the van drops:"
	hint.add_theme_font_size_override("font_size", 12)
	vb.add_child(hint)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	vb.add_child(row)
	for i in 3:
		var btn := Button.new()
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(_select.bind(i))
		row.add_child(btn)
		_deploy_buttons.append(btn)
	var close_btn := Button.new()
	close_btn.text = "CLOSE"
	close_btn.pressed.connect(close)
	vb.add_child(close_btn)
