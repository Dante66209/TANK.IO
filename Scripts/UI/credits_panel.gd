# res://Scripts/UI/credits_panel.gd
class_name CreditsPanel extends Control

## Developer & Project Credits Panel for TANK.IO.
## Developer entries can be customized directly in DEVELOPER_CREDITS.

signal closed()

const SoundManagerScript = preload("res://Scripts/Core/sound_manager.gd")

const DEVELOPER_CREDITS: Array[Dictionary] = [
	{
		"role": "Dirección, Diseño y Producción",
		"name": "Equipo TANK.IO (Desarrollador Principal)",
		"detail": "Concepto Battle Royale, mecánicas de combate, balance y dirección creativa."
	},
	{
		"role": "Programación de Gameplay e IA",
		"name": "Equipo TANK.IO — Ingeniería GDScript",
		"detail": "Física de tanques, bots autónomos con context steering, power-ups, morteros y minas."
	},
	{
		"role": "Interfaz, Audio y Arquitectura Pre-Servidor",
		"name": "Equipo TANK.IO — Sistemas y UI",
		"detail": "HUD táctico, menú principal, sala de espera (5–30 jugadores), audio espacial y configuración."
	}
]

@onready var dev_list: VBoxContainer = $Center/Panel/VBox/Scroll/ContentVBox/DevelopersList
@onready var back_btn: Button = $Center/Panel/VBox/BackButton

func _ready() -> void:
	_populate_developer_cards()
	if back_btn != null:
		back_btn.pressed.connect(_on_back_pressed)

func _populate_developer_cards() -> void:
	if dev_list == null:
		return
	for child in dev_list.get_children():
		child.queue_free()

	for dev in DEVELOPER_CREDITS:
		var card := PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.10, 0.13, 0.19, 0.92)
		sb.border_width_left = 3
		sb.border_width_top = 1
		sb.border_width_right = 1
		sb.border_width_bottom = 1
		sb.border_color = Color(0.32, 0.78, 0.95, 0.75)
		sb.corner_radius_top_left = 6
		sb.corner_radius_top_right = 6
		sb.corner_radius_bottom_right = 6
		sb.corner_radius_bottom_left = 6
		sb.content_margin_left = 14
		sb.content_margin_top = 10
		sb.content_margin_right = 14
		sb.content_margin_bottom = 10
		card.add_theme_stylebox_override("panel", sb)

		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 3)

		var role_lbl := Label.new()
		role_lbl.text = str(dev.get("role", "Desarrollador")).to_upper()
		role_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.30, 1.0))
		role_lbl.add_theme_font_size_override("font_size", 12)
		vb.add_child(role_lbl)

		var name_lbl := Label.new()
		name_lbl.text = str(dev.get("name", "Desarrollador"))
		name_lbl.add_theme_color_override("font_color", Color(0.95, 0.98, 1.0, 1.0))
		name_lbl.add_theme_font_size_override("font_size", 16)
		vb.add_child(name_lbl)

		var detail_lbl := Label.new()
		detail_lbl.text = str(dev.get("detail", ""))
		detail_lbl.add_theme_color_override("font_color", Color(0.76, 0.83, 0.92, 0.92))
		detail_lbl.add_theme_font_size_override("font_size", 13)
		detail_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vb.add_child(detail_lbl)

		card.add_child(vb)
		dev_list.add_child(card)

func _on_back_pressed() -> void:
	if SoundManagerScript != null:
		SoundManagerScript.play_ui_click()
	closed.emit()
