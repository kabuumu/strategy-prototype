extends RefCounted
# Minimal assertion collector — one instance per test method. Dependency-free
# (no GUT/addon), matching the project's pure-stdlib tooling ethos. Tests call
# these helpers; each records a failure string rather than throwing (GDScript
# has no exceptions), so a test "passes" iff it records zero failures.

var failures: Array[String] = []
var checks: int = 0

func ok(cond: bool, msg: String = "") -> void:
	checks += 1
	if not cond:
		failures.append("expected true — %s" % msg)

func eq(a: Variant, b: Variant, msg: String = "") -> void:
	checks += 1
	if a != b:
		failures.append("expected %s == %s — %s" % [str(a), str(b), msg])

func ne(a: Variant, b: Variant, msg: String = "") -> void:
	checks += 1
	if a == b:
		failures.append("expected %s != %s — %s" % [str(a), str(b), msg])

func gt(a: Variant, b: Variant, msg: String = "") -> void:
	checks += 1
	if not (a > b):
		failures.append("expected %s > %s — %s" % [str(a), str(b), msg])

func ge(a: Variant, b: Variant, msg: String = "") -> void:
	checks += 1
	if not (a >= b):
		failures.append("expected %s >= %s — %s" % [str(a), str(b), msg])

func between(v: Variant, lo: Variant, hi: Variant, msg: String = "") -> void:
	checks += 1
	if v < lo or v > hi:
		failures.append("expected %s in [%s, %s] — %s" % [str(v), str(lo), str(hi), msg])

func has(container: Variant, key: Variant, msg: String = "") -> void:
	checks += 1
	if not (key in container):
		failures.append("expected %s to contain %s — %s" % [str(container), str(key), msg])

func contains_str(s: String, sub: String, msg: String = "") -> void:
	checks += 1
	if not s.contains(sub):
		failures.append("expected '%s' to contain '%s' — %s" % [s, sub, msg])

func approx(a: float, b: float, eps: float = 0.0001, msg: String = "") -> void:
	checks += 1
	if absf(a - b) > eps:
		failures.append("expected %s ~= %s — %s" % [str(a), str(b), msg])
