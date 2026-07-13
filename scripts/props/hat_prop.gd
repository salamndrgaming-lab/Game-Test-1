class_name HatProp
extends RigidBody3D
## A hat that came off (the wind WILL take it). Grabbable, chaseable, and
## wearable again with E. Spawned via run-manager RPC with hat_id preset.
## Also the single source of hat meshes (the player's head reuses them).

var hat_id := 1

func _ready() -> void:
	if not multiplayer.is_server():
		freeze = true  # Never simulate physics on clients (design rule).
	$Mesh.mesh = build_mesh(hat_id)

static func build_mesh(id: int) -> Mesh:
	var mat := StandardMaterial3D.new()
	match id:
		1:  # safety cone
			var cone := CylinderMesh.new()
			cone.top_radius = 0.02
			cone.bottom_radius = 0.18
			cone.height = 0.35
			mat.albedo_color = Color(1.0, 0.45, 0.05)
			cone.material = mat
			return cone
		2:  # bucket
			var bucket := CylinderMesh.new()
			bucket.top_radius = 0.16
			bucket.bottom_radius = 0.13
			bucket.height = 0.22
			mat.albedo_color = Color(0.6, 0.62, 0.66)
			bucket.material = mat
			return bucket
		3:  # "crown"
			var crown := CylinderMesh.new()
			crown.top_radius = 0.17
			crown.bottom_radius = 0.15
			crown.height = 0.12
			mat.albedo_color = Color(0.95, 0.8, 0.2)
			crown.material = mat
			return crown
	return BoxMesh.new()
