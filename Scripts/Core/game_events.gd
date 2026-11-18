# res://Scripts/Core/game_events.gd
extends Node

## Global event bus singleton for TANK.IO decoupled event communication

# Combat & Damage Signals
signal tank_damaged(victim: Node2D, attacker: Node2D, amount: float, is_barrel: bool)
signal tank_killed(victim: Node2D, killer: Node2D, is_barrel: bool)
signal tank_respawned(tank: Node2D, spawn_pos: Vector2)
signal barrel_destroyed(barrel: Node2D, destroyer: Node2D)
signal weapon_fired(shooter: Node2D, pos: Vector2)
signal mine_thrown(owner_tank: Node2D, mine: Node2D, start_pos: Vector2, target_pos: Vector2)
signal killstreak_achieved(killer: Node2D, title: String, subtitle: String, color: Color, tier: int)

# Power-Up Signals
signal powerup_spawned(powerup: Node2D, type: int, pos: Vector2)
signal powerup_collected(powerup: Node2D, collector: Node2D, type: int)
signal powerup_expired(tank: Node2D, type: int)

# Match Flow Signals
signal match_started(duration: float)
signal match_tick(time_remaining: float)
signal match_ended(leaderboard: Array[Dictionary])
signal leaderboard_updated(leaderboard: Array[Dictionary])
signal kill_feed_announced(text: String, color: Color)
signal sudden_death_started()
signal zone_updated(center: Vector2, current_radius: float, max_radius: float, active: bool)
signal spectate_target_changed(target: Node2D, index: int, total: int)

# Mortar Event & Visual Juice Signals
signal mortar_event_started(duration: float)
signal mortar_event_tick(time_remaining: float, duration: float)
signal mortar_event_ended()
signal screen_shake_requested(trauma: float)

func _ready() -> void:
	_ensure_input_actions()

## Fallback registration for required input map actions in case project.godot lacks them
func _ensure_input_actions() -> void:
	var required_actions: Dictionary = {
		"move_up": [KEY_W, KEY_UP],
		"move_down": [KEY_S, KEY_DOWN],
		"move_left": [KEY_A, KEY_LEFT],
		"move_right": [KEY_D, KEY_RIGHT],
		"shoot": [KEY_SPACE],
		"dash": [KEY_SHIFT],
		"throw_mine": [KEY_Q]
	}
	
	for action in required_actions.keys():
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for key in required_actions[action]:
			var event := InputEventKey.new()
			event.physical_keycode = key
			event.keycode = key
			if not InputMap.action_has_event(action, event):
				InputMap.action_add_event(action, event)
	
	# Add Left Mouse Button to shoot action
	if not InputMap.has_action("shoot"):
		InputMap.add_action("shoot")
	var mouse_event := InputEventMouseButton.new()
	mouse_event.button_index = MOUSE_BUTTON_LEFT
	if not InputMap.action_has_event("shoot", mouse_event):
		InputMap.action_add_event("shoot", mouse_event)
