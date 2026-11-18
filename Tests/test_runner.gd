# res://Tests/test_runner.gd
extends Node

## Master Test Runner for TANK.IO Automated E2E Testing (Godot 4.6)
## Executes test suites headless, aggregates assertions, and exits with code 0 or 1.

var total_tests: int = 0
var passed_tests: int = 0
var failed_tests: int = 0
var total_assertions: int = 0
var filter_keyword: String = ""
var target_tier: int = 0 # 0 = run all

func _ready() -> void:
	# Disable background MCP server if present to prevent port collisions in headless test runs
	if has_node("/root/MCPRuntime"):
		get_node("/root/MCPRuntime").process_mode = Node.PROCESS_MODE_DISABLED

	print("\n==============================================================")
	print("       TANK.IO HEADLESS AUTOMATED TEST RUNNER (GODOT 4.6)     ")
	print("==============================================================")
	
	_parse_cli_arguments()
	# Defer execution to let the engine scene tree finish initial frame setup
	call_deferred("_execute_test_suites")

func _parse_cli_arguments() -> void:
	var all_args: Array[String] = []
	all_args.append_array(OS.get_cmdline_user_args())
	all_args.append_array(OS.get_cmdline_args())
	
	for arg in all_args:
		if arg.begins_with("--tier="):
			target_tier = int(arg.trim_prefix("--tier="))
		elif arg.begins_with("--filter="):
			filter_keyword = arg.trim_prefix("--filter=").to_lower()
	
	print("[CONFIG] Target Tier: %s | Filter: '%s'" % [
		"ALL (1-4)" if target_tier == 0 else str(target_tier),
		filter_keyword if not filter_keyword.is_empty() else "(none)"
	])

func _execute_test_suites() -> void:
	var start_time = Time.get_ticks_msec()
	
	if target_tier == 0 or target_tier == 1:
		await _run_suite("res://Tests/suites/tier1_features_test.gd", "TIER 1: FEATURE COVERAGE (R1-R8)")
	if target_tier == 0 or target_tier == 2:
		await _run_suite("res://Tests/suites/tier2_boundaries_test.gd", "TIER 2: BOUNDARY & CORNER CASES (R1-R8)")
	if target_tier == 0 or target_tier == 3:
		await _run_suite("res://Tests/suites/tier3_combinations_test.gd", "TIER 3: CROSS-FEATURE COMBINATIONS")
	if target_tier == 0 or target_tier == 4:
		await _run_suite("res://Tests/suites/tier4_simulations_test.gd", "TIER 4: REAL-WORLD MATCH SIMULATIONS")
	if target_tier == 0 or target_tier == 5:
		await _run_suite("res://Tests/suites/test_user_improvements.gd", "TIER 5: USER REQUESTED IMPROVEMENTS")
	if target_tier == 0 or target_tier == 6:
		await _run_suite("res://Tests/suites/test_pre_server_menus_and_flow.gd", "TIER 6: PRE-SERVER MENUS, LOBBY (5-30), COUNTDOWN & PAUSE")
	if target_tier == 0 or target_tier == 7:
		await _run_suite("res://Tests/suites/test_network_lobby.gd", "TIER 7: WEBSOCKET DEDICATED SERVER & ONLINE LOBBY")
	if target_tier == 0 or target_tier == 8:
		await _run_suite("res://Tests/suites/test_network_match.gd", "TIER 8: AUTHORITATIVE MULTIPLAYER MATCH SYNC")
		
	var duration_sec = (Time.get_ticks_msec() - start_time) / 1000.0
	_print_summary(duration_sec)

func _run_suite(suite_path: String, suite_title: String) -> void:
	if not ResourceLoader.exists(suite_path):
		printerr("[ERROR] Test suite script not found: ", suite_path)
		return
		
	print("\n>>> RUNNING %s <<<" % suite_title)
	var script = load(suite_path)
	if not script:
		printerr("[ERROR] Failed to load script: ", suite_path)
		return
		
	var instance = script.new()
	add_child(instance)
	
	# Find and deterministically sort all test methods starting with 'test_'
	var test_methods: Array[String] = []
	for method in instance.get_method_list():
		var mname: String = method["name"]
		if mname.begins_with("test_"):
			if filter_keyword.is_empty() or filter_keyword in mname.to_lower():
				test_methods.append(mname)
	test_methods.sort()
	
	for mname in test_methods:
		await _run_single_test(instance, mname)
				
	remove_child(instance)
	instance.queue_free()
	await get_tree().physics_frame

func _run_single_test(instance: Node, method_name: String) -> void:
	total_tests += 1
	instance.failed_assertions = 0
	instance.passed_assertions = 0
	instance.failure_messages.clear()
	instance.test_name = method_name
	
	instance.setup()
	var t0 = Time.get_ticks_msec()
	
	# Call test method (coroutine)
	await instance.call(method_name)
	
	var elapsed = Time.get_ticks_msec() - t0
	instance.teardown()
	await get_tree().physics_frame
	
	total_assertions += instance.passed_assertions + instance.failed_assertions
	
	if instance.failed_assertions == 0:
		passed_tests += 1
		print("  [PASS] %s (%d ms)" % [method_name, elapsed])
	else:
		failed_tests += 1
		print("  [FAIL] %s (%d ms) -> %d assertion failures" % [method_name, elapsed, instance.failed_assertions])
		for msg in instance.failure_messages:
			print("         %s" % msg)

func _print_summary(duration: float) -> void:
	print("\n==============================================================")
	print("                   AUTOMATED TEST SUMMARY                     ")
	print("==============================================================")
	print("  Total Tests Executed : %d" % total_tests)
	print("  Passed               : %d" % passed_tests)
	print("  Failed               : %d" % failed_tests)
	print("  Total Assertions     : %d" % total_assertions)
	print("  Total Execution Time : %.2f seconds" % duration)
	print("==============================================================")
	
	if failed_tests == 0 and total_tests > 0:
		print("  RESULT: SUCCESS - ALL TESTS PASSED (EXIT CODE 0)\n")
		get_tree().quit(0)
	else:
		printerr("  RESULT: FAILURE - TESTS FAILED (EXIT CODE 1)\n")
		get_tree().quit(1)
