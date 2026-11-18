# res://Scripts/Core/sound_manager.gd
class_name SoundManager extends Node

## Standalone Procedural Audio Synthesizer for TANK.IO.
## Generates procedural 16-bit PCM sound effects for alarms, ricochets, explosions, mines, and killstreaks.
## Zero external dependencies; 100% self-contained and fails cleanly in headless environments.

static var instance = null
static var _cached_bombardment_stream: AudioStream = null
static var _cached_zone_closing_stream: AudioStream = null
static var _cached_mortar_explosion_stream: AudioStream = null
static var _cached_tank_shoot_stream: AudioStream = null
static var _cached_tank_hit_stream: AudioStream = null
static var _cached_tank_destroyed_stream: AudioStream = null
static var _cached_wood_break_stream: AudioStream = null
static var _cached_tank_move_stream: AudioStream = null
static var _cached_monster_bounce_stream: AudioStream = null

var _siren_stream: AudioStreamWAV = null
var _bombardment_stream: AudioStream = null
var _zone_closing_stream: AudioStream = null
var _mortar_explosion_stream: AudioStream = null
var _ricochet_stream: AudioStreamWAV = null
var _explosion_stream: AudioStreamWAV = null
var _shoot_stream: AudioStream = null
var _hit_stream: AudioStream = null
var _tank_destroyed_stream: AudioStream = null
var _tank_move_stream: AudioStream = null
var _monster_stream: AudioStream = null
var _monster_bounce_music_stream: AudioStream = null
var _mine_throw_stream: AudioStreamWAV = null
var _mine_arm_stream: AudioStreamWAV = null
var _killstreak_stream: AudioStreamWAV = null
var _wood_break_stream: AudioStream = null
var _pickup_stream: AudioStreamWAV = null
var _countdown_tick_stream: AudioStreamWAV = null
var _countdown_go_stream: AudioStreamWAV = null
var _ui_click_stream: AudioStreamWAV = null

var _player_pool: Array[AudioStreamPlayer] = []
var _positional_pool: Array[AudioStreamPlayer2D] = []
var _siren_player: AudioStreamPlayer = null
var _bombardment_player: AudioStreamPlayer = null
var _zone_closing_player: AudioStreamPlayer = null
const POOL_SIZE: int = 28

## Spatial hearing tuning: wide tactical radius around the player, silent across the rest of the map.
const FULL_VOLUME_RADIUS: float = 420.0
const HEARING_RADIUS_COMBAT: float = 1650.0
const HEARING_RADIUS_EXPLOSION: float = 2100.0
const HEARING_RADIUS_MORTAR: float = 2350.0
const HEARING_RADIUS_TACTICAL: float = 1450.0
const HEARING_RADIUS_PICKUP: float = 1350.0
const HEARING_RADIUS_MOVEMENT: float = 1050.0
const BOMBARDMENT_BASE_DB: float = -10.5
const ZONE_CLOSING_BASE_DB: float = -11.0

func _init() -> void:
	if instance == null:
		instance = self

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if instance == null or instance == self:
		instance = self
		_ensure_audio_buses()
		_init_synth_audio()
		_init_audio_pool()

func _exit_tree() -> void:
	for p in _player_pool:
		if is_instance_valid(p):
			p.stop()
			p.stream = null
	for p2d in _positional_pool:
		if is_instance_valid(p2d):
			p2d.stop()
			p2d.stream = null
	if is_instance_valid(_siren_player):
		_siren_player.stop()
		_siren_player.stream = null
	if is_instance_valid(_bombardment_player):
		_bombardment_player.stop()
		_bombardment_player.stream = null
	if is_instance_valid(_zone_closing_player):
		_zone_closing_player.stop()
		_zone_closing_player.stream = null
	if instance == self:
		instance = null

static func _ensure_audio_buses() -> void:
	for bus_name in ["SFX", "Music"]:
		if AudioServer.get_bus_index(bus_name) == -1:
			var idx: int = AudioServer.bus_count
			AudioServer.add_bus(idx)
			AudioServer.set_bus_name(idx, bus_name)
			AudioServer.set_bus_send(idx, &"Master")

func _get_sfx_bus_name() -> StringName:
	_ensure_audio_buses()
	return &"SFX" if AudioServer.get_bus_index("SFX") != -1 else &"Master"

func _get_music_bus_name() -> StringName:
	_ensure_audio_buses()
	return &"Music" if AudioServer.get_bus_index("Music") != -1 else &"Master"

func _init_audio_pool() -> void:
	var sfx_bus := _get_sfx_bus_name()
	var music_bus := _get_music_bus_name()
	for i in range(4):
		var p := AudioStreamPlayer.new()
		p.bus = sfx_bus
		add_child(p)
		_player_pool.append(p)
		
	for i in range(POOL_SIZE):
		var p2d := AudioStreamPlayer2D.new()
		p2d.bus = sfx_bus
		p2d.max_distance = 10000.0
		p2d.attenuation = 0.0001
		p2d.panning_strength = 0.85
		add_child(p2d)
		_positional_pool.append(p2d)
		
	_siren_player = AudioStreamPlayer.new()
	_siren_player.bus = sfx_bus
	add_child(_siren_player)
	
	_bombardment_player = AudioStreamPlayer.new()
	_bombardment_player.bus = music_bus
	add_child(_bombardment_player)
	
	_zone_closing_player = AudioStreamPlayer.new()
	_zone_closing_player.bus = music_bus
	add_child(_zone_closing_player)

func _get_listener_position() -> Variant:
	if not is_inside_tree() or get_tree() == null:
		return null
	var players := get_tree().get_nodes_in_group("player")
	if not players.is_empty() and is_instance_valid(players[0]) and players[0] is Node2D:
		var p_node := players[0] as Node2D
		if p_node.get("is_spectating") == true:
			var spec = p_node.get("spectated_tank")
			if spec != null and is_instance_valid(spec) and spec is Node2D and spec.get("is_dead") != true:
				return (spec as Node2D).global_position
		return p_node.global_position
	for t in get_tree().get_nodes_in_group("tanks"):
		if is_instance_valid(t) and t is Node2D and t.get("is_player") == true:
			return (t as Node2D).global_position
	var vp := get_viewport()
	if vp != null:
		var cam := vp.get_camera_2d()
		if cam != null:
			return cam.get_screen_center_position()
	return null

func is_within_hearing_range(sound_pos: Vector2, max_range: float) -> bool:
	var listener_pos = _get_listener_position()
	if listener_pos == null:
		return true
	return (listener_pos as Vector2).distance_to(sound_pos) <= max_range

func compute_spatial_volume_db(sound_pos: Vector2, base_volume_db: float, max_range: float) -> float:
	var listener_pos = _get_listener_position()
	if listener_pos == null:
		return base_volume_db
	var dist: float = (listener_pos as Vector2).distance_to(sound_pos)
	if dist <= FULL_VOLUME_RADIUS:
		return base_volume_db
	if dist > max_range:
		return -80.0
	var t: float = clampf((dist - FULL_VOLUME_RADIUS) / maxf(1.0, max_range - FULL_VOLUME_RADIUS), 0.0, 1.0)
	var gain: float = pow(1.0 - t, 1.5)
	return base_volume_db + linear_to_db(maxf(0.015, gain))

func _play_stream(stream: AudioStream, volume_db: float = 0.0, pitch_scale: float = 1.0) -> void:
	if stream == null or _player_pool.is_empty():
		return
	if not is_inside_tree() or DisplayServer.get_name() == "headless":
		return
	for p in _player_pool:
		if not p.playing:
			p.stream = stream
			p.volume_db = volume_db
			p.pitch_scale = pitch_scale
			p.play()
			return
	var steal := _player_pool[0]
	steal.stream = stream
	steal.volume_db = volume_db
	steal.pitch_scale = pitch_scale
	steal.play()

func _play_positional_stream(stream: AudioStream, pos: Vector2, base_volume_db: float = 0.0, pitch_scale: float = 1.0, max_range: float = HEARING_RADIUS_COMBAT) -> void:
	if stream == null or _positional_pool.is_empty():
		return
	if not is_within_hearing_range(pos, max_range):
		return
	var final_db: float = compute_spatial_volume_db(pos, base_volume_db, max_range)
	if not is_inside_tree() or DisplayServer.get_name() == "headless":
		return
	for p2d in _positional_pool:
		if not p2d.playing:
			p2d.global_position = pos
			p2d.stream = stream
			p2d.volume_db = final_db
			p2d.pitch_scale = pitch_scale
			p2d.play()
			return
	# Pool full: steal quietest channel only if new sound is at least as loud
	var quietest: AudioStreamPlayer2D = _positional_pool[0]
	for p2d in _positional_pool:
		if p2d.volume_db < quietest.volume_db:
			quietest = p2d
	if final_db >= quietest.volume_db - 1.0:
		quietest.global_position = pos
		quietest.stream = stream
		quietest.volume_db = final_db
		quietest.pitch_scale = pitch_scale
		quietest.play()

# --- Public Play API ---

static func _ensure_instance() -> Node:
	if instance != null and is_instance_valid(instance):
		return instance
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null and tree.root != null:
		var sm_script: GDScript = load("res://Scripts/Core/sound_manager.gd")
		var sm: Node = sm_script.new()
		sm.name = "SoundManager"
		instance = sm
		tree.root.add_child(sm)
		return sm
	return null

static func play_siren() -> void:
	_ensure_instance()
	if DisplayServer.get_name() == "headless":
		return
	if instance != null and instance._siren_player != null and instance._siren_stream != null:
		if instance._siren_player.is_inside_tree():
			instance._siren_player.stream = instance._siren_stream
			instance._siren_player.volume_db = 2.0
			instance._siren_player.play()

static func play_bombardment() -> void:
	_ensure_instance()
	if instance == null or instance._bombardment_player == null:
		return
	if instance._bombardment_stream == null and (DisplayServer.get_name() != "headless" or _cached_bombardment_stream != null):
		instance._bombardment_stream = instance._load_bombardment_stream()
	if instance._bombardment_stream != null:
		instance._bombardment_player.stream = instance._bombardment_stream
	instance._bombardment_player.volume_db = BOMBARDMENT_BASE_DB
	if DisplayServer.get_name() != "headless" and instance._bombardment_stream != null and instance._bombardment_player.is_inside_tree():
		instance._bombardment_player.play(0.0)

static func update_bombardment_volume(time_remaining: float, _total_duration: float = 25.0) -> void:
	if instance == null or instance._bombardment_player == null:
		return
	var fade_gain: float = clampf(time_remaining / 2.5, 0.015, 1.0)
	instance._bombardment_player.volume_db = BOMBARDMENT_BASE_DB + linear_to_db(fade_gain)

static func stop_bombardment() -> void:
	if instance != null and instance._bombardment_player != null and is_instance_valid(instance._bombardment_player):
		instance._bombardment_player.stop()

static func get_bombardment_stream() -> AudioStream:
	_ensure_instance()
	if instance != null:
		if instance._bombardment_stream == null:
			instance._bombardment_stream = instance._load_bombardment_stream()
		return instance._bombardment_stream
	return null

static func play_zone_closing() -> void:
	_ensure_instance()
	if instance == null or instance._zone_closing_player == null:
		return
	if instance._zone_closing_stream == null and (DisplayServer.get_name() != "headless" or _cached_zone_closing_stream != null):
		instance._zone_closing_stream = instance._load_zone_closing_stream()
	if instance._zone_closing_stream != null:
		instance._zone_closing_player.stream = instance._zone_closing_stream
	instance._zone_closing_player.volume_db = ZONE_CLOSING_BASE_DB
	if DisplayServer.get_name() != "headless" and instance._zone_closing_stream != null and instance._zone_closing_player.is_inside_tree():
		instance._zone_closing_player.play(0.0)

static func update_zone_closing_volume(time_remaining: float) -> void:
	if instance == null or instance._zone_closing_player == null:
		return
	var fade_gain: float = clampf(time_remaining / 2.0, 0.015, 1.0)
	instance._zone_closing_player.volume_db = ZONE_CLOSING_BASE_DB + linear_to_db(fade_gain)

static func stop_zone_closing() -> void:
	if instance != null and instance._zone_closing_player != null and is_instance_valid(instance._zone_closing_player):
		instance._zone_closing_player.stop()

static func get_zone_closing_stream() -> AudioStream:
	_ensure_instance()
	if instance != null:
		if instance._zone_closing_stream == null:
			instance._zone_closing_stream = instance._load_zone_closing_stream()
		return instance._zone_closing_stream
	return null

static func play_ricochet(pos: Vector2 = Vector2.ZERO) -> void:
	_ensure_instance()
	if instance != null:
		var pitch := randf_range(0.9, 1.2)
		instance._play_positional_stream(instance._ricochet_stream, pos, -2.0, pitch, HEARING_RADIUS_COMBAT)

static func play_explosion(pos: Vector2 = Vector2.ZERO) -> void:
	_ensure_instance()
	if instance != null:
		var pitch := randf_range(0.85, 1.15)
		instance._play_positional_stream(instance._explosion_stream, pos, 1.0, pitch, HEARING_RADIUS_EXPLOSION)

static func play_mortar_explosion(pos: Vector2 = Vector2.ZERO) -> void:
	_ensure_instance()
	if instance != null:
		if instance._mortar_explosion_stream == null:
			instance._mortar_explosion_stream = instance._load_mortar_explosion_stream()
		var stream_to_play: AudioStream = instance._mortar_explosion_stream if instance._mortar_explosion_stream != null else instance._explosion_stream
		var pitch := randf_range(0.94, 1.06)
		instance._play_positional_stream(stream_to_play, pos, 2.5, pitch, HEARING_RADIUS_MORTAR)

static func get_mortar_explosion_stream() -> AudioStream:
	_ensure_instance()
	if instance != null:
		if instance._mortar_explosion_stream == null:
			instance._mortar_explosion_stream = instance._load_mortar_explosion_stream()
		return instance._mortar_explosion_stream
	return null

static func play_shoot(pos: Vector2 = Vector2.ZERO) -> void:
	_ensure_instance()
	if instance != null:
		if instance._shoot_stream == null:
			instance._shoot_stream = instance._load_tank_shoot_stream()
		var pitch := randf_range(0.96, 1.04)
		instance._play_positional_stream(instance._shoot_stream, pos, -2.0, pitch, HEARING_RADIUS_COMBAT)

static func get_tank_shoot_stream() -> AudioStream:
	_ensure_instance()
	if instance != null:
		if instance._shoot_stream == null:
			instance._shoot_stream = instance._load_tank_shoot_stream()
		return instance._shoot_stream
	return null

static func play_hit(pos: Vector2 = Vector2.ZERO) -> void:
	_ensure_instance()
	if instance != null:
		if instance._hit_stream == null:
			instance._hit_stream = instance._load_tank_hit_stream()
		var pitch := randf_range(0.93, 1.07)
		instance._play_positional_stream(instance._hit_stream, pos, -2.5, pitch, HEARING_RADIUS_TACTICAL)

static func get_tank_hit_stream() -> AudioStream:
	_ensure_instance()
	if instance != null:
		if instance._hit_stream == null:
			instance._hit_stream = instance._load_tank_hit_stream()
		return instance._hit_stream
	return null

static func play_tank_destroyed(pos: Vector2 = Vector2.ZERO) -> void:
	_ensure_instance()
	if instance != null:
		if instance._tank_destroyed_stream == null:
			instance._tank_destroyed_stream = instance._load_tank_destroyed_stream()
		var stream_to_play: AudioStream = instance._tank_destroyed_stream if instance._tank_destroyed_stream != null else instance._explosion_stream
		var pitch := randf_range(0.94, 1.06)
		instance._play_positional_stream(stream_to_play, pos, 2.0, pitch, HEARING_RADIUS_EXPLOSION)

static func get_tank_destroyed_stream() -> AudioStream:
	_ensure_instance()
	if instance != null:
		if instance._tank_destroyed_stream == null:
			instance._tank_destroyed_stream = instance._load_tank_destroyed_stream()
		return instance._tank_destroyed_stream
	return null

static func get_tank_move_stream() -> AudioStream:
	_ensure_instance()
	if instance != null:
		if instance._tank_move_stream == null:
			instance._tank_move_stream = instance._load_tank_move_stream()
		return instance._tank_move_stream
	return null

static func play_monster_drink(pos: Vector2 = Vector2.ZERO) -> void:
	_ensure_instance()
	if instance != null:
		instance._play_positional_stream(instance._monster_stream, pos, 2.5, 1.0, HEARING_RADIUS_PICKUP)

static func play_pickup(pos: Vector2 = Vector2.ZERO) -> void:
	_ensure_instance()
	if instance != null:
		instance._play_positional_stream(instance._pickup_stream, pos, -2.5, randf_range(0.96, 1.06), HEARING_RADIUS_PICKUP)

static func play_mine_throw(pos: Vector2 = Vector2.ZERO) -> void:
	_ensure_instance()
	if instance != null:
		instance._play_positional_stream(instance._mine_throw_stream, pos, -2.0, randf_range(0.95, 1.08), HEARING_RADIUS_TACTICAL)

static func play_mine_arm(pos: Vector2 = Vector2.ZERO) -> void:
	_ensure_instance()
	if instance != null:
		instance._play_positional_stream(instance._mine_arm_stream, pos, -3.0, 1.0, HEARING_RADIUS_TACTICAL)

static func play_killstreak(tier: int = 1, pos: Vector2 = Vector2.ZERO, is_local_player: bool = true) -> void:
	_ensure_instance()
	if instance != null:
		var pitch := clampf(0.95 + float(tier - 1) * 0.08, 0.9, 1.35)
		if is_local_player:
			instance._play_stream(instance._killstreak_stream, 2.5, pitch)
		else:
			instance._play_positional_stream(instance._killstreak_stream, pos, 1.0, pitch, HEARING_RADIUS_EXPLOSION)

static func play_wood_break(pos: Vector2 = Vector2.ZERO) -> void:
	_ensure_instance()
	if instance != null:
		if instance._wood_break_stream == null:
			instance._wood_break_stream = instance._load_wood_break_stream()
		instance._play_positional_stream(instance._wood_break_stream, pos, 0.5, randf_range(0.94, 1.08), HEARING_RADIUS_TACTICAL)

static func get_wood_break_stream() -> AudioStream:
	_ensure_instance()
	if instance != null:
		if instance._wood_break_stream == null:
			instance._wood_break_stream = instance._load_wood_break_stream()
		return instance._wood_break_stream
	return null

static func get_monster_bounce_music_stream() -> AudioStream:
	_ensure_instance()
	if instance != null:
		if instance._monster_bounce_music_stream == null:
			instance._monster_bounce_music_stream = instance._load_monster_bounce_music_stream()
		return instance._monster_bounce_music_stream
	return null

static func play_countdown_tick(step: int = 3) -> void:
	_ensure_instance()
	if instance != null:
		var pitch := clampf(1.0 + float(3 - step) * 0.08, 0.92, 1.24)
		instance._play_stream(instance._countdown_tick_stream, -1.0, pitch)

static func play_countdown_go() -> void:
	_ensure_instance()
	if instance != null:
		instance._play_stream(instance._countdown_go_stream, 0.5, 1.0)

static func play_ui_click() -> void:
	_ensure_instance()
	if instance != null:
		instance._play_stream(instance._ui_click_stream, -5.0, randf_range(0.96, 1.04))

static func stop_all_match_audio() -> void:
	stop_bombardment()
	stop_zone_closing()
	if instance == null:
		return
	if is_instance_valid(instance._siren_player):
		instance._siren_player.stop()
	for p in instance._player_pool:
		if is_instance_valid(p):
			p.stop()
	for p2d in instance._positional_pool:
		if is_instance_valid(p2d):
			p2d.stop()

# --- Procedural Waveform Synthesizers ---

func _init_synth_audio() -> void:
	_siren_stream = _generate_siren_wave()
	if DisplayServer.get_name() != "headless":
		_bombardment_stream = _load_bombardment_stream()
		_zone_closing_stream = _load_zone_closing_stream()
		_tank_move_stream = _load_tank_move_stream()
		_monster_bounce_music_stream = _load_monster_bounce_music_stream()
	_ricochet_stream = _generate_ricochet_wave()
	_explosion_stream = _generate_explosion_wave()
	_mortar_explosion_stream = _load_mortar_explosion_stream()
	_shoot_stream = _load_tank_shoot_stream()
	_hit_stream = _load_tank_hit_stream()
	_tank_destroyed_stream = _load_tank_destroyed_stream()
	_monster_stream = _load_monster_drink_stream()
	_mine_throw_stream = _generate_mine_throw_wave()
	_mine_arm_stream = _generate_mine_arm_wave()
	_killstreak_stream = _generate_killstreak_wave()
	_wood_break_stream = _load_wood_break_stream()
	_pickup_stream = _generate_pickup_wave()
	_countdown_tick_stream = _generate_countdown_tick_wave()
	_countdown_go_stream = _generate_countdown_go_wave()
	_ui_click_stream = _generate_ui_click_wave()

func _load_bombardment_stream() -> AudioStream:
	if _cached_bombardment_stream != null:
		return _cached_bombardment_stream
	if ResourceLoader.exists("res://Assets/mortar_bombardment.mp3"):
		var res = load("res://Assets/mortar_bombardment.mp3")
		if res is AudioStreamMP3:
			(res as AudioStreamMP3).loop = true
			_cached_bombardment_stream = res
			return res
		elif res is AudioStream:
			_cached_bombardment_stream = res
			return res
	if FileAccess.file_exists("res://Assets/mortar_bombardment.mp3"):
		var bytes := FileAccess.get_file_as_bytes("res://Assets/mortar_bombardment.mp3")
		if not bytes.is_empty():
			var mp3 := AudioStreamMP3.new()
			mp3.data = bytes
			mp3.loop = true
			_cached_bombardment_stream = mp3
			return mp3
	return _siren_stream

func _load_zone_closing_stream() -> AudioStream:
	if _cached_zone_closing_stream != null:
		return _cached_zone_closing_stream
	if ResourceLoader.exists("res://Assets/zone_closing_siren.mp3"):
		var res = load("res://Assets/zone_closing_siren.mp3")
		if res is AudioStreamMP3:
			(res as AudioStreamMP3).loop = true
			_cached_zone_closing_stream = res
			return res
		elif res is AudioStream:
			_cached_zone_closing_stream = res
			return res
	if FileAccess.file_exists("res://Assets/zone_closing_siren.mp3"):
		var bytes := FileAccess.get_file_as_bytes("res://Assets/zone_closing_siren.mp3")
		if not bytes.is_empty():
			var mp3 := AudioStreamMP3.new()
			mp3.data = bytes
			mp3.loop = true
			_cached_zone_closing_stream = mp3
			return mp3
	return _siren_stream

func _load_mortar_explosion_stream() -> AudioStream:
	if _cached_mortar_explosion_stream != null:
		return _cached_mortar_explosion_stream
	if ResourceLoader.exists("res://Assets/mortar_explosion.mp3"):
		var res = load("res://Assets/mortar_explosion.mp3")
		if res is AudioStreamMP3:
			(res as AudioStreamMP3).loop = false
			_cached_mortar_explosion_stream = res
			return res
		elif res is AudioStream:
			_cached_mortar_explosion_stream = res
			return res
	if FileAccess.file_exists("res://Assets/mortar_explosion.mp3"):
		var bytes := FileAccess.get_file_as_bytes("res://Assets/mortar_explosion.mp3")
		if not bytes.is_empty():
			var mp3 := AudioStreamMP3.new()
			mp3.data = bytes
			mp3.loop = false
			_cached_mortar_explosion_stream = mp3
			return mp3
	return _explosion_stream

func _load_tank_shoot_stream() -> AudioStream:
	if _cached_tank_shoot_stream != null:
		return _cached_tank_shoot_stream
	if ResourceLoader.exists("res://Assets/tank_shoot.mp3"):
		var res = load("res://Assets/tank_shoot.mp3")
		if res is AudioStreamMP3:
			(res as AudioStreamMP3).loop = false
			_cached_tank_shoot_stream = res
			return res
		elif res is AudioStream:
			_cached_tank_shoot_stream = res
			return res
	if FileAccess.file_exists("res://Assets/tank_shoot.mp3"):
		var bytes := FileAccess.get_file_as_bytes("res://Assets/tank_shoot.mp3")
		if not bytes.is_empty():
			var mp3 := AudioStreamMP3.new()
			mp3.data = bytes
			mp3.loop = false
			_cached_tank_shoot_stream = mp3
			return mp3
	return _generate_shoot_wave()

func _load_tank_hit_stream() -> AudioStream:
	if _cached_tank_hit_stream != null:
		return _cached_tank_hit_stream
	if ResourceLoader.exists("res://Assets/tank_hit.mp3"):
		var res = load("res://Assets/tank_hit.mp3")
		if res is AudioStreamMP3:
			(res as AudioStreamMP3).loop = false
			_cached_tank_hit_stream = res
			return res
		elif res is AudioStream:
			_cached_tank_hit_stream = res
			return res
	if FileAccess.file_exists("res://Assets/tank_hit.mp3"):
		var bytes := FileAccess.get_file_as_bytes("res://Assets/tank_hit.mp3")
		if not bytes.is_empty():
			var mp3 := AudioStreamMP3.new()
			mp3.data = bytes
			mp3.loop = false
			_cached_tank_hit_stream = mp3
			return mp3
	return _generate_hit_wave()

func _load_tank_destroyed_stream() -> AudioStream:
	if _cached_tank_destroyed_stream != null:
		return _cached_tank_destroyed_stream
	if ResourceLoader.exists("res://Assets/tank_destroyed.mp3"):
		var res = load("res://Assets/tank_destroyed.mp3")
		if res is AudioStreamMP3:
			(res as AudioStreamMP3).loop = false
			_cached_tank_destroyed_stream = res
			return res
		elif res is AudioStream:
			_cached_tank_destroyed_stream = res
			return res
	if FileAccess.file_exists("res://Assets/tank_destroyed.mp3"):
		var bytes := FileAccess.get_file_as_bytes("res://Assets/tank_destroyed.mp3")
		if not bytes.is_empty():
			var mp3 := AudioStreamMP3.new()
			mp3.data = bytes
			mp3.loop = false
			_cached_tank_destroyed_stream = mp3
			return mp3
	return _explosion_stream

func _load_wood_break_stream() -> AudioStream:
	if _cached_wood_break_stream != null:
		return _cached_wood_break_stream
	if ResourceLoader.exists("res://Assets/wood_wall_break.mp3"):
		var res = load("res://Assets/wood_wall_break.mp3")
		if res is AudioStreamMP3:
			(res as AudioStreamMP3).loop = false
			_cached_wood_break_stream = res
			return res
		elif res is AudioStream:
			_cached_wood_break_stream = res
			return res
	if FileAccess.file_exists("res://Assets/wood_wall_break.mp3"):
		var bytes := FileAccess.get_file_as_bytes("res://Assets/wood_wall_break.mp3")
		if not bytes.is_empty():
			var mp3 := AudioStreamMP3.new()
			mp3.data = bytes
			mp3.loop = false
			_cached_wood_break_stream = mp3
			return mp3
	return _generate_wood_break_wave()

func _load_tank_move_stream() -> AudioStream:
	if _cached_tank_move_stream != null:
		return _cached_tank_move_stream
	if ResourceLoader.exists("res://Assets/tank_move.mp3"):
		var res = load("res://Assets/tank_move.mp3")
		if res is AudioStreamMP3:
			(res as AudioStreamMP3).loop = true
			_cached_tank_move_stream = res
			return res
		elif res is AudioStream:
			_cached_tank_move_stream = res
			return res
	if FileAccess.file_exists("res://Assets/tank_move.mp3"):
		var bytes := FileAccess.get_file_as_bytes("res://Assets/tank_move.mp3")
		if not bytes.is_empty():
			var mp3 := AudioStreamMP3.new()
			mp3.data = bytes
			mp3.loop = true
			_cached_tank_move_stream = mp3
			return mp3
	return null

func _load_monster_bounce_music_stream() -> AudioStream:
	if _cached_monster_bounce_stream != null:
		return _cached_monster_bounce_stream
	if ResourceLoader.exists("res://Assets/monster_bounce_music.mp3"):
		var res = load("res://Assets/monster_bounce_music.mp3")
		if res is AudioStreamMP3:
			(res as AudioStreamMP3).loop = true
			_cached_monster_bounce_stream = res
			return res
		elif res is AudioStream:
			_cached_monster_bounce_stream = res
			return res
	if FileAccess.file_exists("res://Assets/monster_bounce_music.mp3"):
		var bytes := FileAccess.get_file_as_bytes("res://Assets/monster_bounce_music.mp3")
		if not bytes.is_empty():
			var mp3 := AudioStreamMP3.new()
			mp3.data = bytes
			mp3.loop = true
			_cached_monster_bounce_stream = mp3
			return mp3
	return _monster_stream

func _generate_pickup_wave() -> AudioStreamWAV:
	var sample_rate := 22050
	var duration := 0.16
	var total_samples := int(sample_rate * duration)
	var bytes := PackedByteArray()
	bytes.resize(total_samples * 2)
	
	var phase := 0.0
	for i in range(total_samples):
		var t := float(i) / float(sample_rate)
		var freq := 587.33 if t < 0.075 else 880.0
		var local_t := t if t < 0.075 else (t - 0.075)
		phase += (freq * TAU) / float(sample_rate)
		var env := exp(-local_t * 18.0)
		var s := (sin(phase) * 0.75 + sin(phase * 2.0) * 0.25) * env
		var val := int(clampf(s * 21000.0, -32000.0, 32000.0))
		bytes.encode_s16(i * 2, val)
		
	return _make_wav(sample_rate, bytes)

func _load_monster_drink_stream() -> AudioStream:
	if ResourceLoader.exists("res://Assets/monster_drink.mp3"):
		var res = load("res://Assets/monster_drink.mp3")
		if res is AudioStream:
			return res
	if FileAccess.file_exists("res://Assets/monster_drink.mp3"):
		var bytes := FileAccess.get_file_as_bytes("res://Assets/monster_drink.mp3")
		if not bytes.is_empty():
			var mp3 := AudioStreamMP3.new()
			mp3.data = bytes
			return mp3
	return null

func _generate_siren_wave() -> AudioStreamWAV:
	var sample_rate := 22050
	var duration := 2.2
	var total_samples := int(sample_rate * duration)
	var bytes := PackedByteArray()
	bytes.resize(total_samples * 2)
	
	var phase := 0.0
	for i in range(total_samples):
		var t := float(i) / float(sample_rate)
		var freq := 800.0 + sin(t * TAU * 1.8) * 180.0
		phase += (freq * TAU) / float(sample_rate)
		var s := sin(phase) * 0.8 + sin(phase * 3.0) * 0.15
		var env := 1.0
		if t < 0.05:
			env = t / 0.05
		elif t > (duration - 0.2):
			env = (duration - t) / 0.2
		var val := int(clampf(s * env * 24000.0, -32000.0, 32000.0))
		bytes.encode_s16(i * 2, val)
		
	return _make_wav(sample_rate, bytes)

func _generate_ricochet_wave() -> AudioStreamWAV:
	var sample_rate := 22050
	var duration := 0.35
	var total_samples := int(sample_rate * duration)
	var bytes := PackedByteArray()
	bytes.resize(total_samples * 2)
	
	for i in range(total_samples):
		var t := float(i) / float(sample_rate)
		var env := exp(-t * 18.0)
		var s := sin(t * TAU * 1350.0) * 0.7 + sin(t * TAU * 2100.0) * 0.3
		var val := int(clampf(s * env * 26000.0, -32000.0, 32000.0))
		bytes.encode_s16(i * 2, val)
		
	return _make_wav(sample_rate, bytes)

func _generate_explosion_wave() -> AudioStreamWAV:
	var sample_rate := 22050
	var duration := 0.65
	var total_samples := int(sample_rate * duration)
	var bytes := PackedByteArray()
	bytes.resize(total_samples * 2)
	
	var prev := 0.0
	for i in range(total_samples):
		var t := float(i) / float(sample_rate)
		var env := exp(-t * 6.5)
		var white := randf_range(-1.0, 1.0)
		prev = lerpf(prev, white, 0.12)
		var rumble := sin(t * TAU * 55.0 * (1.0 - t * 0.5)) * 0.5
		var s := (prev * 0.7 + rumble * 0.5) * env
		var val := int(clampf(s * 28000.0, -32000.0, 32000.0))
		bytes.encode_s16(i * 2, val)
		
	return _make_wav(sample_rate, bytes)

func _generate_shoot_wave() -> AudioStreamWAV:
	var sample_rate := 22050
	var duration := 0.18
	var total_samples := int(sample_rate * duration)
	var bytes := PackedByteArray()
	bytes.resize(total_samples * 2)
	
	var phase := 0.0
	for i in range(total_samples):
		var t := float(i) / float(sample_rate)
		var env := exp(-t * 22.0)
		var freq := lerpf(240.0, 50.0, t / duration)
		phase += (freq * TAU) / float(sample_rate)
		var s := sin(phase) * 0.8 + randf_range(-0.2, 0.2)
		var val := int(clampf(s * env * 22000.0, -32000.0, 32000.0))
		bytes.encode_s16(i * 2, val)
		
	return _make_wav(sample_rate, bytes)

func _generate_hit_wave() -> AudioStreamWAV:
	var sample_rate := 22050
	var duration := 0.12
	var total_samples := int(sample_rate * duration)
	var bytes := PackedByteArray()
	bytes.resize(total_samples * 2)
	
	for i in range(total_samples):
		var t := float(i) / float(sample_rate)
		var env := exp(-t * 30.0)
		var s := sin(t * TAU * 110.0) + randf_range(-0.3, 0.3)
		var val := int(clampf(s * env * 20000.0, -32000.0, 32000.0))
		bytes.encode_s16(i * 2, val)
		
	return _make_wav(sample_rate, bytes)

func _generate_mine_throw_wave() -> AudioStreamWAV:
	var sample_rate := 22050
	var duration := 0.22
	var total_samples := int(sample_rate * duration)
	var bytes := PackedByteArray()
	bytes.resize(total_samples * 2)
	
	var phase := 0.0
	var prev := 0.0
	for i in range(total_samples):
		var t := float(i) / float(sample_rate)
		var norm_t := t / duration
		var env := sin(norm_t * PI)
		var freq := lerpf(320.0, 150.0, norm_t)
		phase += (freq * TAU) / float(sample_rate)
		prev = lerpf(prev, randf_range(-1.0, 1.0), 0.25)
		var s := (sin(phase) * 0.55 + prev * 0.45) * env
		var val := int(clampf(s * 20000.0, -32000.0, 32000.0))
		bytes.encode_s16(i * 2, val)
		
	return _make_wav(sample_rate, bytes)

func _generate_mine_arm_wave() -> AudioStreamWAV:
	var sample_rate := 22050
	var duration := 0.18
	var total_samples := int(sample_rate * duration)
	var bytes := PackedByteArray()
	bytes.resize(total_samples * 2)
	
	for i in range(total_samples):
		var t := float(i) / float(sample_rate)
		var s := 0.0
		if t < 0.07:
			var env := exp(-t * 25.0)
			s = sin(t * TAU * 1650.0) * env
		elif t >= 0.09:
			var t2 := t - 0.09
			var env2 := exp(-t2 * 22.0)
			s = sin(t2 * TAU * 2250.0) * env2
		var val := int(clampf(s * 21000.0, -32000.0, 32000.0))
		bytes.encode_s16(i * 2, val)
		
	return _make_wav(sample_rate, bytes)

func _generate_killstreak_wave() -> AudioStreamWAV:
	var sample_rate := 22050
	var duration := 0.48
	var total_samples := int(sample_rate * duration)
	var bytes := PackedByteArray()
	bytes.resize(total_samples * 2)
	
	var phase := 0.0
	for i in range(total_samples):
		var t := float(i) / float(sample_rate)
		var freq := 440.0
		var local_t := t
		if t >= 0.12 and t < 0.24:
			freq = 554.37
			local_t = t - 0.12
		elif t >= 0.24:
			freq = 659.25
			local_t = t - 0.24
			
		phase += (freq * TAU) / float(sample_rate)
		var raw := sin(phase) * 0.6 + sin(phase * 2.0) * 0.25 + sin(phase * 0.5) * 0.25
		var env := exp(-local_t * 5.5)
		if t > duration - 0.08:
			env *= (duration - t) / 0.08
		var val := int(clampf(raw * env * 25000.0, -32000.0, 32000.0))
		bytes.encode_s16(i * 2, val)
		
	return _make_wav(sample_rate, bytes)

func _generate_wood_break_wave() -> AudioStreamWAV:
	var sample_rate := 22050
	var duration := 0.28
	var total_samples := int(sample_rate * duration)
	var bytes := PackedByteArray()
	bytes.resize(total_samples * 2)
	
	var prev := 0.0
	for i in range(total_samples):
		var t := float(i) / float(sample_rate)
		var env := exp(-t * 11.0)
		var crack := 1.0 if (int(t * 95.0) % 3 == 0) else 0.4
		prev = lerpf(prev, randf_range(-1.0, 1.0), 0.35)
		var thud := sin(t * TAU * 145.0) * exp(-t * 20.0)
		var s := (prev * crack * 0.7 + thud * 0.5) * env
		var val := int(clampf(s * 24000.0, -32000.0, 32000.0))
		bytes.encode_s16(i * 2, val)
		
	return _make_wav(sample_rate, bytes)

func _make_wav(sample_rate: int, bytes: PackedByteArray) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false
	stream.data = bytes
	return stream

func _generate_countdown_tick_wave() -> AudioStreamWAV:
	var sample_rate := 22050
	var duration := 0.18
	var total_samples := int(sample_rate * duration)
	var bytes := PackedByteArray()
	bytes.resize(total_samples * 2)
	for i in range(total_samples):
		var t := float(i) / float(sample_rate)
		var env := exp(-t * 20.0)
		var s := (sin(t * TAU * 660.0) * 0.72 + sin(t * TAU * 1320.0) * 0.25) * env
		bytes.encode_s16(i * 2, int(clampf(s * 22000.0, -32000.0, 32000.0)))
	return _make_wav(sample_rate, bytes)

func _generate_countdown_go_wave() -> AudioStreamWAV:
	var sample_rate := 22050
	var duration := 0.42
	var total_samples := int(sample_rate * duration)
	var bytes := PackedByteArray()
	bytes.resize(total_samples * 2)
	for i in range(total_samples):
		var t := float(i) / float(sample_rate)
		var env := exp(-t * 6.5)
		var s := (sin(t * TAU * 523.25) * 0.45 + sin(t * TAU * 659.25) * 0.35 + sin(t * TAU * 783.99) * 0.35 + sin(t * TAU * 1046.5) * 0.25) * env
		bytes.encode_s16(i * 2, int(clampf(s * 24000.0, -32000.0, 32000.0)))
	return _make_wav(sample_rate, bytes)

func _generate_ui_click_wave() -> AudioStreamWAV:
	var sample_rate := 22050
	var duration := 0.06
	var total_samples := int(sample_rate * duration)
	var bytes := PackedByteArray()
	bytes.resize(total_samples * 2)
	for i in range(total_samples):
		var t := float(i) / float(sample_rate)
		var env := exp(-t * 55.0)
		var s := (sin(t * TAU * 920.0) * 0.65 + sin(t * TAU * 1840.0) * 0.25) * env
		bytes.encode_s16(i * 2, int(clampf(s * 18000.0, -32000.0, 32000.0)))
	return _make_wav(sample_rate, bytes)
