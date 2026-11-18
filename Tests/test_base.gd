# res://Tests/test_base.gd
class_name TestBase
extends Node

## Base Test Harness for TANK.IO Headless Testing (Godot 4.6)
## Provides assertions, async frame stepping, lifecycle management, and node tracking.

var test_name: String = ""
var passed_assertions: int = 0
var failed_assertions: int = 0
var failure_messages: Array[String] = []
var _tracked_nodes: Array[Node] = []

func setup() -> void:
	pass

func teardown() -> void:
	for node in _tracked_nodes:
		if is_instance_valid(node) and not node.is_queued_for_deletion():
			if node.get_parent():
				node.get_parent().remove_child(node)
			node.queue_free()
	_tracked_nodes.clear()

## Registers a node for automatic cleanup in teardown
func track_node(node: Node) -> Node:
	if node and not _tracked_nodes.has(node):
		_tracked_nodes.append(node)
	return node

## Instantiates a scene from res:// path, tracks it, and optionally attaches to parent
func spawn_scene(path: String, parent: Node = null) -> Node:
	if not ResourceLoader.exists(path):
		return null
	var res = load(path)
	if not res or not (res is PackedScene):
		return null
	var instance = (res as PackedScene).instantiate()
	if instance:
		track_node(instance)
		if parent != null:
			parent.add_child(instance)
		else:
			add_child(instance)
	return instance

## Safely loads a GDScript only if it exists, avoiding engine error logs
func load_script(path: String) -> GDScript:
	if ResourceLoader.exists(path):
		var s = load(path)
		if s is GDScript:
			return s as GDScript
	return null

## Robust property inspection helpers for tank stats across conventions
func get_tank_health(tank: Node) -> float:
	if tank == null: return 0.0
	for prop in ["current_health", "current_hp", "health", "hp"]:
		if prop in tank:
			return float(tank.get(prop))
	return 0.0

func get_tank_max_health(tank: Node) -> float:
	if tank == null: return 100.0
	for prop in ["max_health", "max_hp"]:
		if prop in tank:
			return float(tank.get(prop))
	return 100.0

func get_tank_shield(tank: Node) -> float:
	if tank == null: return 0.0
	for prop in ["shield", "current_shield"]:
		if prop in tank:
			return float(tank.get(prop))
	return 0.0

## Safely locates or mocks GameEvents singleton
func get_game_events() -> Node:
	if has_node("/root/GameEvents"):
		return get_node("/root/GameEvents")
	var ge_class = load("res://Scripts/Core/game_events.gd")
	if ge_class:
		if "instance" in ge_class and ge_class.instance != null:
			return ge_class.instance
		var instance = ge_class.new()
		track_node(instance)
		get_tree().root.add_child(instance)
		return instance
	return null

# --- Async Stepping Helpers ---

func wait_physics_frames(count: int = 1) -> void:
	for _i in range(count):
		await get_tree().physics_frame

func wait_process_frames(count: int = 1) -> void:
	for _i in range(count):
		await get_tree().process_frame

func wait_simulated_seconds(seconds: float) -> void:
	var frames = int(ceil(seconds * Engine.physics_ticks_per_second))
	await wait_physics_frames(frames)

# --- Assertion Helpers ---

func assert_true(condition: bool, message: String = "") -> bool:
	if condition:
		passed_assertions += 1
		return true
	else:
		failed_assertions += 1
		var err = "[FAIL] Expected true, got false. %s" % message
		failure_messages.append(err)
		printerr("    ", err)
		return false

func assert_false(condition: bool, message: String = "") -> bool:
	return assert_true(not condition, message)

func assert_equal(actual, expected, message: String = "") -> bool:
	if actual == expected:
		passed_assertions += 1
		return true
	else:
		failed_assertions += 1
		var err = "[FAIL] Expected '%s', got '%s'. %s" % [str(expected), str(actual), message]
		failure_messages.append(err)
		printerr("    ", err)
		return false

func assert_not_equal(actual, expected, message: String = "") -> bool:
	if actual != expected:
		passed_assertions += 1
		return true
	else:
		failed_assertions += 1
		var err = "[FAIL] Expected not '%s', got '%s'. %s" % [str(expected), str(actual), message]
		failure_messages.append(err)
		printerr("    ", err)
		return false

func assert_approx_equal(actual: float, expected: float, tolerance: float = 0.05, message: String = "") -> bool:
	if abs(actual - expected) <= tolerance:
		passed_assertions += 1
		return true
	else:
		failed_assertions += 1
		var err = "[FAIL] Expected ~%f, got %f (diff: %f > tol: %f). %s" % [expected, actual, abs(actual - expected), tolerance, message]
		failure_messages.append(err)
		printerr("    ", err)
		return false

func assert_vector_approx(actual: Vector2, expected: Vector2, tolerance: float = 0.1, message: String = "") -> bool:
	if actual.distance_to(expected) <= tolerance:
		passed_assertions += 1
		return true
	else:
		failed_assertions += 1
		var err = "[FAIL] Expected Vector2%s, got Vector2%s (dist: %f > tol: %f). %s" % [str(expected), str(actual), actual.distance_to(expected), tolerance, message]
		failure_messages.append(err)
		printerr("    ", err)
		return false

func assert_not_null(object, message: String = "") -> bool:
	if object != null:
		passed_assertions += 1
		return true
	else:
		failed_assertions += 1
		var err = "[FAIL] Expected non-null object, got null. %s" % message
		failure_messages.append(err)
		printerr("    ", err)
		return false

func assert_null(object, message: String = "") -> bool:
	if object == null:
		passed_assertions += 1
		return true
	else:
		failed_assertions += 1
		var err = "[FAIL] Expected null, got '%s'. %s" % [str(object), message]
		failure_messages.append(err)
		printerr("    ", err)
		return false

func assert_in_range(val: float, min_val: float, max_val: float, message: String = "") -> bool:
	var ok = val >= min_val and val <= max_val
	if ok:
		passed_assertions += 1
		return true
	else:
		failed_assertions += 1
		var err = "[FAIL] Expected in range [%f, %f], got %f. %s" % [min_val, max_val, val, message]
		failure_messages.append(err)
		printerr("    ", err)
		return false
