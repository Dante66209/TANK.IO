# res://Scripts/Entities/shield_aura.gd
class_name ShieldAura extends Node2D

@export var radius: float = 34.0
@export var aura_color: Color = Color(0.2, 0.8, 1.0, 0.45)
@export var border_color: Color = Color(0.4, 0.9, 1.0, 0.85)

func _ready() -> void:
	queue_redraw()

func _draw() -> void:
	draw_circle(Vector2.ZERO, radius, aura_color)
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 32, border_color, 2.5)
