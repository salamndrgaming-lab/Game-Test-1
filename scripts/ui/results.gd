extends Control
## Post-run results: auto-generated run title, per-player footage + awards
## (Best Cameraman / Most Airborne / Least Useful), best-clip caption, views,
## money — and the CLIP THAT button, which is a joke that markets itself.

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	%ContinueButton.visible = multiplayer.is_server()
	%WaitLabel.visible = not multiplayer.is_server()
	%ContinueButton.pressed.connect(func() -> void:
		Game.net_change_state.rpc(Game.State.GARAGE))
	%ClipButton.pressed.connect(func() -> void:
		%ClipButton.text = "CLIPPED. (the last 30s existed. real replays post-launch)")
	%TitleLabel.text = '"%s"' % Game.last_run_title
	var rows := ""
	var best_pts := -1
	var best_line := ""
	for row in Game.last_run_results:
		rows += "P%s   —   %d footage pts   (%.0fs airborne)\n" \
				% [row["pid"], row["footage"], float(row.get("air", 0.0))]
		if int(row["best"]) > best_pts:
			best_pts = int(row["best"])
			best_line = "BEST CLIP: %s  (%d pts in one second, filmed by P%s)" \
					% [row["caption"], best_pts, row["pid"]]
	%RowsLabel.text = rows if rows != "" else "nobody filmed anything. incredible."
	%ClipLabel.text = best_line
	%StatsLabel.text = _awards()
	%TotalsLabel.text = "%d views   →   $%d earned   (crew total: $%d)" \
			% [Game.last_run_views, Game.last_run_money, Game.crew_money]

func _awards() -> String:
	var results: Array = Game.last_run_results
	if results.is_empty():
		return ""
	var best_cam: Dictionary = results[0]
	var most_air: Dictionary = results[0]
	var least: Dictionary = results[0]
	for row in results:
		if int(row["footage"]) > int(best_cam["footage"]):
			best_cam = row
		if float(row.get("air", 0.0)) > float(most_air.get("air", 0.0)):
			most_air = row
		if int(row["footage"]) < int(least["footage"]):
			least = row
	return "Best Cameraman: P%s      Most Airborne: P%s (%.0fs)      Least Useful: P%s" \
			% [best_cam["pid"], most_air["pid"], float(most_air.get("air", 0.0)), least["pid"]]
