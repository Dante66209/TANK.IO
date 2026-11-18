# res://Scripts/Core/game_settings.gd
extends Node

## Global Settings, Audio Bus Controller & Pre-Server Lobby Session State.
## Registered as Autoload singleton `GameSettings`.

signal audio_settings_changed()
signal settings_reset()

const MIN_LOBBY_PLAYERS: int = 5
const MAX_LOBBY_PLAYERS: int = 30
const DEFAULT_LOBBY_PLAYERS: int = 10
const SETTINGS_PATH: String = "user://tank_io_settings.cfg"

const BOT_CALLSIGNS: Array[String] = [
	"Bot Alpha", "Bot Bravo", "Bot Charlie", "Bot Delta", "Bot Echo",
	"Bot Foxtrot", "Bot Golf", "Bot Hotel", "Bot India", "Bot Juliet",
	"Bot Kilo", "Bot Lima", "Bot Mike", "Bot November", "Bot Oscar",
	"Bot Papa", "Bot Quebec", "Bot Romeo", "Bot Sierra", "Bot Tango",
	"Bot Uniform", "Bot Victor", "Bot Whiskey", "Bot X-Ray", "Bot Yankee",
	"Bot Zulu", "Bot Titan", "Bot Viper", "Bot Ghost"
]

# Audio Settings (0.0 to 1.0 linear scale)
var master_volume: float = 0.85
var sfx_volume: float = 0.85
var music_volume: float = 0.80
var master_muted: bool = false
var sfx_muted: bool = false
var music_muted: bool = false

# Display & Profile Preferences
var fullscreen: bool = false
var player_name: String = "Player"
var player_color: Color = Color(0.2, 0.45, 0.75, 1.0)

const TANK_COLOR_PRESETS: Array[Dictionary] = [
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

# Pre-Server & Online Match/Lobby Session Configuration
var match_configured_from_lobby: bool = false
var use_prematch_countdown: bool = false
var lobby_mode: String = "local" # "local" or "server"
var lobby_room_name: String = "Arena Local TANK.IO"
var configured_max_players: int = DEFAULT_LOBBY_PLAYERS
var connected_players: Array[Dictionary] = []
var server_ip: String = "127.0.0.1"
var server_port: int = 7777
var server_url: String = "ws://127.0.0.1:7777"

func _ready() -> void:
	ensure_audio_buses()
	if DisplayServer.get_name() != "headless":
		load_settings()
	apply_audio_volumes()

func ensure_audio_buses() -> void:
	for bus_name in ["SFX", "Music"]:
		if AudioServer.get_bus_index(bus_name) == -1:
			var idx: int = AudioServer.bus_count
			AudioServer.add_bus(idx)
			AudioServer.set_bus_name(idx, bus_name)
			AudioServer.set_bus_send(idx, &"Master")

func apply_audio_volumes() -> void:
	ensure_audio_buses()
	_apply_single_bus("Master", master_volume, master_muted)
	_apply_single_bus("SFX", sfx_volume, sfx_muted)
	_apply_single_bus("Music", music_volume, music_muted)
	audio_settings_changed.emit()

func _apply_single_bus(bus_name: String, linear_val: float, muted: bool) -> void:
	var idx: int = AudioServer.get_bus_index(bus_name)
	if idx == -1:
		return
	var clamped: float = clampf(linear_val, 0.0, 1.0)
	var is_silent: bool = muted or clamped <= 0.001
	AudioServer.set_bus_mute(idx, is_silent)
	if not is_silent:
		AudioServer.set_bus_volume_db(idx, linear_to_db(clamped))
	else:
		AudioServer.set_bus_volume_db(idx, -80.0)

func set_master_volume(linear_val: float, persist: bool = true) -> void:
	master_volume = clampf(linear_val, 0.0, 1.0)
	if master_volume > 0.001 and master_muted:
		master_muted = false
	apply_audio_volumes()
	if persist:
		save_settings()

func set_sfx_volume(linear_val: float, persist: bool = true) -> void:
	sfx_volume = clampf(linear_val, 0.0, 1.0)
	if sfx_volume > 0.001 and sfx_muted:
		sfx_muted = false
	apply_audio_volumes()
	if persist:
		save_settings()

func set_music_volume(linear_val: float, persist: bool = true) -> void:
	music_volume = clampf(linear_val, 0.0, 1.0)
	if music_volume > 0.001 and music_muted:
		music_muted = false
	apply_audio_volumes()
	if persist:
		save_settings()

func set_master_muted(muted: bool, persist: bool = true) -> void:
	master_muted = muted
	apply_audio_volumes()
	if persist:
		save_settings()

func set_sfx_muted(muted: bool, persist: bool = true) -> void:
	sfx_muted = muted
	apply_audio_volumes()
	if persist:
		save_settings()

func set_music_muted(muted: bool, persist: bool = true) -> void:
	music_muted = muted
	apply_audio_volumes()
	if persist:
		save_settings()

func set_player_name(new_name: String, persist: bool = true) -> void:
	var trimmed: String = new_name.strip_edges()
	player_name = trimmed.substr(0, 18) if not trimmed.is_empty() else "Player"
	if persist:
		save_settings()

func set_player_color(col: Color, persist: bool = true) -> void:
	player_color = Color(col.r, col.g, col.b, 1.0)
	if persist:
		save_settings()

func set_fullscreen(enabled: bool, persist: bool = true) -> void:
	fullscreen = enabled
	if DisplayServer.get_name() != "headless":
		var target_mode := DisplayServer.WINDOW_MODE_FULLSCREEN if enabled else DisplayServer.WINDOW_MODE_WINDOWED
		DisplayServer.window_set_mode(target_mode)
	if persist:
		save_settings()

func reset_defaults(persist: bool = true) -> void:
	master_volume = 0.85
	sfx_volume = 0.85
	music_volume = 0.80
	master_muted = false
	sfx_muted = false
	music_muted = false
	player_name = "Player"
	player_color = Color(0.2, 0.45, 0.75, 1.0)
	set_fullscreen(false, false)
	apply_audio_volumes()
	if persist:
		save_settings()
	settings_reset.emit()

func save_settings(path: String = SETTINGS_PATH) -> void:
	if DisplayServer.get_name() == "headless" and path == SETTINGS_PATH:
		return
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "master_volume", master_volume)
	cfg.set_value("audio", "sfx_volume", sfx_volume)
	cfg.set_value("audio", "music_volume", music_volume)
	cfg.set_value("audio", "master_muted", master_muted)
	cfg.set_value("audio", "sfx_muted", sfx_muted)
	cfg.set_value("audio", "music_muted", music_muted)
	cfg.set_value("display", "fullscreen", fullscreen)
	cfg.set_value("profile", "player_name", player_name)
	cfg.set_value("profile", "player_color", player_color)
	cfg.set_value("network", "server_url", server_url)
	cfg.save(path)

func load_settings(path: String = SETTINGS_PATH) -> void:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return
	master_volume = clampf(float(cfg.get_value("audio", "master_volume", master_volume)), 0.0, 1.0)
	sfx_volume = clampf(float(cfg.get_value("audio", "sfx_volume", sfx_volume)), 0.0, 1.0)
	music_volume = clampf(float(cfg.get_value("audio", "music_volume", music_volume)), 0.0, 1.0)
	master_muted = bool(cfg.get_value("audio", "master_muted", false))
	sfx_muted = bool(cfg.get_value("audio", "sfx_muted", false))
	music_muted = bool(cfg.get_value("audio", "music_muted", false))
	var fs: bool = bool(cfg.get_value("display", "fullscreen", false))
	set_fullscreen(fs, false)
	var saved_name: String = str(cfg.get_value("profile", "player_name", "Player")).strip_edges()
	if not saved_name.is_empty():
		player_name = saved_name.substr(0, 18)
	var saved_color = cfg.get_value("profile", "player_color", player_color)
	if saved_color is Color:
		player_color = saved_color
	var saved_url: String = str(cfg.get_value("network", "server_url", server_url)).strip_edges()
	if not saved_url.is_empty():
		server_url = saved_url
	apply_audio_volumes()

func set_server_url(new_url: String, persist: bool = true) -> void:
	var trimmed := new_url.strip_edges()
	if not trimmed.is_empty():
		server_url = trimmed
	if persist:
		save_settings()

func get_initial_server_url() -> String:
	if OS.has_feature("web") and Engine.has_singleton("JavaScriptBridge"):
		var js_bridge := Engine.get_singleton("JavaScriptBridge")
		if js_bridge != null:
			var js_code := """
				(() => {
					try {
						const params = new URLSearchParams(window.location.search);
						return params.get("server") || "";
					} catch (e) {
						return "";
					}
				})();
			"""
			var query_url := str(js_bridge.call("eval", js_code)).strip_edges()
			if not query_url.is_empty():
				return query_url
	return server_url

# ------------------------------------------------------------------------------
# Pre-Server Lobby & Match Session Helpers
# ------------------------------------------------------------------------------

func configure_lobby_match(roster: Array, max_cap: int, mode: String = "local", room_name: String = "Arena Local TANK.IO") -> void:
	configured_max_players = clampi(max_cap, MIN_LOBBY_PLAYERS, MAX_LOBBY_PLAYERS)
	lobby_mode = mode
	lobby_room_name = room_name
	connected_players.clear()
	for entry in roster:
		if entry is Dictionary:
			connected_players.append((entry as Dictionary).duplicate(true))
	# Ensure at least minimum 5 slots if roster was smaller
	while connected_players.size() < MIN_LOBBY_PLAYERS:
		var bot_idx: int = connected_players.size() - 1
		connected_players.append({
			"name": get_bot_name_for_index(maxi(0, bot_idx)),
			"is_player": false,
			"is_bot": true,
			"ready": true
		})
	match_configured_from_lobby = true
	use_prematch_countdown = true

func clear_lobby_match() -> void:
	match_configured_from_lobby = false
	use_prematch_countdown = false
	connected_players.clear()
	configured_max_players = DEFAULT_LOBBY_PLAYERS

func get_effective_combatant_count() -> int:
	if not match_configured_from_lobby or connected_players.is_empty():
		return DEFAULT_LOBBY_PLAYERS
	return clampi(connected_players.size(), MIN_LOBBY_PLAYERS, MAX_LOBBY_PLAYERS)

func get_bot_name_for_index(bot_index: int) -> String:
	if bot_index >= 0 and bot_index < BOT_CALLSIGNS.size():
		return BOT_CALLSIGNS[bot_index]
	return "Bot #%d" % (bot_index + 1)
