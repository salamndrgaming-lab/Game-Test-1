extends RigidBody3D
## Physics prop the host simulates; everyone else watches synced transforms.
## Membership in the "grabbable" group (set in the scene file) is what makes
## E-grab find it.

func _ready() -> void:
	if not multiplayer.is_server():
		freeze = true  # Never simulate physics on clients (design rule).
