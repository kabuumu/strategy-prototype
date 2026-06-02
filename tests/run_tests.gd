extends SceneTree
# Headless test runner. Run with:
#   godot --headless --script res://tests/run_tests.gd
# Discovers every res://tests/test_*.gd, instantiates it, and calls each method
# named test_* with a fresh framework instance. Exits non-zero if any fail.

const FRAMEWORK := preload("res://tests/framework.gd")

func _initialize() -> void:
	var files := _discover()
	var total := 0
	var passed := 0
	var failed := 0
	print("== running %d test file(s) ==" % files.size())
	for path in files:
		var script: GDScript = load(path)
		if script == null:
			print("  FAIL  could not load %s" % path)
			failed += 1
			continue
		var inst: Object = script.new()
		var names: Array = []
		for m in inst.get_method_list():
			var n: String = String(m.get("name", ""))
			if n.begins_with("test_") and not names.has(n):
				names.append(n)
		names.sort()
		for n in names:
			total += 1
			var t = FRAMEWORK.new()
			inst.call(n, t)
			if t.failures.is_empty():
				passed += 1
				print("  ok    %s::%s  (%d checks)" % [String(path).get_file(), n, t.checks])
			else:
				failed += 1
				print("  FAIL  %s::%s" % [String(path).get_file(), n])
				for f in t.failures:
					print("          - %s" % f)
	print("\n%d passed, %d failed, %d total" % [passed, failed, total])
	quit(1 if failed > 0 else 0)

func _discover() -> Array:
	var out: Array = []
	var d := DirAccess.open("res://tests")
	if d == null:
		return out
	d.list_dir_begin()
	var f := d.get_next()
	while f != "":
		if not d.current_is_dir() and f.begins_with("test_") and f.ends_with(".gd"):
			out.append("res://tests/" + f)
		f = d.get_next()
	d.list_dir_end()
	out.sort()
	return out
