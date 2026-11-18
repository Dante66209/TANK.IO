# res://Scripts/Core/mortar_manager.gd
class_name MortarManager extends Node

const SoundManagerScript = preload("res://Scripts/Core/sound_manager.gd")
const MortarTargetScript = preload("res://Scripts/Entities/mortar_target.gd")

## Dynamic Mortar Artillery Event Coordinator for TANK.IO.
## Triggers 2-3 times per match for 25 seconds with a cooldown refresh period.
## Sounds an emergency siren alarm, announces in HUD, and rains mortar strikes across the battlefield.

@export var event_duration: float = 25.0
@export var min_cooldown: float = 28.0
@export var max_cooldown: float = 42.0
@export var max_events_per_match: int = 3
@export var mortar_target_script: GDScript = preload("res://Scripts/Entities/mortar_target.gd")

signal network_mortar_state_changed(active: bool, duration: float)
signal network_mortar_strike_spawned(pos: Vector2)

var is_network_puppet: bool = false
var is_event_active: bool = false
var event_time_remaining: float = 0.0
var events_triggered: int = 0
var _cooldown_timer: float = 30.0 # Initial grace period before first event
var _strike_timer: float = 0.0

func _ready() -> void:
	add_to_group("mortar_manager")
	_cooldown_timer = randf_range(min_cooldown, max_cooldown)
	if GameEvents != null:
		GameEvents.match_started.connect(_on_match_started)
		GameEvents.match_ended.connect(_on_match_ended)

func _exit_tree() -> void:
	if SoundManagerScript != null:
		SoundManagerScript.stop_bombardment()

func _on_match_started(_duration: float) -> void:
	reset()

func _on_match_ended(_leaderboard: Array[Dictionary]) -> void:
	if is_event_active:
		end_event()
	elif SoundManagerScript != null:
		SoundManagerScript.stop_bombardment()

func reset() -> void:
	if SoundManagerScript != null:
		SoundManagerScript.stop_bombardment()
	is_event_active = false
	event_time_remaining = 0.0
	events_triggered = 0
	_cooldown_timer = randf_range(min_cooldown, max_cooldown)
	_strike_timer = 0.0

func enter_network_puppet_mode() -> void:
	is_network_puppet = true
	reset()

func apply_network_mortar_state(active: bool, duration: float) -> void:
	if active:
		if not is_event_active:
			is_event_active = true
			event_time_remaining = duration
			events_triggered += 1
			if SoundManagerScript != null:
				SoundManagerScript.play_bombardment()
			if GameEvents != null:
				GameEvents.mortar_event_started.emit(duration)
				GameEvents.kill_feed_announced.emit("¡ALERTA DE MORTEROS! BUSCA COBERTURA (25s)", Color(1.0, 0.3, 0.2))
	else:
		if is_event_active:
			is_event_active = false
			event_time_remaining = 0.0
			if SoundManagerScript != null:
				SoundManagerScript.stop_bombardment()
			if GameEvents != null:
				GameEvents.mortar_event_ended.emit()
				GameEvents.kill_feed_announced.emit("BARRERA DE MORTEROS FINALIZADA", Color(0.3, 0.9, 0.5))

func spawn_network_mortar_strike(target_pos: Vector2) -> Node2D:
	var target_node: Node2D = MortarTargetScript.new() as Node2D
	target_node.global_position = target_pos
	if "is_network_puppet" in target_node:
		target_node.set("is_network_puppet", true)
	var entities := get_tree().get_first_node_in_group("entities") if get_tree() != null else null
	if entities != null:
		entities.add_child(target_node)
	else:
		add_child(target_node)
	return target_node

func _process(delta: float) -> void:
	if is_network_puppet:
		if is_event_active:
			event_time_remaining = maxf(0.0, event_time_remaining - delta)
			if SoundManagerScript != null:
				SoundManagerScript.update_bombardment_volume(event_time_remaining, event_duration)
			if GameEvents != null:
				GameEvents.mortar_event_tick.emit(event_time_remaining, event_duration)
		return
	var mm := get_tree().get_first_node_in_group("match_manager") if get_tree() != null else null
	if mm != null and mm.get("is_match_active") == false:
		return
	if is_event_active:
		_process_active_event(delta)
	else:
		_process_cooldown(delta)

func _process_cooldown(delta: float) -> void:
	if events_triggered >= max_events_per_match:
		return
		
	_cooldown_timer -= delta
	if _cooldown_timer <= 0.0:
		start_event()

func start_event() -> void:
	if is_event_active:
		return
		
	is_event_active = true
	event_time_remaining = event_duration
	events_triggered += 1
	_strike_timer = 0.3 # Initial strike drops almost immediately after siren
	
	# Realistic Air-Raid & Bombardment Audio + Global Signals
	if SoundManagerScript != null:
		SoundManagerScript.play_bombardment()
		
	if GameEvents != null:
		GameEvents.mortar_event_started.emit(event_duration)
		GameEvents.kill_feed_announced.emit("¡ALERTA DE MORTEROS! BUSCA COBERTURA (25s)", Color(1.0, 0.3, 0.2))
	network_mortar_state_changed.emit(true, event_duration)

func end_event() -> void:
	if not is_event_active:
		return
		
	is_event_active = false
	event_time_remaining = 0.0
	_cooldown_timer = randf_range(min_cooldown, max_cooldown)
	if SoundManagerScript != null:
		SoundManagerScript.stop_bombardment()
	
	if GameEvents != null:
		GameEvents.mortar_event_ended.emit()
		GameEvents.kill_feed_announced.emit("BARRERA DE MORTEROS FINALIZADA", Color(0.3, 0.9, 0.5))
	network_mortar_state_changed.emit(false, 0.0)

func _process_active_event(delta: float) -> void:
	event_time_remaining -= delta
	if SoundManagerScript != null:
		SoundManagerScript.update_bombardment_volume(event_time_remaining, event_duration)
	
	if GameEvents != null:
		GameEvents.mortar_event_tick.emit(event_time_remaining, event_duration)
		
	if event_time_remaining <= 0.0:
		end_event()
		return
		
	_strike_timer -= delta
	if _strike_timer <= 0.0:
		_strike_timer = randf_range(0.65, 1.05)
		spawn_mortar_strike()
		if randf() < 0.70: # 70% chance for simultaneous double strike
			spawn_mortar_strike()
		if randf() < 0.35: # 35% chance for triple strike barrage
			spawn_mortar_strike()

func spawn_mortar_strike() -> Node2D:
	var target_pos := _calculate_strike_position()
	
	var target_node: Node2D = MortarTargetScript.new() as Node2D
	target_node.global_position = target_pos
	
	var entities := get_tree().get_first_node_in_group("entities") if get_tree() != null else null
	if entities != null:
		entities.add_child(target_node)
	else:
		add_child(target_node)
	network_mortar_strike_spawned.emit(target_pos)
		
	return target_node

func _calculate_strike_position() -> Vector2:
	# 65% chance near an active tank for high engagement/evasion gameplay
	var tanks := get_tree().get_nodes_in_group("tanks") if get_tree() != null else []
	var living_tanks: Array[Node2D] = []
	for t in tanks:
		if is_instance_valid(t) and t is Node2D:
			var dead_val: bool = t.get("is_dead") if "is_dead" in t else false
			if not dead_val:
				living_tanks.append(t as Node2D)
				
	var max_bound: float = 3000.0
	var mm := get_tree().get_first_node_in_group("match_manager") if get_tree() != null else null
	if mm != null and mm.get("is_sudden_death") == true:
		var sz_val = mm.get("safe_zone_radius")
		if sz_val != null:
			max_bound = minf(max_bound, maxf(350.0, float(sz_val) * 0.9))
		
	if not living_tanks.is_empty() and randf() < 0.65:
		var chosen_tank: Node2D = living_tanks[randi() % living_tanks.size()]
		var offset := Vector2(randf_range(-240.0, 240.0), randf_range(-240.0, 240.0))
		var pos := chosen_tank.global_position + offset
		return pos.clamp(Vector2(-max_bound, -max_bound), Vector2(max_bound, max_bound))
		
	# Fallback: random arena strike
	return Vector2(randf_range(-max_bound, max_bound), randf_range(-max_bound, max_bound))
