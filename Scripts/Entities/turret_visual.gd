# res://Scripts/Entities/turret_visual.gd
class_name TurretVisual extends Node2D

@export var turret_color: Color = Color(0.15, 0.35, 0.65, 1.0):
	set(val):
		turret_color = val
		queue_redraw()
@export var barrel_color: Color = Color(0.2, 0.22, 0.25, 1.0):
	set(val):
		barrel_color = val
		queue_redraw()
@export var outline_color: Color = Color(0.08, 0.1, 0.12, 1.0)

func _ready() -> void:
	queue_redraw()

func get_hatch_color() -> Color:
	return turret_color.darkened(0.25)

func _draw() -> void:
	# Long barrel extending right (x > 0)
	var barrel_rect := Rect2(0.0, -4.0, 38.0, 8.0)
	draw_rect(barrel_rect, barrel_color, true)
	draw_rect(barrel_rect, outline_color, false, 1.5)
	
	# Muzzle brake ring
	var brake_rect := Rect2(32.0, -6.0, 6.0, 12.0)
	draw_rect(brake_rect, Color(0.12, 0.14, 0.16, 1.0), true)
	draw_rect(brake_rect, outline_color, false, 1.0)
	
	# Turret cupola (main dome)
	draw_circle(Vector2.ZERO, 15.0, turret_color)
	draw_arc(Vector2.ZERO, 15.0, 0.0, TAU, 32, outline_color, 2.0)
	
	# Hatch details matching selected turret color
	draw_circle(Vector2(-3.0, 0.0), 6.0, get_hatch_color())
	draw_arc(Vector2(-3.0, 0.0), 6.0, 0.0, TAU, 16, outline_color, 1.0)
