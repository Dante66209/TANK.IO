# res://Scripts/UI/main_menu.gd
class_name MainMenu extends Control

## Main Menu Entry Scene for TANK.IO (Pre-Server Phase).
## Hosts navigation to Buscar Partida (Salas & Modo Local Bots),
## Configuración (Audio & Profile), Créditos, Salir, and right-side Tank Customizer
## with live tank name, color picker swatches, and bouncy miniature tank preview.

const SoundManagerScript = preload("res://Scripts/Core/sound_manager.gd")

const FALLBACK_COLORS: Array[Dictionary] = [
	{"name": "Azul Táctico", "color": Color(0.20, 0.45, 0.75, 1.0)},
	{"name": "Rojo Carmesí", "color": Color(0.82, 0.22, 0.24, 1.0)},
	{"name": "Verde Esmeralda", "color": Color(0.18, 0.72, 0.36, 1.0)},
	{"name": "Dorado Ámbar", "color": Color(0.92, 0.68, 0.16, 1.0)},
	{"name": "Cian Neón", "color": Color(0.14, 0.78, 0.90, 1.0)},
	{"name": "Púrpura Real", "color": Color(0.62, 0.28, 0.85, 1.0)},
	{"name": "Naranja Fuego", "color": Color(0.95, 0.44, 0.14, 1.0)},
	{"name": "Rosa Eléctrico", "color": Color(0.92, 0.25, 0.62, 1.0)},
	{"name": "Blanco Ártico", "color": Color(0.84, 0.88, 0.94, 1.0)},
	{"name": "Grafito Oscuro", "color": Color(0.28, 0.32, 0.38, 1.0)}
]

@onready var home_container: Control = $HomeCenter
@onready var pilot_badge: Label = $HomeCenter/HomeLayout/Panel/VBox/PilotBadge
@onready var find_match_btn: Button = $HomeCenter/HomeLayout/Panel/VBox/Buttons/FindMatchButton
@onready var settings_btn: Button = $HomeCenter/HomeLayout/Panel/VBox/Buttons/SettingsButton
@onready var credits_btn: Button = $HomeCenter/HomeLayout/Panel/VBox/Buttons/CreditsButton
@onready var quit_btn: Button = $HomeCenter/HomeLayout/Panel/VBox/Buttons/QuitButton

# Right-side Tank Customizer
@onready var tank_name_input: LineEdit = $HomeCenter/HomeLayout/CustomizerPanel/VBox/TankNameInput
@onready var color_grid: GridContainer = $HomeCenter/HomeLayout/CustomizerPanel/VBox/ColorSwatchesGrid
@onready var selected_color_label: Label = $HomeCenter/HomeLayout/CustomizerPanel/VBox/SelectedColorLabel
@onready var tank_preview: Control = $HomeCenter/HomeLayout/CustomizerPanel/VBox/PreviewFrame/TankPreview

@onready var match_browser_panel: Control = $MatchBrowserPanel
@onready var settings_panel: Control = $SettingsPanel
@onready var credits_panel: Control = $CreditsPanel
@onready var backdrop_canvas: Control = $BackdropCanvas

var color_buttons: Array[Button] = []
var _anim_time: float = 0.0
var _syncing_customizer: bool = false

func _ready() -> void:
	if get_tree() != null:
		get_tree().paused = false
	if quit_btn != null and OS.has_feature("web"):
		quit_btn.visible = false
	_build_color_swatches()
	_connect_signals()
	show_home()

func _process(delta: float) -> void:
	_anim_time += delta
	if backdrop_canvas != null:
		backdrop_canvas.queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var ke := event as InputEventKey
		if ke.pressed and not ke.echo:
			var code: int = ke.keycode if ke.keycode != 0 else ke.physical_keycode
			if code == KEY_ESCAPE:
				if match_browser_panel != null and match_browser_panel.visible:
					if match_browser_panel.get("in_lobby") == true and match_browser_panel.has_method("show_browse_view"):
						match_browser_panel.show_browse_view()
					else:
						show_home()
					if get_viewport() != null:
						get_viewport().set_input_as_handled()
				elif (settings_panel != null and settings_panel.visible) or (credits_panel != null and credits_panel.visible):
					show_home()
					if get_viewport() != null:
						get_viewport().set_input_as_handled()

func _connect_signals() -> void:
	if find_match_btn != null:
		find_match_btn.pressed.connect(open_match_browser)
	if settings_btn != null:
		settings_btn.pressed.connect(open_settings)
	if credits_btn != null:
		credits_btn.pressed.connect(open_credits)
	if quit_btn != null:
		quit_btn.pressed.connect(_on_quit_pressed)
	if tank_name_input != null:
		tank_name_input.text_changed.connect(_on_tank_name_changed)

	if match_browser_panel != null and match_browser_panel.has_signal("closed"):
		match_browser_panel.closed.connect(show_home)
	if settings_panel != null and settings_panel.has_signal("closed"):
		settings_panel.closed.connect(show_home)
	if credits_panel != null and credits_panel.has_signal("closed"):
		credits_panel.closed.connect(show_home)

	if backdrop_canvas != null:
		backdrop_canvas.draw.connect(_on_backdrop_draw)

func _get_color_presets() -> Array[Dictionary]:
	var gs := get_node_or_null("/root/GameSettings")
	if gs != null and "TANK_COLOR_PRESETS" in gs:
		var presets = gs.get("TANK_COLOR_PRESETS")
		if presets is Array and not presets.is_empty():
			return presets
	return FALLBACK_COLORS

func _build_color_swatches() -> void:
	if color_grid == null:
		return
	for child in color_grid.get_children():
		child.queue_free()
	color_buttons.clear()

	var presets := _get_color_presets()
	for i in range(presets.size()):
		var entry: Dictionary = presets[i]
		var col: Color = entry.get("color", Color(0.20, 0.45, 0.75, 1.0))
		var c_name: String = str(entry.get("name", "Color %d" % (i + 1)))

		var btn := Button.new()
		btn.custom_minimum_size = Vector2(54, 34)
		btn.tooltip_text = c_name
		btn.focus_mode = Control.FOCUS_NONE
		btn.set_meta("tank_color", col)
		btn.set_meta("color_name", c_name)
		btn.pressed.connect(select_tank_color.bind(i))
		color_grid.add_child(btn)
		color_buttons.append(btn)

func select_tank_color(index: int) -> void:
	var presets := _get_color_presets()
	if index < 0 or index >= presets.size():
		return
	if SoundManagerScript != null:
		SoundManagerScript.play_ui_click()
	var col: Color = presets[index].get("color", Color(0.20, 0.45, 0.75, 1.0))
	var gs := get_node_or_null("/root/GameSettings")
	if gs != null and gs.has_method("set_player_color"):
		gs.set_player_color(col)
	_sync_customizer_from_settings()

func _on_tank_name_changed(new_text: String) -> void:
	if _syncing_customizer:
		return
	var gs := get_node_or_null("/root/GameSettings")
	if gs != null and gs.has_method("set_player_name"):
		gs.set_player_name(new_text)
	var effective_name: String = str(gs.get("player_name")) if gs != null else (new_text.strip_edges() if not new_text.strip_edges().is_empty() else "Player")
	if tank_preview != null:
		tank_preview.set("tank_name", effective_name)
	_update_pilot_badge()

func _sync_customizer_from_settings() -> void:
	_syncing_customizer = true
	var gs := get_node_or_null("/root/GameSettings")
	var p_name: String = str(gs.get("player_name")) if gs != null else "Player"
	if p_name.strip_edges().is_empty():
		p_name = "Player"
	var p_col: Color = gs.get("player_color") if (gs != null and gs.get("player_color") is Color) else Color(0.20, 0.45, 0.75, 1.0)

	if tank_name_input != null and tank_name_input.text != p_name:
		tank_name_input.text = p_name
	if tank_preview != null:
		tank_preview.set("tank_name", p_name)
		tank_preview.set("tank_color", p_col)

	var matched_name: String = "Personalizado"
	for btn in color_buttons:
		var btn_col: Color = btn.get_meta("tank_color", Color.WHITE)
		var is_sel: bool = btn_col.is_equal_approx(p_col)
		if is_sel:
			matched_name = str(btn.get_meta("color_name", "Seleccionado"))
		_apply_swatch_style(btn, btn_col, is_sel)

	if selected_color_label != null:
		selected_color_label.text = "Color seleccionado: %s" % matched_name

	_syncing_customizer = false

func _apply_swatch_style(btn: Button, col: Color, selected: bool) -> void:
	for state_name in ["normal", "hover", "pressed"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = col.lightened(0.08) if state_name == "hover" else col
		sb.border_width_left = 3 if selected else 1
		sb.border_width_top = 3 if selected else 1
		sb.border_width_right = 3 if selected else 1
		sb.border_width_bottom = 3 if selected else 1
		sb.border_color = Color(1.0, 0.92, 0.35, 1.0) if selected else Color(0.22, 0.28, 0.36, 0.85)
		sb.corner_radius_top_left = 6
		sb.corner_radius_top_right = 6
		sb.corner_radius_bottom_right = 6
		sb.corner_radius_bottom_left = 6
		btn.add_theme_stylebox_override(state_name, sb)
	var mark_col := Color.WHITE if col.get_luminance() < 0.55 else Color(0.08, 0.1, 0.14)
	btn.text = ""
	btn.icon = preload("res://Assets/Icons/check.svg") if selected else null
	btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	btn.add_theme_constant_override("icon_max_width", 18)
	btn.add_theme_color_override("icon_normal_color", mark_col)
	btn.add_theme_color_override("icon_hover_color", mark_col)
	btn.add_theme_color_override("icon_pressed_color", mark_col)

func show_home() -> void:
	if home_container != null:
		home_container.visible = true
	if match_browser_panel != null:
		match_browser_panel.visible = false
	if settings_panel != null:
		settings_panel.visible = false
	if credits_panel != null:
		credits_panel.visible = false
	_sync_customizer_from_settings()
	_update_pilot_badge()
	if find_match_btn != null and is_inside_tree():
		find_match_btn.grab_focus()

func _update_pilot_badge() -> void:
	if pilot_badge == null:
		return
	var gs := get_node_or_null("/root/GameSettings")
	var p_name: String = str(gs.get("player_name")) if gs != null else "Player"
	if p_name.strip_edges().is_empty():
		p_name = "Player"
	pilot_badge.text = "PILOTO ACTUAL: %s  •  FASE PRE-SERVIDOR" % p_name.to_upper()

func open_match_browser() -> void:
	if SoundManagerScript != null:
		SoundManagerScript.play_ui_click()
	if home_container != null:
		home_container.visible = false
	if settings_panel != null:
		settings_panel.visible = false
	if credits_panel != null:
		credits_panel.visible = false
	if match_browser_panel != null:
		match_browser_panel.visible = true
		if match_browser_panel.has_method("show_browse_view"):
			match_browser_panel.show_browse_view()

func open_settings() -> void:
	if SoundManagerScript != null:
		SoundManagerScript.play_ui_click()
	if home_container != null:
		home_container.visible = false
	if match_browser_panel != null:
		match_browser_panel.visible = false
	if credits_panel != null:
		credits_panel.visible = false
	if settings_panel != null:
		settings_panel.visible = true
		if settings_panel.has_method("sync_from_settings"):
			settings_panel.sync_from_settings()

func open_credits() -> void:
	if SoundManagerScript != null:
		SoundManagerScript.play_ui_click()
	if home_container != null:
		home_container.visible = false
	if match_browser_panel != null:
		match_browser_panel.visible = false
	if settings_panel != null:
		settings_panel.visible = false
	if credits_panel != null:
		credits_panel.visible = true

func _on_quit_pressed() -> void:
	if SoundManagerScript != null:
		SoundManagerScript.play_ui_click()
	if get_tree() != null:
		get_tree().quit()

func _on_backdrop_draw() -> void:
	if backdrop_canvas == null:
		return
	var sz: Vector2 = backdrop_canvas.size
	if sz.x <= 1.0 or sz.y <= 1.0:
		return

	# Tactical dark slate grid backdrop
	backdrop_canvas.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.05, 0.07, 0.10, 1.0), true)
	var grid_col := Color(0.11, 0.16, 0.22, 0.55)
	var step: float = 64.0
	var offset_x: float = fmod(_anim_time * 14.0, step)
	var offset_y: float = fmod(_anim_time * 9.0, step)

	var x: float = -step + offset_x
	while x < sz.x + step:
		backdrop_canvas.draw_line(Vector2(x, 0.0), Vector2(x, sz.y), grid_col, 1.0)
		x += step
	var y: float = -step + offset_y
	while y < sz.y + step:
		backdrop_canvas.draw_line(Vector2(0.0, y), Vector2(sz.x, y), grid_col, 1.0)
		y += step

	# Subtle tactical radar rings centered in viewport
	var center := sz * 0.5
	for r in [180.0, 320.0, 460.0]:
		backdrop_canvas.draw_arc(center, r, 0.0, TAU, 64, Color(0.18, 0.45, 0.62, 0.16), 1.5)
	var sweep_ang: float = _anim_time * 0.65
	backdrop_canvas.draw_line(center, center + Vector2.RIGHT.rotated(sweep_ang) * 460.0, Color(0.25, 0.85, 0.92, 0.18), 2.0)

	# Stylized cruising tank silhouettes in background
	_draw_bg_tank(Vector2(fmod(_anim_time * 55.0, sz.x + 180.0) - 90.0, sz.y * 0.16), 0.0, Color(0.22, 0.55, 0.85, 0.22))
	_draw_bg_tank(Vector2(sz.x + 90.0 - fmod(_anim_time * 42.0, sz.x + 180.0), sz.y * 0.84), PI, Color(0.92, 0.35, 0.28, 0.20))

func _draw_bg_tank(pos: Vector2, angle: float, col: Color) -> void:
	backdrop_canvas.draw_set_transform(pos, angle, Vector2(1.4, 1.4))
	backdrop_canvas.draw_rect(Rect2(-24.0, -20.0, 48.0, 9.0), Color(0.08, 0.10, 0.14, 0.35), true)
	backdrop_canvas.draw_rect(Rect2(-24.0, 11.0, 48.0, 9.0), Color(0.08, 0.10, 0.14, 0.35), true)
	backdrop_canvas.draw_rect(Rect2(-20.0, -14.0, 40.0, 28.0), col, true)
	backdrop_canvas.draw_rect(Rect2(0.0, -3.5, 36.0, 7.0), col.lightened(0.2), true)
	backdrop_canvas.draw_circle(Vector2.ZERO, 13.0, col.lightened(0.1))
	backdrop_canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
