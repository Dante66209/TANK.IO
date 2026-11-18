# res://Scripts/UI/minimap.gd
class_name TacticalMinimap extends Control

## Tactical Radar / Mini-Map HUD Widget (CoD / Battle Royale style).
## Displays the 6400x6400 arena, closing Sudden Death storm circle, player position & aim vector,
## visible enemies, temporary red pulsing gunfire blips when enemies shoot in Fog of War,
## incoming mortar strikes, and the player's stealth proximity mines.

const BLIP_DURATION: float = 1.85

var arena_half_size: float = 3200.0
var player_tank: Node2D = null

var _gunfire_blips: Array[Dictionary] = []
var _zone_active: bool = false
var _zone_center: Vector2 = Vector2.ZERO
var _zone_radius: float = 4550.0
var _sweep_angle: float = 0.0

func _ready() -> void:
	add_to_group("minimap")
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if custom_minimum_size == Vector2.ZERO:
		custom_minimum_size = Vector2(148, 148)
		
	if GameEvents != null:
		if not GameEvents.weapon_fired.is_connected(_on_weapon_fired):
			GameEvents.weapon_fired.connect(_on_weapon_fired)
		if not GameEvents.zone_updated.is_connected(_on_zone_updated):
			GameEvents.zone_updated.connect(_on_zone_updated)
		if not GameEvents.match_started.is_connected(_on_match_started):
			GameEvents.match_started.connect(_on_match_started)
	queue_redraw()

func _process(delta: float) -> void:
	_sweep_angle = fmod(_sweep_angle + delta * 1.9, TAU)
	
	# Sync arena bounds from WorldMap if present
	if get_tree() != null:
		var wmap := get_tree().get_first_node_in_group("world_map")
		if wmap != null and "half_size" in wmap:
			var hs = wmap.get("half_size")
			if hs != null:
				arena_half_size = maxf(500.0, float(hs))
		if not is_instance_valid(player_tank):
			for t in get_tree().get_nodes_in_group("tanks"):
				if is_instance_valid(t) and t.get("is_player") == true:
					player_tank = t as Node2D
					break
					
	# Decay gunfire radar blips
	for i in range(_gunfire_blips.size() - 1, -1, -1):
		_gunfire_blips[i]["time_left"] = float(_gunfire_blips[i]["time_left"]) - delta
		if float(_gunfire_blips[i]["time_left"]) <= 0.0:
			_gunfire_blips.remove_at(i)
			
	queue_redraw()

func _on_weapon_fired(shooter: Node2D, pos: Vector2) -> void:
	if is_instance_valid(shooter) and shooter.get("is_player") == true:
		return
	_gunfire_blips.append({
		"pos": pos,
		"time_left": BLIP_DURATION,
		"max_time": BLIP_DURATION
	})
	queue_redraw()

func _on_zone_updated(center: Vector2, current_radius: float, _max_radius: float, active: bool) -> void:
	_zone_center = center
	_zone_radius = current_radius
	_zone_active = active
	queue_redraw()

func _on_match_started(_duration: float) -> void:
	_gunfire_blips.clear()
	_zone_active = false
	queue_redraw()

func get_gunfire_blip_count() -> int:
	return _gunfire_blips.size()

func world_to_radar(world_pos: Vector2, radar_rect: Rect2) -> Vector2:
	var norm_x := clampf((world_pos.x + arena_half_size) / (arena_half_size * 2.0), 0.0, 1.0)
	var norm_y := clampf((world_pos.y + arena_half_size) / (arena_half_size * 2.0), 0.0, 1.0)
	return Vector2(
		radar_rect.position.x + norm_x * radar_rect.size.x,
		radar_rect.position.y + norm_y * radar_rect.size.y
	)

func _draw() -> void:
	var pad := 4.0
	var w := maxf(64.0, size.x)
	var h := maxf(64.0, size.y)
	var radar_rect := Rect2(Vector2(pad, pad), Vector2(w - pad * 2.0, h - pad * 2.0))
	var center := radar_rect.position + radar_rect.size * 0.5
	var scale_px_per_unit := radar_rect.size.x / (arena_half_size * 2.0)
	
	# 1. Tactical dark phosphor radar background
	draw_rect(radar_rect, Color(0.04, 0.08, 0.11, 0.90), true)
	
	# 2. Quadrant & sector grid lines
	var grid_col := Color(0.15, 0.35, 0.38, 0.42)
	draw_line(Vector2(center.x, radar_rect.position.y), Vector2(center.x, radar_rect.end.y), grid_col, 1.0)
	draw_line(Vector2(radar_rect.position.x, center.y), Vector2(radar_rect.end.x, center.y), grid_col, 1.0)
	var q_rect := Rect2(center - radar_rect.size * 0.25, radar_rect.size * 0.5)
	draw_rect(q_rect, Color(0.15, 0.35, 0.38, 0.28), false, 1.0)
	
	# 3. Rotating radar sweep line
	var sweep_len := radar_rect.size.x * 0.48
	var sweep_end := center + Vector2.RIGHT.rotated(_sweep_angle) * sweep_len
	draw_line(center, sweep_end, Color(0.2, 0.95, 0.65, 0.26), 1.5)
	
	# 4. Closing Sudden Death Storm Circle
	if _zone_active:
		var z_center := world_to_radar(_zone_center, radar_rect)
		var z_rad_px := clampf(_zone_radius * scale_px_per_unit, 2.0, radar_rect.size.x * 0.72)
		draw_arc(z_center, z_rad_px, 0.0, TAU, 48, Color(1.0, 0.22, 0.32, 0.95), 2.0)
		
	if get_tree() != null:
		# 5. Active Mortar Strikes (orange rings)
		for m in get_tree().get_nodes_in_group("mortars"):
			if is_instance_valid(m) and m is Node2D:
				var m_pt := world_to_radar((m as Node2D).global_position, radar_rect)
				draw_circle(m_pt, 3.5, Color(1.0, 0.45, 0.1, 0.75))
				
		# 6. Player's Deployed Stealth Mines (cyan tactical pips)
		for mine in get_tree().get_nodes_in_group("mines"):
			if is_instance_valid(mine) and mine is Node2D:
				if is_instance_valid(player_tank) and mine.get("owner_tank") == player_tank:
					var mp := world_to_radar((mine as Node2D).global_position, radar_rect)
					draw_circle(mp, 2.6, Color(0.2, 0.95, 1.0, 0.95))
					
		# 7. Enemy Tanks within active vision subject's sight radius
		var focus_tank: Node2D = player_tank
		var spectating_now: bool = false
		if is_instance_valid(player_tank) and player_tank.get("is_spectating") == true:
			var spec = player_tank.get("spectated_tank")
			if spec != null and is_instance_valid(spec) and spec is Node2D and spec.get("is_dead") != true:
				focus_tank = spec as Node2D
				spectating_now = true
		if is_instance_valid(focus_tank) and focus_tank.get("is_dead") != true:
			var sr_val = focus_tank.get("sight_radius") if "sight_radius" in focus_tank else null
			var p_sight: float = maxf(560.0, float(sr_val)) if (spectating_now and sr_val != null) else (float(sr_val) if sr_val != null else 560.0)
			for t in get_tree().get_nodes_in_group("tanks"):
				if is_instance_valid(t) and t != focus_tank and t is Node2D and t.get("is_dead") != true:
					var d := focus_tank.global_position.distance_to((t as Node2D).global_position)
					if d <= p_sight:
						var ep := world_to_radar((t as Node2D).global_position, radar_rect)
						draw_circle(ep, 3.4, Color(1.0, 0.22, 0.22, 1.0))
						
	# 8. Temporary Gunfire Blips (CoD UAV style pulsing red ping when enemies shoot)
	for blip in _gunfire_blips:
		var ratio := clampf(float(blip["time_left"]) / maxf(0.01, float(blip["max_time"])), 0.0, 1.0)
		var bp := world_to_radar(blip["pos"], radar_rect)
		var ring_r := lerpf(8.5, 2.5, ratio)
		draw_arc(bp, ring_r, 0.0, TAU, 18, Color(1.0, 0.25, 0.2, ratio * 0.85), 1.5)
		draw_circle(bp, 2.8, Color(1.0, 0.3, 0.2, ratio))
		
	# 9. Local Player (or Spectated Survivor) Marker, Sight Ring & Aim Line
	var marker_tank: Node2D = player_tank
	var marker_is_spec: bool = false
	if is_instance_valid(player_tank) and player_tank.get("is_spectating") == true:
		var spec_m = player_tank.get("spectated_tank")
		if spec_m != null and is_instance_valid(spec_m) and spec_m is Node2D and spec_m.get("is_dead") != true:
			marker_tank = spec_m as Node2D
			marker_is_spec = true
	if is_instance_valid(marker_tank) and marker_tank.get("is_dead") != true:
		var pp := world_to_radar(marker_tank.global_position, radar_rect)
		var p_sr = marker_tank.get("sight_radius") if "sight_radius" in marker_tank else null
		var eff_sr: float = maxf(560.0, float(p_sr)) if (marker_is_spec and p_sr != null) else (float(p_sr) if p_sr != null else 560.0)
		var sight_px := eff_sr * scale_px_per_unit
		var m_ring_col := Color(0.28, 0.90, 1.0, 0.36) if marker_is_spec else Color(0.25, 1.0, 0.55, 0.30)
		var m_dot_col := Color(0.28, 0.90, 1.0, 1.0) if marker_is_spec else Color(0.25, 1.0, 0.45, 1.0)
		draw_arc(pp, sight_px, 0.0, TAU, 28, m_ring_col, 1.0)
		
		var turret := marker_tank.get_node_or_null("TurretPivot") as Node2D
		if turret != null:
			var aim_vec := Vector2.RIGHT.rotated(turret.global_rotation) * 11.0
			draw_line(pp, pp + aim_vec, m_dot_col, 1.8)
		draw_circle(pp, 3.8, m_dot_col)
		draw_circle(pp, 1.8, Color.WHITE)
		
	# 10. Crisp tactical outer frame
	draw_rect(radar_rect, Color(0.32, 0.62, 0.72, 0.85), false, 1.8)
