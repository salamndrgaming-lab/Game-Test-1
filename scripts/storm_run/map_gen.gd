extends Node3D
## Procedural county. Builds the run map from the forecast's seed —
## deterministic RNG, so every peer generates an identical layout with
## identical node names (the physics props' synchronizers depend on that).
## Static geometry is placeholder boxes per the art plan; props are the
## networked grabbable scenes.
##
## CHASER HQ stays fixed at the map corner — home doesn't move.

const PLANK := preload("res://scenes/props/plank.tscn")
const CONE := preload("res://scenes/props/traffic_cone.tscn")
const CRATE := preload("res://scenes/props/crate.tscn")

const HQ := Vector2(450, 450)

var _rng := RandomNumberGenerator.new()
var _placed: Array = []  # structure centers, for spacing
var _prop_seq := 0

func generate(seed_value: int) -> void:
	_rng.seed = seed_value
	for i in _rng.randi_range(4, 6):
		_farmstead()
	_gas_station()
	_water_tower()
	_trailer_park()
	for i in _rng.randi_range(2, 3):
		_corn_field()
	for i in 40:
		_tree()

# --- Placement -----------------------------------------------------------------

func _find_spot(clearance: float) -> Vector2:
	for attempt in 24:
		var p := Vector2(_rng.randf_range(-430.0, 400.0), _rng.randf_range(-430.0, 380.0))
		if p.distance_to(HQ) < 70.0:
			continue  # keep the driveway clear
		var ok := true
		for c in Game.DEPLOY_CANDIDATES:
			if p.distance_to(c) < 30.0:
				ok = false
				break
		if ok:
			for c in _placed:
				if p.distance_to(c) < clearance:
					ok = false
					break
		if ok:
			_placed.append(p)
			return p
	return Vector2(9999.0, 9999.0)  # no room found; effectively skipped

# --- Structures -----------------------------------------------------------------

func _farmstead() -> void:
	var p := _find_spot(60.0)
	if p.x > 9000.0:
		return
	var rot := _rng.randf_range(0.0, TAU)
	_static_box(Vector3(p.x, 3.0, p.y), Vector3(10, 6, 8), Color(0.68, 0.6, 0.52), rot)
	if _rng.randf() < 0.8:  # most farms get a barn + loose planks
		var bp := p + Vector2(_rng.randf_range(20.0, 35.0), _rng.randf_range(-15.0, 15.0))
		_static_box(Vector3(bp.x, 4.0, bp.y), Vector3(12, 8, 10), Color(0.62, 0.22, 0.18), rot)
		for i in _rng.randi_range(4, 7):
			_prop(PLANK, "plank",
					Vector3(bp.x + _rng.randf_range(-9.0, 9.0), 0.3, bp.y + _rng.randf_range(-9.0, 9.0)))
	if _rng.randf() < 0.5:
		_prop(CRATE, "crate",
				Vector3(p.x + _rng.randf_range(-10.0, 10.0), 0.5, p.y + _rng.randf_range(-10.0, 10.0)))

func _gas_station() -> void:
	var p := _find_spot(70.0)
	if p.x > 9000.0:
		return
	_static_box(Vector3(p.x, 2.5, p.y), Vector3(12, 5, 10), Color(0.68, 0.6, 0.52), 0.0)
	for i in _rng.randi_range(2, 4):
		_prop(CONE, "cone",
				Vector3(p.x + _rng.randf_range(-12.0, 12.0), 0.2, p.y + 8.0 + _rng.randf_range(0.0, 6.0)))
	for i in 2:
		_prop(CRATE, "crate",
				Vector3(p.x - 7.0 + i * 1.4, 0.5, p.y - 7.0))

func _water_tower() -> void:
	var p := _find_spot(60.0)
	if p.x > 9000.0:
		return
	var body := StaticBody3D.new()
	body.position = Vector3(p.x, 0.0, p.y)
	_add_mesh_shape(body, _box_mesh(Vector3(1.2, 12, 1.2), Color(0.68, 0.6, 0.52)),
			_box_shape(Vector3(1.2, 12, 1.2)), Vector3(0, 6, 0))
	var tank := CylinderMesh.new()
	tank.top_radius = 3.0
	tank.bottom_radius = 3.0
	tank.height = 8.0
	tank.material = _mat(Color(0.68, 0.6, 0.52))
	var tank_shape := CylinderShape3D.new()
	tank_shape.radius = 3.0
	tank_shape.height = 8.0
	_add_mesh_shape(body, tank, tank_shape, Vector3(0, 16, 0))
	add_child(body)

func _trailer_park() -> void:
	var p := _find_spot(80.0)
	if p.x > 9000.0:
		return
	var rot := _rng.randf_range(0.0, TAU)
	for i in _rng.randi_range(3, 5):
		_static_box(Vector3(p.x + i * 11.0 - 22.0, 1.5, p.y + _rng.randf_range(-4.0, 4.0)),
				Vector3(3, 3, 9), Color(0.68, 0.6, 0.52), rot)
	for i in 2:
		_prop(CONE, "cone",
				Vector3(p.x + _rng.randf_range(-15.0, 15.0), 0.2, p.y + _rng.randf_range(-15.0, 15.0)))

func _corn_field() -> void:
	var p := _find_spot(120.0)
	if p.x > 9000.0:
		return
	var plane := PlaneMesh.new()
	plane.size = Vector2(_rng.randf_range(120.0, 220.0), _rng.randf_range(120.0, 220.0))
	plane.material = _mat(Color(0.25, 0.42, 0.14))
	var mesh := MeshInstance3D.new()
	mesh.mesh = plane
	mesh.position = Vector3(p.x, 0.05, p.y)
	mesh.rotation.y = _rng.randf_range(0.0, TAU)
	add_child(mesh)

func _tree() -> void:
	var p := Vector2(_rng.randf_range(-460.0, 430.0), _rng.randf_range(-460.0, 420.0))
	if p.distance_to(HQ) < 40.0:
		return
	for c in Game.DEPLOY_CANDIDATES:
		if p.distance_to(c) < 12.0:
			return
	var body := StaticBody3D.new()
	body.position = Vector3(p.x, 0.0, p.y)
	var h := _rng.randf_range(4.0, 7.0)
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.3
	trunk.bottom_radius = 0.4
	trunk.height = h
	trunk.material = _mat(Color(0.4, 0.28, 0.16))
	var trunk_shape := CylinderShape3D.new()
	trunk_shape.radius = 0.35
	trunk_shape.height = h
	_add_mesh_shape(body, trunk, trunk_shape, Vector3(0, h * 0.5, 0))
	var leaves := SphereMesh.new()
	leaves.radius = _rng.randf_range(1.8, 3.0)
	leaves.height = leaves.radius * 2.0
	leaves.material = _mat(Color(0.18, 0.38, 0.16))
	var leaves_mesh := MeshInstance3D.new()
	leaves_mesh.mesh = leaves
	leaves_mesh.position = Vector3(0, h + leaves.radius * 0.4, 0)
	body.add_child(leaves_mesh)
	add_child(body)

# --- Builders -----------------------------------------------------------------

func _static_box(pos: Vector3, size: Vector3, color: Color, yrot: float) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	body.rotation.y = yrot
	_add_mesh_shape(body, _box_mesh(size, color), _box_shape(size), Vector3.ZERO)
	add_child(body)

func _add_mesh_shape(body: StaticBody3D, mesh: Mesh, shape: Shape3D, offset: Vector3) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = offset
	body.add_child(mi)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = offset
	body.add_child(cs)

func _box_mesh(size: Vector3, color: Color) -> BoxMesh:
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = _mat(color)
	return bm

func _box_shape(size: Vector3) -> BoxShape3D:
	var bs := BoxShape3D.new()
	bs.size = size
	return bs

func _mat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	return m

func _prop(scene: PackedScene, kind: String, pos: Vector3) -> void:
	_prop_seq += 1
	var n := scene.instantiate()
	n.name = "gen_%s_%d" % [kind, _prop_seq]
	n.position = pos
	add_child(n)
