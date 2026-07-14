class_name BalanceConfig
extends Resource
## Single source of truth for tunable gameplay values (design rule: no magic
## gameplay numbers in scripts). Tweak res://config/balance.tres in the
## inspector — no code edits needed.
##
## Values for future phases are declared up front so the resource never needs
## a migration; scripts only read the group relevant to their phase.

@export_group("Player")
@export var player_move_speed := 6.0
@export var player_sprint_multiplier := 1.6
@export var player_accel := 40.0
@export var player_jump_velocity := 4.5
@export var player_push_force := 8.0
@export var player_kick_impulse := 1.5  # walking into loose props boots them
@export var player_ragdoll_recover_seconds := 2.0
@export var ragdoll_impact_speed := 7.0  # sudden decel above this = comedy ragdoll
@export var mouse_sensitivity := 0.003
@export var player_max_hp := 100.0
@export var fall_damage_min_decel := 8.0  # ragdoll impacts below this are free
@export var fall_damage_scale := 4.0  # heavy damage, not instant death (design)
@export var player_respawn_seconds := 10.0

@export_group("Grabbing")
@export var grab_spring := 40.0
@export var grab_damping := 6.0
@export var grab_break_distance := 3.5
@export var winch_spring_multiplier := 3.0  # winch towing the van

@export_group("Progression")  # Phase 5
@export var upgrade_prices := {
	"van_engine": 400,
	"van_rollcage": 350,
	"van_tires": 300,
	"van_winch": 450,
	"cam_lens": 250,
	"cam_stabilizer": 300,
	"cam_battery": 200,
}
@export_group("Weather")  # Phase 5.5 — radar/forecast system
@export var tornado_leash_radius := 160.0  # cells wander near their center
@export var home_radius := 18.0  # HQ driveway wifi range
@export var upload_rate := 250.0  # footage pts/s while uploading at home
@export var mark_duration := 45.0  # navigator's storm call lifetime
@export var called_bonus := 1.25  # filming a called cell
@export var spotter_cut := 0.1  # navigator's share of called-cell footage
@export var driver_cut := 0.2  # driver's share of footage filmed from their van

@export_group("Camcorder")
@export var camera_battery_seconds := 90.0

@export_group("Tornado")  # Phase 3
@export var tornado_outer_radius := 200.0
@export var tornado_middle_radius := 80.0
@export var tornado_inner_radius := 25.0
@export var tornado_pull_outer := 4.0
@export var tornado_pull_middle := 14.0
@export var tornado_pull_inner := 40.0
@export var tornado_wander_speed := 7.0
@export var tornado_middle_push := 12.0  # player shove in the middle ring
@export var tornado_inner_lift := 30.0  # ragdoll orbit lift (per torso mass)
@export var tornado_van_push := 2500.0
@export var tornado_van_lift := 14000.0  # > 900kg * 9.8 so it actually flies
@export var tornado_van_lift_intensity := 3.0  # F-rating needed to lift the van

@export_group("Run")  # Phase 3
@export var run_chase_seconds := 600.0  # 10 min storm
@export var run_extract_seconds := 90.0

@export_group("Filming")  # Phase 3
@export var film_max_range := 400.0
@export var film_fov_degrees := 60.0
@export var film_bonus_fling := 40.0  # friend being flung, per second
@export var film_bonus_van_air := 80.0  # van airborne, per second
@export var views_per_point := 12.0

@export_group("Van")  # Phase 2
@export var van_engine_torque := 250.0
@export var van_max_hp := 100.0
@export var van_com_height := 0.9  # raised center of mass = top-heavy on purpose
@export var van_max_steer := 0.55
@export var van_steer_speed := 2.5
@export var van_brake_force := 35.0
@export var van_idle_brake := 3.0
@export var van_impact_min_decel := 5.0  # per-tick velocity loss before damage
@export var van_impact_damage_scale := 3.0
@export var van_exit_ragdoll_speed := 6.0  # bail out faster than this = ragdoll

@export_group("Economy")  # Phase 3/5
@export var footage_base_points_per_second := 10.0
@export var payout_per_100_views := 1.0
