# res://Scripts/main_game.gd
class_name MainGame extends Node2D

## Main gameplay orchestrator for TANK.IO (R8).
## Assembles map, entity containers, player tank, 4–29 AI bot tanks (5–30 total),
## MatchManager, HUD, PodiumScreen, pre-match CountdownOverlay, and PauseMenu.

const BotTankScene: PackedScene = preload("res://Scenes/bot_tank.tscn")
const SoundManagerScript = preload("res://Scripts/Core/sound_manager.gd")
const MatchNetworkSyncScript = preload("res://Scripts/Core/match_network_sync.gd")

@onready var world_map: Node2D = $WorldMap
@onready var match_manager: Node = $MatchManager
@onready var spawn_manager: Node2D = $SpawnManager
@onready var entities: Node2D = $Entities
@onready var tanks_container: Node2D = $Entities/Tanks
@onready var projectiles_container: Node2D = $Entities/Projectiles
@onready var player_tank: CharacterBody2D = $Entities/Tanks/PlayerTank
@onready var bot1: CharacterBody2D = $Entities/Tanks/BotTank1
@onready var bot2: CharacterBody2D = $Entities/Tanks/BotTank2
@onready var bot3: CharacterBody2D = $Entities/Tanks/BotTank3
@onready var bot4: CharacterBody2D = $Entities/Tanks/BotTank4
@onready var bot5: CharacterBody2D = $Entities/Tanks/BotTank5 if has_node("Entities/Tanks/BotTank5") else null
@onready var bot6: CharacterBody2D = $Entities/Tanks/BotTank6 if has_node("Entities/Tanks/BotTank6") else null
@onready var bot7: CharacterBody2D = $Entities/Tanks/BotTank7 if has_node("Entities/Tanks/BotTank7") else null
@onready var bot8: CharacterBody2D = $Entities/Tanks/BotTank8 if has_node("Entities/Tanks/BotTank8") else null
@onready var bot9: CharacterBody2D = $Entities/Tanks/BotTank9 if has_node("Entities/Tanks/BotTank9") else null
@onready var hud: CanvasLayer = $HUD
@onready var podium_screen: CanvasLayer = $PodiumScreen
@onready var countdown_overlay: CanvasLayer = $CountdownOverlay if has_node("CountdownOverlay") else null
@onready var pause_menu: CanvasLayer = $PauseMenu if has_node("PauseMenu") else null

var is_prematch_countdown_active: bool = false
var network_manager_override: Node = null
var online_roster_override: Array = []
var match_network_sync: Node = null

func _get_network_manager() -> Node:
	if network_manager_override != null and is_instance_valid(network_manager_override):
		return network_manager_override
	return get_node_or_null("/root/NetworkManager")

func _ready() -> void:
	var nm := _get_network_manager()
	var gs := get_node_or_null("/root/GameSettings")
	var is_online_server_match: bool = (
		nm != null
		and nm.has_method("is_online")
		and nm.is_online()
		and (not online_roster_override.is_empty() or (gs != null and gs.get("lobby_mode") == "server"))
	)
	if is_online_server_match:
		var roster: Array = online_roster_override
		if roster.is_empty():
			var nm_roster: Variant = nm.get("current_roster")
			if nm_roster is Array and not (nm_roster as Array).is_empty():
				roster = nm_roster
			elif gs != null:
				roster = gs.get("connected_players")
		match_network_sync = MatchNetworkSyncScript.new()
		match_network_sync.name = "MatchNetworkSync"
		add_child(match_network_sync)
		match_network_sync.setup(self, nm, roster)
		_connect_events()
		return

	_apply_lobby_configuration()
	_initialize_world()
	_register_combatants()
	_connect_events()

	var wants_countdown: bool = (DisplayServer.get_name() != "headless")
	if gs != null and gs.get("use_prematch_countdown") == true:
		wants_countdown = true

	if wants_countdown and countdown_overlay != null:
		start_prematch_countdown()
	elif match_manager != null and match_manager.has_method("start_match"):
		match_manager.start_match(180.0)

func _apply_lobby_configuration() -> void:
	var gs := get_node_or_null("/root/GameSettings")
	if gs == null or tanks_container == null:
		return

	if player_tank != null:
		var custom_name: String = str(gs.get("player_name")).strip_edges()
		if not custom_name.is_empty():
			player_tank.tank_name = custom_name
		var custom_color = gs.get("player_color")
		if custom_color is Color and player_tank.has_method("apply_tank_color"):
			player_tank.apply_tank_color(custom_color)

	if gs.get("match_configured_from_lobby") != true:
		return

	var total_combatants: int = gs.get_effective_combatant_count() if gs.has_method("get_effective_combatant_count") else 10
	if spawn_manager != null and "max_powerups" in spawn_manager and total_combatants > 10:
		spawn_manager.set("max_powerups", mini(58, 38 + (total_combatants - 10)))
	var desired_bots: int = clampi(total_combatants - 1, 4, 29)

	var bot_names: Array[String] = []
	var lobby_player_name: String = ""
	var roster: Variant = gs.get("connected_players")
	if roster is Array:
		for entry in roster:
			if entry is Dictionary:
				if entry.get("is_player", false) == true:
					lobby_player_name = str(entry.get("name", "")).strip_edges()
				else:
					bot_names.append(str(entry.get("name", "Bot")))

	if player_tank != null and not lobby_player_name.is_empty():
		player_tank.tank_name = lobby_player_name

	var existing_bots: Array[Node] = []
	for child in tanks_container.get_children():
		if child != player_tank:
			existing_bots.append(child)

	# Trim excess default bots if fewer than 9 bots requested (e.g. 5 total = 1 player + 4 bots)
	while existing_bots.size() > desired_bots:
		var extra: Node = existing_bots.pop_back()
		tanks_container.remove_child(extra)
		extra.queue_free()

	# Rename retained bots
	for i in range(existing_bots.size()):
		var bot_node: Node = existing_bots[i]
		var assigned_name: String = bot_names[i] if i < bot_names.size() else gs.get_bot_name_for_index(i)
		if "tank_name" in bot_node:
			bot_node.set("tank_name", assigned_name)

	# Spawn extra bots up to 29 if more than 10 total players configured (up to 30)
	for i in range(existing_bots.size(), desired_bots):
		if BotTankScene == null:
			break
		var new_bot: Node = BotTankScene.instantiate()
		new_bot.name = "BotTank%d" % (i + 1)
		var assigned_name: String = bot_names[i] if i < bot_names.size() else gs.get_bot_name_for_index(i)
		if "tank_name" in new_bot:
			new_bot.set("tank_name", assigned_name)
		tanks_container.add_child(new_bot)

func _initialize_world() -> void:
	if world_map != null and world_map.has_method("get_spawn_positions"):
		var spawn_positions: Array[Vector2] = world_map.get_spawn_positions()
		if not spawn_positions.is_empty():
			var shuffled := spawn_positions.duplicate()
			shuffled.shuffle()
			var idx := 0
			if tanks_container != null:
				for child in tanks_container.get_children():
					if child is Node2D:
						(child as Node2D).global_position = shuffled[idx % shuffled.size()]
						idx += 1
			elif player_tank != null:
				player_tank.global_position = shuffled[0]
			if player_tank != null and "camera" in player_tank and player_tank.camera != null:
				player_tank.camera.reset_smoothing()
				player_tank.camera.force_update_scroll()

func _register_combatants() -> void:
	if match_manager == null:
		return
	if match_manager.has_method("sync_scene_combatants"):
		match_manager.sync_scene_combatants()
		return
	if match_manager.has_method("register_combatant"):
		if player_tank != null:
			var p_name: String = player_tank.tank_name if "tank_name" in player_tank else "Player"
			match_manager.register_combatant(player_tank, p_name, true)
		if tanks_container != null:
			for child in tanks_container.get_children():
				if child is Node2D and child != player_tank:
					var b_name: String = child.get("tank_name") if "tank_name" in child else child.name
					match_manager.register_combatant(child as Node2D, b_name, false)

func start_prematch_countdown(step_duration: float = -1.0) -> void:
	if countdown_overlay == null:
		_set_all_tanks_locked(false)
		if match_manager != null and match_manager.has_method("start_match"):
			match_manager.start_match(180.0)
		return
	is_prematch_countdown_active = true
	_set_all_tanks_locked(true)
	if match_manager != null:
		match_manager.is_match_active = false
	if not countdown_overlay.countdown_finished.is_connected(_on_countdown_finished):
		countdown_overlay.countdown_finished.connect(_on_countdown_finished, CONNECT_ONE_SHOT)
	countdown_overlay.start_countdown(step_duration)

func _on_countdown_finished() -> void:
	is_prematch_countdown_active = false
	_set_all_tanks_locked(false)
	if match_manager != null and match_manager.has_method("start_match"):
		match_manager.start_match(180.0)

func _set_all_tanks_locked(locked: bool) -> void:
	if tanks_container != null:
		for child in tanks_container.get_children():
			if is_instance_valid(child) and child.has_method("set_controls_locked"):
				child.set_controls_locked(locked)
	if get_tree() != null:
		for t in get_tree().get_nodes_in_group("tanks"):
			if is_instance_valid(t) and t.has_method("set_controls_locked"):
				t.set_controls_locked(locked)

func _connect_events() -> void:
	if GameEvents != null:
		GameEvents.tank_killed.connect(_on_tank_killed)
		GameEvents.tank_respawned.connect(_on_tank_respawned)
		GameEvents.barrel_destroyed.connect(_on_barrel_destroyed)
		GameEvents.powerup_collected.connect(_on_powerup_collected)

func _on_tank_killed(victim: Node2D, killer: Node2D, is_barrel: bool) -> void:
	var victim_name: String = str(victim.name) if is_instance_valid(victim) else "Unknown"
	if is_instance_valid(victim) and "tank_name" in victim:
		victim_name = victim.tank_name
	var killer_name: String = "World"
	if is_instance_valid(killer):
		if killer.is_in_group("mortar") or killer.is_in_group("mortars") or killer.get("is_mortar") == true:
			killer_name = "Mortar"
		elif "tank_name" in killer:
			killer_name = killer.tank_name
		else:
			killer_name = str(killer.name)
	elif is_barrel:
		killer_name = "Barrel"
	print("[MainGame] Tank eliminated: %s by %s" % [victim_name, killer_name])

func _on_tank_respawned(tank: Node2D, spawn_pos: Vector2) -> void:
	var tank_name_str: String = str(tank.name) if is_instance_valid(tank) else "Unknown"
	print("[MainGame] Tank respawned: %s at %s" % [tank_name_str, str(spawn_pos)])

func _on_barrel_destroyed(_barrel: Node2D, destroyer: Node2D) -> void:
	var det_name: String = str(destroyer.name) if is_instance_valid(destroyer) else "World"
	print("[MainGame] Barrel detonated by %s" % det_name)

func _on_powerup_collected(_powerup: Node2D, collector: Node2D, type: int) -> void:
	var col_name: String = str(collector.name) if is_instance_valid(collector) else "Unknown"
	print("[MainGame] Power-up type %d collected by %s" % [type, col_name])
