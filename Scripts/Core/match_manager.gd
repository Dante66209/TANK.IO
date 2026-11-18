# res://Scripts/Core/match_manager.gd
class_name MatchManager extends Node

const SoundManagerScript = preload("res://Scripts/Core/sound_manager.gd")

## Match Loop Controller, Scoring, Sudden Death Closing Zone, and Dynamic Leaderboard (R8).
## Manages 180s match countdown, last-30s closing storm zone (no respawns),
## combatant registry, scoring rules, dynamic leaderboard updates, and match termination.

@export var match_duration: float = 180.0
@export var sudden_death_time: float = 30.0
@export var max_zone_radius: float = 4550.0
@export var min_zone_radius: float = 360.0
@export var storm_damage_per_sec: float = 16.0

signal network_leaderboard_changed(entries: Array)
signal network_match_state_changed(state: Dictionary)

var is_network_puppet: bool = false
var time_remaining: float = 180.0
var is_match_active: bool = false
var is_match_ended: bool = false
var is_sudden_death: bool = false
var no_respawns: bool = false
var safe_zone_center: Vector2 = Vector2.ZERO
var safe_zone_radius: float = 4550.0
var _storm_tick_timer: float = 0.0

## Dictionary of combatants: combatant_id -> Dictionary
var _combatants: Dictionary = {}
var _next_id: int = 1

func _ready() -> void:
	add_to_group("match_manager")
	time_remaining = match_duration
	safe_zone_radius = max_zone_radius
	_connect_events()
	_register_scene_tanks()

func _exit_tree() -> void:
	if SoundManagerScript != null:
		SoundManagerScript.stop_zone_closing()

func _connect_events() -> void:
	if GameEvents != null:
		if not GameEvents.tank_killed.is_connected(_on_tank_killed):
			GameEvents.tank_killed.connect(_on_tank_killed)
		if not GameEvents.barrel_destroyed.is_connected(_on_barrel_destroyed):
			GameEvents.barrel_destroyed.connect(_on_barrel_destroyed)
		if not GameEvents.powerup_collected.is_connected(_on_powerup_collected):
			GameEvents.powerup_collected.connect(_on_powerup_collected)

func _register_scene_tanks() -> void:
	var tanks := get_tree().get_nodes_in_group("tanks")
	for t in tanks:
		if is_instance_valid(t) and not t.is_queued_for_deletion() and t is Node2D:
			var t_name: String = t.get("tank_name") if "tank_name" in t else t.name
			var is_p: bool = t.get("is_player") if "is_player" in t else false
			register_combatant(t as Node2D, t_name, is_p)

func sync_scene_combatants() -> void:
	_combatants.clear()
	_next_id = 1
	_register_scene_tanks()
	if GameEvents != null:
		GameEvents.leaderboard_updated.emit(get_leaderboard())

func start_match(duration: float = -1.0) -> void:
	if duration > 0.0:
		match_duration = duration
	if SoundManagerScript != null:
		SoundManagerScript.stop_zone_closing()
	time_remaining = match_duration
	is_match_active = true
	is_match_ended = false
	is_sudden_death = false
	no_respawns = false
	safe_zone_radius = max_zone_radius
	_storm_tick_timer = 0.0
	
	if GameEvents != null:
		GameEvents.zone_updated.emit(safe_zone_center, safe_zone_radius, max_zone_radius, false)
		GameEvents.match_started.emit(match_duration)
		GameEvents.leaderboard_updated.emit(get_leaderboard())
	_emit_network_match_state()

func start_sudden_death() -> void:
	if is_sudden_death or is_match_ended:
		return
	is_sudden_death = true
	no_respawns = true
	safe_zone_radius = max_zone_radius
	_storm_tick_timer = 0.45
	
	if SoundManagerScript != null:
		SoundManagerScript.play_zone_closing()
		
	if GameEvents != null:
		GameEvents.sudden_death_started.emit()
		GameEvents.zone_updated.emit(safe_zone_center, safe_zone_radius, max_zone_radius, true)
		GameEvents.kill_feed_announced.emit("¡CIERRE DE ZONA! ¡RESPAWNS DESACTIVADOS!", Color(1.0, 0.22, 0.38))
	_emit_network_match_state()

func enter_network_puppet_mode() -> void:
	is_network_puppet = true
	if GameEvents != null:
		if GameEvents.tank_killed.is_connected(_on_tank_killed):
			GameEvents.tank_killed.disconnect(_on_tank_killed)
		if GameEvents.barrel_destroyed.is_connected(_on_barrel_destroyed):
			GameEvents.barrel_destroyed.disconnect(_on_barrel_destroyed)
		if GameEvents.powerup_collected.is_connected(_on_powerup_collected):
			GameEvents.powerup_collected.disconnect(_on_powerup_collected)

func _physics_process(delta: float) -> void:
	if is_network_puppet or not is_match_active or is_match_ended:
		return
		
	time_remaining = maxf(0.0, time_remaining - delta)
	
	# Enter Sudden Death closing zone in the final 30 seconds of full matches
	if not is_sudden_death and match_duration > sudden_death_time and time_remaining <= sudden_death_time and time_remaining > 0.0:
		start_sudden_death()
		
	if is_sudden_death:
		_process_sudden_death(delta)
		
	if GameEvents != null:
		GameEvents.match_tick.emit(time_remaining)
		
	if is_match_ended:
		return
		
	if time_remaining <= 0.0:
		end_match()

func _process_sudden_death(delta: float) -> void:
	var zone_window: float = maxf(0.1, minf(sudden_death_time, match_duration))
	var ratio_left: float = clampf(time_remaining / zone_window, 0.0, 1.0)
	safe_zone_radius = lerpf(min_zone_radius, max_zone_radius, ratio_left)
	if SoundManagerScript != null:
		SoundManagerScript.update_zone_closing_volume(time_remaining)
	
	if GameEvents != null:
		GameEvents.zone_updated.emit(safe_zone_center, safe_zone_radius, max_zone_radius, true)
		
	_storm_tick_timer -= delta
	if _storm_tick_timer <= 0.0:
		_storm_tick_timer = 0.5
		var tick_dmg: float = storm_damage_per_sec * 0.5
		if get_tree() != null:
			for t in get_tree().get_nodes_in_group("tanks"):
				if is_instance_valid(t) and t is Node2D and t.get("is_dead") != true:
					var d: float = (t as Node2D).global_position.distance_to(safe_zone_center)
					if d > safe_zone_radius and t.has_method("take_damage"):
						if "_incoming_storm_hit" in t:
							t.set("_incoming_storm_hit", true)
						t.take_damage(tick_dmg, null, false)
						
	_check_sudden_death_survivors()

func _check_sudden_death_survivors() -> void:
	if not is_sudden_death or is_match_ended:
		return
	if _combatants.size() < 2:
		return
	var valid_registered := 0
	var living_count := 0
	for id in _combatants.keys():
		var t_node = _combatants[id]["node"]
		if is_instance_valid(t_node):
			valid_registered += 1
			if t_node.get("is_dead") != true:
				living_count += 1
	if valid_registered >= 2 and living_count <= 1:
		end_match()

func end_match() -> void:
	if is_match_ended:
		return
	is_match_ended = true
	is_match_active = false
	time_remaining = 0.0
	if SoundManagerScript != null:
		SoundManagerScript.stop_zone_closing()
	
	# Freeze tanks and player inputs
	var tanks := get_tree().get_nodes_in_group("tanks")
	for t in tanks:
		if is_instance_valid(t):
			if t.has_method("set_chassis_input"):
				t.set_chassis_input(Vector2.ZERO)
			if "can_fire" in t:
				t.can_fire = false
			if "velocity" in t:
				t.velocity = Vector2.ZERO
				
	var lb := get_leaderboard()
	if GameEvents != null:
		GameEvents.match_ended.emit(lb)
	_emit_network_match_state()

func restart_match() -> void:
	if SoundManagerScript != null:
		SoundManagerScript.stop_zone_closing()
	time_remaining = match_duration
	is_match_ended = false
	is_match_active = true
	is_sudden_death = false
	no_respawns = false
	safe_zone_radius = max_zone_radius
	_storm_tick_timer = 0.0
	
	if get_tree() != null:
		for m in get_tree().get_nodes_in_group("mines"):
			if is_instance_valid(m):
				m.queue_free()
				
	# Reset all combatant stats
	for id in _combatants.keys():
		_combatants[id]["score"] = 0
		_combatants[id]["kills"] = 0
		_combatants[id]["deaths"] = 0
		_combatants[id]["streak"] = 0
		_combatants[id]["barrel_kills"] = 0
		var tank_node: Node2D = _combatants[id]["node"]
		if is_instance_valid(tank_node):
			if "score" in tank_node: tank_node.score = 0
			if "kills" in tank_node: tank_node.kills = 0
			if "deaths" in tank_node: tank_node.deaths = 0
			if "kill_streak" in tank_node: tank_node.kill_streak = 0
			if "barrel_kills" in tank_node: tank_node.barrel_kills = 0
			if "can_fire" in tank_node: tank_node.can_fire = true
			if tank_node.has_method("reset_mines"): tank_node.reset_mines()
			if tank_node.get("is_dead") == true and tank_node.has_method("request_safe_respawn"):
				tank_node.request_safe_respawn()
			
	if GameEvents != null:
		GameEvents.zone_updated.emit(safe_zone_center, safe_zone_radius, max_zone_radius, false)
		GameEvents.match_started.emit(match_duration)
		GameEvents.leaderboard_updated.emit(get_leaderboard())
	_emit_network_match_state()
	_emit_network_leaderboard()

# ------------------------------------------------------------------------------
# Combatant Registry
# ------------------------------------------------------------------------------
func register_combatant(node: Node2D, combatant_name: String = "", is_player: bool = false) -> String:
	for id in _combatants.keys():
		if _combatants[id]["node"] == node:
			return id
			
	var id := "combatant_%d" % _next_id
	_next_id += 1
	var c_name := combatant_name
	if c_name == "":
		c_name = node.name if is_instance_valid(node) else "Player"
		
	_combatants[id] = {
		"id": id,
		"name": c_name,
		"node": node,
		"is_player": is_player,
		"score": 0,
		"kills": 0,
		"deaths": 0,
		"streak": 0,
		"barrel_kills": 0
	}
	return id

func _find_combatant_id(node: Node2D) -> String:
	if not is_instance_valid(node):
		return ""
	for id in _combatants.keys():
		if _combatants[id]["node"] == node:
			return id
	# Auto register if valid Tank
	if node is CharacterBody2D or node.has_method("take_damage"):
		var t_name: String = node.get("tank_name") if "tank_name" in node else node.name
		var is_p: bool = node.get("is_player") if "is_player" in node else false
		return register_combatant(node, t_name, is_p)
	return ""

# ------------------------------------------------------------------------------
# Scoring Logic
# ------------------------------------------------------------------------------
func record_kill(victim: Node2D, killer: Node2D, is_barrel: bool = false) -> void:
	if is_match_ended and time_remaining <= 0.0:
		return
		
	var killer_id := _find_combatant_id(killer)
	if killer_id != "":
		var k_entry: Dictionary = _combatants[killer_id]
		k_entry["kills"] += 1
		k_entry["streak"] += 1
		
		# Base scoring: 100 for kill, +150 bonus if barrel (250 total)
		var pts: int = 100
		if is_barrel:
			k_entry["barrel_kills"] += 1
			pts += 150
			
		# Streak milestones: 3 kills (+50), 5 kills (+100), 10 kills (+250)
		var streak: int = k_entry["streak"]
		if streak == 3:
			pts += 50
		elif streak == 5:
			pts += 100
		elif streak >= 10 and (streak % 5 == 0 or streak == 10):
			pts += 250
			
		k_entry["score"] += pts
		
		var killer_node: Node2D = k_entry["node"]
		if is_instance_valid(killer_node):
			if "score" in killer_node: killer_node.score = k_entry["score"]
			if "kills" in killer_node: killer_node.kills = k_entry["kills"]
			if "kill_streak" in killer_node: killer_node.kill_streak = k_entry["streak"]
			if "barrel_kills" in killer_node: killer_node.barrel_kills = k_entry["barrel_kills"]
			
	var victim_id := _find_combatant_id(victim)
	if victim_id != "":
		var v_entry: Dictionary = _combatants[victim_id]
		v_entry["deaths"] += 1
		v_entry["streak"] = 0
		var victim_node: Node2D = v_entry["node"]
		if is_instance_valid(victim_node):
			if "deaths" in victim_node: victim_node.deaths = v_entry["deaths"]
			if "kill_streak" in victim_node: victim_node.kill_streak = 0
			
	var lb := get_leaderboard()
	if GameEvents != null:
		GameEvents.leaderboard_updated.emit(lb)
	_emit_network_leaderboard()
	if is_match_active and is_sudden_death:
		_check_sudden_death_survivors()

func record_barrel_destroyed(destroyer: Node2D) -> void:
	var d_id := _find_combatant_id(destroyer)
	if d_id != "":
		_combatants[d_id]["score"] += 20
		var d_node: Node2D = _combatants[d_id]["node"]
		if is_instance_valid(d_node) and "score" in d_node:
			d_node.score = _combatants[d_id]["score"]
		var lb := get_leaderboard()
		if GameEvents != null:
			GameEvents.leaderboard_updated.emit(lb)
		_emit_network_leaderboard()

func record_powerup_collected(collector: Node2D) -> void:
	var c_id := _find_combatant_id(collector)
	if c_id != "":
		_combatants[c_id]["score"] += 10
		var c_node: Node2D = _combatants[c_id]["node"]
		if is_instance_valid(c_node) and "score" in c_node:
			c_node.score = _combatants[c_id]["score"]
		var lb := get_leaderboard()
		if GameEvents != null:
			GameEvents.leaderboard_updated.emit(lb)
		_emit_network_leaderboard()

# ------------------------------------------------------------------------------
# Leaderboard Query & Sorting
# ------------------------------------------------------------------------------
func get_leaderboard() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	for id in _combatants.keys():
		var copy: Dictionary = _combatants[id].duplicate()
		var t_node = copy.get("node")
		if not is_instance_valid(t_node) or t_node.is_queued_for_deletion():
			continue
		copy["alive"] = (t_node.get("is_dead") != true)
		list.append(copy)
		
	# Stable sort descending: score -> kills -> deaths (asc) -> name
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["score"] != b["score"]:
			return a["score"] > b["score"]
		if a["kills"] != b["kills"]:
			return a["kills"] > b["kills"]
		if a["deaths"] != b["deaths"]:
			return a["deaths"] < b["deaths"]
		return a["name"] < b["name"]
	)
	return list

func get_combatant_stats(node: Node2D) -> Dictionary:
	var id := _find_combatant_id(node)
	if id != "" and _combatants.has(id):
		return _combatants[id].duplicate()
	return {}

# ------------------------------------------------------------------------------
# Event Listeners
# ------------------------------------------------------------------------------
func _on_tank_killed(victim: Node2D, killer: Node2D, is_barrel: bool) -> void:
	record_kill(victim, killer, is_barrel)

func _on_barrel_destroyed(_barrel: Node2D, destroyer: Node2D) -> void:
	record_barrel_destroyed(destroyer)

func _on_powerup_collected(_powerup: Node2D, collector: Node2D, _type: int) -> void:
	record_powerup_collected(collector)

# ------------------------------------------------------------------------------
# Network Synchronization Helpers
# ------------------------------------------------------------------------------
func serialize_match_state() -> Dictionary:
	return {
		"t": time_remaining,
		"dur": match_duration,
		"act": is_match_active,
		"end": is_match_ended,
		"sd": is_sudden_death,
		"nr": no_respawns,
		"zc": safe_zone_center,
		"zr": safe_zone_radius
	}

func serialize_leaderboard() -> Array[Dictionary]:
	var lb := get_leaderboard()
	var out: Array[Dictionary] = []
	for entry in lb:
		var t_node: Variant = entry.get("node")
		var slot: int = int(t_node.get("net_slot")) if (t_node != null and is_instance_valid(t_node) and "net_slot" in t_node) else -1
		out.append({
			"slot": slot,
			"name": str(entry.get("name", "Tank")),
			"score": int(entry.get("score", 0)),
			"kills": int(entry.get("kills", 0)),
			"deaths": int(entry.get("deaths", 0)),
			"streak": int(entry.get("streak", 0)),
			"barrel_kills": int(entry.get("barrel_kills", 0)),
			"alive": bool(entry.get("alive", true))
		})
	return out

func _emit_network_match_state() -> void:
	if not is_network_puppet:
		network_match_state_changed.emit(serialize_match_state())

func _emit_network_leaderboard() -> void:
	if not is_network_puppet:
		network_leaderboard_changed.emit(serialize_leaderboard())

func apply_network_state(state: Dictionary) -> void:
	var was_active := is_match_active
	var was_ended := is_match_ended
	var was_sd := is_sudden_death

	match_duration = float(state.get("dur", match_duration))
	time_remaining = float(state.get("t", time_remaining))
	is_match_active = bool(state.get("act", is_match_active))
	is_match_ended = bool(state.get("end", is_match_ended))
	is_sudden_death = bool(state.get("sd", is_sudden_death))
	no_respawns = bool(state.get("nr", no_respawns))
	var zc_val: Variant = state.get("zc", safe_zone_center)
	if zc_val is Vector2:
		safe_zone_center = zc_val
	safe_zone_radius = float(state.get("zr", safe_zone_radius))

	if is_match_active and not is_match_ended and (not was_active or was_ended):
		if SoundManagerScript != null:
			SoundManagerScript.stop_zone_closing()
		if GameEvents != null:
			GameEvents.zone_updated.emit(safe_zone_center, safe_zone_radius, max_zone_radius, false)
			GameEvents.match_started.emit(match_duration)
			GameEvents.leaderboard_updated.emit(get_leaderboard())

	if is_sudden_death and not was_sd and not is_match_ended:
		if SoundManagerScript != null:
			SoundManagerScript.play_zone_closing()
		if GameEvents != null:
			GameEvents.sudden_death_started.emit()
			GameEvents.zone_updated.emit(safe_zone_center, safe_zone_radius, max_zone_radius, true)
			GameEvents.kill_feed_announced.emit("¡CIERRE DE ZONA! ¡RESPAWNS DESACTIVADOS!", Color(1.0, 0.22, 0.38))

	if GameEvents != null:
		GameEvents.match_tick.emit(time_remaining)
	if is_sudden_death:
		if SoundManagerScript != null:
			SoundManagerScript.update_zone_closing_volume(time_remaining)
		if GameEvents != null:
			GameEvents.zone_updated.emit(safe_zone_center, safe_zone_radius, max_zone_radius, true)

	if is_match_ended and not was_ended:
		if SoundManagerScript != null:
			SoundManagerScript.stop_zone_closing()
		if get_tree() != null:
			for t in get_tree().get_nodes_in_group("tanks"):
				if is_instance_valid(t):
					if t.has_method("set_chassis_input"):
						t.set_chassis_input(Vector2.ZERO)
					if "can_fire" in t:
						t.can_fire = false
					if "velocity" in t:
						t.velocity = Vector2.ZERO
		if GameEvents != null:
			GameEvents.match_ended.emit(get_leaderboard())

func apply_network_leaderboard(entries: Array, local_slot: int, tanks_by_slot: Dictionary) -> void:
	_combatants.clear()
	_next_id = 1
	for raw in entries:
		if not (raw is Dictionary):
			continue
		var item := raw as Dictionary
		var slot: int = int(item.get("slot", -1))
		var t_node: Node2D = tanks_by_slot.get(slot, null) as Node2D
		if t_node == null or not is_instance_valid(t_node):
			continue
		var cid := "combatant_%d" % _next_id
		_next_id += 1
		var is_p := (slot == local_slot)
		_combatants[cid] = {
			"id": cid,
			"name": str(item.get("name", t_node.get("tank_name"))),
			"node": t_node,
			"is_player": is_p,
			"score": int(item.get("score", 0)),
			"kills": int(item.get("kills", 0)),
			"deaths": int(item.get("deaths", 0)),
			"streak": int(item.get("streak", 0)),
			"barrel_kills": int(item.get("barrel_kills", 0))
		}
		if "score" in t_node: t_node.score = int(item.get("score", 0))
		if "kills" in t_node: t_node.kills = int(item.get("kills", 0))
		if "deaths" in t_node: t_node.deaths = int(item.get("deaths", 0))
		if "kill_streak" in t_node: t_node.kill_streak = int(item.get("streak", 0))
		if "barrel_kills" in t_node: t_node.barrel_kills = int(item.get("barrel_kills", 0))

	if GameEvents != null:
		GameEvents.leaderboard_updated.emit(get_leaderboard())
