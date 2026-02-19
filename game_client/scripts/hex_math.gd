extends Node

# Pure static hex math functions using axial coordinates (q, r).
# Flat-top hexagon layout (matches backend map generation).
# HEX_SIZE is the radius from center to corner.

const HEX_SIZE: float = 48.0

# Axial direction vectors for the 6 neighbors
const AXIAL_DIRECTIONS: Array = [
	Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1),
	Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1)
]

# Distance between two axial coordinates
static func axial_distance(a: Vector2i, b: Vector2i) -> int:
	var diff = a - b
	return (abs(diff.x) + abs(diff.x + diff.y) + abs(diff.y)) / 2

# Get the 6 neighbors of an axial hex
static func axial_neighbors(hex: Vector2i) -> Array:
	var result: Array = []
	for d in AXIAL_DIRECTIONS:
		result.append(hex + d)
	return result

# Convert axial coordinates to pixel position (flat-top hexagons)
static func axial_to_pixel(hex: Vector2i, hex_size: float = HEX_SIZE) -> Vector2:
	var x = hex_size * (3.0 / 2.0 * hex.x)
	var y = hex_size * (sqrt(3.0) / 2.0 * hex.x + sqrt(3.0) * hex.y)
	return Vector2(x, y)

# Convert pixel position to axial coordinates (flat-top hexagons)
static func pixel_to_axial(pixel: Vector2, hex_size: float = HEX_SIZE) -> Vector2i:
	var q = (2.0 / 3.0 * pixel.x) / hex_size
	var r = (-1.0 / 3.0 * pixel.x + sqrt(3.0) / 3.0 * pixel.y) / hex_size
	return axial_round(Vector2(q, r))

# Round fractional axial coordinates to nearest hex
static func axial_round(frac: Vector2) -> Vector2i:
	var s = -frac.x - frac.y
	var rx = round(frac.x)
	var ry = round(frac.y)
	var rs = round(s)
	var x_diff = abs(rx - frac.x)
	var y_diff = abs(ry - frac.y)
	var s_diff = abs(rs - s)
	if x_diff > y_diff and x_diff > s_diff:
		rx = -ry - rs
	elif y_diff > s_diff:
		ry = -rx - rs
	return Vector2i(int(rx), int(ry))

# Get all hexes within radius of center (inclusive)
static func hexes_in_radius(center: Vector2i, radius: int) -> Array:
	var result: Array = []
	for q in range(-radius, radius + 1):
		for r in range(max(-radius, -q - radius), min(radius, -q + radius) + 1):
			result.append(center + Vector2i(q, r))
	return result

# Get all hexes on a line from a to b (inclusive)
static func hex_line(a: Vector2i, b: Vector2i) -> Array:
	var dist = axial_distance(a, b)
	if dist == 0:
		return [a]
	var result: Array = []
	for i in range(dist + 1):
		var t = float(i) / float(dist)
		var fq = lerp(float(a.x), float(b.x), t)
		var fr = lerp(float(a.y), float(b.y), t)
		result.append(axial_round(Vector2(fq, fr)))
	return result

# Get ring of hexes at exactly radius distance from center
static func hex_ring(center: Vector2i, radius: int) -> Array:
	if radius == 0:
		return [center]
	var result: Array = []
	var hex = center + AXIAL_DIRECTIONS[4] * radius
	for i in range(6):
		for _j in range(radius):
			result.append(hex)
			hex = hex + AXIAL_DIRECTIONS[i]
	return result
