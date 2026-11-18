# res://Scripts/UI/hud.gd
class_name GameHUD extends CanvasLayer

## Match HUD Display Controller (R8).
## Features:
## - Top Left: Tactical Radar / Mini-Map with gunfire pings, storm ring, and mines.
## - Top Center: Digital countdown timer (MM:SS), Sudden Death zone alert, and Mortar bar.
## - Upper Center: Call-of-Duty style animated Killstreak & Multi-Kill Medal Banner.
## - Top Right: Live dynamic leaderboard showing Top 5 with player in gold.
## - Bottom Left: Player Health, Shield, Dash, Proximity Mine [Q] inventory, Score, and Streak badge.
## - Bottom Center: Active power-up indicator and duration bar.
## - Mid Left: Transient kill feed banner fading after 3.5s.

const ICON_RICOCHET: Texture2D = preload("res://Assets/Icons/ricochet.svg")
const ICON_BOLT: Texture2D = preload("res://Assets/Icons/bolt.svg")
const ICON_MINE: Texture2D = preload("res://Assets/Icons/mine.svg")
const ICON_MINE_CLUSTER: Texture2D = preload("res://Assets/Icons/mine_cluster.svg")
const ICON_MINE_EMPTY: Texture2D = preload("res://Assets/Icons/mine_empty.svg")
const ICON_MORTAR: Texture2D = preload("res://Assets/Icons/mortar.svg")
const ICON_BIOHAZARD: Texture2D = preload("res://Assets/Icons/biohazard.svg")
const ICON_TROPHY: Texture2D = preload("res://Assets/Icons/trophy.svg")
const ICON_EYE: Texture2D = preload("res://Assets/Icons/eye.svg")
const ICON_CHEVRON_LEFT: Texture2D = preload("res://Assets/Icons/chevron_left.svg")
const ICON_CHEVRON_RIGHT: Texture2D = preload("res://Assets/Icons/chevron_right.svg")
const ICON_CHECK: Texture2D = preload("res://Assets/Icons/check.svg")
const ICON_ALERT: Texture2D = preload("res://Assets/Icons/alert.svg")
const ICON_CROWN: Texture2D = preload("res://Assets/Icons/crown.svg")

@onready var minimap_widget: Control = $Root/TopLeft/MinimapPanel/VBox/TacticalMinimap if has_node("Root/TopLeft/MinimapPanel/VBox/TacticalMinimap") else null
@onready var timer_label: Label = $Root/TopCenter/TimerLabel
@onready var sudden_death_label: Label = $Root/TopCenter/SuddenDeathLabel if has_node("Root/TopCenter/SuddenDeathLabel") else null
@onready var killstreak_banner: PanelContainer = $Root/KillstreakBanner if has_node("Root/KillstreakBanner") else null
@onready var medal_title_label: Label = $Root/KillstreakBanner/VBox/MedalTitle if has_node("Root/KillstreakBanner/VBox/MedalTitle") else null
@onready var medal_subtitle_label: Label = $Root/KillstreakBanner/VBox/MedalSubtitle if has_node("Root/KillstreakBanner/VBox/MedalSubtitle") else null
@onready var leaderboard_list: VBoxContainer = $Root/TopRight/LeaderboardPanel/VBox/LeaderboardList
@onready var bottom_left_card: Panel = $Root/BottomLeftCard if has_node("Root/BottomLeftCard") else null
@onready var bottom_left_box: VBoxContainer = $Root/BottomLeft if has_node("Root/BottomLeft") else null
@onready var score_label: Label = $Root/BottomLeft/ScoreLabel
@onready var streak_badge: Label = $Root/BottomLeft/StreakBadge
@onready var hp_bar: ProgressBar = $Root/BottomLeft/HPContainer/HPBar
@onready var hp_text: Label = $Root/BottomLeft/HPContainer/HPText
@onready var shield_bar: ProgressBar = $Root/BottomLeft/ShieldContainer/ShieldBar
@onready var shield_text: Label = $Root/BottomLeft/ShieldContainer/ShieldText
@onready var dash_bar: ProgressBar = $Root/BottomLeft/DashContainer/DashBar if has_node("Root/BottomLeft/DashContainer/DashBar") else null
@onready var dash_text: Label = $Root/BottomLeft/DashContainer/DashText if has_node("Root/BottomLeft/DashContainer/DashText") else null
@onready var ammo_bar: ProgressBar = $Root/BottomLeft/AmmoContainer/AmmoBar if has_node("Root/BottomLeft/AmmoContainer/AmmoBar") else null
@onready var ammo_icon: TextureRect = $Root/BottomLeft/AmmoContainer/AmmoIcon if has_node("Root/BottomLeft/AmmoContainer/AmmoIcon") else null
@onready var ammo_text: Label = $Root/BottomLeft/AmmoContainer/AmmoText if has_node("Root/BottomLeft/AmmoContainer/AmmoText") else null
@onready var mine_pips_label: Label = $Root/BottomLeft/MineContainer/MinePipsLabel if has_node("Root/BottomLeft/MineContainer/MinePipsLabel") else null
@onready var mine_pips_icons: HBoxContainer = $Root/BottomLeft/MineContainer/MinePipsIcons if has_node("Root/BottomLeft/MineContainer/MinePipsIcons") else null
@onready var mine_count_label: Label = $Root/BottomLeft/MineContainer/MineCountLabel if has_node("Root/BottomLeft/MineContainer/MineCountLabel") else null
@onready var mortar_container: VBoxContainer = $Root/TopCenter/MortarContainer if has_node("Root/TopCenter/MortarContainer") else null
@onready var mortar_icon: TextureRect = $Root/TopCenter/MortarContainer/MortarAlertRow/MortarIcon if has_node("Root/TopCenter/MortarContainer/MortarAlertRow/MortarIcon") else null
@onready var mortar_alert_label: Label = $Root/TopCenter/MortarContainer/MortarAlertRow/MortarAlertLabel if has_node("Root/TopCenter/MortarContainer/MortarAlertRow/MortarAlertLabel") else ($Root/TopCenter/MortarContainer/MortarAlertLabel if has_node("Root/TopCenter/MortarContainer/MortarAlertLabel") else null)
@onready var mortar_bar: ProgressBar = $Root/TopCenter/MortarContainer/MortarBar if has_node("Root/TopCenter/MortarContainer/MortarBar") else null
@onready var spectator_banner: PanelContainer = $Root/BottomCenter/SpectatorBanner if has_node("Root/BottomCenter/SpectatorBanner") else null
@onready var spectator_eye_icon: TextureRect = $Root/BottomCenter/SpectatorBanner/HBox/SpectatorEyeIcon if has_node("Root/BottomCenter/SpectatorBanner/HBox/SpectatorEyeIcon") else null
@onready var spectator_title_label: Label = $Root/BottomCenter/SpectatorBanner/HBox/InfoVBox/SpectatorTitle if has_node("Root/BottomCenter/SpectatorBanner/HBox/InfoVBox/SpectatorTitle") else null
@onready var prev_spectate_btn: Button = $Root/BottomCenter/SpectatorBanner/HBox/PrevSpectateBtn if has_node("Root/BottomCenter/SpectatorBanner/HBox/PrevSpectateBtn") else null
@onready var next_spectate_btn: Button = $Root/BottomCenter/SpectatorBanner/HBox/NextSpectateBtn if has_node("Root/BottomCenter/SpectatorBanner/HBox/NextSpectateBtn") else null
@onready var powerup_panel: PanelContainer = $Root/BottomCenter/PowerUpPanel
@onready var powerup_name_label: Label = $Root/BottomCenter/PowerUpPanel/HBox/PowerUpName
@onready var powerup_duration_bar: ProgressBar = $Root/BottomCenter/PowerUpPanel/HBox/DurationBar
@onready var kill_feed_container: VBoxContainer = $Root/MidLeft/KillFeedList

var player_tank: Node2D = null
var _last_timer_val: float = 180.0
var _medal_tween: Tween = null
var _medal_icons: Array[TextureRect] = []
var _mine_pip_rects: Array[TextureRect] = []

func _ready() -> void:
	layer = 100
	_find_player_tank()
	_connect_events()
	_setup_hud_icons()
	if powerup_panel != null:
		powerup_panel.visible = false
	if spectator_banner != null:
		spectator_banner.visible = false
	if prev_spectate_btn != null and not prev_spectate_btn.pressed.is_connected(_on_prev_spectate_pressed):
		prev_spectate_btn.pressed.connect(_on_prev_spectate_pressed)
	if next_spectate_btn != null and not next_spectate_btn.pressed.is_connected(_on_next_spectate_pressed):
		next_spectate_btn.pressed.connect(_on_next_spectate_pressed)
	if streak_badge != null:
		streak_badge.visible = false
	if killstreak_banner != null:
		killstreak_banner.visible = false
	if sudden_death_label != null:
		sudden_death_label.visible = false
	call_deferred("_update_bottom_left_card")

func _setup_hud_icons() -> void:
	if mortar_icon != null:
		mortar_icon.texture = ICON_MORTAR
		mortar_icon.modulate = Color(1.0, 0.35, 0.25, 1.0)
	if spectator_eye_icon != null:
		spectator_eye_icon.texture = ICON_EYE
	if prev_spectate_btn != null:
		prev_spectate_btn.icon = ICON_CHEVRON_LEFT
		prev_spectate_btn.add_theme_constant_override("icon_max_width", 14)
	if next_spectate_btn != null:
		next_spectate_btn.icon = ICON_CHEVRON_RIGHT
		next_spectate_btn.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		next_spectate_btn.add_theme_constant_override("icon_max_width", 14)
	if sudden_death_label != null:
		_attach_side_icons(sudden_death_label, ICON_BIOHAZARD, 16.0, 22.0, true)
	if medal_title_label != null:
		_medal_icons = _attach_side_icons(medal_title_label, ICON_TROPHY, 20.0, 28.0, true)
	if mine_pips_icons != null:
		_mine_pip_rects.clear()
		for child in mine_pips_icons.get_children():
			if child is TextureRect:
				child.texture = ICON_MINE
				child.modulate = Color(1.0, 0.85, 0.25, 1.0)
				_mine_pip_rects.append(child)
		if mine_pips_label != null and _mine_pip_rects.size() > 0:
			mine_pips_label.visible = false

func _make_icon_rect(tex: Texture2D, icon_px: float, col: Color = Color.WHITE) -> TextureRect:
	var tr := TextureRect.new()
	tr.custom_minimum_size = Vector2(icon_px, icon_px)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.texture = tex
	tr.modulate = col
	return tr

func _attach_side_icons(lbl: Label, icon_tex: Texture2D, icon_px: float, pad_px: float, both_sides: bool = true) -> Array[TextureRect]:
	var created: Array[TextureRect] = []
	if lbl == null or icon_tex == null:
		return created
	var pad := StyleBoxEmpty.new()
	pad.content_margin_left = pad_px
	if both_sides:
		pad.content_margin_right = pad_px
		lbl.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	lbl.add_theme_stylebox_override("normal", pad)

	var left_icon := _make_icon_rect(icon_tex, icon_px)
	left_icon.anchor_top = 0.5
	left_icon.anchor_bottom = 0.5
	left_icon.offset_left = 0.0
	left_icon.offset_top = -icon_px * 0.5
	left_icon.offset_right = icon_px
	left_icon.offset_bottom = icon_px * 0.5
	lbl.add_child(left_icon)
	created.append(left_icon)

	if both_sides:
		var right_icon := _make_icon_rect(icon_tex, icon_px)
		right_icon.anchor_left = 1.0
		right_icon.anchor_right = 1.0
		right_icon.anchor_top = 0.5
		right_icon.anchor_bottom = 0.5
		right_icon.offset_left = -icon_px
		right_icon.offset_top = -icon_px * 0.5
		right_icon.offset_right = 0.0
		right_icon.offset_bottom = icon_px * 0.5
		lbl.add_child(right_icon)
		created.append(right_icon)

	return created

func _exit_tree() -> void:
	if _medal_tween != null and _medal_tween.is_valid():
		_medal_tween.kill()
	_medal_tween = null

func _find_player_tank() -> void:
	var tanks := get_tree().get_nodes_in_group("tanks")
	for t in tanks:
		if is_instance_valid(t) and t.get("is_player") == true:
			player_tank = t as Node2D
			break

func _connect_events() -> void:
	if GameEvents != null:
		GameEvents.match_started.connect(_on_match_started)
		GameEvents.match_tick.connect(_on_match_tick)
		GameEvents.leaderboard_updated.connect(_on_leaderboard_updated)
		GameEvents.tank_killed.connect(_on_tank_killed)
		GameEvents.powerup_collected.connect(_on_powerup_collected)
		GameEvents.powerup_expired.connect(_on_powerup_expired)
		GameEvents.kill_feed_announced.connect(_on_kill_feed_announced)
		GameEvents.mortar_event_started.connect(_on_mortar_event_started)
		GameEvents.mortar_event_tick.connect(_on_mortar_event_tick)
		GameEvents.mortar_event_ended.connect(_on_mortar_event_ended)
		GameEvents.killstreak_achieved.connect(_on_killstreak_achieved)
		GameEvents.sudden_death_started.connect(_on_sudden_death_started)
		if not GameEvents.match_ended.is_connected(_on_match_ended_hud):
			GameEvents.match_ended.connect(_on_match_ended_hud)

func _process(_delta: float) -> void:
	_update_player_ui()
	_update_bottom_left_card()

func _update_bottom_left_card() -> void:
	if bottom_left_card == null or bottom_left_box == null:
		return
	var first_y: float = INF
	var last_y: float = -INF
	for child in bottom_left_box.get_children():
		if child is Control and (child as Control).visible:
			var ctrl := child as Control
			first_y = minf(first_y, ctrl.position.y)
			last_y = maxf(last_y, ctrl.position.y + ctrl.size.y)
	if first_y == INF or last_y <= first_y:
		bottom_left_card.visible = false
		return
	bottom_left_card.visible = true
	var pad_x: float = 12.0
	var pad_y: float = 10.0
	bottom_left_card.global_position = Vector2(
		bottom_left_box.global_position.x - pad_x,
		bottom_left_box.global_position.y + first_y - pad_y
	)
	bottom_left_card.size = Vector2(
		bottom_left_box.size.x + pad_x * 2.0,
		(last_y - first_y) + pad_y * 2.0
	)

func _on_prev_spectate_pressed() -> void:
	if is_instance_valid(player_tank) and player_tank.has_method("cycle_spectate_target"):
		player_tank.cycle_spectate_target(-1)

func _on_next_spectate_pressed() -> void:
	if is_instance_valid(player_tank) and player_tank.has_method("cycle_spectate_target"):
		player_tank.cycle_spectate_target(1)

func _on_match_ended_hud(_leaderboard: Array[Dictionary]) -> void:
	if spectator_banner != null:
		spectator_banner.visible = false

func _update_player_ui() -> void:
	if not is_instance_valid(player_tank):
		_find_player_tank()
		if not is_instance_valid(player_tank):
			return
			
	var hud_subject: Node2D = player_tank
	var is_spec: bool = (player_tank.get("is_spectating") == true)
	if is_spec:
		var spec_target = player_tank.get("spectated_tank")
		if spec_target != null and is_instance_valid(spec_target) and spec_target is Node2D and spec_target.get("is_dead") != true:
			hud_subject = spec_target as Node2D
			if spectator_banner != null:
				spectator_banner.visible = true
			if spectator_title_label != null:
				var s_name: String = str(hud_subject.get("tank_name")) if "tank_name" in hud_subject else hud_subject.name
				var total_alive: int = 1
				var cur_num: int = 1
				if player_tank.has_method("get_living_spectate_targets"):
					var alive_list: Array = player_tank.get_living_spectate_targets()
					total_alive = maxi(1, alive_list.size())
					var found_i: int = alive_list.find(hud_subject)
					cur_num = (found_i + 1) if found_i >= 0 else 1
				spectator_title_label.text = "ESPECTANDO: %s  (%d/%d VIVOS)" % [s_name.to_upper(), cur_num, total_alive]
		else:
			is_spec = false
			if spectator_banner != null:
				spectator_banner.visible = false
	else:
		if spectator_banner != null:
			spectator_banner.visible = false
			
	var current_hp: float = hud_subject.get("current_health") if "current_health" in hud_subject else 100.0
	var max_hp: float = hud_subject.get("max_health") if "max_health" in hud_subject else 100.0
	var shield: float = hud_subject.get("shield") if "shield" in hud_subject else 0.0
	var max_shield: float = hud_subject.get("max_shield") if "max_shield" in hud_subject else 50.0
	var score: int = int(hud_subject.get("score")) if "score" in hud_subject else 0
	var streak: int = int(hud_subject.get("kill_streak")) if "kill_streak" in hud_subject else 0
	
	if hp_bar != null:
		hp_bar.max_value = max_hp
		hp_bar.value = current_hp
	if hp_text != null:
		hp_text.text = "%d / %d" % [int(current_hp), int(max_hp)]
		
	if shield_bar != null:
		shield_bar.max_value = max_shield
		shield_bar.value = shield
	if shield_text != null:
		shield_text.text = "%d / %d" % [int(shield), int(max_shield)]
		
	var dash: float = hud_subject.get("dash_stamina") if "dash_stamina" in hud_subject else 100.0
	var max_dash: float = hud_subject.get("max_dash_stamina") if "max_dash_stamina" in hud_subject else 100.0
	if dash_bar != null:
		dash_bar.max_value = max_dash
		dash_bar.value = dash
	if dash_text != null:
		var pct := int(clampf((dash / maxf(1.0, max_dash)) * 100.0, 0.0, 100.0))
		dash_text.text = "%d%%" % pct
		
	if ammo_bar != null or ammo_text != null:
		var ricochet: int = int(hud_subject.get("ricochet_shots")) if "ricochet_shots" in hud_subject else 0
		var rapid: bool = (hud_subject.get("has_rapid_fire") == true) if "has_rapid_fire" in hud_subject else false
		var ready_to_fire: bool = (hud_subject.get("can_fire") == true) if "can_fire" in hud_subject else true
		var fire_cd: float = float(hud_subject.get("fire_cooldown")) if "fire_cooldown" in hud_subject else 0.35
		var fire_t: float = float(hud_subject.get("_fire_timer")) if "_fire_timer" in hud_subject else 0.0
		var active_map: Dictionary = hud_subject.get("_active_powerups") if "_active_powerups" in hud_subject else {}
		if ricochet > 0:
			var max_ric: int = 20
			if active_map != null and active_map.has(3):
				max_ric = maxi(1, int(active_map[3].get("total_shots", 20)))
			if ammo_bar != null:
				ammo_bar.max_value = float(max_ric)
				ammo_bar.value = float(ricochet)
				ammo_bar.modulate = Color(0.25, 0.95, 1.0, 1.0)
			if ammo_icon != null:
				ammo_icon.texture = ICON_RICOCHET
				ammo_icon.modulate = Color(0.35, 0.96, 1.0, 1.0)
				ammo_icon.visible = true
			if ammo_text != null:
				ammo_text.text = "REB %d/%d" % [ricochet, max_ric]
				ammo_text.modulate = Color(0.35, 0.96, 1.0, 1.0)
		else:
			var reload_pct: float = 100.0 if ready_to_fire else clampf((1.0 - (fire_t / maxf(0.05, fire_cd))) * 100.0, 0.0, 100.0)
			if ammo_bar != null:
				ammo_bar.max_value = 100.0
				ammo_bar.value = reload_pct
				ammo_bar.modulate = Color(1.0, 0.90, 0.25, 1.0) if rapid else Color.WHITE
			if ammo_icon != null:
				ammo_icon.visible = rapid
				if rapid:
					ammo_icon.texture = ICON_BOLT
					ammo_icon.modulate = Color(1.0, 0.90, 0.25, 1.0)
			if ammo_text != null:
				if rapid:
					ammo_text.text = "RÁPIDO"
					ammo_text.modulate = Color(1.0, 0.90, 0.25, 1.0)
				elif ready_to_fire:
					ammo_text.text = "LISTO"
					ammo_text.modulate = Color(0.96, 0.94, 0.82, 1.0)
				else:
					ammo_text.text = "RECARGA..."
					ammo_text.modulate = Color(0.75, 0.80, 0.88, 0.92)
		
	if mine_count_label != null or mine_pips_label != null or _mine_pip_rects.size() > 0:
		var mines: int = int(hud_subject.get("mines_count")) if "mines_count" in hud_subject else 3
		var cluster_m: int = int(hud_subject.get("cluster_mines_count")) if "cluster_mines_count" in hud_subject else 0
		var max_m: int = 3
		var pips: Array[String] = []
		for i in range(max_m):
			var pip_rect: TextureRect = _mine_pip_rects[i] if i < _mine_pip_rects.size() else null
			if i < cluster_m and i < mines:
				pips.append("[*]")
				if pip_rect != null:
					pip_rect.texture = ICON_MINE_CLUSTER
					pip_rect.modulate = Color(1.0, 0.52, 0.15, 1.0)
			elif i < mines:
				pips.append("[+]")
				if pip_rect != null:
					pip_rect.texture = ICON_MINE
					pip_rect.modulate = Color(1.0, 0.85, 0.25, 1.0)
			else:
				pips.append("[ ]")
				if pip_rect != null:
					pip_rect.texture = ICON_MINE_EMPTY
					pip_rect.modulate = Color(0.55, 0.62, 0.72, 0.45)
		var pip_str := "   ".join(pips)
		var mine_col := Color(1.0, 0.52, 0.15, 1.0) if (cluster_m > 0 and mines > 0) else (Color(1.0, 0.85, 0.25, 1.0) if mines > 0 else Color(0.6, 0.65, 0.72, 0.8))
		if mine_pips_label != null:
			mine_pips_label.text = pip_str
			mine_pips_label.modulate = mine_col
		if mine_count_label != null:
			if cluster_m > 0 and mines > 0:
				mine_count_label.text = "%d/%d RACIMO" % [mines, max_m]
			else:
				mine_count_label.text = "%d / %d" % [mines, max_m]
			mine_count_label.modulate = mine_col
		
	if score_label != null:
		if is_spec:
			var sp_name: String = str(hud_subject.get("tank_name")) if "tank_name" in hud_subject else hud_subject.name
			score_label.text = "SCORE: %d (%s)" % [score, sp_name]
		else:
			score_label.text = "SCORE: %d" % score
		
	if streak_badge != null:
		if streak >= 2:
			streak_badge.visible = true
			streak_badge.text = "STREAK x%d!" % streak
		else:
			streak_badge.visible = false
			
	# Update active powerup (prioritize timed buffs over count-based buffs)
	if "active_powerups" in hud_subject or "_active_powerups" in hud_subject:
		var active_dict: Dictionary = hud_subject.get("_active_powerups") if "_active_powerups" in hud_subject else hud_subject.get("active_powerups")
		if active_dict != null and not active_dict.is_empty():
			var chosen_type: int = active_dict.keys()[0]
			for k in active_dict.keys():
				var d_info: Dictionary = active_dict[k]
				if float(d_info.get("duration", 0.0)) < 900.0:
					chosen_type = k
					break
			var info: Dictionary = active_dict[chosen_type]
			var time_left: float = info.get("time_left", 0.0)
			var duration: float = info.get("duration", 1.0)
			_show_powerup_ui(chosen_type, time_left, duration, info)
		else:
			if powerup_panel != null:
				powerup_panel.visible = false

func _on_match_started(_duration: float) -> void:
	if sudden_death_label != null:
		sudden_death_label.visible = false
	call_deferred("_update_bottom_left_card")
	if killstreak_banner != null:
		killstreak_banner.visible = false

func _on_sudden_death_started() -> void:
	if sudden_death_label != null:
		sudden_death_label.visible = true
		sudden_death_label.text = "¡ZONA CERRÁNDOSE! SIN RESPAWNS"
		sudden_death_label.modulate = Color(1.0, 0.32, 0.42, 1.0)

func _on_killstreak_achieved(killer: Node2D, title: String, subtitle: String, color: Color, _tier: int) -> void:
	# Show prominent CoD-style upper-center medal banner for local player (or when no player tank is present in isolated test)
	if is_instance_valid(player_tank) and is_instance_valid(killer) and killer != player_tank:
		return
	show_killstreak_medal(title, subtitle, color)

func show_killstreak_medal(title: String, subtitle: String, color: Color = Color(1.0, 0.85, 0.2)) -> void:
	if killstreak_banner == null:
		return
	if _medal_tween != null and _medal_tween.is_valid():
		_medal_tween.kill()
		
	if medal_title_label != null:
		medal_title_label.text = title
		medal_title_label.add_theme_color_override("font_color", color)
	for m_icon in _medal_icons:
		if is_instance_valid(m_icon):
			m_icon.modulate = color
	if medal_subtitle_label != null:
		medal_subtitle_label.text = subtitle
		
	killstreak_banner.visible = true
	killstreak_banner.modulate = Color(1, 1, 1, 1)
	killstreak_banner.scale = Vector2(1.42, 1.42)
	
	if get_tree() != null:
		_medal_tween = create_tween()
		_medal_tween.tween_property(killstreak_banner, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_medal_tween.tween_interval(2.2)
		_medal_tween.tween_property(killstreak_banner, "modulate:a", 0.0, 0.45)
		_medal_tween.tween_callback(func() -> void:
			if killstreak_banner != null:
				killstreak_banner.visible = false
		)

func _show_powerup_ui(type: int, time_left: float, total_duration: float, extra_info: Dictionary = {}) -> void:
	if powerup_panel == null:
		return
	powerup_panel.visible = true
	var type_name := "HEALTH"
	match type:
		0: type_name = "+40 HEALTH"
		1: type_name = "SHIELD (+50)"
		2: type_name = "RAPID FIRE"
		3:
			var shots: int = int(extra_info.get("shots_left", time_left))
			type_name = "RICOCHET (%d DISPAROS)" % shots
			if powerup_name_label != null:
				powerup_name_label.text = type_name
			if powerup_duration_bar != null:
				powerup_duration_bar.max_value = 20.0
				powerup_duration_bar.value = shots
			return
		4:
			type_name = "SPEED x2 (MONSTER)"
		5:
			var slots: int = int(extra_info.get("shots_left", 1))
			var tot_slots: int = maxi(1, int(extra_info.get("total_shots", 3)))
			type_name = "MINAS RACIMO (%d/%d)" % [slots, tot_slots]
			if powerup_name_label != null:
				powerup_name_label.text = type_name
			if powerup_duration_bar != null:
				powerup_duration_bar.max_value = float(tot_slots)
				powerup_duration_bar.value = float(slots)
			return
	if powerup_name_label != null:
		powerup_name_label.text = type_name
	if powerup_duration_bar != null:
		powerup_duration_bar.max_value = maxf(total_duration, 0.1)
		powerup_duration_bar.value = time_left

func _on_mortar_event_started(duration: float) -> void:
	if mortar_container != null:
		mortar_container.visible = true
	if mortar_bar != null:
		mortar_bar.max_value = duration
		mortar_bar.value = duration
	if mortar_icon != null:
		mortar_icon.modulate = Color(1.0, 0.35, 0.25, 1.0)
	if mortar_alert_label != null:
		mortar_alert_label.text = "¡ALERTA DE MORTEROS! (%.1fs)" % duration

func _on_mortar_event_tick(time_remaining: float, _duration: float) -> void:
	if mortar_container != null and not mortar_container.visible:
		mortar_container.visible = true
	if mortar_bar != null:
		mortar_bar.value = maxf(0.0, time_remaining)
	var flash := fmod(time_remaining, 0.4) > 0.2
	if mortar_icon != null:
		mortar_icon.modulate = Color(1.0, 0.85, 0.2) if flash else Color(1.0, 0.32, 0.24)
	if mortar_alert_label != null:
		mortar_alert_label.text = "¡ALERTA DE MORTEROS! (%.1fs)" % maxf(0.0, time_remaining)
		mortar_alert_label.modulate = Color(1.0, 0.85, 0.2) if flash else Color.WHITE

func _on_mortar_event_ended() -> void:
	if mortar_container != null:
		mortar_container.visible = false

func _on_match_tick(time_remaining: float) -> void:
	_last_timer_val = time_remaining
	if timer_label == null:
		return
		
	var mins: int = int(time_remaining) / 60
	var secs: int = int(time_remaining) % 60
	timer_label.text = "%02d:%02d" % [mins, secs]
	
	# Flashing red at <= 30 seconds
	if time_remaining <= 30.0 and time_remaining > 0.0:
		var flash := fmod(time_remaining, 0.6) > 0.3
		timer_label.modulate = Color(1.0, 0.25, 0.25, 1.0) if flash else Color.WHITE
		if sudden_death_label != null and sudden_death_label.visible:
			sudden_death_label.modulate = Color(1.0, 0.85, 0.25, 1.0) if flash else Color(1.0, 0.28, 0.38, 1.0)
	elif time_remaining <= 0.0:
		timer_label.modulate = Color(1.0, 0.2, 0.2, 1.0)
		timer_label.text = "00:00"
	else:
		timer_label.modulate = Color.WHITE

func _on_leaderboard_updated(sorted_list: Array[Dictionary]) -> void:
	if leaderboard_list == null:
		return
		
	# Clear old children
	for child in leaderboard_list.get_children():
		child.queue_free()
		
	var top_count: int = mini(5, sorted_list.size())
	for i in range(top_count):
		var entry: Dictionary = sorted_list[i]
		var rank := i + 1
		var c_name: String = str(entry.get("name", "Tank"))
		var c_score: int = int(entry.get("score", 0))
		var is_p: bool = (entry.get("is_player", false) == true)
		
		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		
		var rank_lbl := Label.new()
		rank_lbl.text = "#%d" % rank
		
		var name_lbl := Label.new()
		name_lbl.text = c_name
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_lbl.clip_text = true
		
		var score_lbl := Label.new()
		score_lbl.text = "%d" % c_score
		score_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		
		# Gold highlight for player row
		if is_p or c_name == "Player":
			var gold_color := Color(1.0, 0.84, 0.1, 1.0)
			rank_lbl.modulate = gold_color
			name_lbl.modulate = gold_color
			score_lbl.modulate = gold_color
		else:
			var normal_color := Color(0.85, 0.88, 0.92, 1.0)
			rank_lbl.modulate = normal_color
			name_lbl.modulate = normal_color
			score_lbl.modulate = normal_color

		if i == 0:
			var rank_cell := HBoxContainer.new()
			rank_cell.custom_minimum_size = Vector2(36, 0)
			rank_cell.add_theme_constant_override("separation", 3)
			var crown := _make_icon_rect(ICON_CROWN, 12.0, Color(1.0, 0.84, 0.1, 1.0))
			crown.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			rank_cell.add_child(crown)
			rank_cell.add_child(rank_lbl)
			row.add_child(rank_cell)
		else:
			rank_lbl.custom_minimum_size = Vector2(36, 0)
			row.add_child(rank_lbl)
		row.add_child(name_lbl)
		row.add_child(score_lbl)
		leaderboard_list.add_child(row)

func _on_tank_killed(victim: Node2D, killer: Node2D, is_barrel: bool) -> void:
	var v_name: String = victim.name if is_instance_valid(victim) else "Tank"
	if is_instance_valid(victim) and "tank_name" in victim:
		v_name = victim.tank_name
		
	var is_mortar: bool = false
	var is_mine: bool = is_instance_valid(victim) and victim.get("last_kill_was_mine") == true
	var is_storm: bool = is_instance_valid(victim) and victim.get("last_kill_was_storm") == true
	if is_instance_valid(killer):
		if killer.is_in_group("mortar") or killer.is_in_group("mortars") or killer.get("is_mortar") == true or "mortar" in killer.name.to_lower():
			is_mortar = true
		elif killer.get("is_mine") == true:
			is_mine = true
			
	var k_name: String = "Environment"
	if is_mortar:
		k_name = "Mortero de Artillería"
	elif is_instance_valid(killer):
		k_name = killer.tank_name if "tank_name" in killer else killer.name
	elif is_barrel:
		k_name = "Explosive Barrel"
		
	var text := "%s eliminated %s" % [k_name, v_name]
	var col := Color(0.9, 0.35, 0.3, 1.0)
	var icon_tex: Texture2D = null
	
	if is_mortar:
		text = "%s aniquiló a %s" % [k_name, v_name]
		col = Color(1.0, 0.3, 0.2, 1.0)
		icon_tex = ICON_MORTAR
	elif is_mine:
		text = "MINA • %s voló a %s" % [k_name, v_name]
		col = Color(1.0, 0.52, 0.15, 1.0)
		icon_tex = ICON_MINE
	elif is_storm:
		text = "%s cayó fuera de la zona segura" % v_name
		col = Color(1.0, 0.22, 0.45, 1.0)
		icon_tex = ICON_BIOHAZARD
	elif is_barrel:
		text = "%s destroyed %s (Barril)" % [k_name, v_name]
		col = Color(1.0, 0.55, 0.2, 1.0)
		icon_tex = ICON_ALERT
	elif is_instance_valid(killer) and killer.get("is_player") == true:
		col = Color(0.3, 0.9, 0.4, 1.0)
		
	_add_kill_feed_entry(text, col, icon_tex)

func _on_kill_feed_announced(text: String, color: Color) -> void:
	var icon_tex: Texture2D = null
	if "ZONA" in text:
		icon_tex = ICON_BIOHAZARD
	elif "FINALIZADA" in text:
		icon_tex = ICON_CHECK
	elif "MORTEROS" in text:
		icon_tex = ICON_MORTAR
	elif "RACHA" in text:
		icon_tex = ICON_TROPHY
	_add_kill_feed_entry(text, color, icon_tex)

func _add_kill_feed_entry(text: String, color: Color, icon_tex: Texture2D = null) -> void:
	if kill_feed_container == null:
		return
		
	var lbl := Label.new()
	lbl.text = text
	lbl.modulate = color
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_constant_override("outline_size", 3)
	lbl.add_theme_color_override("font_outline_color", Color(0.04, 0.05, 0.08, 0.95))
	if icon_tex != null:
		_attach_side_icons(lbl, icon_tex, 14.0, 20.0, false)
	kill_feed_container.add_child(lbl)
	
	# Limit maximum entries in feed
	if kill_feed_container.get_child_count() > 5:
		var oldest := kill_feed_container.get_child(0)
		oldest.queue_free()
		
	# Fade out after 3.5s
	if get_tree() != null:
		var tween := create_tween()
		tween.tween_interval(2.5)
		tween.tween_property(lbl, "modulate:a", 0.0, 1.0)
		tween.tween_callback(lbl.queue_free)

func _on_powerup_collected(_powerup: Node2D, collector: Node2D, type: int) -> void:
	if is_instance_valid(collector) and collector.get("is_player") == true:
		var dur := 22.0 if type == 1 else (8.0 if type == 2 else (15.0 if type == 4 else 0.0))
		if dur > 0.0:
			_show_powerup_ui(type, dur, dur)

func _on_powerup_expired(tank: Node2D, _type: int) -> void:
	if is_instance_valid(tank) and tank.get("is_player") == true:
		if powerup_panel != null:
			powerup_panel.visible = false
