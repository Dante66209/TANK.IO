# res://Scripts/UI/podium_screen.gd
class_name PodiumScreen extends CanvasLayer

## Match Over Victory Podium, Full Leaderboard Table & Performance Summary (R8).
## Displays 1st (Gold), 2nd (Silver), 3rd (Bronze) winners, complete Leaderboard standings table,
## player match stats, and offers a Play Again button to restart the match.

@onready var first_place_crown: TextureRect = $Root/Panel/VBox/PodiumHBox/FirstPlace/CrownIcon if has_node("Root/Panel/VBox/PodiumHBox/FirstPlace/CrownIcon") else null
@onready var first_place_name: Label = $Root/Panel/VBox/PodiumHBox/FirstPlace/NameLabel
@onready var first_place_score: Label = $Root/Panel/VBox/PodiumHBox/FirstPlace/ScoreLabel
@onready var second_place_name: Label = $Root/Panel/VBox/PodiumHBox/SecondPlace/NameLabel
@onready var second_place_score: Label = $Root/Panel/VBox/PodiumHBox/SecondPlace/ScoreLabel
@onready var third_place_name: Label = $Root/Panel/VBox/PodiumHBox/ThirdPlace/NameLabel
@onready var third_place_score: Label = $Root/Panel/VBox/PodiumHBox/ThirdPlace/ScoreLabel

@onready var player_rank_label: Label = $Root/Panel/VBox/StatsContainer/RankValue
@onready var player_score_label: Label = $Root/Panel/VBox/StatsContainer/ScoreValue
@onready var player_kills_label: Label = $Root/Panel/VBox/StatsContainer/KillsValue
@onready var player_deaths_label: Label = $Root/Panel/VBox/StatsContainer/DeathsValue
@onready var player_barrel_kills_label: Label = $Root/Panel/VBox/StatsContainer/BarrelKillsValue
@onready var leaderboard_table: VBoxContainer = $Root/Panel/VBox/LeaderboardTable if has_node("Root/Panel/VBox/LeaderboardTable") else null

const SoundManagerScript = preload("res://Scripts/Core/sound_manager.gd")
const MAIN_MENU_SCENE_PATH: String = "res://Scenes/main_menu.tscn"
const ICON_CROWN: Texture2D = preload("res://Assets/Icons/crown.svg")

@onready var restart_button: Button = $Root/Panel/VBox/RestartButton
@onready var back_to_menu_button: Button = $Root/Panel/VBox/BackToMenuButton if has_node("Root/Panel/VBox/BackToMenuButton") else null

func _ready() -> void:
	layer = 105
	visible = false
	if first_place_crown != null:
		first_place_crown.texture = ICON_CROWN
	if restart_button != null:
		restart_button.pressed.connect(_on_restart_pressed)
	if back_to_menu_button != null:
		back_to_menu_button.pressed.connect(_on_back_to_menu_pressed)
	if GameEvents != null:
		GameEvents.match_ended.connect(_on_match_ended)
		if not GameEvents.match_started.is_connected(_on_match_started):
			GameEvents.match_started.connect(_on_match_started)

func _on_match_started(_duration: float) -> void:
	visible = false

func _on_match_ended(leaderboard: Array[Dictionary]) -> void:
	display_results(leaderboard)

func display_results(leaderboard: Array[Dictionary]) -> void:
	visible = true
	var gs := get_node_or_null("/root/GameSettings")
	var nm := get_node_or_null("/root/NetworkManager")
	if restart_button != null:
		if gs != null and gs.get("lobby_mode") == "server" and nm != null and nm.has_method("is_online") and nm.is_online():
			var is_leader: bool = nm.has_method("is_local_leader") and nm.is_local_leader()
			restart_button.disabled = not is_leader
			restart_button.text = "JUGAR DE NUEVO (SALA)" if is_leader else "ESPERANDO AL LÍDER..."
		else:
			restart_button.disabled = false
			restart_button.text = "JUGAR DE NUEVO"
	
	# Pedestals
	if leaderboard.size() > 0:
		_set_podium_entry(first_place_name, first_place_score, leaderboard[0])
	else:
		_set_empty_podium(first_place_name, first_place_score)
		
	if leaderboard.size() > 1:
		_set_podium_entry(second_place_name, second_place_score, leaderboard[1])
	else:
		_set_empty_podium(second_place_name, second_place_score)
		
	if leaderboard.size() > 2:
		_set_podium_entry(third_place_name, third_place_score, leaderboard[2])
	else:
		_set_empty_podium(third_place_name, third_place_score)
		
	# Populate Full Final Leaderboard Table
	_populate_leaderboard_table(leaderboard)
		
	# Find player entry in leaderboard
	var player_entry: Dictionary = {}
	var player_rank: int = 1
	for i in range(leaderboard.size()):
		var e: Dictionary = leaderboard[i]
		if e.get("is_player") == true or e.get("name") == "Player":
			player_entry = e
			player_rank = i + 1
			break
			
	if not player_entry.is_empty():
		if player_rank_label != null: player_rank_label.text = "#%d" % player_rank
		if player_score_label != null: player_score_label.text = "%d" % int(player_entry.get("score", 0))
		if player_kills_label != null: player_kills_label.text = "%d" % int(player_entry.get("kills", 0))
		if player_deaths_label != null: player_deaths_label.text = "%d" % int(player_entry.get("deaths", 0))
		if player_barrel_kills_label != null: player_barrel_kills_label.text = "%d" % int(player_entry.get("barrel_kills", 0))
	else:
		if player_rank_label != null: player_rank_label.text = "#--"
		if player_score_label != null: player_score_label.text = "0"
		if player_kills_label != null: player_kills_label.text = "0"
		if player_deaths_label != null: player_deaths_label.text = "0"
		if player_barrel_kills_label != null: player_barrel_kills_label.text = "0"

func _populate_leaderboard_table(leaderboard: Array[Dictionary]) -> void:
	if leaderboard_table == null:
		return
	for child in leaderboard_table.get_children():
		child.queue_free()
		
	# Header row
	var compact: bool = leaderboard.size() > 6
	var header := _create_table_row("POS", "COMBATIENTE", "BAJAS", "MUERTES", "PUNTOS", "ESTADO", Color(0.65, 0.75, 0.9, 1.0), true, compact)
	leaderboard_table.add_child(header)
	
	var max_rows: int = 10
	var display_count: int = mini(leaderboard.size(), max_rows)
	var player_shown: bool = false
	for i in range(display_count):
		var entry: Dictionary = leaderboard[i]
		var c_name := str(entry.get("name", "Tank"))
		if (entry.get("is_player", false) == true) or c_name == "Player":
			player_shown = true
		leaderboard_table.add_child(_build_leaderboard_row(i, entry, compact))

	if leaderboard.size() > max_rows and not player_shown:
		for i in range(max_rows, leaderboard.size()):
			var entry: Dictionary = leaderboard[i]
			var c_name := str(entry.get("name", "Tank"))
			if (entry.get("is_player", false) == true) or c_name == "Player":
				leaderboard_table.add_child(_build_leaderboard_row(i, entry, compact))
				break

func _build_leaderboard_row(idx: int, entry: Dictionary, compact: bool) -> HBoxContainer:
	var rank_str := "#%d" % (idx + 1)
	var c_name := str(entry.get("name", "Tank"))
	var kills_str := str(int(entry.get("kills", 0)))
	var deaths_str := str(int(entry.get("deaths", 0)))
	var score_str := "%d pts" % int(entry.get("score", 0))
	var is_alive: bool = (entry.get("alive", true) != false)
	var status_str := "VIVO" if is_alive else "BAJA"
	var is_p: bool = (entry.get("is_player", false) == true) or c_name == "Player"
	
	var row_col := Color(0.88, 0.91, 0.96, 1.0)
	if is_p:
		row_col = Color(1.0, 0.86, 0.18, 1.0)
	elif idx == 0:
		row_col = Color(0.95, 0.90, 0.55, 1.0)
		
	return _create_table_row(rank_str, c_name, kills_str, deaths_str, score_str, status_str, row_col, false, compact, idx == 0)

func _create_table_row(col1: String, col2: String, col3: String, col4: String, col5: String, col6: String, col: Color, is_header: bool, compact: bool = false, is_crown: bool = false) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var font_sz := 11 if (is_header or compact) else 13
	
	var widths := [56, 0, 68, 76, 90, 74]
	var texts := [col1, col2, col3, col4, col5, col6]
	var aligns := [
		HORIZONTAL_ALIGNMENT_LEFT,
		HORIZONTAL_ALIGNMENT_LEFT,
		HORIZONTAL_ALIGNMENT_CENTER,
		HORIZONTAL_ALIGNMENT_CENTER,
		HORIZONTAL_ALIGNMENT_RIGHT,
		HORIZONTAL_ALIGNMENT_RIGHT
	]
	for idx in range(texts.size()):
		var lbl := Label.new()
		lbl.text = texts[idx]
		lbl.modulate = col
		lbl.horizontal_alignment = aligns[idx]
		lbl.add_theme_font_size_override("font_size", font_sz)
		if idx == 0 and is_crown and not is_header:
			var rank_cell := HBoxContainer.new()
			rank_cell.custom_minimum_size = Vector2(widths[0], 0)
			rank_cell.add_theme_constant_override("separation", 4)
			var crown := TextureRect.new()
			var c_sz: float = 12.0 if compact else 14.0
			crown.custom_minimum_size = Vector2(c_sz, c_sz)
			crown.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			crown.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			crown.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			crown.texture = ICON_CROWN
			crown.modulate = Color(1.0, 0.84, 0.1, 1.0)
			lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			rank_cell.add_child(crown)
			rank_cell.add_child(lbl)
			row.add_child(rank_cell)
			continue
		if widths[idx] == 0:
			lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			lbl.clip_text = true
		else:
			lbl.custom_minimum_size = Vector2(widths[idx], 0)
		row.add_child(lbl)
	return row

func _set_podium_entry(name_lbl: Label, score_lbl: Label, entry: Dictionary) -> void:
	if name_lbl != null:
		name_lbl.text = str(entry.get("name", "Tank"))
	if score_lbl != null:
		score_lbl.text = "%d pts" % int(entry.get("score", 0))

func _set_empty_podium(name_lbl: Label, score_lbl: Label) -> void:
	if name_lbl != null: name_lbl.text = "---"
	if score_lbl != null: score_lbl.text = "0 pts"

func _on_restart_pressed() -> void:
	var gs := get_node_or_null("/root/GameSettings")
	var nm := get_node_or_null("/root/NetworkManager")
	if gs != null and gs.get("lobby_mode") == "server" and nm != null and nm.has_method("is_online") and nm.is_online():
		if nm.has_method("request_restart_match"):
			nm.request_restart_match()
		return
	restart_match()

func _on_back_to_menu_pressed() -> void:
	if get_tree() != null:
		get_tree().paused = false
	if SoundManagerScript != null:
		SoundManagerScript.stop_all_match_audio()
	var gs := get_node_or_null("/root/GameSettings")
	if gs != null and gs.has_method("clear_lobby_match"):
		gs.clear_lobby_match()
	var nm := get_node_or_null("/root/NetworkManager")
	if nm != null and nm.has_method("is_online") and nm.is_online() and nm.has_method("disconnect_network"):
		nm.disconnect_network()
	if get_tree() != null and ResourceLoader.exists(MAIN_MENU_SCENE_PATH):
		get_tree().change_scene_to_file(MAIN_MENU_SCENE_PATH)

func restart_match() -> void:
	var tree := get_tree()
	if tree != null:
		tree.reload_current_scene()
