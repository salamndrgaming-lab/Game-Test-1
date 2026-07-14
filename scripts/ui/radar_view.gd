class_name RadarView
extends Control
## Custom-drawn county weather radar. Forecast mode (garage) shows cells,
## the heavy area, deploy points, and HQ. Live mode (navigator's TAB radar)
## additionally draws active tornadoes, the van, yourself, and the current
## storm call.

const WORLD_HALF := 500.0
const HQ := Vector2(450, 450)

@export var live := false

func _ready() -> void:
	custom_minimum_size = Vector2(340, 340)

func _process(_delta: float) -> void:
	if visible:
		queue_redraw()

func _map(wx: float, wz: float) -> Vector2:
	return Vector2((wx / WORLD_HALF * 0.5 + 0.5) * size.x, (wz / WORLD_HALF * 0.5 + 0.5) * size.y)

func _draw() -> void:
	var font := ThemeDB.fallback_font
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.03, 0.09, 0.05, 0.96))
	for i in range(1, 4):
		draw_line(Vector2(size.x * i / 4.0, 0), Vector2(size.x * i / 4.0, size.y), Color(0.1, 0.25, 0.12), 1.0)
		draw_line(Vector2(0, size.y * i / 4.0), Vector2(size.x, size.y * i / 4.0), Color(0.1, 0.25, 0.12), 1.0)
	var f: Dictionary = Game.forecast
	if f.is_empty():
		draw_string(font, Vector2(20, size.y * 0.5), "NO DATA — radar warming up",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.5, 0.9, 0.5))
		return
	var heavy: Dictionary = f.get("heavy", {})
	if not heavy.is_empty():
		var hp := _map(float(heavy.x), float(heavy.z))
		draw_circle(hp, size.x * 0.28, Color(0.9, 0.2, 0.1, 0.08))
		draw_circle(hp, size.x * 0.16, Color(0.9, 0.2, 0.1, 0.10))
	for c in f.get("cells", []):
		var peak := float(c.peak)
		var px := _map(float(c.x), float(c.z))
		draw_circle(px, 8.0 + peak * 5.0, Color(0.25 + 0.18 * peak, 0.85 - 0.17 * peak, 0.2, 0.55))
		draw_string(font, px + Vector2(-9, -12), "F%d" % int(round(peak)),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.85))
	var hq := _map(HQ.x, HQ.y)
	draw_rect(Rect2(hq - Vector2(5, 5), Vector2(10, 10)), Color(0.95, 0.95, 0.95))
	draw_string(font, hq + Vector2(-12, 20), "HQ", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)
	var deploys: Array = f.get("deploys", [])
	var selected := int(f.get("selected", 0))
	for i in deploys.size():
		var d: Dictionary = deploys[i]
		var dp := _map(float(d.x), float(d.z))
		var dcol := Color(1, 0.9, 0.2) if i == selected else Color(0.6, 0.6, 0.6)
		draw_arc(dp, 7.0, 0.0, TAU, 20, dcol, 2.0)
		draw_string(font, dp + Vector2(-4, 4), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, dcol)
	if not live:
		return
	# Live extras.
	var mgr := get_tree().get_first_node_in_group("run_manager")
	for tor in get_tree().get_nodes_in_group("tornado"):
		if not tor.active:
			continue
		var tp := _map(tor.global_position.x, tor.global_position.z)
		draw_circle(tp, 6.0 + tor.intensity * 3.0, Color(0.95, 0.3, 0.2, 0.9))
		if mgr != null and mgr.called_cell == tor.cell_index:
			draw_arc(tp, 12.0 + tor.intensity * 3.0, 0.0, TAU, 24, Color(1, 1, 0.3), 2.0)
	for v in get_tree().get_nodes_in_group("vans"):
		var vp := _map(v.global_position.x, v.global_position.z)
		draw_rect(Rect2(vp - Vector2(4, 4), Vector2(8, 8)), Color(1, 0.85, 0.2))
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		draw_circle(_map(cam.global_position.x, cam.global_position.z), 3.0, Color.WHITE)
