extends Node3D
## A dead chaser's dropped camcorder, holding their unsaved footage.
## Spawned/despawned by the run manager via RPC on all peers; `amount` is
## passed in the spawn RPC so nothing needs syncing afterward.

var amount := 0.0
