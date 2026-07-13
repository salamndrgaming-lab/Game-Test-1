extends Node
## Host-side HP, fall damage, death and respawn. hp/dead live on the player
## and are synced. Design rule: flinging your friend is content, killing
## them ends the fun — fall damage is heavy, not instant death.
##
## Death drops a camera pickup holding the player's unsaved footage; a
## teammate can grab it off the ground (instant emergent drama).

var _prev_torso_vel := Vector3.ZERO
var _respawn_timer := 0.0

@onready var player: CharacterBody3D = get_parent()

func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	if player.dead:
		_respawn_timer -= delta
		if _respawn_timer <= 0.0:
			_respawn()
		return
	if player.state == player.PState.RAGDOLL:
		var v: Vector3 = player.ragdoll.torso_velocity()
		var decel := (_prev_torso_vel - v).length()
		_prev_torso_vel = v
		var bal: BalanceConfig = Game.balance
		if decel > bal.fall_damage_min_decel:
			take_damage((decel - bal.fall_damage_min_decel) * bal.fall_damage_scale)
	else:
		_prev_torso_vel = Vector3.ZERO

func take_damage(amount: float) -> void:
	if player.dead:
		return
	player.hp = maxf(player.hp - amount, 0.0)
	if player.hp <= 0.0:
		_die()

func _die() -> void:
	player.dead = true
	_respawn_timer = Game.balance.player_respawn_seconds
	if player.state != player.PState.RAGDOLL:
		player._enter_ragdoll()
	var mgr := get_tree().get_first_node_in_group("run_manager")
	if mgr != null:
		mgr.note_death()  # feeds the auto-generated run title
	if mgr != null and player.footage > 0.0:
		# Drop at ground level: dying mid-orbit would otherwise leave the
		# pickup floating 40m up in the funnel, unreachable. Map is flat.
		var drop := Vector3(player.global_position.x, 0.5, player.global_position.z)
		mgr.spawn_pickup(drop, player.footage)
	player.footage = 0.0

func _respawn() -> void:
	player.dead = false
	player.hp = Game.balance.player_max_hp
	player._exit_ragdoll()
	var pos := Vector3(0.0, 2.0, 0.0)
	var vans := get_tree().get_nodes_in_group("vans")
	if vans.size() > 0:
		pos = (vans[0] as Node3D).global_position + Vector3(2.5, 1.0, 0.0)
	player.global_position = pos
