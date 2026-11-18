# res://Scripts/UI/floating_text.gd
class_name FloatingText extends Node2D

## Floating combat text (damage, crits, heals, notifications) with arcade pop animation.

var text: String = ""
var text_color: Color = Color.WHITE
var lifetime: float = 0.65
var total_lifetime: float = 0.65
var drift: Vector2 = Vector2.ZERO
var _label: Label = null

static func spawn(parent: Node, pos: Vector2, p_text: String, p_color: Color = Color(1.0, 0.35, 0.3, 1.0), p_size: int = 14) -> Node2D:
	if parent == null:
		return null
	var script := load("res://Scripts/UI/floating_text.gd") as GDScript
	var ft: Node2D = script.new() as Node2D
	ft.set("text", p_text)
	ft.set("text_color", p_color)
	ft.global_position = pos + Vector2(randf_range(-14.0, 14.0), -24.0)
	ft.set("drift", Vector2(randf_range(-18.0, 18.0), -55.0))
	parent.add_child(ft)
	ft.call("_create_label", p_size)
	return ft

func _create_label(font_size: int) -> void:
	_label = Label.new()
	_label.text = text
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", font_size)
	_label.add_theme_color_override("font_color", text_color)
	_label.add_theme_color_override("font_outline_color", Color(0.05, 0.05, 0.08, 0.95))
	_label.add_theme_constant_override("outline_size", 4)
	_label.custom_minimum_size = Vector2(60, 20)
	_label.position = Vector2(-30, -10)
	add_child(_label)
	
	# Initial scale punch
	scale = Vector2(1.3, 1.3)

func _process(delta: float) -> void:
	lifetime -= delta
	if lifetime <= 0.0:
		queue_free()
		return
		
	# Move upward with drift
	global_position += drift * delta
	drift.y = lerpf(drift.y, -15.0, 3.0 * delta)
	
	# Settle scale from punch back to 1.0
	scale = scale.lerp(Vector2.ONE, 8.0 * delta)
	
	# Fade out during second half of lifetime
	var alpha := clampf(lifetime / (total_lifetime * 0.5), 0.0, 1.0)
	modulate.a = alpha
