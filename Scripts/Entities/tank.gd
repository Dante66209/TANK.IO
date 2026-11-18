# res://Scripts/Entities/tank.gd
class_name Tank extends CharacterBody2D

## Base kinematic tank entity for player and bot tanks.
## Implements decoupled chassis/turret, health/shield model, scoring,
## power-ups, damage resolution, and max-min threat safe respawning.

enum PowerUpType { HEALTH = 0, SHIELD = 1, RAPID_FIRE = 2, RICOCHET = 3, SPEED_BOOST = 4, CLUSTER_MINES = 5 }

const FloatingTextScript = preload("res://Scripts/UI/floating_text.gd")
const SoundManagerScript = preload("res://Scripts/Core/sound_manager.gd")
const ProximityMineScript = preload("res://Scripts/Entities/mine.gd")

# Physics Constants
const BASE_SPEED: float = 240.0
const ACCELERATION: float = 1200.0
const FRICTION: float = 900.0
const CHASSIS_TURN_RATE: float = 8.0
const TURRET_ROTATION_SPEED: float = 6.0
const BASE_FIRE_COOLDOWN: float = 0.35
const BASE_BULLET_SPEED: float = 650.0
const RESPAWN_DELAY: float = 3.5
const INVULNERABILITY_DURATION: float = 1.5
const MAX_MINES: int = 3
const MINE_THROW_DISTANCE: float = 235.0
const MINE_THROW_COOLDOWN: float = 0.40
const CLUSTER_SPREAD_DEG: float = 19.0
const MULTIKILL_WINDOW: float = 4.5

# Combat & Scoring Stats
@export var tank_name: String = "Tank":
	set(value):
		tank_name = value
		if is_node_ready() and name_label != null:
			name_label.text = value
@export var is_player: bool = false
@export var max_health: float = 100.0
@export var sight_radius: float = 560.0:
	set(value):
		sight_radius = value
		if is_node_ready() and has_node("SightArea2D/CollisionShape2D"):
			var col: CollisionShape2D = get_node("SightArea2D/CollisionShape2D")
			if col.shape is CircleShape2D:
				col.shape.radius = value
@export var projectile_scene: PackedScene = preload("res://Scenes/projectile.tscn")

# Dash / Sprint Mechanics (Prototype feature)
@export var max_dash_stamina: float = 100.0
@export var dash_drain_rate: float = 60.0
@export var dash_recharge_rate: float = 25.0
@export var dash_speed_multiplier: float = 1.6 # 240 * 1.6 = 384 px/s (prototype sprint_speed = 380)

var dash_stamina: float = 100.0
var is_dashing: bool = false
var dash_requested: bool = false

var current_health: float = 100.0
var current_hp: float:
	get: return current_health
var hp: float:
	get: return current_health
var shield: float = 0.0
var current_shield: float:
	get: return shield
var max_shield: float = 50.0
var is_dead: bool = false
var is_invulnerable: bool = false
var can_fire: bool = true
var controls_locked: bool = false
var is_in_sight: bool = true

var score: int = 0
var kills: int = 0
var deaths: int = 0
var kill_streak: int = 0
var barrel_kills: int = 0
var multikill_count: int = 0
var mines_count: int = MAX_MINES
var cluster_mines_count: int = 0
var has_cluster_mines: bool:
	get: return cluster_mines_count > 0
var permanently_eliminated: bool = false
var _incoming_mine_hit: bool = false
var _incoming_storm_hit: bool = false
var last_kill_was_mine: bool = false
var last_kill_was_storm: bool = false
var last_killer: Node2D = null

# Runtime Modifiers
var current_speed: float = BASE_SPEED
var fire_cooldown: float = BASE_FIRE_COOLDOWN
var bullet_speed: float = BASE_BULLET_SPEED
var ricochet_shots: int = 0
var has_rapid_fire: bool:
	get: return _active_powerups.has(PowerUpType.RAPID_FIRE)
var has_speed_boost: bool:
	get: return _active_powerups.has(PowerUpType.SPEED_BOOST)

signal network_projectile_spawned(tank: Node2D, proj: Node2D, spawn_pos: Vector2, shoot_dir: Vector2, p_speed: float, p_damage: float, is_ricochet: bool, bounces: int)
signal network_mine_spawned(tank: Node2D, mine: Node2D, start_pos: Vector2, target_pos: Vector2, is_cluster: bool, play_sound: bool)
signal network_damaged_synced(tank: Node2D, amount: float, kind: int)
signal network_eliminated_synced(tank: Node2D, killer_slot: int, is_barrel: bool, is_mine: bool, is_storm: bool, is_mortar: bool)
signal network_respawned_synced(tank: Node2D, pos: Vector2)
signal network_powerup_synced(tank: Node2D, type: int, duration: float, value: float, expired: bool)

# Network State (Phase 2 Multiplayer)
var net_slot: int = -1
var owner_peer_id: int = 0
var is_network_puppet: bool = false
var network_authoritative: bool = true
var is_human_remote: bool = false

var _net_target_pos: Vector2 = Vector2.ZERO
var _net_has_snapshot: bool = false
var _net_target_chassis_angle: float = 0.0
var _net_target_turret_angle: float = 0.0
var _net_wants_shoot: bool = false

# Input & Aim Targets
var move_input: Vector2 = Vector2.ZERO
var turret_target_pos: Vector2 = Vector2.ZERO
var target_aim_angle: float = 0.0

# Timers
var _fire_timer: float = 0.0
var _respawn_timer: float = 0.0
var _invulnerability_timer: float = 0.0
var _mine_cooldown: float = 0.0
var _multikill_timer: float = 0.0

# Power-Up Tracking
var _active_powerups: Dictionary = {}

# Monster Energy "Bouncing Yaris" Visual & Beat Sync (136.0 BPM)
const MONSTER_BOUNCE_BPM: float = 136.0
const MONSTER_BOUNCE_BPS: float = MONSTER_BOUNCE_BPM / 60.0
const MONSTER_DROP_TIME: float = 1.765
const MONSTER_BOUNCE_HEIGHT: float = 20.0
const MONSTER_AUDIO_RANGE: float = 1500.0

# Tank engine/treads movement loop volume (dB). Lower = quieter.
const MOVE_AUDIO_LOCAL_DB: float = -14.5
const MOVE_AUDIO_REMOTE_DB: float = -17.5

var _chassis_angle: float = 0.0
var _monster_bounce_time: float = 0.0
var monster_bounce_offset_y: float = 0.0
var monster_squash_scale: Vector2 = Vector2.ONE
var _monster_music_player: AudioStreamPlayer2D = null
var _move_audio_player: AudioStreamPlayer2D = null

# Node References
@onready var chassis_visual: Node2D = $ChassisVisual
@onready var turret_pivot: Node2D = $TurretPivot
@onready var turret_visual: Node2D = $TurretPivot/TurretVisual
@onready var muzzle: Marker2D = $TurretPivot/Muzzle
@onready var shield_aura: Node2D = $ShieldAura
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var overhead_ui: Node2D = $OverheadUI
@onready var hp_bar: ProgressBar = $OverheadUI/HPBar
@onready var shield_bar: ProgressBar = $OverheadUI/ShieldBar
@onready var name_label: Label = $OverheadUI/NameLabel

var _pending_tank_color: Variant = null

func _ready() -> void:
	current_health = max_health
	dash_stamina = max_dash_stamina
	mines_count = MAX_MINES
	cluster_mines_count = 0
	permanently_eliminated = false
	if name_label != null:
		name_label.text = tank_name
		name_label.visible = true
	if GameEvents != null and not GameEvents.match_ended.is_connected(_on_match_ended_stop_music):
		GameEvents.match_ended.connect(_on_match_ended_stop_music)
	if _pending_tank_color is Color:
		apply_tank_color(_pending_tank_color)
	_update_ui()
	turret_target_pos = global_position + Vector2.RIGHT * 100.0

func apply_tank_color(col: Color) -> void:
	var opaque_col := Color(col.r, col.g, col.b, 1.0)
	_pending_tank_color = opaque_col
	if chassis_visual != null:
		if "body_color" in chassis_visual:
			chassis_visual.set("body_color", opaque_col)
		chassis_visual.queue_redraw()
	if turret_visual != null:
		if "turret_color" in turret_visual:
			turret_visual.set("turret_color", opaque_col.darkened(0.18))
		turret_visual.queue_redraw()

func _exit_tree() -> void:
	if _monster_music_player != null and is_instance_valid(_monster_music_player):
		_monster_music_player.stop()
		_monster_music_player.stream = null
	if _move_audio_player != null and is_instance_valid(_move_audio_player):
		_move_audio_player.stop()
		_move_audio_player.stream = null

func _on_match_ended_stop_music(_leaderboard: Array[Dictionary]) -> void:
	_reset_monster_bounce()
	_stop_movement_audio()

func set_controls_locked(locked: bool) -> void:
	controls_locked = locked
	if locked:
		move_input = Vector2.ZERO
		dash_requested = false
		is_dashing = false
		velocity = Vector2.ZERO
		_stop_movement_audio()

func set_chassis_input(dir: Vector2) -> void:
	if controls_locked:
		move_input = Vector2.ZERO
		return
	move_input = dir.limit_length(1.0)

func set_dash_input(pressed: bool) -> void:
	if controls_locked:
		dash_requested = false
		return
	dash_requested = pressed

func set_turret_target(pos: Vector2) -> void:
	if controls_locked:
		return
	turret_target_pos = pos
	target_aim_angle = (pos - global_position).angle()

func set_turret_aim_angle(angle: float) -> void:
	if controls_locked:
		return
	target_aim_angle = angle
	turret_target_pos = global_position + Vector2.RIGHT.rotated(angle) * 200.0

func apply_remote_input(dir: Vector2, aim_angle: float, wants_shoot: bool, wants_dash: bool) -> void:
	if controls_locked or is_dead:
		move_input = Vector2.ZERO
		dash_requested = false
		_net_wants_shoot = false
		return
	set_chassis_input(dir)
	set_turret_aim_angle(aim_angle)
	set_dash_input(wants_dash)
	_net_wants_shoot = wants_shoot

func snap_network_position(pos: Vector2) -> void:
	global_position = pos
	_net_target_pos = pos
	_net_has_snapshot = true
	velocity = Vector2.ZERO

func get_network_flags() -> int:
	var flags: int = 0
	if is_dead: flags |= 1
	if is_dashing: flags |= 2
	if is_invulnerable: flags |= 4
	if has_speed_boost: flags |= 8
	if has_rapid_fire: flags |= 16
	if permanently_eliminated: flags |= 32
	if controls_locked: flags |= 64
	return flags

func apply_network_snapshot(pos: Vector2, ch_ang: float, tur_ang: float, hp_val: float, sh_val: float, flags: int, dash_val: float = -1.0, mines_val: int = -1, ric_val: int = -1) -> void:
	var srv_dead: bool = (flags & 1) != 0
	var srv_dashing: bool = (flags & 2) != 0
	var srv_invuln: bool = (flags & 4) != 0
	var srv_speed: bool = (flags & 8) != 0
	var srv_rapid: bool = (flags & 16) != 0
	var srv_perm_elim: bool = (flags & 32) != 0
	var srv_locked: bool = (flags & 64) != 0

	current_health = hp_val
	shield = sh_val
	is_dashing = srv_dashing
	is_invulnerable = srv_invuln
	permanently_eliminated = srv_perm_elim
	controls_locked = srv_locked

	if dash_val >= 0.0:
		dash_stamina = dash_val
	if mines_val >= 0:
		mines_count = mines_val
	if ric_val >= 0:
		ricochet_shots = ric_val
		if ricochet_shots <= 0 and _active_powerups.has(PowerUpType.RICOCHET):
			_active_powerups.erase(PowerUpType.RICOCHET)
			if is_player and GameEvents != null:
				GameEvents.powerup_expired.emit(self, PowerUpType.RICOCHET)

	if shield_aura != null:
		shield_aura.visible = (not srv_dead) and (shield > 0.0 or is_invulnerable)

	if srv_speed and not has_speed_boost:
		apply_network_powerup(PowerUpType.SPEED_BOOST, 15.0, 2.0, false)
	elif not srv_speed and has_speed_boost:
		_active_powerups.erase(PowerUpType.SPEED_BOOST)
		_reset_monster_bounce()

	if srv_rapid and not has_rapid_fire:
		apply_network_powerup(PowerUpType.RAPID_FIRE, 8.0, 0.6, false)
	elif not srv_rapid and has_rapid_fire:
		_active_powerups.erase(PowerUpType.RAPID_FIRE)
		fire_cooldown = BASE_FIRE_COOLDOWN
		bullet_speed = BASE_BULLET_SPEED

	if srv_dead and not is_dead:
		apply_network_eliminate_fx(-1, false, false, false, false, false)
	elif not srv_dead and is_dead:
		apply_network_respawn_fx(pos)

	if is_network_puppet:
		_net_target_pos = pos
		_net_target_chassis_angle = ch_ang
		_net_target_turret_angle = tur_ang
		if not _net_has_snapshot:
			_net_has_snapshot = true
			global_position = pos
			_chassis_angle = ch_ang
			if chassis_visual != null:
				chassis_visual.transform = Transform2D(_chassis_angle, Vector2.ZERO)
			if turret_pivot != null:
				turret_pivot.global_rotation = tur_ang
	else:
		_net_target_pos = pos
		if not _net_has_snapshot:
			_net_has_snapshot = true
			global_position = pos
		elif not srv_dead:
			var dist := global_position.distance_to(pos)
			if dist > 95.0:
				global_position = pos
			elif dist > 4.0:
				global_position = global_position.lerp(pos, 0.25)

	_update_ui()

func _physics_process(delta: float) -> void:
	if is_network_puppet:
		_process_network_puppet(delta)
		return

	if is_dead:
		_process_dead_state(delta)
		return
	if controls_locked:
		move_input = Vector2.ZERO
		dash_requested = false
		is_dashing = false
		velocity = Vector2.ZERO
		_stop_movement_audio()
		_update_ui()
		return
		
	_process_timers(delta)
	_process_movement(delta)
	_process_movement_audio()
	_process_turret(delta)
	if is_human_remote and network_authoritative and _net_wants_shoot:
		shoot()
	_process_powerups(delta)
	_process_monster_bounce(delta)
	_update_ui()

func _process_network_puppet(delta: float) -> void:
	if is_dead:
		_stop_movement_audio()
		velocity = Vector2.ZERO
		return
	if _net_has_snapshot:
		var prev_pos := global_position
		var lerp_w := clampf(delta * 18.0, 0.0, 1.0)
		global_position = global_position.lerp(_net_target_pos, lerp_w)
		velocity = (global_position - prev_pos) / maxf(delta, 0.001)
		_chassis_angle = rotate_toward(_chassis_angle, _net_target_chassis_angle, CHASSIS_TURN_RATE * 2.2 * delta)
		if chassis_visual != null and not has_speed_boost:
			chassis_visual.transform = Transform2D(_chassis_angle, Vector2.ZERO)
		if turret_pivot != null:
			turret_pivot.global_rotation = rotate_toward(turret_pivot.global_rotation, _net_target_turret_angle, TURRET_ROTATION_SPEED * 3.5 * delta)
	_process_timers(delta)
	_process_movement_audio()
	_process_powerups(delta)
	_process_monster_bounce(delta)
	_update_ui()

func _process_timers(delta: float) -> void:
	if not can_fire:
		_fire_timer -= delta
		if _fire_timer <= 0.0:
			can_fire = true
			
	if _mine_cooldown > 0.0:
		_mine_cooldown = maxf(0.0, _mine_cooldown - delta)
		
	if _multikill_timer > 0.0:
		_multikill_timer -= delta
		if _multikill_timer <= 0.0:
			multikill_count = 0
			
	if is_invulnerable:
		_invulnerability_timer -= delta
		if _invulnerability_timer <= 0.0:
			is_invulnerable = false
			if shield_aura != null:
				shield_aura.visible = (shield > 0.0)

func _process_dead_state(delta: float) -> void:
	_stop_movement_audio()
	velocity = Vector2.ZERO
	move_and_slide()
	if not network_authoritative:
		return
	var mm := get_tree().get_first_node_in_group("match_manager") if get_tree() != null else null
	if mm != null and mm.get("no_respawns") == true:
		permanently_eliminated = true
		return
	_respawn_timer -= delta
	if _respawn_timer <= 0.0:
		request_safe_respawn()

func _process_movement(delta: float) -> void:
	var speed_mult: float = 2.0 if has_speed_boost else 1.0
	var target_speed := BASE_SPEED * speed_mult
	if dash_requested and move_input != Vector2.ZERO and dash_stamina > 0.0:
		is_dashing = true
		dash_stamina = maxf(0.0, dash_stamina - dash_drain_rate * delta)
		target_speed = BASE_SPEED * dash_speed_multiplier * speed_mult
	else:
		is_dashing = false
		dash_stamina = minf(max_dash_stamina, dash_stamina + dash_recharge_rate * delta)
		target_speed = BASE_SPEED * speed_mult

	current_speed = target_speed

	if move_input != Vector2.ZERO:
		velocity = velocity.move_toward(move_input * current_speed, ACCELERATION * speed_mult * delta)
		_chassis_angle = rotate_toward(_chassis_angle, move_input.angle(), CHASSIS_TURN_RATE * delta)
		if chassis_visual != null and not has_speed_boost:
			chassis_visual.transform = Transform2D(_chassis_angle, Vector2.ZERO)
		if has_speed_boost and velocity.length() > 50.0 and randf() < 0.3:
			_spawn_speed_trail()
	else:
		velocity = velocity.move_toward(Vector2.ZERO, FRICTION * delta)
		
	move_and_slide()

func _spawn_speed_trail() -> void:
	var parent_node := get_parent()
	if parent_node == null:
		return
	var puff := CPUParticles2D.new()
	puff.emitting = true
	puff.one_shot = true
	puff.explosiveness = 0.85
	puff.lifetime = 0.22
	puff.amount = 5
	puff.spread = 40.0
	puff.direction = -velocity.normalized()
	puff.initial_velocity_min = 20.0
	puff.initial_velocity_max = 60.0
	puff.gravity = Vector2.ZERO
	puff.scale_amount_min = 2.0
	puff.scale_amount_max = 4.0
	puff.color = Color(0.85, 1.0, 0.3, 0.55)
	puff.global_position = global_position
	parent_node.add_child(puff)
	if get_tree() != null:
		var timer := get_tree().create_timer(0.25)
		timer.timeout.connect(puff.queue_free)

func _process_turret(delta: float) -> void:
	if turret_pivot == null:
		return
	if is_player:
		# Player turret directly points at target in real time
		turret_pivot.global_rotation = (turret_target_pos - global_position).angle()
	elif is_human_remote:
		turret_pivot.global_rotation = target_aim_angle
	else:
		# Bot turret rotates toward target angle with rotational velocity limit
		turret_pivot.global_rotation = rotate_toward(turret_pivot.global_rotation, target_aim_angle, TURRET_ROTATION_SPEED * delta)

func shoot() -> void:
	if not network_authoritative:
		return
	if is_dead or controls_locked or not can_fire:
		return
		
	can_fire = false
	_fire_timer = fire_cooldown
	
	if projectile_scene == null:
		return
		
	var projectile: Node2D = projectile_scene.instantiate() as Node2D
	if projectile == null:
		return
		
	var shoot_dir: Vector2 = Vector2.RIGHT.rotated(turret_pivot.global_rotation)
	var spawn_pos: Vector2 = muzzle.global_position if muzzle != null else global_position + shoot_dir * 36.0
	projectile.global_position = spawn_pos
	var used_ricochet := false
	var bounces := 0
	var proj_dmg := 25.0
	if projectile.has_method("setup"):
		projectile.setup(self, shoot_dir, bullet_speed, proj_dmg)
		if ricochet_shots > 0:
			used_ricochet = true
			bounces = 2
			proj_dmg = 38.0
			if "bounces_remaining" in projectile:
				projectile.set("bounces_remaining", bounces)
			if "is_ricochet" in projectile:
				projectile.set("is_ricochet", true)
			if "damage" in projectile:
				projectile.set("damage", proj_dmg)
			ricochet_shots -= 1
			if _active_powerups.has(PowerUpType.RICOCHET):
				_active_powerups[PowerUpType.RICOCHET]["shots_left"] = ricochet_shots
			if ricochet_shots <= 0:
				_active_powerups.erase(PowerUpType.RICOCHET)
				if GameEvents != null:
					GameEvents.powerup_expired.emit(self, PowerUpType.RICOCHET)
	
	var container: Node = _get_projectile_container()
	container.add_child(projectile)
	network_projectile_spawned.emit(self, projectile, spawn_pos, shoot_dir, bullet_speed, proj_dmg, used_ricochet, bounces)
	
	if SoundManagerScript != null:
		SoundManagerScript.play_shoot(global_position)
		
	if GameEvents != null:
		GameEvents.weapon_fired.emit(self, global_position)
		if is_player:
			GameEvents.screen_shake_requested.emit(0.08)

func reset_mines() -> void:
	mines_count = MAX_MINES
	cluster_mines_count = 0
	_mine_cooldown = 0.0
	_active_powerups.erase(PowerUpType.CLUSTER_MINES)

func throw_mine() -> Node2D:
	if not network_authoritative:
		return null
	if is_dead or controls_locked or mines_count <= 0 or _mine_cooldown > 0.0:
		return null
		
	mines_count -= 1
	_mine_cooldown = MINE_THROW_COOLDOWN
	
	var aim_dir: Vector2 = Vector2.RIGHT
	if turret_pivot != null:
		aim_dir = Vector2.RIGHT.rotated(turret_pivot.global_rotation)
	elif turret_target_pos != global_position:
		aim_dir = (turret_target_pos - global_position).normalized()
		
	var start_pt: Vector2 = muzzle.global_position if muzzle != null else (global_position + aim_dir * 32.0)
	var container := _get_mine_container()
	
	if cluster_mines_count > 0:
		cluster_mines_count = maxi(0, cluster_mines_count - 1)
		if _active_powerups.has(PowerUpType.CLUSTER_MINES):
			_active_powerups[PowerUpType.CLUSTER_MINES]["shots_left"] = cluster_mines_count
		if cluster_mines_count <= 0:
			_active_powerups.erase(PowerUpType.CLUSTER_MINES)
			if GameEvents != null:
				GameEvents.powerup_expired.emit(self, PowerUpType.CLUSTER_MINES)
				
		var spread_rad := deg_to_rad(CLUSTER_SPREAD_DEG)
		var offsets: Array[Dictionary] = [
			{ "ang": 0.0, "dist_mult": 1.0, "sound": true },
			{ "ang": -spread_rad, "dist_mult": 0.94, "sound": false },
			{ "ang": spread_rad, "dist_mult": 0.94, "sound": false }
		]
		var primary_mine: Node2D = null
		for cfg in offsets:
			var sub_dir := aim_dir.rotated(float(cfg["ang"]))
			var sub_dist := MINE_THROW_DISTANCE * float(cfg["dist_mult"])
			var sub_landing := _find_safe_mine_landing(global_position, sub_dir, sub_dist)
			var sub_mine: Node2D = ProximityMineScript.new() as Node2D
			container.add_child(sub_mine)
			if sub_mine.has_method("setup"):
				sub_mine.setup(self, start_pt, sub_landing, true, bool(cfg["sound"]))
			network_mine_spawned.emit(self, sub_mine, start_pt, sub_landing, true, bool(cfg["sound"]))
			if GameEvents != null:
				GameEvents.mine_thrown.emit(self, sub_mine, start_pt, sub_landing)
			if primary_mine == null:
				primary_mine = sub_mine
		return primary_mine
		
	var landing_pt: Vector2 = _find_safe_mine_landing(global_position, aim_dir, MINE_THROW_DISTANCE)
	var mine: Node2D = ProximityMineScript.new() as Node2D
	container.add_child(mine)
	if mine.has_method("setup"):
		mine.setup(self, start_pt, landing_pt)
	network_mine_spawned.emit(self, mine, start_pt, landing_pt, false, true)
		
	if GameEvents != null:
		GameEvents.mine_thrown.emit(self, mine, start_pt, landing_pt)
		
	return mine

func _find_safe_mine_landing(origin: Vector2, aim_dir: Vector2, throw_dist: float) -> Vector2:
	var clamp_min := Vector2(-3120.0, -3120.0)
	var clamp_max := Vector2(3120.0, 3120.0)
	var candidate := (origin + aim_dir * throw_dist).clamp(clamp_min, clamp_max)
	
	var world2d := get_world_2d()
	if world2d == null or world2d.direct_space_state == null:
		return candidate
		
	var space_state := world2d.direct_space_state
	var scales: Array[float] = [1.0, 0.85, 0.70, 0.55, 0.40, 0.25, 1.15]
	for mult in scales:
		var test_pt := (origin + aim_dir * (throw_dist * mult)).clamp(clamp_min, clamp_max)
		var query := PhysicsShapeQueryParameters2D.new()
		var circle := CircleShape2D.new()
		circle.radius = 16.0
		query.shape = circle
		query.transform = Transform2D(0.0, test_pt)
		query.collision_mask = 1 | 2
		query.collide_with_bodies = true
		query.collide_with_areas = false
		if space_state.intersect_shape(query, 1).is_empty():
			return test_pt
			
	return candidate

func _get_mine_container() -> Node:
	var entities: Node = get_tree().get_first_node_in_group("entities") if get_tree() != null else null
	if entities != null:
		return entities
	return get_parent() if get_parent() != null else self

func _get_fx_container() -> Node:
	var entities: Node = get_tree().get_first_node_in_group("entities") if get_tree() != null else null
	if entities != null:
		return entities
	return get_parent()

func _get_projectile_container() -> Node:
	var proj_nodes: Array[Node] = get_tree().get_nodes_in_group("projectiles")
	if not proj_nodes.is_empty():
		return proj_nodes[0]
	var entities: Node = get_tree().get_first_node_in_group("entities")
	if entities != null and entities.has_node("Projectiles"):
		return entities.get_node("Projectiles")
	return get_parent()

func take_damage(amount: float, attacker: Node2D, is_barrel: bool = false) -> void:
	if not network_authoritative:
		return
	var is_mine_hit: bool = _incoming_mine_hit or (attacker != null and is_instance_valid(attacker) and attacker.get("is_mine") == true)
	var is_storm_hit: bool = _incoming_storm_hit
	_incoming_mine_hit = false
	_incoming_storm_hit = false
	
	if is_dead or is_invulnerable or controls_locked:
		return
		
	var remaining: float = amount
	if shield > 0.0:
		var absorbed: float = min(shield, remaining)
		shield -= absorbed
		remaining -= absorbed
		if shield <= 0.0:
			if shield_aura != null and not is_invulnerable:
				shield_aura.visible = false
			if _active_powerups.has(PowerUpType.SHIELD):
				_active_powerups.erase(PowerUpType.SHIELD)
				if GameEvents != null:
					GameEvents.powerup_expired.emit(self, PowerUpType.SHIELD)
			
	if remaining > 0.0:
		current_health = max(0.0, current_health - remaining)
		
	var is_mortar: bool = (attacker != null and is_instance_valid(attacker) and (attacker.is_in_group("mortar") or attacker.is_in_group("mortars") or attacker.get("is_mortar") == true))
	var dmg_kind: int = 4 if is_mortar else (2 if is_mine_hit else (3 if is_storm_hit else (1 if is_barrel else 0)))
	apply_network_damage_fx(amount, dmg_kind)
	network_damaged_synced.emit(self, amount, dmg_kind)
		
	var valid_attacker: Node2D = attacker if is_instance_valid(attacker) else null
	if GameEvents != null:
		GameEvents.tank_damaged.emit(self, valid_attacker, amount, is_barrel)
		
	_update_ui()
	
	if current_health <= 0.0:
		last_kill_was_mine = is_mine_hit
		last_kill_was_storm = is_storm_hit
		eliminate(valid_attacker, is_barrel)

func apply_network_damage_fx(amount: float, kind: int) -> void:
	var is_storm_hit: bool = (kind == 3)
	var is_mine_hit: bool = (kind == 2)
	var is_mortar: bool = (kind == 4)
	var is_barrel: bool = (kind == 1)

	_play_hit_flash()
	if not is_storm_hit and current_health > 0.0 and SoundManagerScript != null:
		SoundManagerScript.play_hit(global_position)
	if is_player and GameEvents != null:
		GameEvents.screen_shake_requested.emit(0.14 if is_storm_hit else 0.35)

	var txt_parent := _get_fx_container()
	if txt_parent != null:
		var color := Color(1.0, 0.28, 0.28)
		var prefix := "-%d"
		if is_mortar:
			color = Color(1.0, 0.25, 0.15)
			prefix = "-%d MORTERO!"
		elif is_mine_hit:
			color = Color(1.0, 0.42, 0.12)
			prefix = "-%d MINA!"
		elif is_storm_hit:
			color = Color(0.95, 0.2, 0.45)
			prefix = "-%d ZONA!"
		elif is_barrel:
			color = Color(1.0, 0.55, 0.15)
			prefix = "-%d BLAST!"
		FloatingTextScript.spawn(txt_parent, global_position, prefix % maxi(1, int(roundf(amount))), color)

func eliminate(attacker: Node2D, is_barrel: bool) -> void:
	if not network_authoritative:
		return
	if is_dead:
		return
	is_dead = true
	deaths += 1
	kill_streak = 0
	multikill_count = 0
	_multikill_timer = 0.0

	var valid_killer: Node2D = attacker if is_instance_valid(attacker) else null
	if valid_killer != null and not (valid_killer is Tank):
		var raw_owner: Variant = valid_killer.get("owner_tank") if "owner_tank" in valid_killer else null
		last_killer = raw_owner as Node2D if (raw_owner != null and is_instance_valid(raw_owner) and raw_owner is Node2D) else null
	else:
		last_killer = valid_killer
	var is_mortar_kill: bool = (valid_killer != null and (valid_killer.is_in_group("mortar") or valid_killer.is_in_group("mortars") or valid_killer.get("is_mortar") == true))
	var killer_slot: int = int(last_killer.get("net_slot")) if (last_killer != null and is_instance_valid(last_killer) and "net_slot" in last_killer) else -1

	apply_network_eliminate_fx(killer_slot, is_barrel, last_kill_was_mine, last_kill_was_storm, is_mortar_kill, false)

	var mm := get_tree().get_first_node_in_group("match_manager") if get_tree() != null else null
	if mm != null and mm.get("no_respawns") == true:
		permanently_eliminated = true
	if valid_killer != null and valid_killer != self and valid_killer.has_method("record_kill"):
		valid_killer.record_kill(self, is_barrel)

	network_eliminated_synced.emit(self, killer_slot, is_barrel, last_kill_was_mine, last_kill_was_storm, is_mortar_kill)
	if GameEvents != null:
		GameEvents.tank_killed.emit(self, valid_killer, is_barrel)
		
	_respawn_timer = RESPAWN_DELAY

func apply_network_eliminate_fx(killer_slot: int = -1, _is_barrel: bool = false, was_mine: bool = false, was_storm: bool = false, _was_mortar: bool = false, emit_event: bool = false) -> void:
	is_dead = true
	last_kill_was_mine = was_mine
	last_kill_was_storm = was_storm
	set_collision_layer_value(3, false)
	set_collision_mask_value(1, false)
	set_collision_mask_value(2, false)
	set_collision_mask_value(3, false)
	set_collision_mask_value(5, false)

	if chassis_visual != null:
		chassis_visual.visible = false
	if turret_pivot != null:
		turret_pivot.visible = false
	if overhead_ui != null:
		overhead_ui.visible = false
	if shield_aura != null:
		shield_aura.visible = false
	_reset_monster_bounce()
	_stop_movement_audio()
	if SoundManagerScript != null:
		SoundManagerScript.play_tank_destroyed(global_position)
	_spawn_death_fx()

	if killer_slot >= 0 and get_tree() != null:
		for t in get_tree().get_nodes_in_group("tanks"):
			if is_instance_valid(t) and "net_slot" in t and int(t.get("net_slot")) == killer_slot:
				last_killer = t as Node2D
				break
	if emit_event and GameEvents != null:
		GameEvents.tank_killed.emit(self, last_killer, _is_barrel)

func record_kill(_victim: Node2D, is_barrel: bool) -> void:
	kills += 1
	kill_streak += 1
	multikill_count += 1
	_multikill_timer = MULTIKILL_WINDOW
	
	var points: int = 250 if is_barrel else 100
	if is_barrel:
		barrel_kills += 1
	# Streak bonus
	if kill_streak == 3:
		points += 50
	elif kill_streak == 5:
		points += 100
	elif kill_streak == 7:
		points += 150
	elif kill_streak >= 10:
		points += 250
	score += points
	
	_evaluate_killstreak_medals()

func _evaluate_killstreak_medals() -> void:
	var mk_title := ""
	var mk_sub := ""
	var mk_col := Color.WHITE
	var mk_tier := 0
	
	if multikill_count == 2:
		mk_title = "¡DOBLE BAJA!"
		mk_sub = "DOS ENEMIGOS ABATIDOS EN CADENA"
		mk_col = Color(1.0, 0.85, 0.2)
		mk_tier = 2
	elif multikill_count == 3:
		mk_title = "¡TRIPLE BAJA!"
		mk_sub = "TRES ENEMIGOS DEMOLIDOS SEGUIDOS"
		mk_col = Color(1.0, 0.48, 0.14)
		mk_tier = 3
	elif multikill_count >= 4:
		mk_title = "¡MULTI-BAJA LETAL! (x%d)" % multikill_count
		mk_sub = "FURIA IMPLACABLE EN COMBATE"
		mk_col = Color(1.0, 0.2, 0.48)
		mk_tier = 4
		
	var ks_title := ""
	var ks_sub := ""
	var ks_col := Color.WHITE
	var ks_tier := 0
	
	if kill_streak == 3:
		ks_title = "¡EN RACHA! (3 BAJAS)"
		ks_sub = "RACHA DE ASALTO (+50 PTS)"
		ks_col = Color(0.25, 0.92, 1.0)
		ks_tier = 1
	elif kill_streak == 5:
		ks_title = "¡RACHA FRENÉTICA! (5 BAJAS)"
		ks_sub = "DOMINANDO LA ARENA (+100 PTS)"
		ks_col = Color(1.0, 0.65, 0.15)
		ks_tier = 2
	elif kill_streak == 7:
		ks_title = "¡IMPARABLE! (7 BAJAS)"
		ks_sub = "TERROR BLINDADO (+150 PTS)"
		ks_col = Color(1.0, 0.32, 0.2)
		ks_tier = 3
	elif kill_streak >= 10 and (kill_streak == 10 or kill_streak % 5 == 0):
		ks_title = "¡RACHA NUCLEAR! (%d BAJAS)" % kill_streak
		ks_sub = "ANIQUILACIÓN TOTAL (+250 PTS)"
		ks_col = Color(0.95, 0.25, 1.0)
		ks_tier = 4
		
	if mk_tier == 0 and ks_tier == 0:
		return
		
	var final_title := mk_title if mk_tier >= ks_tier and mk_title != "" else ks_title
	var final_sub := mk_sub if mk_tier >= ks_tier and mk_title != "" else ks_sub
	var final_col := mk_col if mk_tier >= ks_tier and mk_title != "" else ks_col
	var final_tier := maxi(mk_tier, ks_tier)
	
	if mk_title != "" and ks_title != "":
		final_sub = "%s  •  %s" % [mk_title, ks_title]
		
	if SoundManagerScript != null and (is_player or final_tier >= 2):
		SoundManagerScript.play_killstreak(final_tier, global_position, is_player)
		
	if GameEvents != null:
		GameEvents.killstreak_achieved.emit(self, final_title, final_sub, final_col, final_tier)
		GameEvents.kill_feed_announced.emit("RACHA • %s: %s" % [tank_name, final_title], final_col)

func request_safe_respawn() -> void:
	var safe_pos: Vector2 = select_safe_spawn_point()
	respawn(safe_pos)

func select_safe_spawn_point() -> Vector2:
	var map_node: Node = get_tree().get_first_node_in_group("world_map")
	var spawn_points: Array[Vector2] = []
	if map_node != null and map_node.has_method("get_spawn_positions"):
		spawn_points = map_node.get_spawn_positions()
	else:
		spawn_points = [
			Vector2(-950, -950), Vector2(950, -950),
			Vector2(-950, 950), Vector2(950, 950),
			Vector2(0, -800), Vector2(0, 800),
			Vector2(-800, 0), Vector2(800, 0)
		]
		
	if spawn_points.is_empty():
		return global_position
		
	var active_tanks: Array[Node] = get_tree().get_nodes_in_group("tanks")
	var best_point: Vector2 = spawn_points[0]
	var highest_min_dist: float = -1.0
	
	for pt in spawn_points:
		var min_dist_to_threat: float = INF
		for other in active_tanks:
			if is_instance_valid(other) and other is Tank and other != self and not other.is_dead:
				var dist: float = pt.distance_to(other.global_position)
				if dist < min_dist_to_threat:
					min_dist_to_threat = dist
		if min_dist_to_threat > highest_min_dist:
			highest_min_dist = min_dist_to_threat
			best_point = pt
			
	return best_point

func respawn(pos: Vector2) -> void:
	if not network_authoritative:
		return
	apply_network_respawn_fx(pos)
	network_respawned_synced.emit(self, pos)
	if GameEvents != null:
		GameEvents.tank_respawned.emit(self, pos)

func apply_network_respawn_fx(pos: Vector2) -> void:
	snap_network_position(pos)
	is_dead = false
	permanently_eliminated = false
	last_killer = null
	last_kill_was_mine = false
	last_kill_was_storm = false
	current_health = max_health
	shield = 0.0
	dash_stamina = max_dash_stamina
	mines_count = MAX_MINES
	cluster_mines_count = 0
	_mine_cooldown = 0.0
	multikill_count = 0
	_multikill_timer = 0.0
	is_dashing = false
	dash_requested = false
	velocity = Vector2.ZERO
	can_fire = true
	_fire_timer = 0.0
	
	# Restore collisions
	set_collision_layer_value(3, true)
	set_collision_mask_value(1, true)
	set_collision_mask_value(2, true)
	set_collision_mask_value(3, true)
	set_collision_mask_value(5, true)
	
	# Restore visuals
	if chassis_visual != null:
		chassis_visual.visible = true
	if turret_pivot != null:
		turret_pivot.visible = true
	if overhead_ui != null:
		overhead_ui.visible = true
		
	# Post-respawn invulnerability (1.5s)
	is_invulnerable = true
	_invulnerability_timer = INVULNERABILITY_DURATION
	if shield_aura != null:
		shield_aura.visible = true
		
	_active_powerups.clear()
	ricochet_shots = 0
	_revert_powerup_stats()
	_update_ui()

func _play_hit_flash() -> void:
	if chassis_visual != null:
		chassis_visual.modulate = Color(2.6, 2.6, 2.6, 1.0)
		var tween := create_tween()
		if tween != null:
			tween.tween_property(chassis_visual, "modulate", Color.WHITE, 0.08)

func apply_powerup(type: int, duration: float, value: float) -> void:
	if not network_authoritative or is_dead:
		return
	apply_network_powerup(type, duration, value, true)

func apply_network_powerup(type: int, duration: float, value: float, show_fx: bool = true) -> void:
	if is_dead:
		return
		
	var txt_parent := _get_fx_container() if show_fx else null
	match type:
		PowerUpType.HEALTH:
			current_health = min(max_health, current_health + value)
			if txt_parent != null:
				FloatingTextScript.spawn(txt_parent, global_position, "+%d HP" % int(value), Color(0.25, 1.0, 0.4), 16)
		PowerUpType.SHIELD:
			shield = min(max_shield, value)
			_active_powerups[PowerUpType.SHIELD] = { "time_left": duration, "duration": duration }
			if shield_aura != null:
				shield_aura.visible = true
			if txt_parent != null:
				FloatingTextScript.spawn(txt_parent, global_position, "+%d SHIELD" % int(value), Color(0.2, 0.85, 1.0), 16)
		PowerUpType.RAPID_FIRE:
			fire_cooldown = BASE_FIRE_COOLDOWN * 0.4 # -60% cooldown
			bullet_speed = BASE_BULLET_SPEED * 1.3  # +30% speed
			_active_powerups[PowerUpType.RAPID_FIRE] = { "time_left": duration, "duration": duration }
			if txt_parent != null:
				FloatingTextScript.spawn(txt_parent, global_position, "RAPID FIRE!", Color(1.0, 0.85, 0.2), 16)
		PowerUpType.RICOCHET:
			ricochet_shots = int(value)
			_active_powerups[PowerUpType.RICOCHET] = {
				"shots_left": ricochet_shots,
				"total_shots": int(value),
				"time_left": 999.0,
				"duration": 999.0
			}
			if txt_parent != null:
				FloatingTextScript.spawn(txt_parent, global_position, "+%d RICOCHET!" % ricochet_shots, Color(0.2, 0.95, 1.0), 16)
		PowerUpType.SPEED_BOOST:
			var was_boosting: bool = has_speed_boost
			_active_powerups[PowerUpType.SPEED_BOOST] = { "time_left": duration, "duration": duration }
			current_speed = BASE_SPEED * 2.0
			if txt_parent != null:
				FloatingTextScript.spawn(txt_parent, global_position, "SPEED x2 (MONSTER)!", Color(0.85, 1.0, 0.3), 16)
			if show_fx and SoundManagerScript != null:
				SoundManagerScript.play_pickup(global_position)
			_start_monster_bounce_music(not was_boosting)
		PowerUpType.CLUSTER_MINES:
			if mines_count > 0:
				cluster_mines_count = mines_count
				_active_powerups[PowerUpType.CLUSTER_MINES] = {
					"shots_left": cluster_mines_count,
					"total_shots": cluster_mines_count,
					"time_left": 999.0,
					"duration": 999.0
				}
				if txt_parent != null:
					FloatingTextScript.spawn(txt_parent, global_position, "MINAS RACIMO (%d/3)!" % cluster_mines_count, Color(1.0, 0.50, 0.14), 16)
			else:
				mines_count = MAX_MINES
				cluster_mines_count = 0
				_active_powerups.erase(PowerUpType.CLUSTER_MINES)
				if txt_parent != null:
					FloatingTextScript.spawn(txt_parent, global_position, "+3 MINAS!", Color(1.0, 0.85, 0.25), 16)
			
	if show_fx and type != PowerUpType.SPEED_BOOST and SoundManagerScript != null:
		SoundManagerScript.play_pickup(global_position)
	_update_ui()

func _process_powerups(delta: float) -> void:
	var expired_types: Array[int] = []
	for p_type in _active_powerups.keys():
		_active_powerups[p_type]["time_left"] -= delta
		if _active_powerups[p_type]["time_left"] <= 0.0:
			expired_types.append(p_type)
			
	for p_type in expired_types:
		_active_powerups.erase(p_type)
		match p_type:
			PowerUpType.SHIELD:
				shield = 0.0
				if shield_aura != null and not is_invulnerable:
					shield_aura.visible = false
			PowerUpType.RAPID_FIRE:
				fire_cooldown = BASE_FIRE_COOLDOWN
				bullet_speed = BASE_BULLET_SPEED
			PowerUpType.SPEED_BOOST:
				current_speed = BASE_SPEED
				_reset_monster_bounce()
		if network_authoritative:
			network_powerup_synced.emit(self, p_type, 0.0, 0.0, true)
		if GameEvents != null:
			GameEvents.powerup_expired.emit(self, p_type)

func _revert_powerup_stats() -> void:
	current_speed = BASE_SPEED
	fire_cooldown = BASE_FIRE_COOLDOWN
	bullet_speed = BASE_BULLET_SPEED
	_reset_monster_bounce()

func _process_movement_audio() -> void:
	var spd: float = velocity.length()
	if is_dead or spd <= 18.0 or SoundManagerScript == null:
		_stop_movement_audio()
		return
	var mm := get_tree().get_first_node_in_group("match_manager") if get_tree() != null else null
	if mm != null and mm.get("is_match_ended") == true:
		_stop_movement_audio()
		return
		
	var is_local_focus: bool = is_player
	if not is_local_focus and get_tree() != null:
		var players := get_tree().get_nodes_in_group("player")
		if not players.is_empty() and is_instance_valid(players[0]):
			var p := players[0]
			if p.get("is_spectating") == true and p.get("spectated_tank") == self:
				is_local_focus = true
				
	var sm = SoundManagerScript.instance
	if not is_local_focus and sm != null:
		if not sm.is_within_hearing_range(global_position, SoundManagerScript.HEARING_RADIUS_MOVEMENT):
			_stop_movement_audio()
			return
			
	if _move_audio_player == null:
		var m_stream: AudioStream = SoundManagerScript.get_tank_move_stream()
		if m_stream == null:
			return
		SoundManagerScript._ensure_audio_buses()
		_move_audio_player = AudioStreamPlayer2D.new()
		_move_audio_player.name = "TankMoveAudioPlayer"
		_move_audio_player.bus = &"SFX" if AudioServer.get_bus_index("SFX") != -1 else &"Master"
		_move_audio_player.max_distance = 10000.0
		_move_audio_player.attenuation = 0.0001
		_move_audio_player.stream = m_stream
		add_child(_move_audio_player)
		
	_move_audio_player.panning_strength = 0.0 if is_local_focus else 0.85
	var speed_gain: float = clampf(spd / 130.0, 0.15, 1.0)
	var base_db: float = MOVE_AUDIO_LOCAL_DB if is_local_focus else MOVE_AUDIO_REMOTE_DB
	if has_speed_boost:
		base_db -= 5.0
	var final_db: float = base_db + linear_to_db(speed_gain)
	if not is_local_focus and sm != null:
		final_db = sm.compute_spatial_volume_db(global_position, base_db, SoundManagerScript.HEARING_RADIUS_MOVEMENT) + linear_to_db(speed_gain)
	_move_audio_player.volume_db = final_db
	
	var id_jitter: float = float(absi(get_instance_id()) % 9 - 4) * 0.008
	var target_pitch: float = lerpf(0.86, 1.02, clampf(spd / BASE_SPEED, 0.0, 1.0)) + id_jitter
	if is_dashing:
		target_pitch += 0.14
	_move_audio_player.pitch_scale = clampf(target_pitch, 0.80, 1.25)
	
	if is_inside_tree() and DisplayServer.get_name() != "headless" and not _move_audio_player.playing:
		_move_audio_player.play()

func _stop_movement_audio() -> void:
	if _move_audio_player != null and is_instance_valid(_move_audio_player):
		if _move_audio_player.playing:
			_move_audio_player.stop()
		_move_audio_player.volume_db = -80.0

func _start_monster_bounce_music(restart_track: bool = true) -> void:
	if restart_track:
		_monster_bounce_time = 0.0
	if SoundManagerScript == null:
		return
	var stream: AudioStream = SoundManagerScript.get_monster_bounce_music_stream()
	if stream == null:
		return
	if _monster_music_player == null:
		SoundManagerScript._ensure_audio_buses()
		_monster_music_player = AudioStreamPlayer2D.new()
		_monster_music_player.name = "MonsterBounceMusicPlayer"
		_monster_music_player.bus = &"Music" if AudioServer.get_bus_index("Music") != -1 else &"Master"
		_monster_music_player.max_distance = 10000.0
		_monster_music_player.attenuation = 0.0001
		add_child(_monster_music_player)
	_monster_music_player.panning_strength = 0.0 if is_player else 0.85
	_monster_music_player.stream = stream
	_update_monster_music_volume()
	if is_inside_tree() and DisplayServer.get_name() != "headless":
		if restart_track or not _monster_music_player.playing:
			_monster_music_player.play(0.0)

func _update_monster_music_volume() -> void:
	if _monster_music_player == null:
		return
	var time_left: float = 15.0
	if _active_powerups.has(PowerUpType.SPEED_BOOST):
		time_left = float(_active_powerups[PowerUpType.SPEED_BOOST].get("time_left", 15.0))
	var fade_gain: float = clampf(time_left / 0.8, 0.015, 1.0)
	var fade_db: float = linear_to_db(fade_gain)
	var base_db: float = 1.5 if is_player else -1.5
	var target_db: float = base_db + fade_db
	if not is_player and SoundManagerScript != null and SoundManagerScript.instance != null:
		var sm = SoundManagerScript.instance
		if not sm.is_within_hearing_range(global_position, MONSTER_AUDIO_RANGE):
			target_db = -80.0
		else:
			target_db = sm.compute_spatial_volume_db(global_position, base_db, MONSTER_AUDIO_RANGE) + fade_db
	_monster_music_player.volume_db = target_db

func _process_monster_bounce(delta: float) -> void:
	if not has_speed_boost or is_dead:
		if monster_bounce_offset_y != 0.0 or monster_squash_scale != Vector2.ONE or (_monster_music_player != null and _monster_music_player.playing):
			_reset_monster_bounce()
		return
		
	_monster_bounce_time += delta
	_update_monster_music_volume()
	
	var sync_t: float = _monster_bounce_time
	if _monster_music_player != null and _monster_music_player.playing:
		sync_t = _monster_music_player.get_playback_position() + AudioServer.get_time_since_last_mix()
		
	var beat_pos: float = sync_t * MONSTER_BOUNCE_BPS
	var phase: float = fmod(beat_pos, 1.0)
	var intensity: float = lerpf(0.55, 0.88, clampf(sync_t / MONSTER_DROP_TIME, 0.0, 1.0)) if sync_t < MONSTER_DROP_TIME else 1.0
	
	var hop_y: float = 0.0
	var squash_x: float = 1.0
	var squash_y: float = 1.0
	if phase < 0.17:
		var c_t: float = phase / 0.17
		var comp: float = sin(c_t * PI) * intensity
		hop_y = -2.5 * comp
		squash_x = 1.0 + 0.25 * comp
		squash_y = 1.0 - 0.23 * comp
	else:
		var air_t: float = (phase - 0.17) / 0.83
		var arc: float = sin(air_t * PI) * intensity
		hop_y = arc * MONSTER_BOUNCE_HEIGHT
		var stretch: float = arc * 0.16
		squash_x = 1.0 - stretch * 0.85
		squash_y = 1.0 + stretch * 1.12
		
	var rock_angle: float = sin(beat_pos * PI) * deg_to_rad(4.5) * intensity
	monster_bounce_offset_y = -hop_y
	monster_squash_scale = Vector2(squash_x, squash_y)
	
	var screen_bounce := Transform2D(Vector2(squash_x, 0.0), Vector2(0.0, squash_y), Vector2(0.0, -hop_y))
	if chassis_visual != null:
		chassis_visual.transform = screen_bounce * Transform2D(_chassis_angle + rock_angle, Vector2.ZERO)
	if turret_visual != null and turret_pivot != null:
		var p_rot := Transform2D(turret_pivot.rotation, Vector2.ZERO)
		turret_visual.transform = p_rot.affine_inverse() * (screen_bounce * Transform2D(turret_pivot.rotation + rock_angle * 0.5, Vector2.ZERO))
	if shield_aura != null:
		shield_aura.position = Vector2(0.0, -hop_y)
	if overhead_ui != null:
		overhead_ui.position = Vector2(0.0, -45.0 - maxf(0.0, hop_y) * 0.55)
	queue_redraw()

func _reset_monster_bounce() -> void:
	_monster_bounce_time = 0.0
	monster_bounce_offset_y = 0.0
	monster_squash_scale = Vector2.ONE
	if _monster_music_player != null and is_instance_valid(_monster_music_player):
		_monster_music_player.stop()
	if chassis_visual != null:
		chassis_visual.transform = Transform2D(_chassis_angle, Vector2.ZERO)
	if turret_visual != null:
		turret_visual.transform = Transform2D.IDENTITY
	if shield_aura != null:
		shield_aura.position = Vector2.ZERO
	if overhead_ui != null:
		overhead_ui.position = Vector2(0.0, -45.0)
	queue_redraw()

func _draw() -> void:
	if not has_speed_boost or is_dead:
		return
	var hop_ratio: float = clampf(-monster_bounce_offset_y / MONSTER_BOUNCE_HEIGHT, 0.0, 1.0)
	var shadow_scale_x: float = lerpf(1.16, 0.68, hop_ratio)
	var shadow_scale_y: float = lerpf(0.62, 0.38, hop_ratio)
	var shadow_alpha: float = lerpf(0.46, 0.20, hop_ratio)
	draw_set_transform(Vector2(0.0, 11.0), 0.0, Vector2(shadow_scale_x, shadow_scale_y))
	draw_circle(Vector2.ZERO, 25.0, Color(0.02, 0.03, 0.05, shadow_alpha))
	var sync_t: float = _monster_bounce_time
	if _monster_music_player != null and _monster_music_player.playing:
		sync_t = _monster_music_player.get_playback_position() + AudioServer.get_time_since_last_mix()
	var phase: float = fmod(sync_t * MONSTER_BOUNCE_BPS, 1.0)
	if phase < 0.26:
		var ring_t: float = phase / 0.26
		var ring_r: float = lerpf(22.0, 38.0, ring_t)
		var ring_a: float = (1.0 - ring_t) * 0.55
		draw_arc(Vector2.ZERO, ring_r, 0.0, TAU, 28, Color(0.65, 1.0, 0.22, ring_a), 2.5)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _update_ui() -> void:
	if hp_bar != null:
		hp_bar.max_value = max_health
		hp_bar.value = current_health
	if shield_bar != null:
		shield_bar.max_value = max_shield
		shield_bar.value = shield
		shield_bar.visible = (shield > 0.0)
	if name_label != null and name_label.text != tank_name:
		name_label.text = tank_name

func _spawn_death_fx() -> void:
	var explosion := CPUParticles2D.new()
	explosion.emitting = true
	explosion.one_shot = true
	explosion.explosiveness = 1.0
	explosion.lifetime = 0.6
	explosion.amount = 32
	explosion.spread = 180.0
	explosion.initial_velocity_min = 80.0
	explosion.initial_velocity_max = 240.0
	explosion.gravity = Vector2.ZERO
	explosion.scale_amount_min = 4.0
	explosion.scale_amount_max = 8.0
	explosion.color = Color(1.0, 0.4, 0.1, 1.0)
	explosion.global_position = global_position
	
	var parent_node := _get_fx_container()
	if parent_node != null:
		parent_node.add_child(explosion)
		if get_tree() != null:
			var timer := get_tree().create_timer(0.8)
			timer.timeout.connect(explosion.queue_free)
