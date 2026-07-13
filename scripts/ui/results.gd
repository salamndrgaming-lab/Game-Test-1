extends Control
## Post-run results: per-player footage, views, money. Data arrives via
## Game.set_run_results (broadcast by the host before the scene change).

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	%ContinueButton.visible = multiplayer.is_server()
	%WaitLabel.visible = not multiplayer.is_server()
	%ContinueButton.pressed.connect(func() -> void:
		Game.net_change_state.rpc(Game.State.LOBBY))
	var rows := ""
	var best_pts := -1
	var best_line := ""
	for row in Game.last_run_results:
		rows += "P%s   —   %d footage pts\n" % [row["pid"], row["footage"]]
		if int(row["best"]) > best_pts:
			best_pts = int(row["best"])
			best_line = "BEST CLIP: %s  (%d pts in one second, filmed by P%s)" \
					% [row["caption"], best_pts, row["pid"]]
	%RowsLabel.text = rows if rows != "" else "nobody filmed anything. incredible."
	%ClipLabel.text = best_line
	%TotalsLabel.text = "%d views   →   $%d earned   (crew total: $%d)" \
			% [Game.last_run_views, Game.last_run_money, Game.crew_money]
