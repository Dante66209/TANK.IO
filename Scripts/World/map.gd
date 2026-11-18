# res://Scripts/World/map.gd
class_name WorldMap extends Node2D

const DestructibleWallScript = preload("res://Scripts/World/destructible_wall.gd")

## 6400x6400 Expanded Modular Gotcha Combat Arena for TANK.IO (2x Scale).
## Extends from (-3200, -3200) to (+3200, +3200).
## Perimeter boundary walls on Layer 1.
## Tactical Gotcha cover obstacles, bunkers, corridors, and Destructible Gotcha Barricades on Layer 2.
## Also renders the Sudden Death Closing Storm Zone overlay in world space.

@onready var spawn_points_container: Node2D = $SpawnPoints
@onready var powerup_spawns_container: Node2D = $PowerUpSpawns
@onready var boundary_walls: StaticBody2D = $BoundaryWalls
@onready var modular_covers: StaticBody2D = $ModularCovers

const ARENA_SIZE: float = 6400.0
const HALF_SIZE: float = 3200.0

var arena_size: Vector2 = Vector2(ARENA_SIZE, ARENA_SIZE)
var half_size: float = HALF_SIZE
var destructible_covers_container: Node2D = null
var _storm_overlay: Node2D = null

var _zone_active: bool = false
var _zone_center: Vector2 = Vector2.ZERO
var _zone_radius: float = 4600.0
var _zone_pulse: float = 0.0

## Internal helper overlay node rendered above ground & walls for the closing storm ring
class StormZoneCanvas extends Node2D:
	var map_ref: WorldMap = null
	func _draw() -> void:
		if map_ref == null or not map_ref._zone_active:
			return
		var r: float = maxf(40.0, map_ref._zone_radius)
		var c: Vector2 = map_ref._zone_center
		var pulse: float = (sin(map_ref._zone_pulse * 6.0) + 1.0) * 0.5
		
		# Outer toxic/electric storm field concentric thick bands outside safe_zone_radius
		var max_r: float = 5200.0
		if max_r > r:
			var band_thickness: float = max_r - r
			var mid_r: float = r + band_thickness * 0.5
			draw_arc(c, mid_r, 0.0, TAU, 96, Color(0.88, 0.10, 0.18, 0.22 + pulse * 0.06), band_thickness)
			
		# Glowing electric storm perimeter border
		draw_arc(c, r + 8.0, 0.0, TAU, 96, Color(1.0, 0.15, 0.25, 0.35), 14.0)
		draw_arc(c, r, 0.0, TAU, 96, Color(1.0, 0.28 + pulse * 0.3, 0.22, 0.95), 5.0)
		draw_arc(c, maxf(10.0, r - 6.0), 0.0, TAU, 72, Color(1.0, 0.85, 0.3, 0.55), 2.0)

func _ready() -> void:
	add_to_group("world_map")
	_build_expanded_gotcha_walls()
	_build_destructible_gotcha_walls()
	_build_expanded_markers()
	_setup_storm_overlay()
	if GameEvents != null:
		if not GameEvents.zone_updated.is_connected(_on_zone_updated):
			GameEvents.zone_updated.connect(_on_zone_updated)
		if not GameEvents.match_started.is_connected(_on_match_started):
			GameEvents.match_started.connect(_on_match_started)
	queue_redraw()

func _process(delta: float) -> void:
	if _zone_active:
		_zone_pulse += delta
		if _storm_overlay != null:
			_storm_overlay.queue_redraw()

func _setup_storm_overlay() -> void:
	var overlay := StormZoneCanvas.new()
	overlay.name = "StormZoneOverlay"
	overlay.z_index = 25
	overlay.map_ref = self
	add_child(overlay)
	_storm_overlay = overlay

func _on_zone_updated(center: Vector2, current_radius: float, _max_radius: float, active: bool) -> void:
	_zone_center = center
	_zone_radius = current_radius
	_zone_active = active
	if _storm_overlay != null:
		_storm_overlay.queue_redraw()

func _on_match_started(_duration: float) -> void:
	_zone_active = false
	if _storm_overlay != null:
		_storm_overlay.queue_redraw()
	restore_destructible_walls()

func restore_destructible_walls() -> void:
	if destructible_covers_container == null:
		return
	for child in destructible_covers_container.get_children():
		if is_instance_valid(child) and child.has_method("restore"):
			child.restore()

func _add_solid_cover(cover_name: String, pos: Vector2, size: Vector2, col: Color = Color(0.28, 0.35, 0.44, 1.0)) -> void:
	if modular_covers == null or modular_covers.has_node(cover_name):
		return
	var cs := CollisionShape2D.new()
	cs.name = cover_name
	cs.position = pos
	var shape := RectangleShape2D.new()
	shape.size = size
	cs.shape = shape
	
	var rect := ColorRect.new()
	rect.name = "Visual"
	rect.position = -size * 0.5
	rect.size = size
	rect.color = col
	cs.add_child(rect)
	modular_covers.add_child(cs)

func _build_expanded_gotcha_walls() -> void:
	if modular_covers == null:
		return
		
	var steel_col := Color(0.28, 0.35, 0.44, 1.0)
	var bunker_col := Color(0.30, 0.38, 0.48, 1.0)
	var accent_col := Color(0.32, 0.41, 0.52, 1.0)
	
	# 1. Sector Ring Gate Dividers (between inner 3200 arena and outer 6400 ring)
	_add_solid_cover("GotchaSectorGateN", Vector2(0, -1620), Vector2(260, 44), bunker_col)
	_add_solid_cover("GotchaSectorGateS", Vector2(0, 1620), Vector2(260, 44), bunker_col)
	_add_solid_cover("GotchaSectorGateW", Vector2(-1620, 0), Vector2(44, 260), bunker_col)
	_add_solid_cover("GotchaSectorGateE", Vector2(1620, 0), Vector2(44, 260), bunker_col)
	
	# 2. Diagonal Sector L-Bunkers at (±1600, ±1600)
	var diag_signs := [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]
	for i in range(diag_signs.size()):
		var s: Vector2 = diag_signs[i]
		_add_solid_cover("GotchaDiagBunkerV_%d" % i, Vector2(s.x * 1600.0, s.y * 1480.0), Vector2(46, 240), bunker_col)
		_add_solid_cover("GotchaDiagBunkerH_%d" % i, Vector2(s.x * 1480.0, s.y * 1600.0), Vector2(240, 46), bunker_col)
		
	# 3. Outer Cardinal Tank Bastions (North, South, West, East at ±2400..2650)
	_add_solid_cover("GotchaNorthBastionL", Vector2(-420, -2400), Vector2(52, 300), bunker_col)
	_add_solid_cover("GotchaNorthBastionR", Vector2(420, -2400), Vector2(52, 300), bunker_col)
	_add_solid_cover("GotchaNorthBastionCap", Vector2(0, -2650), Vector2(380, 52), accent_col)
	
	_add_solid_cover("GotchaSouthBastionL", Vector2(-420, 2400), Vector2(52, 300), bunker_col)
	_add_solid_cover("GotchaSouthBastionR", Vector2(420, 2400), Vector2(52, 300), bunker_col)
	_add_solid_cover("GotchaSouthBastionCap", Vector2(0, 2650), Vector2(380, 52), accent_col)
	
	_add_solid_cover("GotchaWestBastionT", Vector2(-2400, -420), Vector2(300, 52), bunker_col)
	_add_solid_cover("GotchaWestBastionB", Vector2(-2400, 420), Vector2(300, 52), bunker_col)
	_add_solid_cover("GotchaWestBastionCap", Vector2(-2650, 0), Vector2(52, 380), accent_col)
	
	_add_solid_cover("GotchaEastBastionT", Vector2(2400, -420), Vector2(300, 52), bunker_col)
	_add_solid_cover("GotchaEastBastionB", Vector2(2400, 420), Vector2(300, 52), bunker_col)
	_add_solid_cover("GotchaEastBastionCap", Vector2(2650, 0), Vector2(52, 380), accent_col)
	
	# 4. Outer Quadrant Gotcha X-Crosses & Corner Fortresses (±2350 & ±2800)
	for i in range(diag_signs.size()):
		var s: Vector2 = diag_signs[i]
		_add_solid_cover("GotchaOuterCrossV_%d" % i, Vector2(s.x * 2350.0, s.y * 2350.0), Vector2(44, 280), steel_col)
		_add_solid_cover("GotchaOuterCrossH_%d" % i, Vector2(s.x * 2350.0, s.y * 2350.0), Vector2(280, 44), steel_col)
		_add_solid_cover("GotchaCornerPillbox_%d" % i, Vector2(s.x * 2800.0, s.y * 2800.0), Vector2(96, 96), accent_col)
		_add_solid_cover("GotchaOuterTrenchH_%d" % i, Vector2(s.x * 1850.0, s.y * 2850.0), Vector2(260, 46), steel_col)
		_add_solid_cover("GotchaOuterTrenchV_%d" % i, Vector2(s.x * 2850.0, s.y * 1850.0), Vector2(46, 260), steel_col)
		
	# 5. Tournament Gotcha Snake Lanes across all 4 outer corridors
	for sx in [-1.0, 1.0]:
		_add_solid_cover("SnakeNorthA_%s" % ("L" if sx < 0 else "R"), Vector2(sx * 1150.0, -2150.0), Vector2(240, 44), steel_col)
		_add_solid_cover("SnakeNorthB_%s" % ("L" if sx < 0 else "R"), Vector2(sx * 800.0, -2350.0), Vector2(240, 44), steel_col)
		_add_solid_cover("SnakeSouthA_%s" % ("L" if sx < 0 else "R"), Vector2(sx * 1150.0, 2150.0), Vector2(240, 44), steel_col)
		_add_solid_cover("SnakeSouthB_%s" % ("L" if sx < 0 else "R"), Vector2(sx * 800.0, 2350.0), Vector2(240, 44), steel_col)
		
	for sy in [-1.0, 1.0]:
		_add_solid_cover("SnakeWestA_%s" % ("T" if sy < 0 else "B"), Vector2(-2150.0, sy * 1150.0), Vector2(44, 240), steel_col)
		_add_solid_cover("SnakeWestB_%s" % ("T" if sy < 0 else "B"), Vector2(-2350.0, sy * 800.0), Vector2(44, 240), steel_col)
		_add_solid_cover("SnakeEastA_%s" % ("T" if sy < 0 else "B"), Vector2(2150.0, sy * 1150.0), Vector2(44, 240), steel_col)
		_add_solid_cover("SnakeEastB_%s" % ("T" if sy < 0 else "B"), Vector2(2350.0, sy * 800.0), Vector2(44, 240), steel_col)
		
	# 6. Inner-to-Mid Ring Gap Covers (eliminates long open lanes inside ±1600)
	for i in range(diag_signs.size()):
		var s: Vector2 = diag_signs[i]
		_add_solid_cover("GotchaInnerFlankH_%d" % i, Vector2(s.x * 1360.0, s.y * 380.0), Vector2(180, 44), steel_col)
		_add_solid_cover("GotchaInnerFlankV_%d" % i, Vector2(s.x * 380.0, s.y * 1480.0), Vector2(44, 180), steel_col)
		_add_solid_cover("GotchaMidRingBoxA_%d" % i, Vector2(s.x * 900.0, s.y * 1460.0), Vector2(86, 86), accent_col)
		_add_solid_cover("GotchaMidRingBoxB_%d" % i, Vector2(s.x * 1460.0, s.y * 900.0), Vector2(86, 86), accent_col)
		
	# 7. Cardinal Outer Plaza Bunkers (covers open zones between ±1620 gates and ±2400 bastions)
	for i in range(diag_signs.size()):
		var s: Vector2 = diag_signs[i]
		_add_solid_cover("CardinalPlazaWallNS_%d" % i, Vector2(s.x * 390.0, s.y * 1960.0), Vector2(210, 46), bunker_col)
		_add_solid_cover("CardinalPlazaPillarNS_%d" % i, Vector2(s.x * 640.0, s.y * 1780.0), Vector2(88, 88), accent_col)
		_add_solid_cover("CardinalPlazaWallWE_%d" % i, Vector2(s.x * 1960.0, s.y * 390.0), Vector2(46, 210), bunker_col)
		_add_solid_cover("CardinalPlazaPillarWE_%d" % i, Vector2(s.x * 1780.0, s.y * 640.0), Vector2(88, 88), accent_col)
		
	# 8. Mid-Outer Transition Corridors & Diagonal Bunkers
	for i in range(diag_signs.size()):
		var s: Vector2 = diag_signs[i]
		_add_solid_cover("MidOuterWallNS_%d" % i, Vector2(s.x * 1060.0, s.y * 1840.0), Vector2(48, 230), bunker_col)
		_add_solid_cover("MidOuterWallWE_%d" % i, Vector2(s.x * 1840.0, s.y * 1060.0), Vector2(230, 48), bunker_col)
		_add_solid_cover("DiagMidBunkerA_%d" % i, Vector2(s.x * 1760.0, s.y * 2060.0), Vector2(92, 92), accent_col)
		_add_solid_cover("DiagMidBunkerB_%d" % i, Vector2(s.x * 2060.0, s.y * 1760.0), Vector2(92, 92), accent_col)
		
	# 9. Outer Octant L-Bunkers & Flank Covers (fills all 8 outer mid-plains)
	for i in range(diag_signs.size()):
		var s: Vector2 = diag_signs[i]
		_add_solid_cover("OctantBunkerNS_H_%d" % i, Vector2(s.x * 1020.0, s.y * 2720.0), Vector2(250, 48), bunker_col)
		_add_solid_cover("OctantBunkerNS_V_%d" % i, Vector2(s.x * 1145.0, s.y * 2600.0), Vector2(48, 220), bunker_col)
		_add_solid_cover("OctantFlankNS_%d" % i, Vector2(s.x * 1540.0, s.y * 2460.0), Vector2(220, 46), steel_col)
		_add_solid_cover("OctantPillboxNS_%d" % i, Vector2(s.x * 760.0, s.y * 2960.0), Vector2(92, 92), accent_col)
		
		_add_solid_cover("OctantBunkerWE_V_%d" % i, Vector2(s.x * 2720.0, s.y * 1020.0), Vector2(48, 250), bunker_col)
		_add_solid_cover("OctantBunkerWE_H_%d" % i, Vector2(s.x * 2600.0, s.y * 1145.0), Vector2(220, 48), bunker_col)
		_add_solid_cover("OctantFlankWE_%d" % i, Vector2(s.x * 2460.0, s.y * 1540.0), Vector2(46, 220), steel_col)
		_add_solid_cover("OctantPillboxWE_%d" % i, Vector2(s.x * 2960.0, s.y * 760.0), Vector2(92, 92), accent_col)
		
	# 10. Outer Perimeter Sniper-Lane Dividers & Corner Wings
	_add_solid_cover("PerimeterGuardN", Vector2(0.0, -2960.0), Vector2(52, 220), steel_col)
	_add_solid_cover("PerimeterGuardS", Vector2(0.0, 2960.0), Vector2(52, 220), steel_col)
	_add_solid_cover("PerimeterGuardW", Vector2(-2960.0, 0.0), Vector2(220, 52), steel_col)
	_add_solid_cover("PerimeterGuardE", Vector2(2960.0, 0.0), Vector2(220, 52), steel_col)
	
	for i in range(diag_signs.size()):
		var s: Vector2 = diag_signs[i]
		_add_solid_cover("CornerWingH_%d" % i, Vector2(s.x * 2400.0, s.y * 2920.0), Vector2(240, 46), steel_col)
		_add_solid_cover("CornerWingV_%d" % i, Vector2(s.x * 2920.0, s.y * 2400.0), Vector2(46, 240), steel_col)
		_add_solid_cover("CornerMidPillarA_%d" % i, Vector2(s.x * 2620.0, s.y * 2120.0), Vector2(86, 86), accent_col)
		_add_solid_cover("CornerMidPillarB_%d" % i, Vector2(s.x * 2120.0, s.y * 2620.0), Vector2(86, 86), accent_col)

func _build_destructible_gotcha_walls() -> void:
	if has_node("DestructibleCovers"):
		destructible_covers_container = $DestructibleCovers
		return
		
	destructible_covers_container = Node2D.new()
	destructible_covers_container.name = "DestructibleCovers"
	add_child(destructible_covers_container)
	
	var layouts: Array[Dictionary] = [
		# Central Gotcha ring destructible gates
		{ "pos": Vector2(0, -180), "size": Vector2(150, 38) },
		{ "pos": Vector2(0, 180), "size": Vector2(150, 38) },
		{ "pos": Vector2(-180, 0), "size": Vector2(38, 150) },
		{ "pos": Vector2(180, 0), "size": Vector2(38, 150) },
		# Inner tactical flank barricades
		{ "pos": Vector2(-500, -680), "size": Vector2(160, 40) },
		{ "pos": Vector2(500, -680), "size": Vector2(160, 40) },
		{ "pos": Vector2(-500, 420), "size": Vector2(160, 40) },
		{ "pos": Vector2(500, 420), "size": Vector2(160, 40) },
		# Mid-ring corridor doors
		{ "pos": Vector2(-950, -350), "size": Vector2(40, 170) },
		{ "pos": Vector2(950, -350), "size": Vector2(40, 170) },
		{ "pos": Vector2(-950, 350), "size": Vector2(40, 170) },
		{ "pos": Vector2(950, 350), "size": Vector2(40, 170) },
		{ "pos": Vector2(-380, -1250), "size": Vector2(170, 40) },
		{ "pos": Vector2(380, -1250), "size": Vector2(170, 40) },
		{ "pos": Vector2(-380, 1250), "size": Vector2(170, 40) },
		{ "pos": Vector2(380, 1250), "size": Vector2(170, 40) },
		# Outer ring Gotcha destructible bunkers
		{ "pos": Vector2(0, -1820), "size": Vector2(180, 42) },
		{ "pos": Vector2(0, 1820), "size": Vector2(180, 42) },
		{ "pos": Vector2(-1820, 0), "size": Vector2(42, 180) },
		{ "pos": Vector2(1820, 0), "size": Vector2(42, 180) },
		{ "pos": Vector2(-1500, -2150), "size": Vector2(180, 42) },
		{ "pos": Vector2(1500, -2150), "size": Vector2(180, 42) },
		{ "pos": Vector2(-1500, 2150), "size": Vector2(180, 42) },
		{ "pos": Vector2(1500, 2150), "size": Vector2(180, 42) },
		{ "pos": Vector2(-2150, -1500), "size": Vector2(42, 180) },
		{ "pos": Vector2(2150, -1500), "size": Vector2(42, 180) },
		{ "pos": Vector2(-2150, 1500), "size": Vector2(42, 180) },
		{ "pos": Vector2(2150, 1500), "size": Vector2(42, 180) },
		# Outer bastion gates & perimeter trench destructible barricades
		{ "pos": Vector2(0, -2400), "size": Vector2(170, 42) },
		{ "pos": Vector2(0, 2400), "size": Vector2(170, 42) },
		{ "pos": Vector2(-2400, 0), "size": Vector2(42, 170) },
		{ "pos": Vector2(2400, 0), "size": Vector2(42, 170) },
		{ "pos": Vector2(-1450, -2850), "size": Vector2(42, 175) },
		{ "pos": Vector2(1450, -2850), "size": Vector2(42, 175) },
		{ "pos": Vector2(-1450, 2850), "size": Vector2(42, 175) },
		{ "pos": Vector2(1450, 2850), "size": Vector2(42, 175) },
		{ "pos": Vector2(-2850, -1450), "size": Vector2(175, 42) },
		{ "pos": Vector2(2850, -1450), "size": Vector2(175, 42) },
		{ "pos": Vector2(-2850, 1450), "size": Vector2(175, 42) },
		{ "pos": Vector2(2850, 1450), "size": Vector2(175, 42) },
		# Additional inner & mid-ring tactical Gotcha barricades
		{ "pos": Vector2(-900, 0), "size": Vector2(42, 165) },
		{ "pos": Vector2(900, 0), "size": Vector2(42, 165) },
		{ "pos": Vector2(0, -1500), "size": Vector2(165, 42) },
		{ "pos": Vector2(0, 1500), "size": Vector2(165, 42) },
		{ "pos": Vector2(-1150, -450), "size": Vector2(42, 170) },
		{ "pos": Vector2(1150, -450), "size": Vector2(42, 170) },
		{ "pos": Vector2(-1150, 450), "size": Vector2(42, 170) },
		{ "pos": Vector2(1150, 450), "size": Vector2(42, 170) },
		{ "pos": Vector2(-600, -1350), "size": Vector2(42, 170) },
		{ "pos": Vector2(600, -1350), "size": Vector2(42, 170) },
		{ "pos": Vector2(-600, 1350), "size": Vector2(42, 170) },
		{ "pos": Vector2(600, 1350), "size": Vector2(42, 170) },
		# Cardinal plaza & bastion flank destructible shields
		{ "pos": Vector2(-720, -2050), "size": Vector2(175, 42) },
		{ "pos": Vector2(720, -2050), "size": Vector2(175, 42) },
		{ "pos": Vector2(-720, 2050), "size": Vector2(175, 42) },
		{ "pos": Vector2(720, 2050), "size": Vector2(175, 42) },
		{ "pos": Vector2(-2050, -720), "size": Vector2(42, 175) },
		{ "pos": Vector2(2050, -720), "size": Vector2(42, 175) },
		{ "pos": Vector2(-2050, 720), "size": Vector2(42, 175) },
		{ "pos": Vector2(2050, 720), "size": Vector2(42, 175) },
		# Mid-outer diagonal lane destructible gates
		{ "pos": Vector2(-1320, -1820), "size": Vector2(175, 42) },
		{ "pos": Vector2(1320, -1820), "size": Vector2(175, 42) },
		{ "pos": Vector2(-1320, 1820), "size": Vector2(175, 42) },
		{ "pos": Vector2(1320, 1820), "size": Vector2(175, 42) },
		{ "pos": Vector2(-1820, -1320), "size": Vector2(42, 175) },
		{ "pos": Vector2(1820, -1320), "size": Vector2(42, 175) },
		{ "pos": Vector2(-1820, 1320), "size": Vector2(42, 175) },
		{ "pos": Vector2(1820, 1320), "size": Vector2(42, 175) },
		# Outer octant & corner corridor destructible barricades
		{ "pos": Vector2(-1850, -2520), "size": Vector2(180, 42) },
		{ "pos": Vector2(1850, -2520), "size": Vector2(180, 42) },
		{ "pos": Vector2(-1850, 2520), "size": Vector2(180, 42) },
		{ "pos": Vector2(1850, 2520), "size": Vector2(180, 42) },
		{ "pos": Vector2(-2520, -1850), "size": Vector2(42, 180) },
		{ "pos": Vector2(2520, -1850), "size": Vector2(42, 180) },
		{ "pos": Vector2(-2520, 1850), "size": Vector2(42, 180) },
		{ "pos": Vector2(2520, 1850), "size": Vector2(42, 180) },
		{ "pos": Vector2(-420, -2920), "size": Vector2(42, 175) },
		{ "pos": Vector2(420, -2920), "size": Vector2(42, 175) },
		{ "pos": Vector2(-420, 2920), "size": Vector2(42, 175) },
		{ "pos": Vector2(420, 2920), "size": Vector2(42, 175) },
		{ "pos": Vector2(-2920, -420), "size": Vector2(175, 42) },
		{ "pos": Vector2(2920, -420), "size": Vector2(175, 42) },
		{ "pos": Vector2(-2920, 420), "size": Vector2(175, 42) },
		{ "pos": Vector2(2920, 420), "size": Vector2(175, 42) }
	]
	
	for i in range(layouts.size()):
		var item: Dictionary = layouts[i]
		var dw: StaticBody2D = DestructibleWallScript.new() as StaticBody2D
		dw.name = "DestructibleGotcha_%d" % (i + 1)
		dw.position = item["pos"]
		dw.set("wall_size", item["size"])
		dw.set("max_health", 125.0)
		dw.set("respawn_delay", 20.0)
		destructible_covers_container.add_child(dw)

func _build_expanded_markers() -> void:
	if spawn_points_container != null:
		var extra_spawns: Array[Vector2] = [
			Vector2(-2100, -2100), Vector2(2100, -2100),
			Vector2(-2100, 2100), Vector2(2100, 2100),
			Vector2(0, -2200), Vector2(0, 2200),
			Vector2(-2200, 0), Vector2(2200, 0),
			Vector2(-620, -2620), Vector2(620, -2620),
			Vector2(-620, 2620), Vector2(620, 2620),
			Vector2(-2620, -620), Vector2(2620, -620),
			Vector2(-2620, 620), Vector2(2620, 620),
			Vector2(-1620, -2700), Vector2(1620, -2700),
			Vector2(-1620, 2700), Vector2(1620, 2700),
			Vector2(-2700, -1620), Vector2(2700, -1620),
			Vector2(-2700, 1620), Vector2(2700, 1620),
			Vector2(-220, -2960), Vector2(220, -2960),
			Vector2(-220, 2960), Vector2(220, 2960),
			Vector2(-2960, -220), Vector2(2960, -220),
			Vector2(-2960, 220), Vector2(2960, 220)
		]
		for i in range(extra_spawns.size()):
			var m_name := "OuterSpawn_%d" % (i + 1)
			if not spawn_points_container.has_node(m_name):
				var m := Marker2D.new()
				m.name = m_name
				m.position = extra_spawns[i]
				spawn_points_container.add_child(m)
				
	if powerup_spawns_container != null:
		var extra_powerups: Array[Vector2] = [
			Vector2(0, -2050), Vector2(0, 2050),
			Vector2(-2050, 0), Vector2(2050, 0),
			Vector2(-1900, -1900), Vector2(1900, -1900),
			Vector2(-1900, 1900), Vector2(1900, 1900),
			Vector2(-2650, -1350), Vector2(2650, -1350),
			Vector2(-2650, 1350), Vector2(2650, 1350),
			Vector2(-1350, -2650), Vector2(1350, -2650),
			Vector2(-1350, 2650), Vector2(1350, 2650),
			Vector2(-2580, -2580), Vector2(2580, -2580),
			Vector2(-2580, 2580), Vector2(2580, 2580),
			Vector2(-580, -2750), Vector2(580, -2750),
			Vector2(-580, 2750), Vector2(580, 2750),
			Vector2(-2750, -580), Vector2(2750, -580),
			Vector2(-2750, 580), Vector2(2750, 580),
			Vector2(-1480, -600), Vector2(1480, -600),
			Vector2(-1480, 600), Vector2(1480, 600),
			Vector2(-280, -980), Vector2(280, -980),
			Vector2(-280, 980), Vector2(280, 980),
			Vector2(-1650, -750), Vector2(1650, -750),
			Vector2(-1650, 750), Vector2(1650, 750),
			Vector2(-1650, -1250), Vector2(1650, -1250),
			Vector2(-1650, 1250), Vector2(1650, 1250),
			Vector2(-1250, -1650), Vector2(1250, -1650),
			Vector2(-1250, 1650), Vector2(1250, 1650),
			Vector2(-2250, -1850), Vector2(2250, -1850),
			Vector2(-2250, 1850), Vector2(2250, 1850),
			Vector2(-1850, -2250), Vector2(1850, -2250),
			Vector2(-1850, 2250), Vector2(1850, 2250)
		]
		for i in range(extra_powerups.size()):
			var p_name := "OuterPowerUpSpawn_%d" % (i + 1)
			if not powerup_spawns_container.has_node(p_name):
				var m := Marker2D.new()
				m.name = p_name
				m.position = extra_powerups[i]
				powerup_spawns_container.add_child(m)

func get_spawn_points() -> Array[Marker2D]:
	var points: Array[Marker2D] = []
	if spawn_points_container != null:
		for child in spawn_points_container.get_children():
			if child is Marker2D:
				points.append(child)
	return points

func get_spawn_positions() -> Array[Vector2]:
	var positions: Array[Vector2] = []
	for marker in get_spawn_points():
		positions.append(marker.global_position)
	if positions.is_empty():
		positions = [
			Vector2(-1350, -1350), Vector2(1350, -1350),
			Vector2(-1350, 1350), Vector2(1350, 1350),
			Vector2(0, -1050), Vector2(0, 1050),
			Vector2(-1050, 0), Vector2(1050, 0),
			Vector2(-2100, -2100), Vector2(2100, -2100),
			Vector2(-2100, 2100), Vector2(2100, 2100)
		]
	return positions

func get_powerup_spawn_positions() -> Array[Vector2]:
	var positions: Array[Vector2] = []
	if powerup_spawns_container != null:
		for child in powerup_spawns_container.get_children():
			if child is Marker2D:
				positions.append(child.global_position)
	if positions.is_empty():
		positions = [
			Vector2(0, 0), Vector2(0, -500), Vector2(0, 500),
			Vector2(-450, -350), Vector2(450, -350),
			Vector2(-850, -850), Vector2(850, -850),
			Vector2(-850, 850), Vector2(850, 850),
			Vector2(0, -1100), Vector2(0, 1100),
			Vector2(-1100, 0), Vector2(1100, 0),
			Vector2(0, -2050), Vector2(0, 2050),
			Vector2(-2050, 0), Vector2(2050, 0),
			Vector2(-1900, -1900), Vector2(1900, -1900),
			Vector2(-1900, 1900), Vector2(1900, 1900),
			Vector2(-1350, -2650), Vector2(1350, -2650),
			Vector2(-1350, 2650), Vector2(1350, 2650)
		]
	return positions

func get_barrel_spawn_positions() -> Array[Vector2]:
	return [
		Vector2(-175, -650), Vector2(175, -650),
		Vector2(0, -260), Vector2(-550, 120),
		Vector2(550, 120), Vector2(0, 600),
		Vector2(-425, 750), Vector2(425, 750),
		Vector2(-1750, -1750), Vector2(1750, -1750),
		Vector2(-1750, 1750), Vector2(1750, 1750),
		Vector2(0, -2000), Vector2(0, 2000),
		Vector2(-2000, 0), Vector2(2000, 0),
		Vector2(-1020, -2480), Vector2(1020, -2480),
		Vector2(-1020, 2480), Vector2(1020, 2480),
		Vector2(-2480, -1020), Vector2(2480, -1020),
		Vector2(-2480, 1020), Vector2(2480, 1020),
		Vector2(-920, -750), Vector2(920, -750),
		Vector2(-920, 750), Vector2(920, 750),
		Vector2(-1500, -1150), Vector2(1500, -1150),
		Vector2(-1500, 1150), Vector2(1500, 1150),
		Vector2(-380, -2180), Vector2(380, -2180),
		Vector2(-380, 2180), Vector2(380, 2180),
		Vector2(-2180, -380), Vector2(2180, -380),
		Vector2(-2180, 380), Vector2(2180, 380),
		Vector2(-1500, -1900), Vector2(1500, -1900),
		Vector2(-1500, 1900), Vector2(1500, 1900),
		Vector2(-2350, -2650), Vector2(2350, -2650),
		Vector2(-2350, 2650), Vector2(2350, 2650)
	]

func _draw() -> void:
	# Floor background (tactical dark grid across full 6400x6400 arena)
	var rect := Rect2(-HALF_SIZE, -HALF_SIZE, ARENA_SIZE, ARENA_SIZE)
	draw_rect(rect, Color(0.08, 0.09, 0.11, 1.0), true)
	
	# Grid lines every 100px
	var grid_color := Color(0.13, 0.15, 0.18, 0.7)
	for x in range(-int(HALF_SIZE), int(HALF_SIZE) + 1, 100):
		draw_line(Vector2(x, -HALF_SIZE), Vector2(x, HALF_SIZE), grid_color, 1.0)
	for y in range(-int(HALF_SIZE), int(HALF_SIZE) + 1, 100):
		draw_line(Vector2(-HALF_SIZE, y), Vector2(HALF_SIZE, y), grid_color, 1.0)
		
	# Major quadrant dividers
	var divider_color := Color(0.18, 0.22, 0.28, 0.9)
	draw_line(Vector2(0, -HALF_SIZE), Vector2(0, HALF_SIZE), divider_color, 2.0)
	draw_line(Vector2(-HALF_SIZE, 0), Vector2(HALF_SIZE, 0), divider_color, 2.0)
	
	# Inner sector boundary tactical guide rectangle (1600px ring)
	var inner_rect := Rect2(-1600.0, -1600.0, 3200.0, 3200.0)
	draw_rect(inner_rect, Color(0.20, 0.28, 0.38, 0.45), false, 3.0)
	
	# Central combat circle rings
	draw_arc(Vector2.ZERO, 300.0, 0.0, TAU, 64, Color(0.25, 0.45, 0.65, 0.5), 3.0)
	draw_arc(Vector2.ZERO, 80.0, 0.0, TAU, 32, Color(0.8, 0.3, 0.2, 0.4), 2.0)
	
	# Perimeter boundary outline
	draw_rect(rect, Color(0.8, 0.2, 0.2, 0.8), false, 6.0)
