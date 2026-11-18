# res://Scripts/Entities/powerup.gd
class_name PowerUp extends Area2D

## Collectible power-up entity.
## Area2D on Layer 6 (Pickups: 32), Mask: Layer 3 (Tanks: 4).

enum Type { HEALTH = 0, SHIELD = 1, RAPID_FIRE = 2, RICOCHET = 3, SPEED_BOOST = 4, CLUSTER_MINES = 5 }

var _monster_tex_instance: Texture2D = null

func _get_monster_texture() -> Texture2D:
	if _monster_tex_instance == null:
		if ResourceLoader.exists("res://Assets/monster_energy.png"):
			_monster_tex_instance = load("res://Assets/monster_energy.png") as Texture2D
		if _monster_tex_instance == null and FileAccess.file_exists("res://Assets/monster_energy.png"):
			var bytes := FileAccess.get_file_as_bytes("res://Assets/monster_energy.png")
			var img := Image.new()
			if not bytes.is_empty() and img.load_png_from_buffer(bytes) == OK:
				_monster_tex_instance = ImageTexture.create_from_image(img)
	return _monster_tex_instance

@export var powerup_type: Type = Type.HEALTH
@export var duration: float = 0.0
@export var value: float = 40.0
@export var auto_despawn: bool = false

var net_id: int = 0
var is_network_puppet: bool = false
var is_collected: bool = false
var lifetime: float = 0.0
const MAX_LIFETIME: float = 38.0
const BLINK_TIME: float = 33.0
var is_in_sight: bool = true

var _time: float = 0.0
var _base_y: float = 0.0
var _visual_rotation: float = 0.0

@onready var collision_shape: CollisionShape2D = $CollisionShape2D

func _ready() -> void:
	add_to_group("powerups")
	add_to_group("pickups")
	collision_layer = 32 # Layer 6
	collision_mask = 4   # Layer 3 (Tanks)
	_base_y = position.y
	_apply_type_defaults()
	body_entered.connect(_on_body_entered)
	queue_redraw()

func _apply_type_defaults() -> void:
	match powerup_type:
		Type.HEALTH:
			duration = 0.0
			value = 40.0
		Type.SHIELD:
			duration = 22.0
			value = 50.0
		Type.RAPID_FIRE:
			duration = 8.0
			value = 0.6
		Type.RICOCHET:
			duration = 0.0 # Count-based (20 shots)
			value = 20.0
		Type.SPEED_BOOST:
			duration = 15.0 # 15 seconds
			value = 2.0     # 2x speed multiplier
		Type.CLUSTER_MINES:
			duration = 0.0
			value = 3.0

func setup(p_type: Type) -> void:
	powerup_type = p_type
	_apply_type_defaults()
	queue_redraw()

func _process(delta: float) -> void:
	if is_collected:
		return
		
	_time += delta
	lifetime += delta
	
	# Floating bobbing animation: sin(time * 4) * 5px
	position.y = _base_y + sin(_time * 4.0) * 5.0
	_visual_rotation += 1.5 * delta
	
	# Optional lifetime despawn (disabled by default so powerups remain on map until collected)
	if not is_network_puppet and auto_despawn:
		if lifetime >= BLINK_TIME:
			var blink_factor: float = 0.4 + 0.6 * absf(sin(_time * 10.0))
			modulate.a = blink_factor
			
		if lifetime >= MAX_LIFETIME:
			queue_free()
			return
	elif modulate.a != 1.0:
		modulate.a = 1.0
		
	queue_redraw()

func _on_body_entered(body: Node2D) -> void:
	if is_network_puppet or is_collected:
		return
	collect(body)

func collect(collector: Node2D) -> void:
	if is_network_puppet or is_collected:
		return
	if not is_instance_valid(collector):
		return
	if collector.get("is_dead") == true:
		return
		
	is_collected = true
	
	# Disable collisions immediately
	collision_layer = 0
	collision_mask = 0
	if collision_shape != null:
		collision_shape.set_deferred("disabled", true)
		
	if collector.has_method("apply_powerup"):
		collector.apply_powerup(int(powerup_type), duration, value)
		
	if GameEvents != null:
		GameEvents.powerup_collected.emit(self, collector, int(powerup_type))
		
	_spawn_collect_vfx()
	visible = false
	queue_free()

func apply_network_collect_fx(collector: Node2D) -> void:
	if is_collected:
		return
	is_collected = true
	collision_layer = 0
	collision_mask = 0
	if collision_shape != null:
		collision_shape.set_deferred("disabled", true)
	if collector != null and is_instance_valid(collector):
		if collector.has_method("apply_network_powerup"):
			collector.apply_network_powerup(int(powerup_type), duration, value, true)
		if GameEvents != null and collector.get("is_player") == true:
			GameEvents.powerup_collected.emit(self, collector, int(powerup_type))
	_spawn_collect_vfx()
	visible = false
	queue_free()

func _spawn_collect_vfx() -> void:
	var parent_node := get_parent()
	if parent_node == null:
		return
		
	var sparkle := CPUParticles2D.new()
	sparkle.emitting = true
	sparkle.one_shot = true
	sparkle.explosiveness = 0.8
	sparkle.lifetime = 0.4
	sparkle.amount = 16
	sparkle.spread = 180.0
	sparkle.initial_velocity_min = 40.0
	sparkle.initial_velocity_max = 90.0
	sparkle.gravity = Vector2.ZERO
	sparkle.scale_amount_min = 2.0
	sparkle.scale_amount_max = 4.0
	
	match powerup_type:
		Type.HEALTH:
			sparkle.color = Color(0.2, 0.9, 0.3, 1.0)
		Type.SHIELD:
			sparkle.color = Color(0.2, 0.8, 1.0, 1.0)
		Type.RAPID_FIRE:
			sparkle.color = Color(1.0, 0.85, 0.2, 1.0)
		Type.RICOCHET:
			sparkle.color = Color(0.2, 0.9, 1.0, 1.0)
		Type.SPEED_BOOST:
			sparkle.color = Color(0.85, 1.0, 0.3, 1.0)
		Type.CLUSTER_MINES:
			sparkle.color = Color(1.0, 0.48, 0.14, 1.0)
			
	sparkle.global_position = global_position
	parent_node.add_child(sparkle)
	
	if get_tree() != null:
		var timer := get_tree().create_timer(0.45)
		timer.timeout.connect(sparkle.queue_free)

func _draw() -> void:
	# Rotating glow aura
	var aura_color: Color
	match powerup_type:
		Type.HEALTH:
			aura_color = Color(0.2, 0.85, 0.3, 0.25)
		Type.SHIELD:
			aura_color = Color(0.2, 0.75, 1.0, 0.25)
		Type.RAPID_FIRE:
			aura_color = Color(1.0, 0.8, 0.2, 0.25)
		Type.RICOCHET:
			aura_color = Color(0.1, 0.85, 1.0, 0.3)
		Type.SPEED_BOOST:
			aura_color = Color(0.8, 1.0, 0.3, 0.35)
		Type.CLUSTER_MINES:
			aura_color = Color(1.0, 0.45, 0.12, 0.32)
			
	draw_circle(Vector2.ZERO, 22.0, aura_color)
	draw_arc(Vector2.ZERO, 18.0, 0.0, TAU, 24, aura_color * Color(1, 1, 1, 2.5), 2.0)
	
	# Icon specifics
	match powerup_type:
		Type.HEALTH:
			draw_circle(Vector2.ZERO, 15.0, Color(0.12, 0.18, 0.15, 0.9))
			var green := Color(0.2, 0.9, 0.35, 1.0)
			draw_rect(Rect2(-3.5, -10.0, 7.0, 20.0), green, true)
			draw_rect(Rect2(-10.0, -3.5, 20.0, 7.0), green, true)
		Type.SHIELD:
			draw_circle(Vector2.ZERO, 15.0, Color(0.1, 0.18, 0.25, 0.9))
			var cyan := Color(0.2, 0.8, 1.0, 1.0)
			var points := PackedVector2Array([
				Vector2(0, -10), Vector2(8, -5), Vector2(8, 4),
				Vector2(0, 10), Vector2(-8, 4), Vector2(-8, -5)
			])
			draw_colored_polygon(points, cyan)
		Type.RAPID_FIRE:
			draw_circle(Vector2.ZERO, 15.0, Color(0.25, 0.18, 0.08, 0.9))
			var gold := Color(1.0, 0.85, 0.2, 1.0)
			draw_line(Vector2(-4, -8), Vector2(-4, 8), gold, 3.0)
			draw_line(Vector2(4, -8), Vector2(4, 8), gold, 3.0)
			draw_circle(Vector2(-4, -8), 2.0, Color(1, 1, 1, 1))
			draw_circle(Vector2(4, -8), 2.0, Color(1, 1, 1, 1))
		Type.RICOCHET:
			# Angled bouncing arrow chevron
			draw_circle(Vector2.ZERO, 15.0, Color(0.08, 0.2, 0.25, 0.9))
			var teal := Color(0.2, 0.95, 1.0, 1.0)
			var ricochet_pts := PackedVector2Array([
				Vector2(-8, 6), Vector2(0, -6), Vector2(8, 6)
			])
			draw_polyline(ricochet_pts, teal, 3.0)
			draw_circle(Vector2(0, -6), 2.5, Color.WHITE)
		Type.SPEED_BOOST:
			# Dynamic ground shadow responsive to floating bobbing
			var bob_offset: float = position.y - _base_y
			draw_circle(Vector2(0.0, 20.0 - bob_offset), maxf(4.0, 14.0 - absf(bob_offset) * 0.8), Color(0.05, 0.08, 0.05, 0.35))
			
			# Backing circular badge
			draw_circle(Vector2.ZERO, 16.0, Color(0.12, 0.15, 0.14, 0.92))
			
			# White Monster Energy can sprite scaled to match the other power-up icons (~24x33px)
			var m_tex := _get_monster_texture()
			if m_tex != null:
				var can_w: float = 24.0
				var can_h: float = 33.0
				var can_rect := Rect2(-can_w * 0.5, -can_h * 0.5, can_w, can_h)
				draw_texture_rect(m_tex, can_rect, false)
			else:
				var lime := Color(0.8, 1.0, 0.3, 1.0)
				draw_line(Vector2(-6, 8), Vector2(0, -8), lime, 3.0)
				draw_line(Vector2(0, -8), Vector2(6, 8), lime, 3.0)
		Type.CLUSTER_MINES:
			draw_circle(Vector2.ZERO, 16.0, Color(0.22, 0.12, 0.08, 0.92))
			var sub_positions := [Vector2(0.0, -6.5), Vector2(-6.5, 4.5), Vector2(6.5, 4.5)]
			for mp in sub_positions:
				draw_circle(mp, 5.2, Color(0.20, 0.24, 0.28, 1.0))
				draw_arc(mp, 5.2, 0.0, TAU, 14, Color(1.0, 0.58, 0.16, 1.0), 1.4)
				draw_circle(mp, 2.2, Color(1.0, 0.25, 0.12, 1.0))
