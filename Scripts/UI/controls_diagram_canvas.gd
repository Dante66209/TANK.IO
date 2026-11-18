# res://Scripts/UI/controls_diagram_canvas.gd
class_name ControlsDiagramCanvas extends Control

## Illustrated "Cómo Jugar" diagram for TANK.IO in translucent grayscale-slate style.
## Renders keyboard layout (Q, W, A, S, D, SHIFT, ESPACIO, ESC), illustrated mouse
## (Left Click, Right Click, Aim), callout lines, and starred tactical tips.

const COL_KEY_FILL := Color(0.76, 0.80, 0.86, 0.24)
const COL_KEY_FILL_HI := Color(0.86, 0.90, 0.95, 0.34)
const COL_KEY_BORDER := Color(0.90, 0.93, 0.97, 0.82)
const COL_KEY_SHADOW := Color(0.06, 0.08, 0.11, 0.55)
const COL_KEY_TEXT := Color(0.96, 0.97, 0.99, 0.96)
const COL_LABEL_YELLOW := Color(1.0, 0.92, 0.32, 1.0)
const COL_CALLOUT := Color(0.84, 0.88, 0.94, 0.78)
const COL_SUBTLE_TEXT := Color(0.86, 0.89, 0.94, 0.88)

func _ready() -> void:
	if custom_minimum_size == Vector2.ZERO:
		custom_minimum_size = Vector2(920, 445)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()

func _draw() -> void:
	var font: Font = get_theme_default_font()
	if font == null:
		font = ThemeDB.fallback_font

	_draw_keyboard_diagram(font)
	_draw_mouse_diagram(font)
	_draw_bottom_tips(font)

func _draw_keyboard_diagram(font: Font) -> void:
	# Row 1: Q, W, ESC
	var r_q := Rect2(190, 74, 60, 56)
	var r_w := Rect2(258, 74, 60, 56)
	var r_esc := Rect2(336, 74, 72, 56)

	# Row 2 (QWERTY offset): A, S, D
	var r_a := Rect2(206, 138, 60, 56)
	var r_s := Rect2(274, 138, 60, 56)
	var r_d := Rect2(342, 138, 60, 56)

	# Row 3 & 4: SHIFT (left), ESPACIO (bottom)
	var r_shift := Rect2(118, 202, 118, 50)
	var r_space := Rect2(256, 246, 208, 48)

	# Draw keys
	_draw_keycap(font, r_q, "Q", false)
	_draw_mine_icon(r_q.get_center() + Vector2(3, 6))

	_draw_keycap(font, r_w, "W", false)
	_draw_arrow_triangle(r_w.get_center() + Vector2(2, 6), -PI * 0.5)

	_draw_keycap(font, r_esc, "ESC", false, 14)
	_draw_pause_icon(r_esc.get_center() + Vector2(10, 7))

	_draw_keycap(font, r_a, "A", false)
	_draw_arrow_triangle(r_a.get_center() + Vector2(2, 6), PI)

	_draw_keycap(font, r_s, "S", false)
	_draw_arrow_triangle(r_s.get_center() + Vector2(2, 6), PI * 0.5)

	_draw_keycap(font, r_d, "D", false)
	_draw_arrow_triangle(r_d.get_center() + Vector2(2, 6), 0.0)

	_draw_keycap(font, r_shift, "SHIFT", true, 16)
	_draw_keycap(font, r_space, "ESPACIO", true, 16)

	# Callout lines & bright yellow labels
	# Q -> Mina de Proximidad (left)
	_draw_callout_left(font, Vector2(r_q.position.x, r_q.get_center().y), 26.0, "Mina de Proximidad")
	# W -> Mover arriba (top)
	_draw_callout_up(font, Vector2(r_w.get_center().x, r_w.position.y), 26.0, "Mover arriba")
	# ESC -> Pausa / Volumen (right)
	_draw_callout_right(font, Vector2(r_esc.end.x, r_esc.get_center().y), 26.0, "Pausa / Volumen")
	# A -> Mover izquierda (left)
	_draw_callout_left(font, Vector2(r_a.position.x, r_a.get_center().y), 26.0, "Mover izquierda")
	# S -> Mover abajo (down into gap above spacebar)
	_draw_callout_down(font, Vector2(r_s.get_center().x, r_s.end.y), 18.0, "Mover abajo")
	# D -> Mover derecha (right)
	_draw_callout_right(font, Vector2(r_d.end.x, r_d.get_center().y), 26.0, "Mover derecha")
	# SHIFT -> Dash / Turbo (left)
	_draw_callout_left(font, Vector2(r_shift.position.x, r_shift.get_center().y), 22.0, "Dash / Turbo")
	# ESPACIO -> Disparar (alt.) (right)
	_draw_callout_right(font, Vector2(r_space.end.x, r_space.get_center().y), 24.0, "Disparar (alt.)")

	# Arrow-keys fallback note cleanly under SHIFT (left of spacebar)
	_draw_centered_text(font, Vector2(142, 276), "o Teclas de Flechas", 12, COL_SUBTLE_TEXT, 200.0)

func _draw_mouse_diagram(font: Font) -> void:
	var mx := 648.0
	var my := 80.0
	var mw := 124.0
	var mh := 184.0
	var body_rect := Rect2(mx, my, mw, mh)
	var mid_x := mx + mw * 0.5
	var split_y := my + 82.0

	# Drop shadow
	_draw_rounded_box(Rect2(mx + 4, my + 5, mw, mh), 46.0, COL_KEY_SHADOW, Color(0, 0, 0, 0), 0.0)
	# Outer mouse shell
	_draw_rounded_box(body_rect, 46.0, Color(0.68, 0.72, 0.78, 0.20), COL_KEY_BORDER, 2.5)

	# Left click button highlight (active firing button)
	var lmb_poly := PackedVector2Array([
		Vector2(mx + 3, split_y - 2),
		Vector2(mx + 3, my + 44),
		Vector2(mx + 14, my + 18),
		Vector2(mx + 36, my + 5),
		Vector2(mid_x - 2, my + 3),
		Vector2(mid_x - 2, split_y - 2)
	])
	draw_colored_polygon(lmb_poly, Color(0.92, 0.95, 0.98, 0.34))

	# Right click button highlight (dash)
	var rmb_poly := PackedVector2Array([
		Vector2(mid_x + 2, split_y - 2),
		Vector2(mid_x + 2, my + 3),
		Vector2(mx + mw - 36, my + 5),
		Vector2(mx + mw - 14, my + 18),
		Vector2(mx + mw - 3, my + 44),
		Vector2(mx + mw - 3, split_y - 2)
	])
	draw_colored_polygon(rmb_poly, Color(0.76, 0.80, 0.86, 0.22))

	# Divider lines & scroll wheel
	draw_line(Vector2(mx + 2, split_y), Vector2(mx + mw - 2, split_y), COL_KEY_BORDER, 2.2)
	draw_line(Vector2(mid_x, my + 2), Vector2(mid_x, split_y), COL_KEY_BORDER, 2.2)
	_draw_rounded_box(Rect2(mid_x - 7, my + 22, 14, 34), 6.0, Color(0.20, 0.23, 0.28, 0.55), COL_KEY_BORDER, 2.0)

	# Bullet shell icon inside Left Click
	var bx := mx + mw * 0.26
	var by := my + 44.0
	draw_rect(Rect2(bx - 4, by - 6, 8, 16), Color(0.16, 0.20, 0.26, 0.90), true)
	draw_colored_polygon(PackedVector2Array([Vector2(bx - 4, by - 6), Vector2(bx, by - 14), Vector2(bx + 4, by - 6)]), Color(0.96, 0.84, 0.28, 0.95))

	# Dash double chevron inside Right Click
	var rx := mx + mw * 0.74
	var ry := my + 44.0
	draw_polyline(PackedVector2Array([Vector2(rx - 6, ry - 6), Vector2(rx, ry), Vector2(rx - 6, ry + 6)]), Color(0.16, 0.20, 0.26, 0.92), 2.5)
	draw_polyline(PackedVector2Array([Vector2(rx + 1, ry - 6), Vector2(rx + 7, ry), Vector2(rx + 1, ry + 6)]), Color(0.16, 0.20, 0.26, 0.92), 2.5)

	# Subtle aim crosshair inside lower mouse palm
	var palm_c := Vector2(mid_x, my + 132.0)
	draw_arc(palm_c, 16.0, 0.0, TAU, 24, Color(0.92, 0.95, 0.98, 0.45), 1.8)
	draw_line(palm_c + Vector2(-22, 0), palm_c + Vector2(22, 0), Color(0.92, 0.95, 0.98, 0.40), 1.6)
	draw_line(palm_c + Vector2(0, -22), palm_c + Vector2(0, 22), Color(0.92, 0.95, 0.98, 0.40), 1.6)

	# Callout lines for Mouse
	_draw_callout_up(font, Vector2(bx, my), 26.0, "Disparar")
	_draw_callout_right(font, Vector2(mx + mw, my + 42.0), 18.0, "Dash / Turbo")
	_draw_callout_down(font, Vector2(mid_x, my + mh), 18.0, "Mover Ratón: Apuntar Torreta")

func _draw_bottom_tips(font: Font) -> void:
	# Subtle divider
	draw_line(Vector2(28, 310), Vector2(size.x - 28, 310), Color(0.85, 0.89, 0.95, 0.28), 1.5)

	# Bottom-left tank emblem with tactical target crosshair
	var tc := Vector2(105, 376)
	draw_set_transform(tc, deg_to_rad(-14.0), Vector2(1.25, 1.25))
	draw_rect(Rect2(-22, -19, 44, 8), Color(0.15, 0.17, 0.21, 0.85), true)
	draw_rect(Rect2(-22, 11, 44, 8), Color(0.15, 0.17, 0.21, 0.85), true)
	draw_rect(Rect2(-18, -13, 36, 26), Color(0.65, 0.70, 0.78, 0.55), true)
	draw_rect(Rect2(-18, -13, 36, 26), COL_KEY_BORDER, false, 1.8)
	draw_rect(Rect2(0, -3.5, 32, 7), Color(0.78, 0.82, 0.88, 0.72), true)
	draw_circle(Vector2.ZERO, 12.0, Color(0.75, 0.80, 0.86, 0.65))
	draw_arc(Vector2.ZERO, 12.0, 0.0, TAU, 24, COL_KEY_BORDER, 1.8)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# Crosshair overlay on tank emblem
	draw_arc(tc, 22.0, 0.0, TAU, 28, Color(1.0, 0.32, 0.30, 0.90), 2.0)
	draw_line(tc + Vector2(-28, 0), tc + Vector2(28, 0), Color(1.0, 0.32, 0.30, 0.85), 1.8)
	draw_line(tc + Vector2(0, -28), tc + Vector2(0, 28), Color(1.0, 0.32, 0.30, 0.85), 1.8)

	# 3 Starred Tactical Tips
	var tips: Array[String] = [
		"Recoge Power-Ups (Vida, Escudo, Fuego Rápido, Rebote, Monster y Minas Racimo) en la arena.",
		"Dispara a los barriles rojos cerca de enemigos para causar explosiones que atraviesan muros.",
		"En los últimos 30 segundos se cierra la zona sin respawns: ¡sobrevive hasta el final!"
	]
	for i in range(tips.size()):
		var ty := 342.0 + float(i) * 34.0
		_draw_star_icon(Vector2(204, ty - 5.0), 9.0, Color(1.0, 0.84, 0.22, 1.0))
		draw_string(font, Vector2(224, ty), tips[i], HORIZONTAL_ALIGNMENT_LEFT, 650.0, 14, Color(0.94, 0.96, 0.99, 0.95))

# --- Drawing Helpers ---

func _draw_keycap(font: Font, rect: Rect2, label: String, centered_text: bool, font_size: int = 15) -> void:
	_draw_rounded_box(Rect2(rect.position + Vector2(2, 3), rect.size), 7.0, COL_KEY_SHADOW, Color(0, 0, 0, 0), 0.0)
	_draw_rounded_box(rect, 7.0, COL_KEY_FILL_HI if centered_text else COL_KEY_FILL, COL_KEY_BORDER, 2.0)
	if centered_text:
		_draw_centered_text(font, Vector2(rect.get_center().x, rect.get_center().y + 6.0), label, font_size, COL_KEY_TEXT, rect.size.x - 8.0)
	else:
		draw_string(font, rect.position + Vector2(8, 19), label, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 12.0, font_size, COL_KEY_TEXT)

func _draw_rounded_box(rect: Rect2, radius: float, fill: Color, border: Color, border_w: float) -> void:
	var r := minf(radius, minf(rect.size.x, rect.size.y) * 0.45)
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	var bw := int(roundf(border_w))
	style.border_width_left = bw
	style.border_width_top = bw
	style.border_width_right = bw
	style.border_width_bottom = bw
	var cr := int(roundf(r))
	style.corner_radius_top_left = cr
	style.corner_radius_top_right = cr
	style.corner_radius_bottom_right = cr
	style.corner_radius_bottom_left = cr
	draw_style_box(style, rect)

func _draw_arrow_triangle(center: Vector2, angle: float) -> void:
	var pts := PackedVector2Array([
		center + Vector2(9, 0).rotated(angle),
		center + Vector2(-6, -8).rotated(angle),
		center + Vector2(-6, 8).rotated(angle)
	])
	draw_colored_polygon(pts, Color(0.18, 0.22, 0.28, 0.88))

func _draw_mine_icon(center: Vector2) -> void:
	draw_circle(center, 7.0, Color(0.18, 0.22, 0.28, 0.90))
	for i in range(4):
		var ang := float(i) * (PI * 0.5) + PI * 0.25
		draw_line(center + Vector2.RIGHT.rotated(ang) * 5.0, center + Vector2.RIGHT.rotated(ang) * 9.5, Color(0.18, 0.22, 0.28, 0.90), 2.0)
	draw_circle(center, 2.5, Color(1.0, 0.30, 0.25, 0.95))

func _draw_pause_icon(center: Vector2) -> void:
	draw_rect(Rect2(center + Vector2(-5, -6), Vector2(3.5, 12)), Color(0.18, 0.22, 0.28, 0.88), true)
	draw_rect(Rect2(center + Vector2(1.5, -6), Vector2(3.5, 12)), Color(0.18, 0.22, 0.28, 0.88), true)

func _draw_star_icon(center: Vector2, outer_r: float, col: Color) -> void:
	var inner_r := outer_r * 0.45
	var pts := PackedVector2Array()
	for i in range(10):
		var r := outer_r if (i % 2 == 0) else inner_r
		var ang := -PI * 0.5 + float(i) * (TAU / 10.0)
		pts.append(center + Vector2.RIGHT.rotated(ang) * r)
	draw_colored_polygon(pts, col)

func _draw_callout_left(font: Font, anchor: Vector2, length: float, text: String) -> void:
	var end_pt := anchor + Vector2(-length, 0)
	draw_line(anchor, end_pt, COL_CALLOUT, 2.0)
	draw_string(font, Vector2(end_pt.x - 166.0, end_pt.y + 5.0), text, HORIZONTAL_ALIGNMENT_RIGHT, 160.0, 14, COL_LABEL_YELLOW)

func _draw_callout_right(font: Font, anchor: Vector2, length: float, text: String) -> void:
	var end_pt := anchor + Vector2(length, 0)
	draw_line(anchor, end_pt, COL_CALLOUT, 2.0)
	draw_string(font, Vector2(end_pt.x + 6.0, end_pt.y + 5.0), text, HORIZONTAL_ALIGNMENT_LEFT, 190.0, 14, COL_LABEL_YELLOW)

func _draw_callout_up(font: Font, anchor: Vector2, length: float, text: String) -> void:
	var end_pt := anchor + Vector2(0, -length)
	draw_line(anchor, end_pt, COL_CALLOUT, 2.0)
	_draw_centered_text(font, Vector2(end_pt.x, end_pt.y - 6.0), text, 14, COL_LABEL_YELLOW, 150.0)

func _draw_callout_down(font: Font, anchor: Vector2, length: float, text: String) -> void:
	var end_pt := anchor + Vector2(0, length)
	draw_line(anchor, end_pt, COL_CALLOUT, 2.0)
	_draw_centered_text(font, Vector2(end_pt.x, end_pt.y + 15.0), text, 14, COL_LABEL_YELLOW, 220.0)

func _draw_centered_text(font: Font, center_baseline: Vector2, text: String, font_size: int, col: Color, width: float) -> void:
	draw_string(font, Vector2(center_baseline.x - width * 0.5, center_baseline.y), text, HORIZONTAL_ALIGNMENT_CENTER, width, font_size, col)
