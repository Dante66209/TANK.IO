# res://Scripts/World/fog_of_war.gd
class_name FogOfWar extends CanvasLayer

## Fog of War controller for TANK.IO.
## Renders circular vision vignette (560px radius) around the local player tank
## and performs real-time entity culling for entities outside player sight radius.

@export var default_sight_radius: float = 560.0
@export var feather_radius: float = 90.0
@export var fog_shader: Shader = preload("res://Shaders/fog_of_war.gdshader")

var player_tank: Node2D = null
var _color_rect: ColorRect = null
var _shader_mat: ShaderMaterial = null

func _ready() -> void:
	layer = 10 # Above world entities, beneath HUD
	_setup_fog_overlay()
	_find_player()

func _setup_fog_overlay() -> void:
	_color_rect = ColorRect.new()
	_color_rect.anchors_preset = Control.PRESET_FULL_RECT
	_color_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	if fog_shader != null:
		_shader_mat = ShaderMaterial.new()
		_shader_mat.shader = fog_shader
		_shader_mat.set_shader_parameter("viewport_size", Vector2(1300.0, 800.0))
		_shader_mat.set_shader_parameter("sight_radius_px", default_sight_radius)
		_shader_mat.set_shader_parameter("feather_px", feather_radius)
		_shader_mat.set_shader_parameter("fog_color", Color(0.06, 0.07, 0.1, 0.85))
		_color_rect.material = _shader_mat
	else:
		_color_rect.color = Color(0, 0, 0, 0)
		
	add_child(_color_rect)

func _find_player() -> void:
	var players := get_tree().get_nodes_in_group("player")
	if not players.is_empty():
		player_tank = players[0] as Node2D
		return
	var tanks := get_tree().get_nodes_in_group("tanks")
	for t in tanks:
		if is_instance_valid(t) and t.get("is_player") == true:
			player_tank = t as Node2D
			return

func _get_active_vision_target() -> Node2D:
	if is_instance_valid(player_tank) and player_tank.get("is_spectating") == true:
		var spec = player_tank.get("spectated_tank")
		if spec != null and is_instance_valid(spec) and spec is Node2D and spec.get("is_dead") != true:
			return spec as Node2D
	return player_tank

func _process(_delta: float) -> void:
	if not is_instance_valid(player_tank):
		_find_player()
		
	var vision_target: Node2D = _get_active_vision_target()
	var is_spec: bool = (vision_target != null and vision_target != player_tank)
	var player_pos: Vector2 = Vector2.ZERO
	var sight_radius: float = default_sight_radius
	var viewport := get_viewport()
	var vp_size: Vector2 = viewport.get_visible_rect().size if viewport != null else Vector2(1300.0, 800.0)
	if _shader_mat != null:
		_shader_mat.set_shader_parameter("viewport_size", vp_size)
	
	if is_instance_valid(vision_target):
		player_pos = vision_target.global_position
		if "sight_radius" in vision_target:
			var sr_val = vision_target.get("sight_radius")
			if sr_val != null:
				sight_radius = maxf(default_sight_radius, float(sr_val)) if is_spec else float(sr_val)
			
		# Screen-space conversion for shader
		if viewport != null:
			var canvas_transform := viewport.get_canvas_transform()
			var screen_pos := canvas_transform * player_pos
			if _shader_mat != null:
				_shader_mat.set_shader_parameter("player_screen_pos", screen_pos)
				_shader_mat.set_shader_parameter("sight_radius_px", sight_radius)
				_shader_mat.set_shader_parameter("feather_px", feather_radius)
	else:
		# If no player, center fog
		if _shader_mat != null:
			_shader_mat.set_shader_parameter("player_screen_pos", vp_size * 0.5)
			_shader_mat.set_shader_parameter("sight_radius_px", 0.0)
			
	_cull_entities(player_pos, sight_radius, vision_target)

func _cull_entities(player_pos: Vector2, sight_radius: float, vision_target: Node2D = null) -> void:
	var active_node: Node2D = vision_target if vision_target != null else player_tank
	var has_player: bool = is_instance_valid(active_node) and active_node.get("is_dead") != true
	
	# Cull Enemy Tanks
	var tanks := get_tree().get_nodes_in_group("tanks")
	for tank in tanks:
		if not is_instance_valid(tank) or tank == player_tank:
			continue
		var is_dead_tank: bool = tank.get("is_dead") == true
		var in_sight := false
		if has_player:
			var dist: float = player_pos.distance_to((tank as Node2D).global_position)
			in_sight = (dist <= sight_radius)
			
		tank.set("is_in_sight", in_sight)
		if "overhead_ui" in tank and tank.overhead_ui != null:
			tank.overhead_ui.visible = in_sight and not is_dead_tank
			
	# Cull Barrels
	var barrels := get_tree().get_nodes_in_group("barrels")
	for barrel in barrels:
		if not is_instance_valid(barrel):
			continue
		var in_sight := false
		if has_player:
			var dist: float = player_pos.distance_to((barrel as Node2D).global_position)
			in_sight = (dist <= sight_radius)
		barrel.set("is_in_sight", in_sight)
		
	# Cull Power-ups
	var powerups := get_tree().get_nodes_in_group("powerups")
	for pu in powerups:
		if not is_instance_valid(pu):
			continue
		var in_sight := false
		if has_player:
			var dist: float = player_pos.distance_to((pu as Node2D).global_position)
			in_sight = (dist <= sight_radius)
		pu.set("is_in_sight", in_sight)
