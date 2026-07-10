extends CanvasLayer
## Local-player HUD: camcorder viewfinder (REC dot, battery, stubbed Footage
## Score meter — real scoring lands in Phase 3) and the hold-Q emote wheel.
## Built in code to keep the .tscn small. Remote players' copies disable
## themselves.

var battery := 1.0
var footage_score := 0.0
var wheel_open := false
var _wheel_used := false

var viewfinder: Control
var rec_dot: ColorRect
var battery_bar: ProgressBar
var score_label: Label
var wheel: PanelContainer
var click: AudioStreamPlayer

@onready var player: CharacterBody3D = get_parent()

func _ready() -> void:
	if not player.is_local():
		visible = false
		set_process(false)
		set_process_input(false)
		return
	click = AudioStreamPlayer.new()
	click.stream = preload("res://assets/audio/click.wav")
	add_child(click)
	_build_viewfinder()
	_build_wheel()

func _process(delta: float) -> void:
	_update_film(delta)
	_update_wheel()

# --- Camcorder ----------------------------------------------------------------

func _update_film(delta: float) -> void:
	var want := Input.is_action_pressed("film") and battery > 0.0 \
			and player.state == player.PState.NORMAL and not wheel_open
	if want != player.filming:
		player.set_filming(want)
	if player.filming:
		battery = maxf(battery - delta / Game.balance.camera_battery_seconds, 0.0)
		# Stub: flat tick rate. Phase 3 replaces this with frustum scoring.
		footage_score += Game.balance.footage_base_points_per_second * delta
	viewfinder.visible = player.filming
	if player.filming:
		rec_dot.visible = fmod(Time.get_ticks_msec() / 1000.0, 1.0) < 0.65
		battery_bar.value = battery * 100.0
		score_label.text = "FOOTAGE %05d" % int(footage_score)

func _build_viewfinder() -> void:
	viewfinder = Control.new()
	viewfinder.set_anchors_preset(Control.PRESET_FULL_RECT)
	viewfinder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	viewfinder.visible = false
	add_child(viewfinder)
	var frame := Panel.new()
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.border_color = Color(1, 1, 1, 0.8)
	sb.set_border_width_all(3)
	frame.add_theme_stylebox_override("panel", sb)
	viewfinder.add_child(frame)
	rec_dot = ColorRect.new()
	rec_dot.color = Color(1, 0.15, 0.1)
	rec_dot.position = Vector2(26, 26)
	rec_dot.size = Vector2(16, 16)
	viewfinder.add_child(rec_dot)
	var rec_label := Label.new()
	rec_label.text = "REC"
	rec_label.position = Vector2(50, 22)
	viewfinder.add_child(rec_label)
	score_label = Label.new()
	score_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	score_label.position = Vector2(-220, 22)
	score_label.size = Vector2(196, 24)
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	viewfinder.add_child(score_label)
	battery_bar = ProgressBar.new()
	battery_bar.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	battery_bar.position = Vector2(26, -46)
	battery_bar.size = Vector2(220, 20)
	battery_bar.show_percentage = false
	viewfinder.add_child(battery_bar)
	var batt_label := Label.new()
	batt_label.text = "BATT"
	batt_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	batt_label.position = Vector2(26, -70)
	viewfinder.add_child(batt_label)

# --- Emote wheel -----------------------------------------------------------------

func _update_wheel() -> void:
	var held := Input.is_action_pressed("emote_wheel")
	if held and not wheel_open and not _wheel_used:
		_set_wheel(true)
	elif not held:
		_wheel_used = false
		if wheel_open:
			_set_wheel(false)

func _set_wheel(open: bool) -> void:
	wheel_open = open
	wheel.visible = open
	click.play()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if open else Input.MOUSE_MODE_CAPTURED

func _input(event: InputEvent) -> void:
	if wheel_open and event is InputEventKey and event.pressed and not event.echo:
		var idx: int = event.keycode - KEY_1
		if idx >= 0 and idx <= 3:
			_pick_emote(idx)

func _pick_emote(id: int) -> void:
	player.send_emote(id)
	_wheel_used = true
	_set_wheel(false)

func _build_wheel() -> void:
	wheel = PanelContainer.new()
	wheel.visible = false
	add_child(wheel)
	wheel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	var vb := VBoxContainer.new()
	wheel.add_child(vb)
	var title := Label.new()
	title.text = "EMOTE — click or press 1-4"
	vb.add_child(title)
	var names := ["1   POINT", "2   THUMBS UP", "3   PANIC SCREAM", "4   FAINT"]
	for i in 4:
		var b := Button.new()
		b.text = names[i]
		b.pressed.connect(_pick_emote.bind(i))
		vb.add_child(b)
