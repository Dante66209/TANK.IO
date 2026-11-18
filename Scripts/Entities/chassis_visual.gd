# res://Scripts/Entities/chassis_visual.gd
class_name ChassisVisual extends Node2D

@export var body_color: Color = Color(0.2, 0.45, 0.75, 1.0): # Player default blue
	set(val):
		body_color = val
		queue_redraw()
@export var track_color: Color = Color(0.12, 0.14, 0.16, 1.0)
@export var outline_color: Color = Color(0.08, 0.1, 0.12, 1.0)

func _ready() -> void:
	queue_redraw()

func _draw() -> void:
	# Left track (top in local 2D space)
	draw_rect(Rect2(-24.0, -22.0, 48.0, 10.0), track_color, true)
	draw_rect(Rect2(-24.0, -22.0, 48.0, 10.0), outline_color, false, 1.5)
	for i in range(-20, 24, 8):
		draw_line(Vector2(i, -22.0), Vector2(i, -12.0), Color(0.2, 0.22, 0.25, 0.8), 1.0)
		
	# Right track (bottom in local 2D space)
	draw_rect(Rect2(-24.0, 12.0, 48.0, 10.0), track_color, true)
	draw_rect(Rect2(-24.0, 12.0, 48.0, 10.0), outline_color, false, 1.5)
	for i in range(-20, 24, 8):
		draw_line(Vector2(i, 12.0), Vector2(i, 22.0), Color(0.2, 0.22, 0.25, 0.8), 1.0)

	# Main Hull
	var hull_rect := Rect2(-20.0, -15.0, 40.0, 30.0)
	draw_rect(hull_rect, body_color, true)
	draw_rect(hull_rect, outline_color, false, 2.0)
	
	# Front armor slope / chevron
	var points: PackedVector2Array = [
		Vector2(14.0, -10.0),
		Vector2(20.0, 0.0),
		Vector2(14.0, 10.0)
	]
	draw_polyline(points, Color(1.0, 1.0, 1.0, 0.4), 2.0)
