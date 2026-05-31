class_name Hex
extends RefCounted
# Pointy-top, odd-r offset hex math (Civ-style board). Coordinates stay as
# Vector2i(col, row); odd rows are shoved half a hex to the right.
# Centers are LOCAL (relative to the grid origin); callers add GRID_OFFSET when
# drawing on the battle node, or use them directly for _grid_node children.

const SIZE: float  = 37.0     # centre → corner
const W: float     = 64.08    # hex width  = SIZE * sqrt(3)
const H: float     = 74.0     # hex height = SIZE * 2
const VSTEP: float = 55.5     # row spacing = SIZE * 1.5

static func center(col: int, row: int) -> Vector2:
	var x: float = W * col + (W * 0.5 if (row & 1) == 1 else 0.0) + W * 0.5
	var y: float = VSTEP * row + H * 0.5
	return Vector2(x, y)

static func center_v(cell: Vector2i) -> Vector2:
	return center(cell.x, cell.y)

# Six corner points of the hex centred at c (for draw_polygon / outlines).
static func corners(c: Vector2) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(6):
		var ang := deg_to_rad(60.0 * i - 30.0)
		pts.append(c + Vector2(cos(ang), sin(ang)) * SIZE)
	return pts

static func _to_cube(cell: Vector2i) -> Vector3i:
	var x: int = cell.x - (cell.y - (cell.y & 1)) / 2
	var z: int = cell.y
	return Vector3i(x, -x - z, z)

# Hex grid distance (number of steps between two cells).
static func distance(a: Vector2i, b: Vector2i) -> int:
	var ac := _to_cube(a)
	var bc := _to_cube(b)
	return (abs(ac.x - bc.x) + abs(ac.y - bc.y) + abs(ac.z - bc.z)) / 2

# Neighbour offsets differ by row parity in odd-r layout.
const _DIRS_EVEN: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(0, -1), Vector2i(-1, -1),
	Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1),
]
const _DIRS_ODD: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1),
	Vector2i(-1, 0), Vector2i(0, 1), Vector2i(1, 1),
]

static func neighbors(cell: Vector2i) -> Array:
	var dirs: Array[Vector2i] = _DIRS_ODD if (cell.y & 1) == 1 else _DIRS_EVEN
	var out: Array[Vector2i] = []
	for d: Vector2i in dirs:
		out.append(cell + d)
	return out

# Nearest cell to a LOCAL point (brute-force over the board — trivial at this size).
static func from_local(p: Vector2, cols: int, rows: int) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d := INF
	for r in range(rows):
		for c in range(cols):
			var d := p.distance_squared_to(center(c, r))
			if d < best_d:
				best_d = d
				best = Vector2i(c, r)
	return best
