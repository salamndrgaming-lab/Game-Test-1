extends CanvasLayer
## Autoload: PauseMenu — ESC overlay in any session scene. Multiplayer, so
## the game keeps running behind it. Owns leave/quit, the invite-friend flow,
## and local settings (volume, sensitivity, push-to-talk placeholder).

var is_open := false

func _ready() -> void:
	layer = 90
	visible = false
	%ResumeButton.pressed.connect(close)
	%InviteButton.pressed.connect(SteamManager.invite_overlay)
	%SettingsButton.pressed.connect(func() -> void: _show_settings(true))
	%BackButton.pressed.connect(func() -> void: _show_settings(false))
	%LeaveButton.pressed.connect(_on_leave)
	%QuitButton.pressed.connect(func() -> void: get_tree().quit())
	%VolumeSlider.value = float(Game.settings.get("volume", 1.0))
	%VolumeSlider.value_changed.connect(func(v: float) -> void: Game.set_volume(v))
	%SensSlider.value = float(Game.settings.get("sensitivity", 1.0))
	%SensSlider.value_changed.connect(func(v: float) -> void: Game.set_sensitivity(v))
	%PttCheck.button_pressed = bool(Game.settings.get("push_to_talk", false))
	%PttCheck.toggled.connect(func(on: bool) -> void:
		Game.settings["push_to_talk"] = on
		Game.save_settings())

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and Game.state != Game.State.MENU:
		if is_open:
			close()
		else:
			open()
		get_viewport().set_input_as_handled()

func open() -> void:
	is_open = true
	visible = true
	_show_settings(false)
	%InviteButton.disabled = not (SteamManager.steam_ok and SteamManager.lobby_id != 0)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func close() -> void:
	is_open = false
	visible = false
	# Recapture only in first-person-ish scenes; menu/results keep the cursor.
	if Game.state in [Game.State.LOBBY, Game.State.GARAGE, Game.State.STORM_RUN]:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _on_leave() -> void:
	is_open = false
	visible = false
	SteamManager.leave_session()  # Game returns everyone to the menu.

func _show_settings(show_it: bool) -> void:
	%MainBox.visible = not show_it
	%SettingsBox.visible = show_it
