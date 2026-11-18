# res://Scripts/Entities/player_tank.gd
class_name PlayerTank extends Tank

## Player-controlled Tank subclass.
## Reads WASD/arrow locomotion inputs, rotates turret tracking the mouse cursor,
## fires ballistic projectiles on left click or space, and supports Sudden Death
## Spectator Mode (cycling between surviving players when respawns are disabled).

signal local_mine_requested(aim_angle: float)

@onready var camera: Camera2D = $Camera2D

@export var is_local_controlled: bool = true
var local_wants_shoot: bool = false

var _trauma: float = 0.0
const MAX_SHAKE_OFFSET: float = 14.0
const TRAUMA_DECAY: float = 1.6

# Sudden Death Spectator State
var is_spectating: bool = false
var spectated_tank: Node2D = null
var spectate_index: int = 0

func _ready() -> void:
	if is_local_controlled:
		is_player = true
		if tank_name == "Tank":
			tank_name = "Player"
		add_to_group("player")
	else:
		is_player = false
		if is_in_group("player"):
			remove_from_group("player")
		if camera != null:
			camera.enabled = false
	super._ready()
	if is_local_controlled and DisplayServer.get_name() != "headless":
		if camera != null:
			camera.enabled = true
	elif camera != null:
		camera.enabled = false
	if is_local_controlled and GameEvents != null:
		GameEvents.screen_shake_requested.connect(add_trauma)
		if not GameEvents.match_started.is_connected(_on_match_started_reset_spectator):
			GameEvents.match_started.connect(_on_match_started_reset_spectator)
		if not GameEvents.match_ended.is_connected(_on_match_ended_stop_spectator):
			GameEvents.match_ended.connect(_on_match_ended_stop_spectator)

func _on_match_started_reset_spectator(_duration: float) -> void:
	exit_spectator_mode()

func _on_match_ended_stop_spectator(_leaderboard: Array[Dictionary]) -> void:
	# Keep camera at final showdown position until restart, but stop active input cycling
	is_spectating = false

func respawn(pos: Vector2) -> void:
	exit_spectator_mode()
	super.respawn(pos)

func add_trauma(amount: float) -> void:
	_trauma = clampf(_trauma + amount, 0.0, 1.0)

func _process(_delta: float) -> void:
	if is_spectating and camera != null and is_instance_valid(spectated_tank) and spectated_tank.get("is_dead") != true:
		if not camera.top_level:
			camera.top_level = true
		camera.global_position = spectated_tank.global_position

func _physics_process(delta: float) -> void:
	if not is_local_controlled or is_network_puppet:
		local_wants_shoot = false
		super._physics_process(delta)
		return

	if not is_dead:
		if is_spectating:
			exit_spectator_mode()
		var menu_paused := false
		if not network_authoritative and get_tree() != null:
			var pm := get_tree().get_first_node_in_group("pause_menu")
			if pm != null and pm.get("is_open") == true:
				menu_paused = true
		if not controls_locked and not menu_paused:
			_handle_player_input()
		else:
			if menu_paused:
				set_chassis_input(Vector2.ZERO)
				set_dash_input(false)
			local_wants_shoot = false
	else:
		local_wants_shoot = false
		_process_spectator()
		
	# Process screen shake trauma
	if _trauma > 0.0:
		_trauma = maxf(0.0, _trauma - TRAUMA_DECAY * delta)
		var shake := _trauma * _trauma
		if camera != null:
			camera.offset = Vector2(
				randf_range(-1.0, 1.0) * MAX_SHAKE_OFFSET * shake,
				randf_range(-1.0, 1.0) * MAX_SHAKE_OFFSET * shake
			)
	elif camera != null and camera.offset != Vector2.ZERO:
		camera.offset = Vector2.ZERO
		
	super._physics_process(delta)

func _is_sudden_death_no_respawn() -> bool:
	if permanently_eliminated:
		return true
	if get_tree() == null:
		return false
	var mm := get_tree().get_first_node_in_group("match_manager")
	return mm != null and mm.get("no_respawns") == true

func _is_match_concluded() -> bool:
	if get_tree() == null:
		return false
	var mm := get_tree().get_first_node_in_group("match_manager")
	return mm != null and mm.get("is_match_ended") == true

func get_living_spectate_targets() -> Array[Node2D]:
	var targets: Array[Node2D] = []
	if get_tree() == null:
		return targets
	for t in get_tree().get_nodes_in_group("tanks"):
		if is_instance_valid(t) and t != self and t is Node2D and t.get("is_dead") != true:
			targets.append(t as Node2D)
	return targets

func _get_valid_killer(tank_node: Variant) -> Node2D:
	if not is_instance_valid(tank_node) or not ("last_killer" in tank_node):
		return null
	var raw_killer: Variant = tank_node.get("last_killer")
	if raw_killer != null and is_instance_valid(raw_killer) and raw_killer is Node2D:
		return raw_killer as Node2D
	return null

func enter_spectator_mode() -> void:
	if is_spectating or _is_match_concluded():
		return
	var targets := get_living_spectate_targets()
	if targets.is_empty():
		return
	is_spectating = true
	if camera != null and not camera.top_level:
		var start_pos := global_position
		camera.top_level = true
		camera.global_position = start_pos
	# Lock onto our killer first if alive, otherwise the first surviving combatant
	var preferred: Node2D = null
	var valid_killer := _get_valid_killer(self)
	if valid_killer != null and targets.has(valid_killer):
		preferred = valid_killer
	else:
		preferred = targets[0]
	set_spectate_target(preferred)

func exit_spectator_mode() -> void:
	is_spectating = false
	spectated_tank = null
	spectate_index = 0
	if camera != null:
		camera.top_level = false
		camera.position = Vector2.ZERO
		camera.reset_smoothing()
	if GameEvents != null:
		GameEvents.spectate_target_changed.emit(null, 0, 0)

func set_spectate_target(target: Node2D) -> Node2D:
	var targets := get_living_spectate_targets()
	if targets.is_empty():
		spectated_tank = null
		spectate_index = 0
		if GameEvents != null:
			GameEvents.spectate_target_changed.emit(null, 0, 0)
		return null
	var idx := targets.find(target)
	if idx == -1:
		idx = clampi(spectate_index, 0, targets.size() - 1)
	spectate_index = idx
	spectated_tank = targets[spectate_index]
	if camera != null and is_instance_valid(spectated_tank):
		if not camera.top_level:
			camera.top_level = true
		camera.global_position = spectated_tank.global_position
	if GameEvents != null:
		GameEvents.spectate_target_changed.emit(spectated_tank, spectate_index + 1, targets.size())
	return spectated_tank

func cycle_spectate_target(step: int = 1) -> Node2D:
	var targets := get_living_spectate_targets()
	if targets.is_empty():
		spectated_tank = null
		spectate_index = 0
		return null
	if not is_spectating:
		enter_spectator_mode()
		targets = get_living_spectate_targets()
		if targets.is_empty():
			return null
	var cur_idx := targets.find(spectated_tank)
	var next_idx: int = 0
	if cur_idx == -1:
		next_idx = 0 if step >= 0 else (targets.size() - 1)
	else:
		next_idx = posmod(cur_idx + step, targets.size())
	return set_spectate_target(targets[next_idx])

func _process_spectator() -> void:
	if _is_match_concluded():
		return
	if not _is_sudden_death_no_respawn():
		return
	if not is_spectating:
		enter_spectator_mode()
		return
	var targets := get_living_spectate_targets()
	if targets.is_empty():
		spectated_tank = null
		return
	# Auto-advance if currently spectated survivor gets eliminated
	if not is_instance_valid(spectated_tank) or spectated_tank.get("is_dead") == true:
		var killer_of_spec := _get_valid_killer(spectated_tank)
		if killer_of_spec != null and targets.has(killer_of_spec):
			set_spectate_target(killer_of_spec)
		else:
			var fallback_idx := clampi(spectate_index, 0, targets.size() - 1)
			set_spectate_target(targets[fallback_idx])
	else:
		spectate_index = targets.find(spectated_tank)
		if camera != null:
			if not camera.top_level:
				camera.top_level = true
			camera.global_position = spectated_tank.global_position

func _unhandled_input(event: InputEvent) -> void:
	if not is_local_controlled or not is_spectating or _is_match_concluded():
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed:
			if mb.button_index == MOUSE_BUTTON_LEFT:
				cycle_spectate_target(1)
				if get_viewport() != null:
					get_viewport().set_input_as_handled()
			elif mb.button_index == MOUSE_BUTTON_RIGHT:
				cycle_spectate_target(-1)
				if get_viewport() != null:
					get_viewport().set_input_as_handled()
	elif event is InputEventKey:
		var ke := event as InputEventKey
		if ke.pressed and not ke.echo:
			var code: int = ke.keycode if ke.keycode != 0 else ke.physical_keycode
			if code in [KEY_D, KEY_RIGHT, KEY_E, KEY_TAB, KEY_SPACE]:
				cycle_spectate_target(1)
				if get_viewport() != null:
					get_viewport().set_input_as_handled()
			elif code in [KEY_A, KEY_LEFT, KEY_Q]:
				cycle_spectate_target(-1)
				if get_viewport() != null:
					get_viewport().set_input_as_handled()

func _handle_player_input() -> void:
	# WASD / Arrow omnidirectional movement
	var move_dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	set_chassis_input(move_dir)
	
	# Turret aims continuously toward global mouse cursor
	var mouse_pos := get_global_mouse_position()
	set_turret_target(mouse_pos)
	
	# Left-click or space triggers shoot()
	local_wants_shoot = Input.is_action_pressed("shoot")
	if local_wants_shoot and network_authoritative:
		shoot()
		
	# "Q" throws a parabolic stealth proximity mine toward aimed direction
	if Input.is_action_just_pressed("throw_mine"):
		if network_authoritative:
			throw_mine()
		else:
			var aim_ang := turret_pivot.global_rotation if turret_pivot != null else target_aim_angle
			local_mine_requested.emit(aim_ang)
		
	# Dash on Shift or Right-Click (as in original prototype)
	var wants_dash: bool = (
		Input.is_action_pressed("dash") or
		Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) or
		Input.is_key_pressed(KEY_SHIFT)
	)
	set_dash_input(wants_dash)
